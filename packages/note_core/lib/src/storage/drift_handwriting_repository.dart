// lib/src/storage/drift_handwriting_repository.dart (internal) — HandwritingRepository on SQLite
// (m5-7/02-core 6.9, contract 7.2.5). Same meaning as the fake store's handwriting
// (test/shared/handwriting_contract.dart runs on both).
//
// Writes go through the write queue (putLocal: field versions, outbox, ChangeBatch(local)).
// Results are outside undo history (R-8). update runs read → transform → write as ONE queue
// job (= one write transaction): no other put / update / remote apply comes in between (G-4).
//
// stalePages / notesWithStalePages use the device-local page cache columns pages.ink_rev
// (sourceRevOf of the page's input strokes) and pages.ink_rev_at (the content_rev it was
// computed at — 6.9.3): only pages whose content_rev moved are read again (stroke id,
// updated_at and tool — never the points), the cache is written by a queue job of its own
// (no version, no outbox, no ChangeBatch). content_rev rises with every stroke / object
// change (local, undo, remote).
//
// CORE T33a adds the ink search units (put / update / removeForPage re-index the page in a
// savepoint of the same transaction — 6.10.3).
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../common/errors.dart';
import '../common/ids.dart';
import '../common/source_rev.dart';
import '../common/write_guard.dart';
import '../model/handwriting.dart';
import '../model/pen_style.dart';
import '../model/sync_entity.dart';
import '../repo/handwriting_repository.dart';
import '../sync/outbox_types.dart';
import 'db/note_database.dart';
import 'drift_note_store.dart';
import 'entity_diff.dart';
import 'outbox_writer.dart';
import 'row_mappers.dart';
import 'watch_hub.dart';
import 'write_queue.dart';

/// Pages per stroke read of the ink_rev refresh (6.9.3); the cache write of each chunk is one
/// queue job, so other writes interleave during a long catch-up.
const int kInkRefreshChunk = 50;

/// Stroke tools that are not recognition input (HandwritingText.isRecognitionInput).
final Set<String> _nonInputTools = {
  PenTool.highlighter.wireName,
  PenTool.tape.wireName,
  PenTool.laser.wireName,
};

/// A page row's cache columns (6.9.3).
typedef _PageInk = ({PageId id, int contentRev, String? inkRev, int? inkRevAt});

/// What one update job ended with: the stored value, or the transform's own error (it wrote
/// nothing, so the job itself succeeds — any exception, not only domain errors, ends the call
/// without a commit retry).
typedef _UpdateOutcome = ({
  HandwritingText? value,
  Object? error,
  StackTrace? stack,
});

final class DriftHandwritingRepository implements HandwritingRepository {
  DriftHandwritingRepository(this.s);
  final DriftNoteStore s;

  NoteDatabase get _db => s.db;

  /// Tests: pages whose ink_rev cache was recomputed (their stroke rows read) so far.
  @visibleForTesting
  int debugInkRefreshedPages = 0;

  Future<HandwritingText?> _row(PageId pageId) async {
    final r =
        await (_db.select(_db.handwriting)
              ..where((t) => t.id.equals(HandwritingText.idFor(pageId))))
            .getSingleOrNull();
    return r == null ? null : handwritingOf(r);
  }

  Future<HandwritingText?> _active(PageId pageId) async {
    final h = await _row(pageId);
    return h == null || h.isDeleted ? null : h;
  }

  @override
  Future<HandwritingText?> forPage(PageId pageId) => _active(pageId);

  @override
  Stream<HandwritingText?> watchPage(PageId pageId) => s.watches.watch(
    affects: (CommitTouch t) => t.kinds.contains(EntityKind.handwriting),
    query: () => _active(pageId),
  );

  /// put / update validation (6.9.4). [pageNoteId]: the note of the page row (null = none).
  static void _check(HandwritingText value, NoteId? pageNoteId) {
    if (pageNoteId == null) {
      throw EntityNotFoundException('Page ${value.pageId} does not exist');
    }
    if (pageNoteId != value.noteId) {
      throw ArgumentError.value(
        value.noteId,
        'noteId',
        'page ${value.pageId} belongs to note $pageNoteId',
      );
    }
    for (final l in value.lines) {
      if (l.alternatives.length > 5) {
        throw ArgumentError.value(
          l.alternatives.length,
          'alternatives',
          'at most 5',
        );
      }
      if (l.languageTag.isEmpty) {
        throw ArgumentError.value(l.languageTag, 'languageTag', 'empty');
      }
    }
  }

  /// Writes [value] over [stored] (the row, deleted or not; null = none): a new row → `{*}`,
  /// otherwise only the JSON keys that differ (a deleted row is revived — deletedAt cleared).
  /// An existing row keeps its createdAt; updatedAt = the transaction time. No synced key
  /// differs from an active row → nothing is written and [stored] is returned.
  Future<HandwritingText> _store(
    WriteTxn tx,
    HandwritingText value,
    HandwritingText? stored,
  ) async {
    final candidate = HandwritingText(
      noteId: value.noteId,
      pageId: value.pageId,
      engineId: value.engineId,
      sourceRev: value.sourceRev,
      lines: value.lines,
      createdAt: stored?.createdAt ?? value.createdAt,
      updatedAt: tx.now,
    );
    if (stored == null) {
      final versions = await tx.putLocal(candidate, const {
        kAllFields,
      }, isNew: true);
      return candidate.copyWith(version: versions.max);
    }
    final fields = changedJsonKeys(stored, candidate);
    if (!stored.isDeleted &&
        syncedFieldsOf(EntityKind.handwriting, fields).isEmpty) {
      return stored;
    }
    final versions = await tx.putLocal(candidate, fields);
    return candidate.copyWith(version: versions.max);
  }

  @override
  Future<void> put(HandwritingText value) => s.queue.run((tx) async {
    _check(value, await tx.noteIdOfPage(value.pageId));
    await _store(tx, value, await _row(value.pageId));
  });

  @override
  Future<HandwritingText?> update(
    PageId pageId,
    HandwritingText? Function(HandwritingText? current) transform,
  ) async {
    final outcome = await s.queue.run<_UpdateOutcome>((tx) async {
      final pageNoteId = await tx.noteIdOfPage(pageId);
      if (pageNoteId == null) {
        throw EntityNotFoundException('Page $pageId does not exist');
      }
      final stored = await _row(pageId);
      final current = stored == null || stored.isDeleted ? null : stored;
      final HandwritingText? next;
      try {
        next = runUpdateTransform(() => transform(current));
      } on Object catch (e, st) {
        return (value: null, error: e, stack: st);
      }
      if (next == null) return (value: current, error: null, stack: null);
      if (next.pageId != pageId) {
        throw ArgumentError.value(next.pageId, 'pageId', 'must be $pageId');
      }
      _check(next, pageNoteId);
      return (value: await _store(tx, next, stored), error: null, stack: null);
    });
    if (outcome.error case final e?) {
      Error.throwWithStackTrace(e, outcome.stack!);
    }
    return outcome.value;
  }

  @override
  Future<void> removeForPage(PageId pageId) => s.queue.run((tx) async {
    final cur = await _row(pageId);
    if (cur == null || cur.isDeleted) return;
    await tx.putLocal(
      cur.copyWith(deletedAt: tx.now, updatedAt: tx.now),
      const {'deletedAt', 'updatedAt'},
    );
  });

  // ---- stalePages · notesWithStalePages (6.9.3) ----------------------------------------

  static bool _stale(String inkRev, String? storedRev) =>
      storedRev == null ? inkRev != kEmptySourceRev : inkRev != storedRev;

  /// The input-stroke sourceRev of each page of [pages]: the cache when it was computed at
  /// the page's content_rev, otherwise recomputed from the stroke rows ([kInkRefreshChunk]
  /// pages per read) and written back (only if content_rev has not moved meanwhile).
  Future<Map<PageId, String>> _refresh(List<_PageInk> pages) async {
    final revs = <PageId, String>{};
    final dirty = <_PageInk>[];
    for (final p in pages) {
      if (p.inkRev case final rev? when p.inkRevAt == p.contentRev) {
        revs[p.id] = rev;
      } else {
        dirty.add(p);
      }
    }
    for (var i = 0; i < dirty.length; i += kInkRefreshChunk) {
      final chunk = dirty.sublist(
        i,
        math.min(i + kInkRefreshChunk, dirty.length),
      );
      // The input strokes of each page joined in SQL ("<id>:<updatedAt>;" in id order — the
      // text sourceRevOf hashes): only one row per page crosses into Dart, the points are
      // never decoded (6.9.3; aggregate ORDER BY — SQLite ≥ 3.44, the bundled 3.54 on every
      // platform). Pages without input strokes have no row (the empty hash).
      final joined = {
        for (final r
            in await _db
                .customSelect(
                  'SELECT page_id AS page_id, '
                  "group_concat(id || ':' || updated_at || ';', '' ORDER BY id) AS joined "
                  'FROM strokes WHERE page_id IN '
                  '(${List.filled(chunk.length, '?').join(', ')}) '
                  'AND deleted_at IS NULL AND tool NOT IN '
                  '(${List.filled(_nonInputTools.length, '?').join(', ')}) '
                  'GROUP BY page_id',
                  variables: [
                    for (final p in chunk) Variable<String>(p.id),
                    for (final t in _nonInputTools) Variable<String>(t),
                  ],
                  readsFrom: {_db.strokes},
                )
                .get())
          r.read<String>('page_id'): r.read<String>('joined'),
      };
      for (final p in chunk) {
        final text = joined[p.id];
        revs[p.id] = text == null ? kEmptySourceRev : sourceRevOfJoined(text);
      }
      debugInkRefreshedPages += chunk.length;
    }
    if (dirty.isNotEmpty) await _writeInkCache(dirty, revs);
    return revs;
  }

  /// Writes the recomputed cache of [pages] as ONE queue job (one commit — a catch-up over a
  /// whole library must not pay a commit per chunk), [kInkRefreshChunk] rows per statement;
  /// a row only where content_rev has not moved since the page row was read.
  Future<void> _writeInkCache(
    List<_PageInk> pages,
    Map<PageId, String> revs,
  ) => s.queue.run((tx) async {
    for (var i = 0; i < pages.length; i += kInkRefreshChunk) {
      final chunk = pages.sublist(
        i,
        math.min(i + kInkRefreshChunk, pages.length),
      );
      await tx.db.customUpdate(
        'UPDATE pages SET ink_rev = v.column2, ink_rev_at = v.column3 '
        'FROM (VALUES ${List.filled(chunk.length, '(?, ?, ?)').join(', ')}) AS v '
        'WHERE pages.id = v.column1 AND pages.content_rev = v.column3',
        variables: [
          for (final p in chunk) ...[
            Variable<String>(p.id),
            Variable<String>(revs[p.id]!),
            Variable<int>(p.contentRev),
          ],
        ],
      );
    }
  });

  /// A page row of the cache queries (columns id, content_rev, ink_rev, ink_rev_at).
  static _PageInk _pageInkOfRow(QueryRow r) => (
    id: r.read<String>('id'),
    contentRev: r.read<int>('content_rev'),
    inkRev: r.readNullable<String>('ink_rev'),
    inkRevAt: r.readNullable<int>('ink_rev_at'),
  );

  @override
  Future<List<PageId>> stalePages(NoteId noteId) async {
    final n = _db.notes;
    final owner =
        await (_db.selectOnly(n)
              ..addColumns([n.ownerId])
              ..where(n.id.equals(noteId)))
            .getSingleOrNull();
    if (owner == null || owner.read(n.ownerId) != s.ownerId) return const [];
    final pages = [
      for (final r
          in await _db
              .customSelect(
                'SELECT id AS id, content_rev AS content_rev, ink_rev AS ink_rev, '
                'ink_rev_at AS ink_rev_at FROM pages '
                'WHERE note_id = ?1 AND deleted_at IS NULL ORDER BY sort_key, id',
                variables: [Variable<String>(noteId)],
                readsFrom: {_db.pages},
              )
              .get())
        _pageInkOfRow(r),
    ];
    if (pages.isEmpty) return const [];
    final revs = await _refresh(pages);
    final stored = {
      for (final r
          in await _db
              .customSelect(
                'SELECT page_id AS page_id, source_rev AS source_rev FROM handwriting '
                'WHERE note_id = ?1 AND deleted_at IS NULL',
                variables: [Variable<String>(noteId)],
                readsFrom: {_db.handwriting},
              )
              .get())
        r.read<String>('page_id'): r.read<String>('source_rev'),
    };
    return List.unmodifiable([
      for (final page in pages)
        if (_stale(revs[page.id]!, stored[page.id])) page.id,
    ]);
  }

  @override
  Future<List<NoteId>> notesWithStalePages() async {
    // 1–2. Active pages of the owner's active notes whose cache is out of date, refreshed.
    final dirty = await _db
        .customSelect(
          'SELECT p.id AS id, p.content_rev AS content_rev, p.ink_rev AS ink_rev, '
          'p.ink_rev_at AS ink_rev_at FROM pages p JOIN notes n ON n.id = p.note_id '
          'WHERE n.owner_id = ?1 AND n.deleted_at IS NULL AND p.deleted_at IS NULL '
          'AND (p.ink_rev IS NULL OR p.ink_rev_at IS NULL '
          'OR p.ink_rev_at != p.content_rev)',
          variables: [Variable<String>(s.ownerId)],
          readsFrom: {_db.pages, _db.notes},
        )
        .get();
    await _refresh([for (final r in dirty) _pageInkOfRow(r)]);
    // 3–4. One query over the cache: notes with a page whose input differs from its result
    // (or that has input and no result), most recently updated first.
    final rows = await _db
        .customSelect(
          'SELECT n.id AS id FROM notes n '
          'WHERE n.owner_id = ?1 AND n.deleted_at IS NULL AND EXISTS ('
          'SELECT 1 FROM pages p LEFT JOIN handwriting h '
          "ON h.id = 'hw_' || p.id AND h.deleted_at IS NULL "
          'WHERE p.note_id = n.id AND p.deleted_at IS NULL AND ('
          '(h.id IS NULL AND p.ink_rev != ?2) OR '
          '(h.id IS NOT NULL AND p.ink_rev != h.source_rev))) '
          'ORDER BY n.updated_at DESC, n.id ASC',
          variables: [
            Variable<String>(s.ownerId),
            const Variable<String>(kEmptySourceRev),
          ],
          readsFrom: {_db.notes, _db.pages, _db.handwriting},
        )
        .get();
    return List.unmodifiable([for (final r in rows) r.read<String>('id')]);
  }
}
