// lib/src/storage/drift_sync_store.dart (internal) — the SyncStore of the SQLite store
// (CORE 6.10, contract 7.2.10 v1.3).
//
// Every write goes through the write queue (one job = one transaction step), so the
// write-Future rule of 7.2.9 holds: a failed commit is retried and the Future stays
// pending; ArgumentError is decided before the queue, state errors and a policy
// exception inside the job (its savepoint is rolled back, nothing changes).
//
// applyRemote / commitRepairs write rows with [WriteTxn.putRemote] (versions as given,
// local-only columns of an existing row kept) and then fix the device-local values
// (6.10.3): new rows start without local values, notes get page_count / first_page_id
// recomputed and updated_at = max(current, applied), written pages content_rev + 1.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../common/hlc.dart';
import '../common/ids.dart';
import '../common/sort_planner.dart';
import '../model/asset.dart';
import '../model/entity_json.dart';
import '../model/note.dart';
import '../model/page.dart';
import '../model/stroke.dart';
import '../model/sync_entity.dart';
import '../repo/events.dart';
import '../repo/settings_internal.dart';
import '../session/page_content.dart';
import '../sync/field_versions.dart';
import '../sync/merge.dart';
import '../sync/outbox_types.dart';
import '../sync/sync_store.dart';
import 'db/note_database.dart';
import 'drift_library_repository.dart';
import 'drift_note_store.dart';
import 'drift_sessions.dart';
import 'drift_trash_repository.dart';
import 'field_version_writer.dart';
import 'kv_keys.dart';
import 'outbox_writer.dart';
import 'row_mappers.dart';
import 'write_queue.dart';

/// Largest SYNC meta value (UTF-8 bytes, 6.10.4).
const int kMaxSyncMetaValueBytes = 256 * 1024;

/// Pseudo kv key a commit touches when only outbox rows changed (acknowledge):
/// watchPendingCount re-counts.
const String kOutboxTouchKey = '#outbox';

/// Ids per `IN (...)` list (SQLite variable limit).
const int _inChunk = 500;

Iterable<List<T>> _chunks<T>(List<T> items) sync* {
  for (var i = 0; i < items.length; i += _inChunk) {
    yield items.sublist(i, math.min(i + _inChunk, items.length));
  }
}

/// A policy exception carried out of the job as a domain error (no retry, the job's
/// savepoint is rolled back); applyRemote rethrows the original.
final class _PolicyFailure extends Error {
  _PolicyFailure(this.error, this.trace);
  final Object error;
  final StackTrace trace;
}

void _checkId(EntityKind kind, String id, String name) {
  if (kind == EntityKind.setting) {
    try {
      checkSettingKeyName(id);
    } on ArgumentError {
      throw ArgumentError.value(id, name, 'invalid setting key');
    }
  } else if (!isValidEntityId(id)) {
    throw ArgumentError.value(id, name, 'invalid entity id');
  }
}

int _pointBytes(Iterable<SyncEntity> entities) {
  var bytes = 0;
  for (final e in entities) {
    if (e is Stroke) bytes += e.points.length * 8;
  }
  return bytes;
}

final class DriftSyncStore implements SyncStore {
  DriftSyncStore(this.s);
  final DriftNoteStore s;

  NoteDatabase get _db => s.db;

  @override
  String get deviceNodeId => s.nodeId;

  @override
  OwnerId get ownerId => s.ownerId;

  // ---- outbox ------------------------------------------------------------------------

  @override
  Future<List<OutboxEntry>> pendingChanges({
    int limit = 500,
    int? afterSeq,
  }) async {
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'must be at least 1');
    }
    return readOutbox(_db, limit: limit, afterSeq: afterSeq);
  }

  @override
  Stream<int> watchPendingCount() => s.watches.watch<int>(
    affects: (t) => t.kinds.isNotEmpty || t.kvKeys.contains(kOutboxTouchKey),
    query: () async {
      final count = _db.outbox.seq.count();
      final row = await (_db.selectOnly(
        _db.outbox,
      )..addColumns([count])).getSingle();
      return row.read(count) ?? 0;
    },
  );

  @override
  Future<void> acknowledge(List<OutboxAck> acks) async {
    if (acks.isEmpty) return;
    final list = [...acks];
    await s.queue.run((tx) async {
      for (final a in list) {
        await (_db.delete(
          _db.outbox,
        )..where((t) => t.seq.equals(a.seq) & t.rev.equals(a.rev))).go();
      }
      tx.touchKv(kOutboxTouchKey);
    });
  }

  // ---- reads -------------------------------------------------------------------------

  @override
  Future<List<VersionedEntity?>> readVersioned(List<EntityRef> refs) async {
    final byKind = <EntityKind, Set<String>>{};
    for (final r in refs) {
      (byKind[r.kind] ??= {}).add(r.id);
    }
    final found = <EntityRef, VersionedEntity>{};
    for (final MapEntry(key: kind, value: ids) in byKind.entries) {
      for (final chunk in _chunks(ids.toList())) {
        for (final v in await _readKind(kind, chunk)) {
          found[EntityRef(kind, v.entity.id)] = v;
        }
      }
    }
    return [for (final r in refs) found[r]];
  }

  Future<List<VersionedEntity>> _readKind(
    EntityKind kind,
    List<String> ids,
  ) async => switch (kind) {
    EntityKind.folder => [
      for (final r in await (_db.select(
        _db.folders,
      )..where((t) => t.id.isIn(ids))).get())
        versionedFolder(r),
    ],
    EntityKind.note => [
      for (final r in await (_db.select(
        _db.notes,
      )..where((t) => t.id.isIn(ids))).get())
        versionedNote(r),
    ],
    EntityKind.page => [
      for (final r in await (_db.select(
        _db.pages,
      )..where((t) => t.id.isIn(ids))).get())
        versionedPage(r),
    ],
    EntityKind.stroke => [
      for (final r in await (_db.select(
        _db.strokes,
      )..where((t) => t.id.isIn(ids))).get())
        versionedStroke(r),
    ],
    EntityKind.penPreset => [
      for (final r in await (_db.select(
        _db.penPresets,
      )..where((t) => t.id.isIn(ids))).get())
        versionedPreset(r),
    ],
    EntityKind.asset => [
      for (final r in await (_db.select(
        _db.assets,
      )..where((t) => t.id.isIn(ids))).get())
        versionedAsset(r),
    ],
    EntityKind.recording => [
      for (final r in await (_db.select(
        _db.recordings,
      )..where((t) => t.id.isIn(ids))).get())
        versionedRecording(r),
    ],
    EntityKind.setting => [
      for (final r in await (_db.select(
        _db.settings,
      )..where((t) => t.key.isIn(ids))).get())
        versionedSetting(r),
    ],
    // (v2.0) A v1 database has no such rows; the tables come with DB v2 (CORE T24 / T28).
    EntityKind.pageObject || EntityKind.handwriting => const [],
  };

  // ---- applyRemote (6.10.3) ----------------------------------------------------------

  @override
  Future<RemoteApplyReport> applyRemote(
    List<RemoteChange> changes, {
    required RemoteMergePolicy policy,
    Map<String, String> metaUpdates = const {},
  }) async {
    final list = [...changes];
    final meta = {...metaUpdates};
    for (final c in list) {
      switch (c) {
        case RemoteUpsert(:final entity, :final versions):
          _checkId(entity.kind, entity.id, 'changes');
          if (entity.version == null || entity.version != versions.max) {
            throw ArgumentError.value(
              c,
              'changes',
              'entity.version of ${entity.kind.name} ${entity.id} must equal '
                  'versions.max',
            );
          }
        case RemotePurge(:final kind, :final id):
          if (kind != EntityKind.folder && kind != EntityKind.note) {
            throw ArgumentError.value(
              kind,
              'changes',
              'RemotePurge is for folders and notes only',
            );
          }
          _checkId(kind, id, 'changes');
      }
    }
    _checkMeta(meta);
    try {
      return await s.queue.run(
        (tx) => _RemoteApply(this, tx, policy).run(list, meta),
        origin: ChangeOrigin.remote,
        bytes: _pointBytes([
          for (final c in list)
            if (c is RemoteUpsert) c.entity,
        ]),
      );
    } on _PolicyFailure catch (f) {
      Error.throwWithStackTrace(f.error, f.trace);
    }
  }

  // ---- commitRepairs (6.10.4) --------------------------------------------------------

  @override
  Future<void> commitRepairs(List<RepairWrite> repairs) async {
    final list = [
      for (final r in repairs)
        (entity: r.entity, fields: syncedFieldsOf(r.entity.kind, r.fields)),
    ];
    for (final r in list) {
      _checkId(r.entity.kind, r.entity.id, 'repairs');
      if (r.fields.isEmpty) {
        throw ArgumentError.value(
          r.fields,
          'repairs',
          'no synced field to write for ${r.entity.kind.name} ${r.entity.id}',
        );
      }
    }
    if (list.isEmpty) return;
    await s.queue.run(
      (tx) async {
        final w = _RemoteWriter(this, tx);
        final h = tx.stamp();
        for (final (:entity, :fields) in list) {
          final ref = EntityRef(entity.kind, entity.id);
          final local = await readVersionedRow(_db, ref);
          final SyncEntity next;
          final EntityFieldVersions versions;
          final Set<String> outFields;
          if (local == null || fields.contains(kAllFields)) {
            next = entity;
            versions = EntityFieldVersions(h);
            outFields = const {kAllFields};
          } else {
            final json = local.entity.toJson();
            final from = entity.toJson();
            for (final f in fields) {
              if (from.containsKey(f)) {
                json[f] = from[f];
              } else {
                json.remove(f);
              }
            }
            json['version'] = h.toString();
            next = EntityJson.decode(entity.kind, json);
            versions = localVersionsAfter(local.versions, fields, h);
            outFields = fields;
          }
          final hints = await w.write(next, versions, local);
          await recordOutbox(
            _db,
            kind: ref.kind,
            id: ref.id,
            noteId: hints.noteId,
            pageId: hints.pageId,
            op: OutboxOp.upsert,
            fields: outFields,
            hlc: h,
            now: tx.now,
          );
        }
        tx.touchKv(kOutboxTouchKey);
        await w.finish();
      },
      origin: ChangeOrigin.remote,
      bytes: _pointBytes([for (final r in list) r.entity]),
    );
  }

  // ---- meta KV (6.10.4) --------------------------------------------------------------

  static void _checkMetaKey(String key) {
    if (!key.startsWith(KvKeys.syncPrefix) ||
        key.length == KvKeys.syncPrefix.length) {
      throw ArgumentError.value(key, 'key', "must start with 'sync.'");
    }
  }

  static void _checkMeta(Map<String, String> updates) {
    for (final MapEntry(:key, :value) in updates.entries) {
      _checkMetaKey(key);
      if (utf8.encode(value).length > kMaxSyncMetaValueBytes) {
        throw ArgumentError.value(
          key,
          'updates',
          'value longer than 256 KiB (UTF-8)',
        );
      }
    }
  }

  @override
  Future<String?> readMeta(String key) async {
    _checkMetaKey(key);
    final row = await (_db.select(
      _db.kv,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  @override
  Future<void> writeMeta(Map<String, String> updates) async {
    final map = {...updates};
    _checkMeta(map);
    if (map.isEmpty) return;
    await s.queue.run((tx) => _putMeta(tx, map));
  }

  Future<void> _putMeta(WriteTxn tx, Map<String, String> updates) async {
    for (final MapEntry(:key, :value) in updates.entries) {
      await _db
          .into(_db.kv)
          .insertOnConflictUpdate(KvCompanion.insert(key: key, value: value));
      tx.touchKv(key);
    }
  }

  // ---- reassignOwner (6.10.5) --------------------------------------------------------

  @override
  Future<void> reassignOwner({
    required OwnerId from,
    required OwnerId to,
  }) async {
    if (to.isEmpty) throw ArgumentError.value(to, 'to', 'must not be empty');
    await s.queue.run((tx) async {
      // The stored value: a reassign queued in the same transaction is already in it.
      final stored = await (_db.select(
        _db.kv,
      )..where((t) => t.key.equals(KvKeys.ownerId))).getSingleOrNull();
      final current = stored?.value ?? s.ownerId;
      if (from != current) {
        throw StateError('reassignOwner: the owner is $current, not $from');
      }
      if (from == to) return;
      await _reassign(tx, EntityKind.folder, _db.folders, from, to);
      await _reassign(tx, EntityKind.note, _db.notes, from, to);
      await _reassign(tx, EntityKind.penPreset, _db.penPresets, from, to);
      await _reassign(tx, EntityKind.asset, _db.assets, from, to);
      await _db
          .into(_db.kv)
          .insertOnConflictUpdate(
            KvCompanion.insert(key: KvKeys.ownerId, value: to),
          );
      tx
        ..touchKv(KvKeys.ownerId)
        ..afterCommit(() => s.switchOwner(to));
    }, origin: ChangeOrigin.remote);
  }

  /// Rows of [table] owned by [from] get [to]; one EntityChange each (no version, no
  /// outbox — ownerId is a special key of SYNC, 6.10.5).
  Future<void> _reassign(
    WriteTxn tx,
    EntityKind kind,
    TableInfo<Table, Object?> table,
    OwnerId from,
    OwnerId to,
  ) async {
    final id = table.columnsByName['id']! as GeneratedColumn<String>;
    final owner = table.columnsByName['owner_id']! as GeneratedColumn<String>;
    final deleted = table.columnsByName['deleted_at']! as GeneratedColumn<int>;
    final rows =
        await (_db.selectOnly(table)
              ..addColumns([id, deleted])
              ..where(owner.equals(from)))
            .get();
    if (rows.isEmpty) return;
    await _db.customUpdate(
      'UPDATE ${table.actualTableName} SET owner_id = ? WHERE owner_id = ?',
      variables: [Variable<String>(to), Variable<String>(from)],
      updates: {table},
    );
    for (final r in rows) {
      tx.addChange(
        EntityChange(
          kind: kind,
          id: r.read(id)!,
          deleted: r.read(deleted) != null,
        ),
      );
    }
  }

  // ---- duplicateNoteForRecovery (6.10.5) ---------------------------------------------

  @override
  Future<NoteId?> duplicateNoteForRecovery(
    NoteId noteId, {
    required String titleSuffix,
  }) async {
    if (titleSuffix.length >= 200) {
      throw ArgumentError.value(
        titleSuffix,
        'titleSuffix',
        'shorter than 200 characters',
      );
    }
    return s.queue.run((tx) async {
      final row = await (_db.select(
        _db.notes,
      )..where((t) => t.id.equals(noteId))).getSingleOrNull();
      if (row == null) return null;
      final note = noteOf(row);
      FolderId? folderId = note.folderId;
      if (folderId != null) {
        final folder =
            await (_db.select(_db.folders)..where(
                  (t) =>
                      t.id.equals(folderId!) &
                      t.ownerId.equals(s.ownerId) &
                      t.deletedAt.isNull(),
                ))
                .getSingleOrNull();
        if (folder == null) folderId = null;
      }
      final n = _db.notes;
      final keys = [
        for (final r
            in await (_db.selectOnly(n)
                  ..addColumns([n.sortKey])
                  ..where(
                    n.ownerId.equals(s.ownerId) &
                        n.deletedAt.isNull() &
                        (folderId == null
                            ? n.folderId.isNull()
                            : n.folderId.equals(folderId)),
                  ))
                .get())
          r.read(n.sortKey)!,
      ];
      return s.library.copyNote(
        tx,
        note,
        folderId: folderId,
        sortKey: sortKeyAfterAll(keys),
        title: nameWithSuffix(note.title, titleSuffix),
      );
    });
  }
}

/// Writes remote / repair rows and fixes the device-local values afterwards (6.10.3
/// writeRow and 'local-only columns'). One per job attempt.
final class _RemoteWriter {
  _RemoteWriter(this.sync, this.tx);
  final DriftSyncStore sync;
  final WriteTxn tx;

  /// Affected notes → the largest applied updatedAt.
  final Map<NoteId, EpochMillis> notes = {};

  /// Pages whose row or strokes were written, and page rows created here.
  final Set<PageId> written = {};
  final Set<PageId> created = {};

  NoteDatabase get _db => sync.s.db;

  void _affect(NoteId? noteId, EpochMillis updatedAt) {
    if (noteId == null || noteId.isEmpty) return;
    notes.update(
      noteId,
      (v) => math.max(v, updatedAt),
      ifAbsent: () => updatedAt,
    );
  }

  /// Writes [entity] with [versions] as given; [local] is the row before (null = new).
  Future<({NoteId? noteId, PageId? pageId})> write(
    SyncEntity entity,
    EntityFieldVersions versions,
    VersionedEntity? local,
  ) async {
    var e = entity;
    int? chunkCount;
    final before = local?.entity;
    switch (entity) {
      case Note():
        e = before is Note
            ? entity.copyWith(
                updatedAt: math.max(entity.updatedAt, before.updatedAt),
              )
            : _withoutLocalValues(entity);
        _affect(entity.id, entity.updatedAt);
      case Page():
        if (local == null) created.add(entity.id);
        written.add(entity.id);
        e = entity.copyWith(
          contentRevision: 0,
        ); // new row: 0; a row keeps its value
        _affect(entity.noteId, entity.updatedAt);
        if (before is Page && before.noteId != entity.noteId) {
          _affect(before.noteId, entity.updatedAt);
        }
      case Stroke():
        written.add(entity.pageId);
        _affect(await tx.noteIdOfPage(entity.pageId), entity.updatedAt);
        if (before is Stroke && before.pageId != entity.pageId) {
          written.add(before.pageId);
          _affect(await tx.noteIdOfPage(before.pageId), entity.updatedAt);
        }
      case Recording():
        _affect(entity.noteId, entity.updatedAt);
        if (before is Recording && before.noteId != entity.noteId) {
          _affect(before.noteId, entity.updatedAt);
        }
      case Asset():
        if (local == null) {
          final state = await sync.s.assets.localStateOf(
            entity.id,
            entity.size,
          );
          e = entity.copyWith(hasLocalBytes: state.hasLocalBytes);
          chunkCount = state.chunkCount;
        }
      default:
        break;
    }
    return tx.putRemote(
      e,
      versions,
      advanceClock: false,
      assetChunkCount: chunkCount,
    );
  }

  /// Device-local values after the writes: content_rev + 1 of written pages that
  /// existed (once), then each affected note's page_count / first_page_id and
  /// updated_at = max(current, applied).
  Future<void> finish() async {
    final bump = written.difference(created).toList();
    for (final chunk in _chunks(bump)) {
      await _db.customUpdate(
        'UPDATE pages SET content_rev = content_rev + 1 '
        'WHERE id IN (${List.filled(chunk.length, '?').join(', ')})',
        variables: [for (final id in chunk) Variable<String>(id)],
        updates: {_db.pages},
      );
    }
    if (bump.isNotEmpty) tx.touch(EntityKind.page);
    for (final MapEntry(key: noteId, value: updatedAt) in notes.entries) {
      await refreshNoteDerived(tx, noteId, updatedAt: updatedAt);
    }
  }
}

/// [n] as a new row: no local values (lastOpenedAt null, derived values recomputed).
Note _withoutLocalValues(Note n) => Note(
  id: n.id,
  ownerId: n.ownerId,
  folderId: n.folderId,
  title: n.title,
  cover: n.cover,
  tags: n.tags,
  isFavorite: n.isFavorite,
  sortKey: n.sortKey,
  schemaVersion: n.schemaVersion,
  createdAt: n.createdAt,
  updatedAt: n.updatedAt,
  deletedAt: n.deletedAt,
  trashRootId: n.trashRootId,
  version: n.version,
);

/// One applyRemote job attempt (6.10.3).
final class _RemoteApply {
  _RemoteApply(this.sync, this.tx, this.policy)
    : writer = _RemoteWriter(sync, tx);

  final DriftSyncStore sync;
  final WriteTxn tx;
  final RemoteMergePolicy policy;
  final _RemoteWriter writer;

  int taken = 0, kept = 0, merged = 0, purged = 0;
  final Set<NoteId> purgedNotes = {};
  final List<PageId> purgedPages = [];
  Hlc? maxRemote;

  NoteDatabase get _db => sync.s.db;

  Future<RemoteApplyReport> run(
    List<RemoteChange> changes,
    Map<String, String> meta,
  ) async {
    for (final c in changes) {
      switch (c) {
        case RemoteUpsert():
          await _upsert(c);
        case RemotePurge():
          await _purge(c);
      }
    }
    final m = maxRemote;
    if (m != null) tx.receive(m);
    await writer.finish();
    await sync._putMeta(tx, meta);
    if (purgedPages.isNotEmpty) {
      final pages = [...purgedPages];
      tx.afterCommit(() => sync.s.thumbnails.dropPurged(pages));
    }
    return RemoteApplyReport(
      taken: taken,
      kept: kept,
      merged: merged,
      purged: purged,
      affectedNoteIds: Set.unmodifiable({...writer.notes.keys, ...purgedNotes}),
    );
  }

  Future<void> _upsert(RemoteUpsert u) async {
    final ref = EntityRef(u.kind, u.id);
    final local = await readVersionedRow(_db, ref);
    final entry = await outboxRowOf(_db, ref.kind, ref.id);
    final isPurge = entry != null && entry.op == OutboxOp.purge.name;
    final Set<String>? pending = entry == null
        ? null
        : isPurge
        ? const {kAllFields}
        : Set.unmodifiable(outboxFieldsOf(entry));
    final MergeDecision decision;
    try {
      decision = policy(local, VersionedEntity(u.entity, u.versions), pending);
    } on Object catch (e, s) {
      throw _PolicyFailure(e, s);
    }
    final m = maxRemote;
    if (m == null || u.versions.max > m) maxRemote = u.versions.max;
    switch (decision) {
      case KeepLocal():
        kept++;
      case TakeRemote(:final dropPendingLocal):
        await writer.write(u.entity, u.versions, local);
        if (entry != null && (dropPendingLocal || isPurge)) {
          await deleteOutboxEntry(_db, ref.kind, ref.id);
          tx.touchKv(kOutboxTouchKey);
        }
        taken++;
      case WriteMerged(:final entity, :final versions, :final fieldsToUpload):
        if (entity.kind != ref.kind || entity.id != ref.id) {
          throw StateError(
            'WriteMerged entity ${entity.kind.name} ${entity.id} is not $ref',
          );
        }
        if (entity.version != versions.max) {
          throw StateError(
            'WriteMerged entity.version of $ref must equal versions.max',
          );
        }
        final hints = await writer.write(entity, versions, local);
        await setOutboxFields(
          _db,
          current: entry,
          kind: ref.kind,
          id: ref.id,
          noteId: hints.noteId,
          pageId: hints.pageId,
          fields: {...fieldsToUpload},
          hlc: versions.max,
          now: tx.now,
        );
        tx.touchKv(kOutboxTouchKey);
        merged++;
    }
  }

  /// RemotePurge (6.10.3): the folder / note row, the members of its trash group,
  /// the notes' pages / strokes / recordings and every outbox entry of them; no new
  /// outbox entry.
  Future<void> _purge(RemotePurge p) async {
    final f = _db.folders;
    final n = _db.notes;
    final folderIds = <FolderId>{
      if (p.kind == EntityKind.folder)
        for (final r
            in await (_db.selectOnly(f)
                  ..addColumns([f.id])
                  ..where(f.id.equals(p.id)))
                .get())
          r.read(f.id)!,
      for (final r
          in await (_db.selectOnly(f)
                ..addColumns([f.id])
                ..where(f.trashRootId.equals(p.id)))
              .get())
        r.read(f.id)!,
    };
    final noteIds = <NoteId>{
      if (p.kind == EntityKind.note)
        for (final r
            in await (_db.selectOnly(n)
                  ..addColumns([n.id])
                  ..where(n.id.equals(p.id)))
                .get())
          r.read(n.id)!,
      for (final r
          in await (_db.selectOnly(n)
                ..addColumns([n.id])
                ..where(n.trashRootId.equals(p.id)))
              .get())
        r.read(n.id)!,
    };
    if (folderIds.isEmpty && noteIds.isEmpty) return;
    for (final id in folderIds) {
      await deleteOutboxEntry(_db, EntityKind.folder, id);
      await tx.purge(EntityRef(EntityKind.folder, id), outbox: false);
    }
    final notes = noteIds.toList();
    purgedPages.addAll(await deleteNoteContents(tx, notes));
    for (final id in notes) {
      await deleteOutboxEntry(_db, EntityKind.note, id);
      await tx.purge(EntityRef(EntityKind.note, id), outbox: false);
    }
    tx.touchKv(kOutboxTouchKey);
    purgedNotes.addAll(notes);
    // A purged note is not 'affected' by an earlier write of this call any more.
    notes.forEach(writer.notes.remove);
    purged++;
  }
}
