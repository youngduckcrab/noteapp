// lib/src/storage/search_indexer.dart (internal) — the search index rows inside CORE write
// transactions (m5-7/02-core 6.10.3, 6.10.5).
//
// Owners: search_owners (source, owner_key) → note / page, sourceRev, pending. Units:
// search_units (id = rowid = the search_fts rowid; a new row is 'the current maximum + 1', so
// re-indexed content is the most recent — 6.10.4) with one search_fts row each (g = the index
// terms of the unit's norm). No outbox, no versions, no ChangeBatch: the index is device-local
// derived data.
//
// ink / text / math owners are re-indexed by the write hook of WriteTxn.putLocal / putRemote
// (text box and math objects, handwriting results; shapes, images and unknown objects have no
// text) in a SAVEPOINT of the source write: a failure rolls back only that savepoint, marks the
// owner pending and the source write commits (C-13). Pending owners are re-indexed at the end of
// the next write transaction (at most [kSearchRetryPerTransaction]) and by one queue job at
// store open — never by a timer. pdf owners are written by DriftSearchIndex (SearchIndexWriter)
// with the same row functions, outside any source write (a failure fails that call).
import 'dart:developer' as developer;

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../common/geometry.dart';
import '../common/hlc.dart';
import '../common/ids.dart';
import '../model/handwriting.dart';
import '../model/stroke.dart';
import '../model/sync_entity.dart';
import '../search/search_spacing.dart';
import '../search/search_text.dart';
import '../search/search_types.dart';
import 'db/note_database.dart';
import 'row_mappers.dart';
import 'write_queue.dart';

/// Pending owners re-indexed at the end of one write transaction (6.10.5).
const int kSearchRetryPerTransaction = 20;

/// Rows per statement of an `IN (…)` list.
const int _inChunk = 500;

/// One unit row to write: non-pdf units keep one rectangle in page pt ([rect]), pdf units a
/// blob key of their glyph boxes ([rectsRef]) and the PDF page aspect.
typedef SearchUnitRowDraft = ({
  String body,
  PageRect? rect,
  String? rectsRef,
  double? pdfAspect,
});

/// The search source of a page object that carries text (null: none — not indexed).
SearchSource? searchSourceOfObject(PageObject o) => switch (o) {
  TextBoxObject() => SearchSource.text,
  MathObject() => SearchSource.math,
  _ => null,
};

/// The object types whose rows are indexed (page_objects.type).
const Map<SearchSource, String> kIndexedObjectTypes = {
  SearchSource.text: 'text',
  SearchSource.math: 'math',
};

String _objectBody(PageObject o) => switch (o) {
  TextBoxObject(:final text) => text,
  MathObject(:final latex) => latex,
  _ => '',
};

/// sourceRev of a text / math owner (6.10.3): `<object version>:<normalizerVersion>`.
String objectSourceRev(Hlc version) =>
    '$version:${SearchText.normalizerVersion}';

/// sourceRev of an ink owner (6.10.3):
/// `<HandwritingText.sourceRev>:<version>:<normalizerVersion>`.
String inkSourceRev(HandwritingText h, Hlc version) =>
    '${h.sourceRev}:$version:${SearchText.normalizerVersion}';

final class SearchIndexer implements TxnIndexHooks {
  SearchIndexer(this.db);
  final NoteDatabase db;

  int _pending = 0;
  bool _txMarked = false;
  int? _txPending;
  int _failNext = 0;

  /// Called after a commit changed [pendingOwners].
  void Function()? onPendingChanged;

  /// Pending owners as of the last commit (SearchIndexStatus.pendingOwners).
  int get pendingOwners => _pending;

  /// Tests: the next [count] owner index writes of the write hook (and of its retry) fail
  /// inside their savepoint; a pdf write through the writer fails its call.
  @visibleForTesting
  void failNextIndexWrites(int count) => _failNext += count;

  /// Reads the pending count (store open).
  Future<void> opened() async => _pending = await _countPending();

  Future<int> _countPending() async {
    final o = db.searchOwners;
    final n = o.source.count();
    final row =
        await (db.selectOnly(o)
              ..addColumns([n])
              ..where(o.pending.equals(true)))
            .getSingle();
    return row.read(n) ?? 0;
  }

  void _maybeFail() {
    if (_failNext > 0) {
      _failNext--;
      throw StateError('injected search index failure');
    }
  }

  // ---- TxnIndexHooks ----------------------------------------------------------------------

  @override
  Future<void> entityWritten(
    SyncEntity entity,
    Hlc version,
    NoteId? noteId,
  ) async {
    switch (entity) {
      case final PageObject o when searchSourceOfObject(o) != null:
        await _indexObject(o, version, noteId);
      case final HandwritingText h:
        await _indexHandwriting(h, version);
      default:
    }
  }

  @override
  Future<void> objectsAdopted(List<ElementId> ids, NoteId noteId) async {
    final t = db.pageObjects;
    for (var i = 0; i < ids.length; i += _inChunk) {
      final chunk = ids.sublist(
        i,
        i + _inChunk > ids.length ? ids.length : i + _inChunk,
      );
      final rows =
          await (db.select(t)..where(
                (r) =>
                    r.id.isIn(chunk) & r.type.isIn(kIndexedObjectTypes.values),
              ))
              .get();
      for (final r in rows) {
        await _guarded(
          SearchSource.values.byName(r.type),
          r.id,
          noteId,
          r.pageId,
          () async {
            final o = pageObjectOf(r);
            await _writeObject(o, o.version!, noteId, force: true);
          },
        );
      }
    }
  }

  @override
  Future<void> beforeCommit() async {
    if (_pending > 0) await _retryPending();
    if (_pending > 0 || _txMarked) _txPending = await _countPending();
  }

  @override
  void committed() {
    final next = _txPending;
    _txMarked = false;
    _txPending = null;
    if (next != null && next != _pending) {
      _pending = next;
      onPendingChanged?.call();
    }
  }

  @override
  void rolledBack() {
    _txMarked = false;
    _txPending = null;
  }

  // ---- the write hook ---------------------------------------------------------------------

  Future<void> _indexObject(PageObject o, Hlc version, NoteId? noteId) =>
      _guarded(
        searchSourceOfObject(o)!,
        o.id,
        noteId,
        o.pageId,
        () => _writeObject(o, version, noteId),
      );

  /// The owner of text / math object [o]: removed when [o] is deleted, otherwise one unit
  /// (none for a body that normalizes to nothing, or an orphan without its note yet).
  Future<void> _writeObject(
    PageObject o,
    Hlc version,
    NoteId? noteId, {
    bool force = false,
  }) async {
    final source = searchSourceOfObject(o)!;
    if (o.isDeleted) {
      await removeOwnerRows(source, o.id);
      return;
    }
    final rev = objectSourceRev(version);
    if (!force && await _upToDate(source, o.id, rev)) return;
    final body = _objectBody(o);
    await writeOwnerRows(
      source: source,
      ownerKey: o.id,
      noteId: noteId,
      pageId: o.pageId,
      sourceRev: rev,
      units: [
        if (noteId != null && SearchText.normalize(body).isNotEmpty)
          (body: body, rect: o.bounds, rectsRef: null, pdfAspect: null),
      ],
    );
  }

  Future<void> _indexHandwriting(HandwritingText h, Hlc version) => _guarded(
    SearchSource.ink,
    h.id,
    h.noteId,
    h.pageId,
    () => _writeHandwriting(h, version),
  );

  /// The ink owner `hw_<pageId>`: one unit per line whose text normalizes to something.
  Future<void> _writeHandwriting(HandwritingText h, Hlc version) async {
    if (h.isDeleted) {
      await removeOwnerRows(SearchSource.ink, h.id);
      return;
    }
    final rev = inkSourceRev(h, version);
    if (await _upToDate(SearchSource.ink, h.id, rev)) return;
    await writeOwnerRows(
      source: SearchSource.ink,
      ownerKey: h.id,
      noteId: h.noteId,
      pageId: h.pageId,
      sourceRev: rev,
      units: [
        for (final l in h.lines)
          if (SearchText.normalize(l.text).isNotEmpty)
            (body: l.text, rect: l.rect, rectsRef: null, pdfAspect: null),
      ],
    );
  }

  /// Runs [body] in a savepoint; a failure rolls the savepoint back and marks the owner
  /// pending (C-13) — the source write goes on.
  Future<void> _guarded(
    SearchSource source,
    String ownerKey,
    NoteId? noteId,
    PageId? pageId,
    Future<void> Function() body,
  ) async {
    try {
      await db.transaction(() async {
        _maybeFail();
        await body();
      });
    } on Object catch (e, st) {
      await _markPending(source, ownerKey, noteId, pageId, e, st);
    }
  }

  Future<void> _markPending(
    SearchSource source,
    String ownerKey,
    NoteId? noteId,
    PageId? pageId,
    Object error,
    StackTrace stack,
  ) async {
    try {
      await db.customStatement(
        'INSERT INTO search_owners '
        '(source, owner_key, note_id, page_id, source_rev, pending) '
        "VALUES (?, ?, ?, ?, '', 1) "
        'ON CONFLICT (source, owner_key) DO UPDATE SET pending = 1',
        [source.name, ownerKey, noteId, pageId],
      );
      _txMarked = true;
    } on Object catch (e, st) {
      // Not even the mark could be written (the database is broken already): a dev log.
      developer.log(
        'search index: could not mark ${source.name} $ownerKey pending',
        name: 'note_core.search',
        error: e,
        stackTrace: st,
      );
    }
    developer.log(
      'search index: ${source.name} $ownerKey pending',
      name: 'note_core.search',
      error: error,
      stackTrace: stack,
    );
  }

  Future<bool> _upToDate(
    SearchSource source,
    String ownerKey,
    String rev,
  ) async {
    final o = db.searchOwners;
    final row =
        await (db.selectOnly(o)
              ..addColumns([o.sourceRev, o.pending])
              ..where(
                o.source.equals(source.name) & o.ownerKey.equals(ownerKey),
              ))
            .getSingleOrNull();
    return row != null &&
        row.read(o.pending) == false &&
        row.read(o.sourceRev) == rev;
  }

  // ---- the pending retry (6.10.5) ---------------------------------------------------------

  Future<void> _retryPending() async {
    final rows =
        await (db.select(db.searchOwners)
              ..where((t) => t.pending.equals(true))
              ..orderBy([
                (t) => OrderingTerm(expression: t.source),
                (t) => OrderingTerm(expression: t.ownerKey),
              ])
              ..limit(kSearchRetryPerTransaction))
            .get();
    for (final r in rows) {
      final source = SearchSource.values.byName(r.source);
      await _guarded(
        source,
        r.ownerKey,
        r.noteId,
        r.pageId,
        () => _reindexFromSource(source, r.ownerKey),
      );
    }
  }

  /// Re-indexes the owner from its source row (gone → the owner goes).
  Future<void> _reindexFromSource(SearchSource source, String ownerKey) async {
    switch (source) {
      case SearchSource.text || SearchSource.math:
        final row = await (db.select(
          db.pageObjects,
        )..where((t) => t.id.equals(ownerKey))).getSingleOrNull();
        if (row == null) {
          await removeOwnerRows(source, ownerKey);
          return;
        }
        final o = pageObjectOf(row);
        await _writeObject(
          o,
          o.version!,
          row.noteId.isEmpty ? null : row.noteId,
          force: true,
        );
      case SearchSource.ink:
        final row = await (db.select(
          db.handwriting,
        )..where((t) => t.id.equals(ownerKey))).getSingleOrNull();
        if (row == null) {
          await removeOwnerRows(source, ownerKey);
          return;
        }
        final h = handwritingOf(row);
        await _writeHandwriting(h, h.version!);
      case SearchSource.pdf:
        // pdf rows come from pdf_io only (never marked by CORE): nothing to rebuild here.
        await (db.update(db.searchOwners)..where(
              (t) => t.source.equals(source.name) & t.ownerKey.equals(ownerKey),
            ))
            .write(const SearchOwnersCompanion(pending: Value(false)));
    }
  }

  // ---- rows -------------------------------------------------------------------------------

  /// Replaces the units of the owner (source, [ownerKey]) with [units] (in seq order) and
  /// upserts the owner row with [sourceRev], not pending — also for an empty [units] list
  /// (C21-09). Returns the rects_ref blob keys of the old units.
  Future<List<String>> writeOwnerRows({
    required SearchSource source,
    required String ownerKey,
    NoteId? noteId,
    PageId? pageId,
    AssetId? assetId,
    int? pdfIndex,
    required String sourceRev,
    required List<SearchUnitRowDraft> units,
  }) async {
    if (source == SearchSource.pdf) _maybeFail();
    final old = await _dropUnits(source, ownerKey);
    for (final (seq, u) in units.indexed) {
      final norm = SearchText.normalize(u.body);
      final id = await db
          .into(db.searchUnits)
          .insert(
            SearchUnitsCompanion.insert(
              source: source.name,
              ownerKey: ownerKey,
              seq: seq,
              noteId: Value(noteId),
              pageId: Value(pageId),
              assetId: Value(assetId),
              pdfIndex: Value(pdfIndex),
              body: u.body,
              norm: norm,
              rectL: Value(u.rect?.left),
              rectT: Value(u.rect?.top),
              rectR: Value(u.rect?.right),
              rectB: Value(u.rect?.bottom),
              rectsRef: Value(u.rectsRef),
              pdfAspect: Value(u.pdfAspect),
            ),
          );
      await db.customStatement(
        'INSERT INTO search_fts (rowid, g) VALUES (?, ?)',
        [id, unitIndexTerms(source, norm)],
      );
    }
    await db
        .into(db.searchOwners)
        .insertOnConflictUpdate(
          SearchOwnersCompanion.insert(
            source: source.name,
            ownerKey: ownerKey,
            noteId: Value(noteId),
            pageId: Value(pageId),
            sourceRev: sourceRev,
            pending: false,
          ),
        );
    return old;
  }

  /// Deletes the owner (source, [ownerKey]) and its units; returns their rects_ref keys.
  Future<List<String>> removeOwnerRows(
    SearchSource source,
    String ownerKey,
  ) async {
    final old = await _dropUnits(source, ownerKey);
    await (db.delete(db.searchOwners)..where(
          (t) => t.source.equals(source.name) & t.ownerKey.equals(ownerKey),
        ))
        .go();
    return old;
  }

  Future<List<String>> _dropUnits(SearchSource source, String ownerKey) async {
    final u = db.searchUnits;
    final rows =
        await (db.selectOnly(u)
              ..addColumns([u.id, u.rectsRef])
              ..where(
                u.source.equals(source.name) & u.ownerKey.equals(ownerKey),
              ))
            .get();
    if (rows.isEmpty) return const [];
    await _deleteFts([for (final r in rows) r.read(u.id)!]);
    await (db.delete(u)..where(
          (t) => t.source.equals(source.name) & t.ownerKey.equals(ownerKey),
        ))
        .go();
    return [for (final r in rows) ?r.read(u.rectsRef)];
  }

  /// contentless_delete=1: a plain DELETE by rowid (no old terms needed — 6.10.3).
  Future<void> _deleteFts(List<int> ids) async {
    for (var i = 0; i < ids.length; i += _inChunk) {
      final chunk = ids.sublist(
        i,
        i + _inChunk > ids.length ? ids.length : i + _inChunk,
      );
      await db.customStatement(
        'DELETE FROM search_fts WHERE rowid IN '
        '(${List.filled(chunk.length, '?').join(', ')})',
        chunk,
      );
    }
  }

  /// Rebuild step 1: drops every owner and unit of [sources]; returns the rects_ref keys.
  Future<List<String>> dropSources(Set<SearchSource> sources) async {
    final names = [for (final s in sources) s.name];
    if (names.isEmpty) return const [];
    final u = db.searchUnits;
    final refs = [
      for (final r
          in await (db.selectOnly(u)
                ..addColumns([u.rectsRef])
                ..where(u.source.isIn(names) & u.rectsRef.isNotNull()))
              .get())
        r.read(u.rectsRef)!,
    ];
    await db.customStatement(
      'DELETE FROM search_fts WHERE rowid IN '
      '(SELECT id FROM search_units WHERE source IN '
      '(${List.filled(names.length, '?').join(', ')}))',
      names,
    );
    await (db.delete(u)..where((t) => t.source.isIn(names))).go();
    await (db.delete(db.searchOwners)..where((t) => t.source.isIn(names))).go();
    _txMarked = true;
    return refs;
  }

  /// Rebuild: indexes up to [limit] active text / math objects of [sources] after id
  /// [after] (id order). Returns the last id read and how many rows were read.
  Future<({String? last, int count})> indexObjectChunk(
    Set<SearchSource> sources,
    String? after,
    int limit,
  ) async {
    final types = [for (final s in sources) ?kIndexedObjectTypes[s]];
    if (types.isEmpty) return (last: null, count: 0);
    final t = db.pageObjects;
    final rows =
        await (db.select(t)
              ..where(
                (r) =>
                    r.type.isIn(types) &
                    r.deletedAt.isNull() &
                    (after == null
                        ? const Constant(true)
                        : r.id.isBiggerThanValue(after)),
              )
              ..orderBy([(r) => OrderingTerm(expression: r.id)])
              ..limit(limit))
            .get();
    for (final r in rows) {
      await _guarded(
        SearchSource.values.byName(r.type),
        r.id,
        r.noteId.isEmpty ? null : r.noteId,
        r.pageId,
        () async {
          final o = pageObjectOf(r);
          await _writeObject(
            o,
            o.version!,
            r.noteId.isEmpty ? null : r.noteId,
            force: true,
          );
        },
      );
    }
    return (last: rows.isEmpty ? null : rows.last.id, count: rows.length);
  }

  /// Rebuild: indexes up to [limit] active handwriting results after id [after].
  Future<({String? last, int count})> indexHandwritingChunk(
    String? after,
    int limit,
  ) async {
    final t = db.handwriting;
    final rows =
        await (db.select(t)
              ..where(
                (r) =>
                    r.deletedAt.isNull() &
                    (after == null
                        ? const Constant(true)
                        : r.id.isBiggerThanValue(after)),
              )
              ..orderBy([(r) => OrderingTerm(expression: r.id)])
              ..limit(limit))
            .get();
    for (final r in rows) {
      await _guarded(SearchSource.ink, r.id, r.noteId, r.pageId, () async {
        final h = handwritingOf(r);
        await _writeHandwriting(h, h.version!);
      });
    }
    return (last: rows.isEmpty ? null : rows.last.id, count: rows.length);
  }
}
