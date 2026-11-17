// lib/src/storage/drift_trash_repository.dart (internal) — TrashRepository on SQLite
// (CORE 6.8 '휴지통').
//
// A trash group is every folder / note whose trash_root_id is the representative's id.
// Restore clears the group and moves the representative to its nearest active
// ancestor (through trashed folders that still have rows), else to the top level.
// Purge deletes the group's folder and note rows with their pages, strokes and
// recordings; the outbox gets one purge per folder / note (pending page, stroke and
// recording entries of those notes are dropped — the server cleans children), assets
// stay (GC later, PDF C-8). The pages' thumbnails are dropped after the commit (6.13).
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';

import '../common/errors.dart';
import '../common/ids.dart';
import '../common/sort_planner.dart';
import '../model/folder.dart';
import '../model/note.dart';
import '../model/sync_entity.dart';
import '../repo/library_types.dart';
import '../repo/trash_repository.dart';
import '../sync/outbox_types.dart';
import 'db/note_database.dart';
import 'drift_note_store.dart';
import 'drift_recording_draft_store.dart';
import 'entity_diff.dart';
import 'row_mappers.dart';
import 'watch_hub.dart';
import 'write_queue.dart';

/// Ids per `IN (...)` list (SQLite variable limit).
const int _inChunk = 500;

/// First automatic purgeExpired after openNoteStore, then the period (6.8).
const Duration kAutoPurgeDelay = Duration(seconds: 10);
const Duration kAutoPurgePeriod = Duration(hours: 6);

Iterable<List<T>> _chunks<T>(List<T> items) sync* {
  for (var i = 0; i < items.length; i += _inChunk) {
    yield items.sublist(
      i,
      i + _inChunk > items.length ? items.length : i + _inChunk,
    );
  }
}

final class DriftTrashRepository implements TrashRepository {
  DriftTrashRepository(this.s);
  final DriftNoteStore s;

  NoteDatabase get _db => s.db;
  OwnerId get _owner => s.ownerId;
  int get _retentionMs => s.config.trashRetention.inMilliseconds;

  Timer? _timer;

  /// Runs purgeExpired after [kAutoPurgeDelay], then every [kAutoPurgePeriod] while
  /// the store is open (openNoteStore only; test stores do not start it).
  void startAutoPurge() {
    _timer?.cancel();
    _timer = Timer(kAutoPurgeDelay, () {
      _runAutoPurge();
      _timer = Timer.periodic(kAutoPurgePeriod, (_) => _runAutoPurge());
    });
  }

  void _runAutoPurge() {
    // A failure (closed store) is not reported: the next period tries again.
    unawaited(purgeExpired().then<void>((_) {}, onError: (Object _) {}));
  }

  void stopAutoPurge() {
    _timer?.cancel();
    _timer = null;
  }

  // ---- queries ----------------------------------------------------------------------

  Future<List<TrashItem>> _items() async {
    final f = _db.folders;
    final n = _db.notes;
    final folderRows =
        await (_db.select(f)..where(
              (t) =>
                  t.ownerId.equals(_owner) &
                  t.deletedAt.isNotNull() &
                  t.trashRootId.equalsExp(t.id),
            ))
            .get();
    final noteRows =
        await (_db.select(n)..where(
              (t) =>
                  t.ownerId.equals(_owner) &
                  t.deletedAt.isNotNull() &
                  t.trashRootId.equalsExp(t.id),
            ))
            .get();
    final folderCounts = <String, int>{};
    final noteCounts = <String, int>{};
    if (folderRows.isNotEmpty) {
      final roots = [for (final r in folderRows) r.id];
      for (final chunk in _chunks(roots)) {
        final fc = f.id.count();
        final fq = _db.selectOnly(f)
          ..addColumns([f.trashRootId, fc])
          ..where(
            f.ownerId.equals(_owner) &
                f.trashRootId.isIn(chunk) &
                f.id.equalsExp(f.trashRootId).not(),
          )
          ..groupBy([f.trashRootId]);
        for (final r in await fq.get()) {
          folderCounts[r.read(f.trashRootId)!] = r.read(fc)!;
        }
        final nc = n.id.count();
        final nq = _db.selectOnly(n)
          ..addColumns([n.trashRootId, nc])
          ..where(n.ownerId.equals(_owner) & n.trashRootId.isIn(chunk))
          ..groupBy([n.trashRootId]);
        for (final r in await nq.get()) {
          noteCounts[r.read(n.trashRootId)!] = r.read(nc)!;
        }
      }
    }
    final out = <TrashItem>[
      for (final r in folderRows)
        TrashedFolder(
          folder: folderOf(r),
          folderCount: folderCounts[r.id] ?? 0,
          noteCount: noteCounts[r.id] ?? 0,
          expiresAt: r.deletedAt! + _retentionMs,
        ),
      for (final r in noteRows)
        TrashedNote(note: noteOf(r), expiresAt: r.deletedAt! + _retentionMs),
    ];
    out.sort((a, b) {
      final c = b.deletedAt.compareTo(a.deletedAt);
      return c != 0 ? c : a.ref.id.compareTo(b.ref.id);
    });
    return List.unmodifiable(out);
  }

  @override
  Stream<List<TrashItem>> watchTrash() => s.watches.watch(
    affects: (CommitTouch t) =>
        t.kinds.contains(EntityKind.folder) ||
        t.kinds.contains(EntityKind.note),
    query: _items,
    equals: const ListEquality<TrashItem>().equals,
  );

  // ---- restore ----------------------------------------------------------------------

  Future<FolderRow?> _folderRow(FolderId id) =>
      (_db.select(_db.folders)
            ..where((t) => t.id.equals(id) & t.ownerId.equals(_owner)))
          .getSingleOrNull();

  Future<NoteRow?> _noteRow(NoteId id) =>
      (_db.select(_db.notes)
            ..where((t) => t.id.equals(id) & t.ownerId.equals(_owner)))
          .getSingleOrNull();

  Future<List<FolderRow>> _groupFolders(String rootId) =>
      (_db.select(_db.folders)..where(
            (t) => t.ownerId.equals(_owner) & t.trashRootId.equals(rootId),
          ))
          .get();

  Future<List<NoteRow>> _groupNotes(String rootId) =>
      (_db.select(_db.notes)..where(
            (t) => t.ownerId.equals(_owner) & t.trashRootId.equals(rootId),
          ))
          .get();

  /// The nearest active ancestor of [parent] (walking up through trashed folders that
  /// still have rows); null = top level (chain broken or reached the top, 6.8).
  Future<FolderId?> _restoreParent(FolderId? parent, String rootId) async {
    final seen = <FolderId>{};
    while (parent != null && seen.add(parent)) {
      final p = await _folderRow(parent);
      if (p == null) return null;
      if (p.deletedAt == null && p.trashRootId != rootId) return parent;
      parent = p.parentId;
    }
    return null;
  }

  @override
  Future<void> restore(List<LibraryItemRef> items) => s.queue.run((tx) async {
    for (final ref in items.toSet()) {
      final rootId = ref.id;
      final Object? root = switch (ref) {
        FolderRef() => await _folderRow(rootId),
        NoteRef() => await _noteRow(rootId),
      };
      if (root == null) throw EntityNotFoundException('$rootId does not exist');
      final deleted = root is FolderRow
          ? root.deletedAt != null
          : (root as NoteRow).deletedAt != null;
      if (!deleted) continue;
      final parent = await _restoreParent(
        root is FolderRow ? root.parentId : (root as NoteRow).folderId,
        rootId,
      );
      for (final r in await _groupFolders(rootId)) {
        final f = folderOf(r);
        var next = f.copyWith(clearDeletedAt: true, clearTrashRootId: true);
        if (f.id == rootId && f.parentId != parent) {
          next = next.copyWith(
            parentId: parent,
            clearParentId: parent == null,
            sortKey: sortKeyAfterAll(await _activeFolderKeys(parent)),
          );
        }
        await _put(tx, f, next);
      }
      for (final r in await _groupNotes(rootId)) {
        final n = noteOf(r);
        var next = n.copyWith(clearDeletedAt: true, clearTrashRootId: true);
        if (n.id == rootId && n.folderId != parent) {
          next = next.copyWith(
            folderId: parent,
            clearFolderId: parent == null,
            sortKey: sortKeyAfterAll(await _activeNoteKeys(parent)),
          );
        }
        await _put(tx, n, next);
      }
    }
  });

  Future<List<String>> _activeFolderKeys(FolderId? parent) async {
    final f = _db.folders;
    final q = _db.selectOnly(f)
      ..addColumns([f.sortKey])
      ..where(
        f.ownerId.equals(_owner) &
            f.deletedAt.isNull() &
            (parent == null ? f.parentId.isNull() : f.parentId.equals(parent)),
      );
    return [for (final r in await q.get()) r.read(f.sortKey)!];
  }

  Future<List<String>> _activeNoteKeys(FolderId? parent) async {
    final n = _db.notes;
    final q = _db.selectOnly(n)
      ..addColumns([n.sortKey])
      ..where(
        n.ownerId.equals(_owner) &
            n.deletedAt.isNull() &
            (parent == null ? n.folderId.isNull() : n.folderId.equals(parent)),
      );
    return [for (final r in await q.get()) r.read(n.sortKey)!];
  }

  Future<void> _put(WriteTxn tx, SyncEntity before, SyncEntity next) async {
    final fields = changedJsonKeys(before, next);
    if (fields.isEmpty) return;
    final stamped = switch (next) {
      Folder() => next.copyWith(updatedAt: tx.now),
      Note() => next.copyWith(updatedAt: tx.now),
      _ => next,
    };
    await tx.putLocal(stamped, fields);
  }

  // ---- purge ------------------------------------------------------------------------

  /// Deletes the group of [rootId] (6.8 '영구 삭제'): folder / note rows, the notes'
  /// pages, strokes and recordings; one outbox purge per folder / note.
  Future<void> _purgeGroup(WriteTxn tx, String rootId) async {
    final folders = await _groupFolders(rootId);
    final notes = await _groupNotes(rootId);
    for (final f in folders) {
      await tx.purge(EntityRef(EntityKind.folder, f.id));
    }
    final noteIds = [for (final n in notes) n.id];
    final purgedPages = await deleteNoteContents(
      tx,
      noteIds,
      drafts: s.recordingDrafts,
    );
    for (final id in noteIds) {
      await tx.purge(EntityRef(EntityKind.note, id));
    }
    if (purgedPages.isNotEmpty) {
      tx.afterCommit(() => s.thumbnails.dropPurged(purgedPages));
    }
  }

  Future<bool> _isTrashedRoot(LibraryItemRef ref) async {
    final Object? root = switch (ref) {
      FolderRef(:final id) => await _folderRow(id),
      NoteRef(:final id) => await _noteRow(id),
    };
    return switch (root) {
      FolderRow(:final deletedAt) => deletedAt != null,
      NoteRow(:final deletedAt) => deletedAt != null,
      _ => false,
    };
  }

  @override
  Future<void> purge(List<LibraryItemRef> items) => s.queue.run((tx) async {
    for (final ref in items.toSet()) {
      if (!await _isTrashedRoot(ref)) continue;
      await _purgeGroup(tx, ref.id);
    }
  });

  @override
  Future<void> emptyTrash() => s.queue.run((tx) async {
    for (final item in await _items()) {
      await _purgeGroup(tx, item.ref.id);
    }
  });

  @override
  Future<int> purgeExpired() => s.queue.run((tx) async {
    var count = 0;
    for (final item in await _items()) {
      if (tx.now - item.deletedAt < _retentionMs) continue;
      await _purgeGroup(tx, item.ref.id);
      count++;
    }
    return count;
  });
}

/// Deletes the pages, strokes and recordings of [noteIds] and their pending outbox
/// entries (purge of a trash group, 6.8; RemotePurge, 6.10.3). The note rows stay.
/// Returns the deleted page ids (their thumbnails go after the commit).
/// (v2.0, m5-7/02-core 6.14.2 — CORE T29) also the page objects and handwriting results
/// (and their outbox entries), the notes' own search owners / units / FTS rows (pdf owners
/// are per asset and stay), and the recording draft rows — their chunks and meta
/// (`rd/<draftId>/`) are deleted after the commit by [drafts].
Future<List<PageId>> deleteNoteContents(
  WriteTxn tx,
  List<NoteId> noteIds, {
  DriftRecordingDraftStore? drafts,
}) async {
  final db = tx.db;
  final purgedPages = <PageId>[];
  final purgedDrafts = <String>[];
  for (final chunk in _chunks(noteIds)) {
    final pageIds = [
      for (final r
          in await (db.selectOnly(db.pages)
                ..addColumns([db.pages.id])
                ..where(db.pages.noteId.isIn(chunk)))
              .get())
        r.read(db.pages.id)!,
    ];
    purgedPages.addAll(pageIds);
    await (db.delete(db.strokes)..where((t) => t.noteId.isIn(chunk))).go();
    await (db.delete(db.pageObjects)..where((t) => t.noteId.isIn(chunk))).go();
    await (db.delete(db.handwriting)..where((t) => t.noteId.isIn(chunk))).go();
    // (v2.17-md, C217M-05) MD 문서 bodies and the conflict-copy record of the note.
    await (db.delete(db.mdDocs)..where((t) => t.noteId.isIn(chunk))).go();
    await (db.delete(db.kv)..where(
          (t) => t.key.isIn([for (final id in chunk) 'md.conflictCopy.$id']),
        ))
        .go();
    for (final pages in _chunks(pageIds)) {
      await (db.delete(db.strokes)..where((t) => t.pageId.isIn(pages))).go();
      // Rows of these pages whose note id is not (yet) the page's — remote orphans.
      await (db.delete(
        db.pageObjects,
      )..where((t) => t.pageId.isIn(pages))).go();
      await (db.delete(
        db.handwriting,
      )..where((t) => t.pageId.isIn(pages))).go();
      await (db.delete(db.outbox)..where(
            (t) =>
                t.entityKind.isIn([
                  EntityKind.stroke.name,
                  EntityKind.pageObject.name,
                  EntityKind.handwriting.name,
                ]) &
                t.pageId.isIn(pages),
          ))
          .go();
    }
    await (db.delete(db.pages)..where((t) => t.noteId.isIn(chunk))).go();
    await (db.delete(db.recordings)..where((t) => t.noteId.isIn(chunk))).go();
    await (db.delete(db.outbox)..where(
          (t) =>
              t.noteId.isIn(chunk) &
              t.entityKind.isIn([
                EntityKind.page.name,
                EntityKind.stroke.name,
                EntityKind.recording.name,
                EntityKind.pageObject.name,
                EntityKind.handwriting.name,
                EntityKind.markdown.name,
              ]),
        ))
        .go();
    // The notes' own search rows (text / math / ink — pdf units have no note id).
    final unitIds = [
      for (final r
          in await (db.selectOnly(db.searchUnits)
                ..addColumns([db.searchUnits.id])
                ..where(db.searchUnits.noteId.isIn(chunk)))
              .get())
        r.read(db.searchUnits.id)!,
    ];
    for (final ids in _chunks(unitIds)) {
      await db.customStatement(
        'DELETE FROM search_fts WHERE rowid IN '
        '(${List.filled(ids.length, '?').join(', ')})',
        ids,
      );
    }
    await (db.delete(db.searchUnits)..where((t) => t.noteId.isIn(chunk))).go();
    await (db.delete(db.searchOwners)..where((t) => t.noteId.isIn(chunk))).go();
    // Recording drafts: the rows now, the blobs after the commit.
    purgedDrafts.addAll([
      for (final r
          in await (db.selectOnly(db.recordingDrafts)
                ..addColumns([db.recordingDrafts.draftId])
                ..where(db.recordingDrafts.noteId.isIn(chunk)))
              .get())
        r.read(db.recordingDrafts.draftId)!,
    ]);
    await (db.delete(
      db.recordingDrafts,
    )..where((t) => t.noteId.isIn(chunk))).go();
  }
  if (noteIds.isNotEmpty) {
    tx
      ..touch(EntityKind.page)
      ..touch(EntityKind.stroke)
      ..touch(EntityKind.recording)
      ..touch(EntityKind.pageObject)
      ..touch(EntityKind.handwriting)
      ..touch(EntityKind.markdown)
      ..forgetPageNotes();
  }
  if (drafts != null && purgedDrafts.isNotEmpty) {
    tx.afterCommit(() => drafts.dropPurged(purgedDrafts));
  }
  return purgedPages;
}
