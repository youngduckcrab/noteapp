// Internal (not exported). The in-memory state behind FakeLocalStore and its CORE
// SyncStore view (contract 7.2.10 v1.3, table 5.1.4 C-01..C-25). 2nd round (07-sync 6.5,
// S2-4a): page objects and handwriting results — page indexes, outbox hints (orphan objects
// included), contentRevision, removal with a purged note and the recovery copy of CORE
// 6.14.1 (recordings, strokes, objects, handwriting).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:note_core/note_core.dart';

import '../model/field_units.dart';
import '../model/field_versions_ext.dart';

/// Largest meta value in UTF-8 bytes (contract 7.2.10: values ≤ 256 KiB).
const int kFakeMetaValueLimit = 256 * 1024;

/// Rows, outbox, meta KV, blob bytes and the HLC of one fake device, with a
/// rollback journal so a failing call changes nothing (contract 7.2.10 v1.3).
final class FakeStoreState {
  FakeStoreState({
    required this.nodeId,
    required this.clock,
    required this.ownerId,
  }) : hlc = HlcClock(nodeId: nodeId, clock: clock);

  final String nodeId;
  final Clock clock;
  OwnerId ownerId;
  final HlcClock hlc;

  final Map<EntityRef, VersionedEntity> rows = {};
  final Map<EntityRef, OutboxEntry> outbox = {};
  final Map<String, String> meta = {};
  final Map<AssetId, Uint8List> blobs = {};

  final Map<NoteId, Set<PageId>> _pagesByNote = {};
  final Map<PageId, Set<String>> _strokesByPage = {};
  final Map<PageId, Set<String>> _objectsByPage = {};

  int _nextSeq = 1;
  int _idCounter = 0;
  int _failWrites = 0;

  List<void Function()>? _journal;
  FakeTxn? _txn;

  final StreamController<void> _localChanges =
      StreamController<void>.broadcast();
  final StreamController<int> _pendingCount = StreamController<int>.broadcast();
  final StreamController<AssetId> _bytesArrived =
      StreamController<AssetId>.broadcast();

  Stream<void> get localChanges => _localChanges.stream;
  Stream<AssetId> get bytesArrived => _bytesArrived.stream;

  int get millis => clock.now().millisecondsSinceEpoch;

  /// A new entity id unique to this device: `<prefix>-<nodeId>-<n>`.
  String newId(String prefix) {
    _idCounter++;
    return '$prefix-$nodeId-${_idCounter.toString().padLeft(6, '0')}';
  }

  // ---- failure injection ------------------------------------------------------------

  void failNextWrites(int count) {
    if (count < 0) throw ArgumentError.value(count, 'count', 'is negative');
    _failWrites = count;
  }

  /// Called first by every write through sync / assets.
  void checkWrite(String operation) {
    if (_failWrites > 0) {
      _failWrites--;
      throw StateError('FakeLocalStore: injected write failure ($operation)');
    }
  }

  // ---- events -------------------------------------------------------------------------

  void emitLocalChange() => _localChanges.add(null);

  void emitPendingCount() => _pendingCount.add(outbox.length);

  void emitBytesArrived(AssetId id) => _bytesArrived.add(id);

  Stream<int> watchPendingCount() => Stream<int>.multi((controller) {
    var last = outbox.length;
    controller.add(last);
    final sub = _pendingCount.stream.listen((n) {
      if (n == last) return;
      last = n;
      controller.add(n);
    });
    controller.onCancel = sub.cancel;
  });

  // ---- transactions -------------------------------------------------------------------

  /// Runs [body] as one transaction: if it throws, every row / outbox / meta change made
  /// through this state is undone and the error is rethrown.
  T transaction<T>(T Function(FakeTxn txn) body) {
    if (_journal != null) throw StateError('nested FakeLocalStore transaction');
    final journal = <void Function()>[];
    final seq = _nextSeq;
    journal.add(() => _nextSeq = seq);
    final txn = FakeTxn();
    _journal = journal;
    _txn = txn;
    try {
      return body(txn);
    } catch (_) {
      _journal = null;
      for (final undo in journal.reversed) {
        undo();
      }
      rethrow;
    } finally {
      _journal = null;
      _txn = null;
    }
  }

  // ---- rows ---------------------------------------------------------------------------

  void putRow(VersionedEntity row) {
    final ref = EntityRef(row.entity.kind, row.entity.id);
    final old = rows[ref];
    _journal?.add(() => old == null ? _rawRemove(ref) : _rawPut(ref, old));
    _rawPut(ref, row);
  }

  void removeRow(EntityRef ref) {
    final old = rows[ref];
    if (old == null) return;
    _journal?.add(() => _rawPut(ref, old));
    _rawRemove(ref);
  }

  void _rawPut(EntityRef ref, VersionedEntity row) {
    final old = rows[ref];
    if (old != null) _unindex(old.entity);
    rows[ref] = row;
    _index(row.entity);
  }

  void _rawRemove(EntityRef ref) {
    final old = rows.remove(ref);
    if (old != null) _unindex(old.entity);
  }

  void _index(SyncEntity e) {
    switch (e) {
      case Page():
        (_pagesByNote[e.noteId] ??= {}).add(e.id);
      case Stroke():
        (_strokesByPage[e.pageId] ??= {}).add(e.id);
      case PageObject():
        (_objectsByPage[e.pageId] ??= {}).add(e.id);
      default:
    }
  }

  void _unindex(SyncEntity e) {
    switch (e) {
      case Page():
        _pagesByNote[e.noteId]?.remove(e.id);
      case Stroke():
        _strokesByPage[e.pageId]?.remove(e.id);
      case PageObject():
        _objectsByPage[e.pageId]?.remove(e.id);
      default:
    }
  }

  /// Page rows (soft-deleted included) whose noteId is [noteId].
  List<Page> pagesOf(NoteId noteId) => [
    for (final id in _pagesByNote[noteId] ?? const <PageId>{})
      rows[EntityRef(EntityKind.page, id)]!.entity as Page,
  ];

  /// Stroke rows (soft-deleted included) whose pageId is [pageId].
  List<Stroke> strokesOf(PageId pageId) => [
    for (final id in _strokesByPage[pageId] ?? const <String>{})
      rows[EntityRef(EntityKind.stroke, id)]!.entity as Stroke,
  ];

  /// Page object rows (soft-deleted included) whose pageId is [pageId].
  List<PageObject> objectsOf(PageId pageId) => [
    for (final id in _objectsByPage[pageId] ?? const <String>{})
      rows[EntityRef(EntityKind.pageObject, id)]!.entity as PageObject,
  ];

  /// The handwriting result row of [pageId] (soft-deleted included; id `hw_<pageId>`).
  HandwritingText? handwritingOf(PageId pageId) =>
      entityOf(EntityKind.handwriting, HandwritingText.idFor(pageId))
          as HandwritingText?;

  /// Recording rows (soft-deleted included) whose noteId is [noteId].
  List<Recording> recordingsOf(NoteId noteId) => [
    for (final row in rows.values)
      if (row.entity case final Recording r when r.noteId == noteId) r,
  ];

  SyncEntity? entityOf(EntityKind kind, String id) =>
      rows[EntityRef(kind, id)]?.entity;

  // ---- outbox -------------------------------------------------------------------------

  void _putEntry(OutboxEntry entry) {
    final ref = entry.ref;
    final old = outbox[ref];
    _journal?.add(() => old == null ? outbox.remove(ref) : outbox[ref] = old);
    outbox[ref] = entry;
  }

  void removeEntry(EntityRef ref) {
    final old = outbox[ref];
    if (old == null) return;
    _journal?.add(() => outbox[ref] = old);
    outbox.remove(ref);
  }

  int _takeSeq() => _nextSeq++;

  /// CORE 6.10.1 merge: one entry per entity, seq kept, rev + 1, field union ('*'
  /// absorbs), purge wins, hlc = the newest change.
  void enqueue(
    EntityRef ref, {
    required OutboxOp op,
    required Set<String> fields,
    required Hlc hlc,
  }) {
    final old = outbox[ref];
    final (noteId, pageId) = hintsOf(ref);
    if (old == null) {
      _putEntry(
        OutboxEntry(
          seq: _takeSeq(),
          rev: 1,
          kind: ref.kind,
          entityId: ref.id,
          noteId: noteId,
          pageId: pageId,
          op: op,
          changedFields: op == OutboxOp.purge
              ? const {kAllFields}
              : Set.unmodifiable(fields),
          hlc: hlc,
          enqueuedAt: millis,
        ),
      );
      return;
    }
    final purge = old.op == OutboxOp.purge || op == OutboxOp.purge;
    final all =
        purge ||
        old.changedFields.contains(kAllFields) ||
        fields.contains(kAllFields);
    _putEntry(
      OutboxEntry(
        seq: old.seq,
        rev: old.rev + 1,
        kind: ref.kind,
        entityId: ref.id,
        noteId: noteId ?? old.noteId,
        pageId: pageId ?? old.pageId,
        op: purge ? OutboxOp.purge : OutboxOp.upsert,
        changedFields: all
            ? const {kAllFields}
            : Set.unmodifiable({...old.changedFields, ...fields}),
        hlc: hlc,
        enqueuedAt: old.enqueuedAt,
      ),
    );
  }

  /// WriteMerged rule (contract 7.2.10 v1.3): the entry's fields become EXACTLY [fields]
  /// (empty → entry deleted, no entry → new one), rev + 1, seq kept; a purge entry becomes
  /// an upsert entry.
  void setEntryFields(EntityRef ref, Set<String> fields, Hlc hlc) {
    final old = outbox[ref];
    if (fields.isEmpty) {
      removeEntry(ref);
      return;
    }
    final (noteId, pageId) = hintsOf(ref);
    _putEntry(
      OutboxEntry(
        seq: old?.seq ?? _takeSeq(),
        rev: (old?.rev ?? 0) + 1,
        kind: ref.kind,
        entityId: ref.id,
        noteId: noteId ?? old?.noteId,
        pageId: pageId ?? old?.pageId,
        op: OutboxOp.upsert,
        changedFields: Set.unmodifiable(fields),
        hlc: hlc,
        enqueuedAt: old?.enqueuedAt ?? millis,
      ),
    );
  }

  /// Routing hints of CORE 4.6: noteId for page / stroke / recording ('' for a stroke whose
  /// page row is not here — CORE's orphan value), pageId for stroke. (2nd round, contract
  /// 7.2.8) pageObject: noteId of its page ('' when orphan) and pageId; handwriting: its
  /// noteId and pageId.
  (NoteId?, PageId?) hintsOf(EntityRef ref) {
    final e = rows[ref]?.entity;
    return switch (e) {
      Page() => (e.noteId, null),
      Recording() => (e.noteId, null),
      Stroke() => (
        (entityOf(EntityKind.page, e.pageId) as Page?)?.noteId ?? '',
        e.pageId,
      ),
      PageObject() => (
        (entityOf(EntityKind.page, e.pageId) as Page?)?.noteId ?? '',
        e.pageId,
      ),
      HandwritingText() => (e.noteId, e.pageId),
      _ => (null, null),
    };
  }

  /// Fills the noteId hint of pending stroke and object entries of [page] that were queued
  /// while the page row was missing (CORE 6.10.1 defensive rule).
  void _fillOrphanHints(Page page) {
    final refs = [
      for (final id in _strokesByPage[page.id] ?? const <String>{})
        EntityRef(EntityKind.stroke, id),
      for (final id in _objectsByPage[page.id] ?? const <String>{})
        EntityRef(EntityKind.pageObject, id),
    ];
    for (final ref in refs) {
      final entry = outbox[ref];
      if (entry == null || entry.noteId != '') continue;
      _putEntry(
        OutboxEntry(
          seq: entry.seq,
          rev: entry.rev,
          kind: entry.kind,
          entityId: entry.entityId,
          noteId: page.noteId,
          pageId: entry.pageId,
          op: entry.op,
          changedFields: entry.changedFields,
          hlc: entry.hlc,
          enqueuedAt: entry.enqueuedAt,
        ),
      );
    }
  }

  List<OutboxEntry> sortedOutbox() =>
      outbox.values.toList()..sort((a, b) => a.seq.compareTo(b.seq));

  // ---- meta ---------------------------------------------------------------------------

  static void checkMetaKey(String key) {
    if (!key.startsWith('sync.')) {
      throw ArgumentError.value(key, 'key', "must start with 'sync.'");
    }
  }

  static void checkMetaUpdates(Map<String, String> updates) {
    for (final MapEntry(:key, :value) in updates.entries) {
      checkMetaKey(key);
      if (utf8.encode(value).length > kFakeMetaValueLimit) {
        throw ArgumentError.value(
          '${value.length} chars',
          'updates[$key]',
          'exceeds 256 KiB',
        );
      }
    }
  }

  void putMeta(Map<String, String> updates) {
    for (final MapEntry(:key, :value) in updates.entries) {
      final old = meta[key];
      _journal?.add(() => old == null ? meta.remove(key) : meta[key] = old);
      meta[key] = value;
    }
  }

  // ---- writing entities ---------------------------------------------------------------

  /// Writes [entity] with [versions], taking device-local values from the current row
  /// (contract 7.2.10 v1.1, 5.1.2 S-12): Note.lastOpenedAt kept (new row null),
  /// Page.contentRevision bumped once per transaction (new row 0), Asset.hasLocalBytes
  /// kept (new row: whether the blob map holds the bytes). Note.pageCount / firstPageId are
  /// recomputed by [finish]. A stroke, a page object or a handwriting result marks its page
  /// as written (contentRevision, CORE C-29).
  void writeEntity(SyncEntity entity, EntityFieldVersions versions) {
    final txn = _txn!;
    final ref = EntityRef(entity.kind, entity.id);
    final old = rows[ref];
    final SyncEntity stored = switch (entity) {
      Note() => entity.copyWith(
        lastOpenedAt: (old?.entity as Note?)?.lastOpenedAt,
      ),
      Page() => entity.copyWith(
        contentRevision: (old?.entity as Page?)?.contentRevision ?? 0,
      ),
      Asset() => entity.copyWith(
        hasLocalBytes:
            (old?.entity as Asset?)?.hasLocalBytes ??
            blobs.containsKey(entity.id),
      ),
      _ => entity,
    };
    putRow(VersionedEntity(stored, versions));
    switch (stored) {
      case Note():
        txn.notes.add(stored.id);
      case Page():
        txn.notes.add(stored.noteId);
        final oldNote = (old?.entity as Page?)?.noteId;
        if (oldNote != null) txn.notes.add(oldNote);
        if (old == null) {
          txn.createdPages.add(stored.id);
          _fillOrphanHints(stored);
        } else {
          touchPage(stored.id);
        }
      case Stroke():
        touchPage(stored.pageId);
      case PageObject():
        touchPage(stored.pageId);
      case HandwritingText():
        touchPage(stored.pageId);
      default:
    }
  }

  /// Page.contentRevision + 1, at most once per transaction; not for a page row created in
  /// this transaction.
  void touchPage(PageId pageId) {
    final txn = _txn!;
    if (txn.createdPages.contains(pageId) || !txn.bumpedPages.add(pageId)) {
      return;
    }
    final ref = EntityRef(EntityKind.page, pageId);
    final row = rows[ref];
    if (row == null) return;
    final page = row.entity as Page;
    putRow(
      VersionedEntity(
        page.copyWith(contentRevision: page.contentRevision + 1),
        row.versions,
      ),
    );
  }

  /// The note a written page / stroke / recording / page object / handwriting result
  /// belongs to (null: none or orphan).
  NoteId? noteOf(SyncEntity e) => switch (e) {
    Note() => e.id,
    Page() => e.noteId,
    Recording() => e.noteId,
    Stroke() => (entityOf(EntityKind.page, e.pageId) as Page?)?.noteId,
    PageObject() => (entityOf(EntityKind.page, e.pageId) as Page?)?.noteId,
    HandwritingText() => e.noteId,
    _ => null,
  };

  static EpochMillis? updatedAtOf(SyncEntity e) => switch (e) {
    Folder() => e.updatedAt,
    Note() => e.updatedAt,
    Page() => e.updatedAt,
    Stroke() => e.updatedAt,
    PenPreset() => e.updatedAt,
    Recording() => e.updatedAt,
    SettingValue() => e.updatedAt,
    PageObject() => e.updatedAt,
    HandwritingText() => e.updatedAt,
    _ => null,
  };

  /// Local-only note values after a transaction: Note.updatedAt per [FakeTxn.noteUpdatedAt]
  /// (local edits set it, remote writes take the max — C-9, 5.1.2 S-11), pageCount /
  /// firstPageId from the active pages.
  void finish() {
    final txn = _txn!;
    final notes = {...txn.notes, ...txn.noteUpdatedAt.keys};
    for (final noteId in notes) {
      final ref = EntityRef(EntityKind.note, noteId);
      final row = rows[ref];
      if (row == null) continue;
      var note = row.entity as Note;
      final bump = txn.noteUpdatedAt[noteId];
      if (bump != null) {
        final next = txn.remote && bump < note.updatedAt
            ? note.updatedAt
            : bump;
        note = note.copyWith(updatedAt: next);
      }
      final active = pagesOf(noteId).where((p) => p.deletedAt == null).toList()
        ..sort(comparePages);
      note = active.isEmpty
          ? note.copyWith(pageCount: 0, clearFirstPageId: true)
          : note.copyWith(
              pageCount: active.length,
              firstPageId: active.first.id,
            );
      if (note != row.entity) putRow(VersionedEntity(note, row.versions));
    }
  }

  /// Page order: (sortKey, id).
  static int comparePages(Page a, Page b) {
    final c = a.sortKey.compareTo(b.sortKey);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  // ---- local commits (FakeLocalStore.localWrite, markUploaded, put) ---------------------

  /// One local commit (CORE 6.5 / 6.10.2): one fresh HLC; '*' or a new row → all fields,
  /// otherwise the listed fields get it; 'version' (and 'updatedAt' where the kind has it)
  /// are set; outbox entries merge; the parent note's updatedAt is bumped without outbox.
  /// [at] replaces the clock for 'updatedAt' (a caller that derived values from it).
  /// Must run inside [transaction].
  void localCommit(
    List<({EntityKind kind, Map<String, Object?> json, Set<String> fields})>
    writes, {
    EpochMillis? at,
  }) {
    final txn = _txn!;
    final h = hlc.now();
    final now = at ?? millis;
    final written = <(EntityRef, Set<String>)>[];
    for (final w in writes) {
      if (w.fields.isEmpty) {
        throw ArgumentError.value(w.fields, 'changedFields', 'is empty');
      }
      final meta = w.fields.intersection(FieldUnits.metaKeys);
      if (meta.isNotEmpty) {
        throw ArgumentError.value(meta, 'changedFields', 'holds meta keys');
      }
      final json = Map<String, Object?>.of(w.json);
      if (w.kind != EntityKind.asset) json['updatedAt'] = now;
      final idKey = w.kind == EntityKind.setting ? 'key' : 'id';
      final id = json[idKey];
      if (id is! String) {
        throw ArgumentError.value(id, 'json[$idKey]', 'missing');
      }
      final ref = EntityRef(w.kind, id);
      final old = rows[ref];
      final all = old == null || w.fields.contains(kAllFields);
      final versions = old == null || all
          ? EntityFieldVersions(h)
          : old.versions.stamped(w.fields, h);
      json['version'] = versions.max.toString();
      final entity = EntityJson.decode(w.kind, json);
      writeEntity(entity, versions);
      written.add((ref, all ? const {kAllFields} : w.fields));
      final noteId = noteOf(entity);
      if (noteId != null) txn.noteUpdatedAt[noteId] = now;
    }
    for (final (ref, fields) in written) {
      enqueue(ref, op: OutboxOp.upsert, fields: fields, hlc: h);
    }
    finish();
  }

  /// Rows of the trash group of [ref] (CORE 6.8): the folder / note itself, members whose
  /// trashRootId is ref.id, and when [extra] is given those refs too.
  Set<EntityRef> groupOf(
    EntityRef ref, [
    Iterable<EntityRef> extra = const [],
  ]) {
    final group = <EntityRef>{ref, ...extra};
    for (final MapEntry(key: r, value: row) in rows.entries) {
      final e = row.entity;
      final root = switch (e) {
        Folder() => e.trashRootId,
        Note() => e.trashRootId,
        _ => null,
      };
      if (root == ref.id) group.add(r);
    }
    return group;
  }

  /// Removes the rows of [group] and the pages / strokes / recordings of its notes — and
  /// (2nd round, CORE 6.14.2) their page objects and handwriting results; returns every
  /// removed ref (group members included even when no row was there).
  Set<EntityRef> removeGroup(Set<EntityRef> group) {
    final removed = <EntityRef>{...group};
    final notes = {
      for (final r in group)
        if (r.kind == EntityKind.note) r.id,
    };
    for (final noteId in notes) {
      for (final page in pagesOf(noteId)) {
        for (final stroke in strokesOf(page.id)) {
          removed.add(EntityRef(EntityKind.stroke, stroke.id));
        }
        for (final object in objectsOf(page.id)) {
          removed.add(EntityRef(EntityKind.pageObject, object.id));
        }
        if (handwritingOf(page.id) case final hw?) {
          removed.add(EntityRef(EntityKind.handwriting, hw.id));
        }
        removed.add(EntityRef(EntityKind.page, page.id));
      }
    }
    for (final row in rows.values) {
      final e = row.entity;
      if (e is Recording && notes.contains(e.noteId)) {
        removed.add(EntityRef(EntityKind.recording, e.id));
      }
      if (e is HandwritingText && notes.contains(e.noteId)) {
        removed.add(EntityRef(EntityKind.handwriting, e.id));
      }
    }
    for (final r in removed) {
      removeRow(r);
    }
    return removed;
  }

  Future<void> close() async {
    await _localChanges.close();
    await _pendingCount.close();
    await _bytesArrived.close();
  }
}

/// Bookkeeping of one transaction.
final class FakeTxn {
  /// Notes whose local-only values (pageCount, firstPageId) need recomputing.
  final Set<NoteId> notes = {};

  /// Note.updatedAt candidates (local: set, remote: max with current).
  final Map<NoteId, EpochMillis> noteUpdatedAt = {};
  final Set<PageId> createdPages = {};
  final Set<PageId> bumpedPages = {};

  /// Remote write (applyRemote / commitRepairs): Note.updatedAt only moves forward.
  bool remote = false;
}

/// CORE SyncStore over [FakeStoreState] (contract 7.2.10 v1.3, 5.1.4 C-01..C-22, C-24,
/// C-25).
final class FakeSyncStore implements SyncStore {
  FakeSyncStore(this._s);

  final FakeStoreState _s;

  @override
  String get deviceNodeId => _s.nodeId;

  @override
  OwnerId get ownerId => _s.ownerId;

  @override
  Future<List<OutboxEntry>> pendingChanges({
    int limit = 500,
    int? afterSeq,
  }) async {
    if (limit < 1) throw ArgumentError.value(limit, 'limit', 'must be ≥ 1');
    return [
      for (final e in _s.sortedOutbox())
        if (afterSeq == null || e.seq > afterSeq) e,
    ].take(limit).toList();
  }

  @override
  Stream<int> watchPendingCount() => _s.watchPendingCount();

  @override
  Future<void> acknowledge(List<OutboxAck> acks) async {
    _s.checkWrite('acknowledge');
    _s.transaction((_) {
      final bySeq = {for (final e in _s.outbox.values) e.seq: e};
      for (final ack in acks) {
        final entry = bySeq[ack.seq];
        if (entry != null && entry.rev == ack.rev) _s.removeEntry(entry.ref);
      }
    });
    _s.emitPendingCount();
  }

  @override
  Future<List<VersionedEntity?>> readVersioned(List<EntityRef> refs) async => [
    for (final ref in refs) _s.rows[ref],
  ];

  @override
  Future<RemoteApplyReport> applyRemote(
    List<RemoteChange> changes, {
    required RemoteMergePolicy policy,
    Map<String, String> metaUpdates = const {},
  }) async {
    _s.checkWrite('applyRemote');
    _validate(changes);
    FakeStoreState.checkMetaUpdates(metaUpdates);
    final report = _s.transaction((txn) {
      txn.remote = true;
      var taken = 0, kept = 0, merged = 0, purged = 0;
      final affected = <NoteId>{};
      Hlc? maxVersion;
      for (final change in changes) {
        switch (change) {
          case RemoteUpsert(:final entity, :final versions):
            if (maxVersion == null || versions.max > maxVersion) {
              maxVersion = versions.max;
            }
            final ref = EntityRef(entity.kind, entity.id);
            final local = _s.rows[ref];
            final entry = _s.outbox[ref];
            final Set<String>? pending = entry == null
                ? null
                : entry.op == OutboxOp.purge
                ? const {kAllFields}
                : entry.changedFields;
            final decision = policy(
              local,
              VersionedEntity(entity, versions),
              pending,
            );
            switch (decision) {
              case KeepLocal():
                kept++;
              case TakeRemote(:final dropPendingLocal):
                _keepNoteUpdatedAt(txn, local);
                _s.writeEntity(entity, versions);
                if (dropPendingLocal || entry?.op == OutboxOp.purge) {
                  _s.removeEntry(ref);
                }
                _noteBump(txn, entity, affected);
                taken++;
              case WriteMerged(
                entity: final e,
                versions: final v,
                :final fieldsToUpload,
              ):
                if (e.kind != entity.kind || e.id != entity.id) {
                  throw StateError(
                    'WriteMerged entity ${e.kind.name}/${e.id} is not '
                    '${entity.kind.name}/${entity.id}',
                  );
                }
                if (e.version != v.max) {
                  throw StateError(
                    'WriteMerged: entity.version ${e.version} != versions.max '
                    '${v.max}',
                  );
                }
                _keepNoteUpdatedAt(txn, local);
                _s.writeEntity(e, v);
                _s.setEntryFields(ref, fieldsToUpload, v.max);
                _noteBump(txn, e, affected);
                merged++;
            }
          case RemotePurge(:final kind, :final id):
            final ref = EntityRef(kind, id);
            final removed = _s.removeGroup(_s.groupOf(ref));
            for (final r in removed) {
              _s.removeEntry(r);
              if (r.kind == EntityKind.note) affected.add(r.id);
            }
            purged++;
        }
      }
      if (maxVersion != null) _s.hlc.receive(maxVersion);
      _s.finish();
      _s.putMeta(metaUpdates);
      return RemoteApplyReport(
        taken: taken,
        kept: kept,
        merged: merged,
        purged: purged,
        affectedNoteIds: Set.unmodifiable(affected),
      );
    });
    _s.emitPendingCount();
    return report;
  }

  /// Before a remote write replaces a note row: its current updatedAt stays a candidate,
  /// so the result is max(current, applied) (contract 7.2.10, 5.1.2 S-11).
  static void _keepNoteUpdatedAt(FakeTxn txn, VersionedEntity? local) {
    final note = local?.entity;
    if (note is! Note) return;
    final current = txn.noteUpdatedAt[note.id];
    if (current == null || note.updatedAt > current) {
      txn.noteUpdatedAt[note.id] = note.updatedAt;
    }
  }

  void _noteBump(FakeTxn txn, SyncEntity e, Set<NoteId> affected) {
    final noteId = _s.noteOf(e);
    if (noteId == null) return;
    affected.add(noteId);
    final applied = FakeStoreState.updatedAtOf(e);
    if (applied == null) return;
    final current = txn.noteUpdatedAt[noteId];
    if (current == null || applied > current) {
      txn.noteUpdatedAt[noteId] = applied;
    }
  }

  static void _validate(List<RemoteChange> changes) {
    for (final change in changes) {
      switch (change) {
        case RemoteUpsert(:final entity, :final versions):
          if (entity.version == null || entity.version != versions.max) {
            throw ArgumentError.value(
              '${entity.kind.name}/${entity.id}',
              'changes',
              'entity.version ${entity.version} != versions.max ${versions.max}',
            );
          }
          final validId = entity.kind == EntityKind.setting
              ? entity.id.isNotEmpty
              : isValidEntityId(entity.id);
          if (!validId) {
            throw ArgumentError.value(entity.id, 'changes', 'invalid id');
          }
        case RemotePurge(:final kind, :final id):
          if (kind != EntityKind.folder && kind != EntityKind.note) {
            throw ArgumentError.value(
              '${kind.name}/$id',
              'changes',
              'RemotePurge is for folders and notes only',
            );
          }
      }
    }
  }

  @override
  Future<void> commitRepairs(List<RepairWrite> repairs) async {
    _s.checkWrite('commitRepairs');
    final cleaned = [
      for (final r in repairs)
        (entity: r.entity, fields: r.fields.difference(FieldUnits.metaKeys)),
    ];
    for (final r in cleaned) {
      if (r.fields.isEmpty) {
        throw ArgumentError.value(
          '${r.entity.kind.name}/${r.entity.id}',
          'repairs',
          'has no fields',
        );
      }
    }
    if (cleaned.isEmpty) return;
    _s.transaction((txn) {
      txn.remote = true;
      final h = _s.hlc.now();
      for (final r in cleaned) {
        final ref = EntityRef(r.entity.kind, r.entity.id);
        final current = _s.rows[ref];
        final all = current == null || r.fields.contains(kAllFields);
        final SyncEntity entity;
        final EntityFieldVersions versions;
        if (current == null) {
          versions = EntityFieldVersions(h);
          entity = _withVersion(r.entity.toJson(), r.entity.kind, versions);
        } else {
          final json = Map<String, Object?>.of(current.entity.toJson());
          final source = r.entity.toJson();
          final fields = all
              ? source.keys.where((k) => !FieldUnits.metaKeys.contains(k))
              : r.fields;
          for (final f in fields) {
            if (source.containsKey(f)) {
              json[f] = source[f];
            } else {
              json.remove(f);
            }
          }
          versions = all
              ? EntityFieldVersions(h)
              : current.versions.stamped(r.fields, h);
          entity = _withVersion(json, r.entity.kind, versions);
        }
        _s.writeEntity(entity, versions);
        _s.enqueue(
          ref,
          op: OutboxOp.upsert,
          fields: all ? const {kAllFields} : r.fields,
          hlc: h,
        );
        final noteId = _s.noteOf(entity);
        if (noteId != null) txn.notes.add(noteId);
      }
      _s.finish();
    });
    _s.emitPendingCount();
  }

  static SyncEntity _withVersion(
    Map<String, Object?> json,
    EntityKind kind,
    EntityFieldVersions versions,
  ) => EntityJson.decode(kind, {...json, 'version': versions.max.toString()});

  @override
  Future<String?> readMeta(String key) async {
    FakeStoreState.checkMetaKey(key);
    return _s.meta[key];
  }

  @override
  Future<void> writeMeta(Map<String, String> updates) async {
    _s.checkWrite('writeMeta');
    FakeStoreState.checkMetaUpdates(updates);
    _s.transaction((_) => _s.putMeta(updates));
  }

  @override
  Future<void> reassignOwner({
    required OwnerId from,
    required OwnerId to,
  }) async {
    _s.checkWrite('reassignOwner');
    if (from != _s.ownerId) {
      throw StateError(
        'reassignOwner: store owner is ${_s.ownerId}, not $from',
      );
    }
    if (from == to) return;
    _s.transaction((_) {
      for (final row in _s.rows.values.toList()) {
        final e = row.entity;
        final SyncEntity? next = switch (e) {
          Folder() when e.ownerId == from => e.copyWith(ownerId: to),
          Note() when e.ownerId == from => e.copyWith(ownerId: to),
          PenPreset() when e.ownerId == from => e.copyWith(ownerId: to),
          Asset() when e.ownerId == from => e.copyWith(ownerId: to),
          _ => null,
        };
        if (next != null) _s.putRow(VersionedEntity(next, row.versions));
      }
      _s.ownerId = to;
    });
  }

  @override
  Future<NoteId?> duplicateNoteForRecovery(
    NoteId noteId, {
    required String titleSuffix,
  }) async {
    _s.checkWrite('duplicateNoteForRecovery');
    final source = _s.entityOf(EntityKind.note, noteId) as Note?;
    if (source == null) return null;
    final copyId = _s.transaction((txn) {
      final now = _s.millis;
      final folder = source.folderId == null
          ? null
          : _s.entityOf(EntityKind.folder, source.folderId!) as Folder?;
      final folderId = folder != null && folder.deletedAt == null
          ? folder.id
          : null;
      final newNoteId = _s.newId('note');
      final writes =
          <({EntityKind kind, Map<String, Object?> json, Set<String> fields})>[
            (
              kind: EntityKind.note,
              json: {
                ...source.toJson(),
                'id': newNoteId,
                'ownerId': _s.ownerId,
                'folderId': folderId,
                'title': recoveryTitle(source.title, titleSuffix),
                'sortKey': lastSortKeyAfter(folderId),
                'createdAt': now,
                'deletedAt': null,
                'trashRootId': null,
              },
              fields: const {kAllFields},
            ),
          ];
      // (2nd round, CORE 6.14.1 ①) recordings: new ids, the same asset / title / timing.
      final recordingIds = <RecordingId, RecordingId>{};
      final recordings =
          _s.recordingsOf(noteId).where((r) => r.deletedAt == null).toList()
            ..sort((a, b) => a.id.compareTo(b.id));
      for (final r in recordings) {
        final newId = _s.newId('recording');
        recordingIds[r.id] = newId;
        writes.add((
          kind: EntityKind.recording,
          json: {
            ...r.toJson(),
            'id': newId,
            'noteId': newNoteId,
            'createdAt': now,
          },
          fields: const {kAllFields},
        ));
      }
      final pages =
          _s.pagesOf(noteId).where((p) => p.deletedAt == null).toList()
            ..sort(FakeStoreState.comparePages);
      for (final page in pages) {
        final newPageId = _s.newId('page');
        writes.add((
          kind: EntityKind.page,
          json: {
            ...page.toJson(),
            'id': newPageId,
            'noteId': newNoteId,
            'createdAt': now,
          },
          fields: const {kAllFields},
        ));
        final strokes =
            _s.strokesOf(page.id).where((s) => s.deletedAt == null).toList()
              ..sort((a, b) {
                final c = a.createdAt.compareTo(b.createdAt);
                return c != 0 ? c : a.id.compareTo(b.id);
              });
        // ② a copied recording's new id; otherwise as it was (R-7 'no link').
        final strokeIds = <ElementId, ElementId>{};
        final copiedStrokes = <Stroke>[];
        for (final stroke in strokes) {
          final copy = stroke.copyWith(
            id: _s.newId('stroke'),
            pageId: newPageId,
            recordingId: recordingIds[stroke.recordingId] ?? stroke.recordingId,
            updatedAt: now,
          );
          strokeIds[stroke.id] = copy.id;
          copiedStrokes.add(copy);
          writes.add((
            kind: EntityKind.stroke,
            json: copy.toJson(),
            fields: const {kAllFields},
          ));
        }
        // ③ objects: new ids, the original createdAt.
        final objects =
            _s.objectsOf(page.id).where((o) => o.deletedAt == null).toList()
              ..sort((a, b) {
                final c = a.createdAt.compareTo(b.createdAt);
                return c != 0 ? c : a.id.compareTo(b.id);
              });
        for (final object in objects) {
          writes.add((
            kind: EntityKind.pageObject,
            json: object
                .copyTo(
                  id: _s.newId('object'),
                  pageId: newPageId,
                  createdAt: object.createdAt,
                )
                .toJson(),
            fields: const {kAllFields},
          ));
        }
        // ④ the handwriting result: the new note / page, stroke ids mapped (ids not copied
        // are dropped), sourceRev of the copied input strokes.
        final hw = _s.handwritingOf(page.id);
        if (hw != null && hw.deletedAt == null) {
          writes.add((
            kind: EntityKind.handwriting,
            json: HandwritingText(
              noteId: newNoteId,
              pageId: newPageId,
              engineId: hw.engineId,
              sourceRev: HandwritingText.sourceRevOf(
                copiedStrokes.where(HandwritingText.isRecognitionInput),
              ),
              lines: [
                for (final l in hw.lines)
                  l.copyWith(
                    strokeIds: [for (final id in l.strokeIds) ?strokeIds[id]],
                  ),
              ],
              createdAt: now,
            ).toJson(),
            fields: const {kAllFields},
          ));
        }
      }
      _s.localCommit(writes, at: now);
      return newNoteId;
    });
    _s.emitPendingCount();
    _s.emitLocalChange();
    return copyId;
  }

  /// Key after the last active note / folder sort key under [folderId] (CORE 6.6: new items
  /// go to the end).
  String lastSortKeyAfter(FolderId? folderId) {
    String? last;
    for (final row in _s.rows.values) {
      final e = row.entity;
      final (parent, key, deleted) = switch (e) {
        Note() => (e.folderId, e.sortKey, e.deletedAt),
        Folder() => (e.parentId, e.sortKey, e.deletedAt),
        _ => (null, null, 1),
      };
      if (key == null || deleted != null || parent != folderId) continue;
      if (last == null || key.compareTo(last) > 0) last = key;
    }
    return SortKeys.between(last, null);
  }

  /// Title + suffix within 200 UTF-16 code units, never cutting a surrogate pair (CORE C-5).
  static String recoveryTitle(String title, String suffix) {
    const max = 200;
    if (title.length + suffix.length <= max) return title + suffix;
    var keep = max - suffix.length;
    if (keep < 0) keep = 0;
    if (keep > 0) {
      final last = title.codeUnitAt(keep - 1);
      if (last >= 0xD800 && last <= 0xDBFF) keep--;
    }
    return title.substring(0, keep) + suffix;
  }
}
