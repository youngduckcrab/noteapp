// lib/src/migration/note_migrator.dart (internal, exposed for tests) — note content
// format migration (CORE 6.15).
//
// A note whose schemaVersion is below kNoteSchemaVersion is migrated lazily when it
// is opened: the steps v → v+1 run in ONE write-queue transaction, the pages / strokes
// they put are written as local writes (changed JSON keys → field versions, outbox)
// and the note gets kNoteSchemaVersion. A step that throws (or a missing step) rolls
// everything back without retry; the caller opens the note read-only (it stays at
// its old version, SessionEngine.isReadOnly). A note from a newer app is never
// touched (Note.requiresNewerApp, N-4).

import '../common/errors.dart';
import '../common/ids.dart';
import '../edit/command_resolver.dart';
import '../model/note.dart';
import '../model/page.dart';
import '../model/stroke.dart';
import '../model/sync_entity.dart';
import '../storage/drift_note_store.dart';
import '../storage/entity_diff.dart';
import '../storage/row_mappers.dart';
import '../storage/write_queue.dart';
import '../sync/outbox_types.dart';

typedef NoteMigrationStep = Future<void> Function(NoteMigrationContext ctx);

/// What a step sees: the note at the step's source version, its pages and strokes
/// (soft-deleted included, with the puts of earlier steps applied), and buffers for
/// the rewritten ones.
abstract interface class NoteMigrationContext {
  Note get note;
  Future<List<Page>> pages();
  Future<List<Stroke>> strokesOf(PageId pageId);
  void putPage(Page page);
  void putStroke(Stroke stroke);
}

/// The steps of this app: none yet (kNoteSchemaVersion 1 is the first format).
const Map<int, NoteMigrationStep> kNoteMigrationSteps = {};

/// A step's error carried out of the write job as a domain error (no retry).
final class _StepFailure extends Error {
  _StepFailure(this.error, this.trace);
  final Object error;
  final StackTrace trace;
}

final class NoteMigrator {
  /// [steps]: key = source version v (the step migrates v → v + 1).
  NoteMigrator(Map<int, NoteMigrationStep> steps, {required this.store})
    : _steps = Map.unmodifiable(steps);

  final DriftNoteStore store;
  final Map<int, NoteMigrationStep> _steps;

  /// The note after migration (unchanged when it is current or newer). Throws
  /// EntityNotFoundException without a row, the step's error when a step fails and
  /// StateError when a step is missing — nothing is written then.
  Future<Note> migrateIfNeeded(NoteId noteId) async {
    final note = await _read(noteId);
    if (note.schemaVersion >= kNoteSchemaVersion) return note;
    try {
      return await store.queue.run((tx) async {
        final current = await _read(noteId);
        if (current.schemaVersion >= kNoteSchemaVersion) return current;
        final ctx = _Context(store, tx, current);
        for (var v = current.schemaVersion; v < kNoteSchemaVersion; v++) {
          final step = _steps[v];
          if (step == null) {
            throw StateError('No note migration step from version $v');
          }
          ctx.note = current.copyWith(schemaVersion: v);
          try {
            await step(ctx);
          } on Object catch (e, s) {
            throw _StepFailure(e, s);
          }
        }
        await ctx.writeAll();
        final next = current.copyWith(
          schemaVersion: kNoteSchemaVersion,
          updatedAt: tx.now > current.updatedAt ? tx.now : current.updatedAt,
        );
        final versions = await tx.putLocal(next, const {'schemaVersion'});
        return next.copyWith(version: versions.max);
      });
    } on _StepFailure catch (f) {
      Error.throwWithStackTrace(f.error, f.trace);
    }
  }

  Future<Note> _read(NoteId noteId) async {
    final db = store.db;
    final row = await (db.select(
      db.notes,
    )..where((t) => t.id.equals(noteId))).getSingleOrNull();
    if (row == null) {
      throw EntityNotFoundException('Note $noteId does not exist');
    }
    return noteOf(row);
  }
}

final class _Context implements NoteMigrationContext {
  _Context(this.store, this.tx, this.note);

  final DriftNoteStore store;
  final WriteTxn tx;
  @override
  Note note;

  /// Rows as read (null = not in the database) and the puts, by id.
  final Map<PageId, Page?> _pageRows = {};
  final Map<ElementId, Stroke?> _strokeRows = {};
  final Map<PageId, Page> _pages = {};
  final Map<ElementId, Stroke> _strokes = {};

  @override
  Future<List<Page>> pages() async {
    final db = store.db;
    final rows = await (db.select(
      db.pages,
    )..where((t) => t.noteId.equals(note.id))).get();
    for (final r in rows) {
      _pageRows.putIfAbsent(r.id, () => pageOf(r));
    }
    final out = {
      for (final r in rows) r.id: _pages[r.id] ?? pageOf(r),
      for (final p in _pages.values) p.id: p,
    };
    return [...out.values]..sort(comparePages);
  }

  @override
  Future<List<Stroke>> strokesOf(PageId pageId) async {
    final db = store.db;
    final rows = await (db.select(
      db.strokes,
    )..where((t) => t.pageId.equals(pageId))).get();
    for (final r in rows) {
      _strokeRows.putIfAbsent(r.id, () => strokeOf(r));
    }
    final out = {
      for (final r in rows) r.id: _strokes[r.id] ?? strokeOf(r),
      for (final s in _strokes.values)
        if (s.pageId == pageId) s.id: s,
    };
    return [...out.values];
  }

  @override
  void putPage(Page page) {
    if (page.noteId != note.id) {
      throw ArgumentError.value(page.id, 'page', 'not a page of ${note.id}');
    }
    _pages[page.id] = page;
  }

  @override
  void putStroke(Stroke stroke) => _strokes[stroke.id] = stroke;

  /// Local writes of the puts: only the JSON keys that changed (new rows: '*').
  Future<void> writeAll() async {
    final db = store.db;
    for (final p in _pages.values) {
      final before = _pageRows.containsKey(p.id)
          ? _pageRows[p.id]
          : await _readPage(p.id);
      await _put(before, p);
    }
    final pageIds = {
      for (final r
          in await (db.selectOnly(db.pages)
                ..addColumns([db.pages.id])
                ..where(db.pages.noteId.equals(note.id)))
              .get())
        r.read(db.pages.id)!,
    };
    for (final s in _strokes.values) {
      if (!pageIds.contains(s.pageId)) {
        throw ArgumentError.value(
          s.id,
          'stroke',
          'not on a page of ${note.id}',
        );
      }
      final before = _strokeRows.containsKey(s.id)
          ? _strokeRows[s.id]
          : await _readStroke(s.id);
      await _put(before, s, strokeNoteId: note.id);
    }
  }

  Future<void> _put(
    SyncEntity? before,
    SyncEntity after, {
    NoteId? strokeNoteId,
  }) async {
    final fields = before == null
        ? const {kAllFields}
        : changedJsonKeys(before, after);
    if (fields.isEmpty) return;
    await tx.putLocal(
      after,
      fields,
      strokeNoteId: strokeNoteId,
      isNew: before == null,
    );
  }

  Future<Page?> _readPage(PageId id) async {
    final db = store.db;
    final r = await (db.select(
      db.pages,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return r == null ? null : pageOf(r);
  }

  Future<Stroke?> _readStroke(ElementId id) async {
    final db = store.db;
    final r = await (db.select(
      db.strokes,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return r == null ? null : strokeOf(r);
  }
}
