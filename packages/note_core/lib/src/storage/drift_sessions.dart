// lib/src/storage/drift_sessions.dart (internal) — note sessions of the SQLite store
// (CORE 6.14, contract 7.2.8 N-1..N-7).
//
// Each open note has one SessionEngine (N-5) on a DB backend: openPage loads the page's
// active strokes and (v2.0) page objects in one read transaction after the queued writes
// commit (m5-7/02-core 6.5); edits are written through the write queue with the versions
// the engine stamped (memory and rows agree, 6.7.6). After every commit the store calls
// [DriftSessions.committed]: a note row change of an open note (rename, trash, restore —
// N-4) reaches the session, and remote writes of its pages / strokes / (v2.0) page objects
// are read back and applied (N-7). Rows with a session write that is still queued are left
// alone: that write commits later and the memory already holds it.
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';

import '../common/errors.dart';
import '../common/ids.dart';
import '../common/sort_keys.dart';
import '../model/page.dart';
import '../model/stroke.dart';
import '../model/sync_entity.dart';
import '../repo/events.dart';
import '../session/note_session.dart';
import '../session/page_content.dart';
import '../session/session_backend.dart';
import '../session/session_engine.dart';
import '../sync/outbox_types.dart';
import 'db/note_database.dart';
import 'drift_note_store.dart';
import 'row_mappers.dart';
import 'write_queue.dart';

/// Ids per `IN (...)` list (SQLite variable limit).
const int _inChunk = 500;

Iterable<List<T>> _chunks<T>(List<T> items) sync* {
  for (var i = 0; i < items.length; i += _inChunk) {
    yield items.sublist(
      i,
      i + _inChunk > items.length ? items.length : i + _inChunk,
    );
  }
}

final class DriftSessions {
  DriftSessions(this.s);
  final DriftNoteStore s;

  final Map<NoteId, SessionEngine> _open = {};
  final Map<NoteId, Future<SessionEngine>> _opening = {};

  /// Session writes queued but not committed yet, per entity.
  final Map<EntityRef, int> _uncommitted = {};

  NoteDatabase get _db => s.db;

  /// N-5 / N-6: the live session of [noteId] (one reference more), or a new one.
  Future<NoteSession> open(NoteId noteId, NoteSessionOptions options) async {
    final SessionEngine session;
    final live = _open[noteId];
    final pending = _opening[noteId];
    if (live != null && !live.isClosed) {
      session = live..retain();
    } else if (pending != null) {
      session = (await pending)..retain();
    } else {
      final created = _create(noteId, options);
      _opening[noteId] = created;
      try {
        session = await created;
      } finally {
        unawaited(_opening.remove(noteId)?.then((_) {}, onError: (_) {}));
      }
      _open[noteId] = session;
    }
    // N-6: CORE is the only writer of 'recent'. The commit is not awaited.
    unawaited(
      s.library.markOpened(noteId).then<void>((_) {}, onError: (Object _) {}),
    );
    return session;
  }

  Future<SessionEngine> _create(
    NoteId noteId,
    NoteSessionOptions options,
  ) async {
    final row = await (_db.select(
      _db.notes,
    )..where((t) => t.id.equals(noteId))).getSingleOrNull();
    if (row == null || row.ownerId != s.ownerId) {
      throw EntityNotFoundException('Note $noteId does not exist');
    }
    // A newer schema opens read-only (Note.requiresNewerApp, N-4). An older one is
    // migrated first (6.15); when that fails the note stays at its version and the
    // session is read-only (SessionEngine.isReadOnly) — not an open failure.
    var note = noteOf(row);
    if (note.schemaVersion < kNoteSchemaVersion) {
      try {
        note = await s.noteMigrator.migrateIfNeeded(noteId);
      } on Object {
        // Read-only below; the note keeps its rows.
      }
    }
    final pages = await (_db.select(
      _db.pages,
    )..where((t) => t.noteId.equals(noteId) & t.deletedAt.isNull())).get();
    return SessionEngine(
      note: note,
      pages: [for (final p in pages) pageOf(p)],
      backend: _DriftSessionBackend(this, noteId),
      options: options,
      hlc: s.hlc,
      clock: s.clock,
      ids: s.ids,
    );
  }

  void _closed(NoteId noteId) {
    final live = _open[noteId];
    if (live != null && live.isClosed) _open.remove(noteId);
  }

  /// The store closes: sessions are forgotten (their writes fail from now on).
  void clear() => _open.clear();

  void _hold(Iterable<EntityRef> refs) {
    for (final r in refs) {
      _uncommitted.update(r, (n) => n + 1, ifAbsent: () => 1);
    }
  }

  void _release(Iterable<EntityRef> refs) {
    for (final r in refs) {
      final n = (_uncommitted[r] ?? 1) - 1;
      if (n <= 0) {
        _uncommitted.remove(r);
      } else {
        _uncommitted[r] = n;
      }
    }
  }

  bool _held(EntityKind kind, String id) =>
      _uncommitted.containsKey(EntityRef(kind, id));

  /// After a commit (WriteQueue.onCommitted): note rows of open notes reach their
  /// sessions; remote page / stroke / (v2.0) page object writes are read back (N-4, N-7).
  Future<void> committed(List<ChangeBatch> batches) async {
    if (_open.isEmpty) return;
    final touched = <NoteId, _Touched>{};
    for (final b in batches) {
      final remote = b.origin == ChangeOrigin.remote;
      for (final c in b.changes) {
        final noteId = c.kind == EntityKind.note ? c.id : c.noteId;
        if (noteId == null || !_open.containsKey(noteId)) continue;
        final t = touched[noteId] ??= _Touched();
        switch (c.kind) {
          case EntityKind.note:
            t.note = true;
          case EntityKind.page when remote:
            t.remote = true;
            t.pages.add(c.id);
          case EntityKind.stroke when remote && c.pageId != null:
            t.remote = true;
            t.strokes[c.id] = c.pageId!;
          // (v2.0) page objects carry noteId and pageId hints always (02-core 6.13).
          case EntityKind.pageObject when remote && c.pageId != null:
            t.remote = true;
            t.objects[c.id] = c.pageId!;
          default:
            break;
        }
      }
    }
    for (final MapEntry(key: noteId, value: t) in touched.entries) {
      final session = _open[noteId];
      if (session == null || session.isClosed) continue;
      final noteRow = await (_db.select(
        _db.notes,
      )..where((r) => r.id.equals(noteId))).getSingleOrNull();
      // A purged note (trash purge, RemotePurge) keeps its last state, read-only (6.10.3).
      final note = noteRow != null
          ? noteOf(noteRow)
          : session.note.isDeleted
          ? null
          : session.note.copyWith(
              deletedAt: s.clock.now().millisecondsSinceEpoch,
            );
      if (!t.remote) {
        if (note != null) session.noteCommitted(note);
        continue;
      }
      final pages = <PageId, Page?>{
        for (final id in t.pages)
          if (!_held(EntityKind.page, id)) id: null,
      };
      for (final chunk in _chunks(pages.keys.toList())) {
        for (final r in await (_db.select(
          _db.pages,
        )..where((p) => p.id.isIn(chunk))).get()) {
          pages[r.id] = pageOf(r);
        }
      }
      final strokes = <ElementId, (PageId, Stroke?)>{
        for (final MapEntry(key: id, value: pageId) in t.strokes.entries)
          if (!_held(EntityKind.stroke, id) &&
              session.pageIfLoaded(pageId) != null)
            id: (pageId, null),
      };
      for (final chunk in _chunks(strokes.keys.toList())) {
        for (final r in await (_db.select(
          _db.strokes,
        )..where((st) => st.id.isIn(chunk))).get()) {
          strokes[r.id] = (strokes[r.id]!.$1, strokeOf(r));
        }
      }
      final objects = <ElementId, (PageId, PageObject?)>{
        for (final MapEntry(key: id, value: pageId) in t.objects.entries)
          if (!_held(EntityKind.pageObject, id) &&
              session.pageIfLoaded(pageId) != null)
            id: (pageId, null),
      };
      for (final chunk in _chunks(objects.keys.toList())) {
        for (final r in await (_db.select(
          _db.pageObjects,
        )..where((o) => o.id.isIn(chunk))).get()) {
          objects[r.id] = (objects[r.id]!.$1, pageObjectOf(r));
        }
      }
      session.remoteCommitted(
        note: note,
        pages: pages,
        strokes: strokes,
        objects: objects,
        contentPages: {...t.strokes.values, ...t.objects.values},
      );
    }
  }
}

final class _Touched {
  bool note = false;
  bool remote = false;
  final Set<PageId> pages = {};
  final Map<ElementId, PageId> strokes = {};
  final Map<ElementId, PageId> objects = {};
}

final class _DriftSessionBackend implements SessionBackend {
  _DriftSessionBackend(this._sessions, this._noteId);
  final DriftSessions _sessions;
  final NoteId _noteId;

  DriftNoteStore get _s => _sessions.s;
  NoteDatabase get _db => _s.db;

  @override
  Future<({List<Stroke> strokes, List<PageObject> objects})> loadContent(
    PageId pageId,
  ) async {
    await _s.queue.flush();
    return readActiveContent(_db, pageId);
  }

  @override
  Future<void> write(SessionWrite w) {
    final refs = [for (final e in w.entities) EntityRef(e.kind, e.id)];
    _sessions._hold(refs);
    var released = false;
    void release() {
      if (released) return;
      released = true;
      _sessions._release(refs);
    }

    var bytes = 0;
    for (final e in w.entities) {
      if (e is Stroke) bytes += e.points.length * 8;
      if (e is PageObject) bytes += e.estimatedBytes;
    }
    return _s.queue
        .run(
          (tx) async {
            for (final e in w.entities) {
              await tx.putLocal(
                e,
                w.changedFields[EntityRef(e.kind, e.id)] ?? const {kAllFields},
                strokeNoteId: _noteId,
                fixedVersion: e.version,
              );
            }
            for (final p in w.localPages) {
              await (_db.update(_db.pages)..where((t) => t.id.equals(p.id)))
                  .write(PagesCompanion(contentRev: Value(p.contentRevision)));
            }
            if (w.localPages.isNotEmpty) tx.touch(EntityKind.page);
            await refreshNoteDerived(tx, _noteId, updatedAt: w.note.updatedAt);
            tx.afterCommit(release);
          },
          origin: w.origin,
          bytes: bytes,
        )
        .whenComplete(release);
  }

  @override
  Future<void> flush() => _s.queue.flush();

  @override
  void sessionClosed(NoteId noteId) => _sessions._closed(noteId);
}

/// Local derived values of note [noteId] (C-9, 6.10.3 (c)): page count and first
/// active page from the page rows, updatedAt = max(current, [updatedAt]). A local
/// write: no version, no outbox; the note is listed in the commit's ChangeBatch.
Future<void> refreshNoteDerived(
  WriteTxn tx,
  NoteId noteId, {
  EpochMillis? updatedAt,
}) async {
  final db = tx.db;
  final row = await (db.select(
    db.notes,
  )..where((t) => t.id.equals(noteId))).getSingleOrNull();
  if (row == null) return;
  final p = db.pages;
  final pages = [
    for (final r
        in await (db.selectOnly(p)
              ..addColumns([p.id, p.sortKey])
              ..where(p.noteId.equals(noteId) & p.deletedAt.isNull()))
            .get())
      (id: r.read(p.id)!, sortKey: r.read(p.sortKey)!),
  ];
  final first = pages
      .sorted((a, b) => compareSortKeyThenId(a.sortKey, a.id, b.sortKey, b.id))
      .firstOrNull;
  final nextUpdated = updatedAt != null && updatedAt > row.updatedAt
      ? updatedAt
      : row.updatedAt;
  if (row.pageCount == pages.length &&
      row.firstPageId == first?.id &&
      row.updatedAt == nextUpdated) {
    return;
  }
  await (db.update(db.notes)..where((t) => t.id.equals(noteId))).write(
    NotesCompanion(
      pageCount: Value(pages.length),
      firstPageId: Value(first?.id),
      updatedAt: Value(nextUpdated),
    ),
  );
  tx
    ..touch(EntityKind.note)
    ..addChange(EntityChange(kind: EntityKind.note, id: noteId));
}

/// The active strokes and (v2.0) page objects of [pageId], each in Stroke.compareOrder, in
/// one read transaction (m5-7/02-core 6.5: a remote commit cannot fall between the two
/// reads). Session loads (after a queue flush) and NoteContentReader.loadPage share it.
Future<({List<Stroke> strokes, List<PageObject> objects})> readActiveContent(
  NoteDatabase db,
  PageId pageId,
) => db.transaction(() async {
  final strokes = await (db.select(
    db.strokes,
  )..where((t) => t.pageId.equals(pageId) & t.deletedAt.isNull())).get();
  final objects = await (db.select(
    db.pageObjects,
  )..where((t) => t.pageId.equals(pageId) & t.deletedAt.isNull())).get();
  return (
    strokes: [for (final r in strokes) strokeOf(r)]..sort(Stroke.compareOrder),
    objects: [for (final r in objects) pageObjectOf(r)]
      ..sort(Stroke.compareOrder),
  );
});
