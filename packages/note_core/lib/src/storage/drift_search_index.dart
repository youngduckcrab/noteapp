// lib/src/storage/drift_search_index.dart (internal) — SearchIndex on SQLite FTS5 + the asset
// blob store (m5-7/02-core 6.10, contract 7.2.5). Same meaning as the fake store's memory index
// (test/shared/search_contract.dart runs on both from CORE T33b).
//
// Writes (CORE T33a): ink / text / math come from CORE's own write hook (search_indexer.dart);
// pdf comes from pdf_io through SearchIndexWriter (validation → glyph box blobs → one queue job
// → old blobs deleted after the commit — 6.10.3). Glyph boxes live OUTSIDE SQLite under the blob
// keys 'si/pdf/<assetId>/<pdfPageIndex>/<token>-<seq>' (web IndexedDB 'noteapp_blobs', native
// file blobs) in the SearchRectsCodec format; a unit row keeps only the key (rects_ref). A key
// is never overwritten (a fresh token per call), so a cut anywhere leaves only unreferenced
// blobs, removed on the first writer use after the store opened. rebuild drops the derived rows
// of the chosen sources and makes ink / text / math again from their source rows in queue jobs
// of [kSearchRebuildChunk] rows; pdf is only dropped (pdf_io refills it — 6.10.5).
//
// Queries (searchPages — CORE T33b, 6.10.4): candidates from FTS5 MATCH (or LIKE for queries
// without a run of two or more code points), live units only, most recent (highest id) first,
// at most kSearchCandidateCap — reading neither bodies nor rects; then the shared
// search_pipeline steps (judgement, pdf expansion, grouping, scores, order) and, for the
// returned pages only, the representative bodies, the unit rects and one blob read of the pdf
// boxes. The fake store's memory index runs the same pipeline on the same candidates (CP-14).
import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../assets/blob_store.dart';
import '../common/geometry.dart';
import '../common/hlc.dart';
import '../common/ids.dart';
import '../search/search_pipeline.dart';
import '../search/search_rects.dart';
import '../search/search_runs.dart';
import '../search/search_text.dart';
import '../search/search_types.dart';
import '../search/search_writer_checks.dart';
import 'db/note_database.dart';
import 'drift_library_repository.dart' show likeContains;
import 'drift_note_store.dart';
import 'kv_keys.dart';
import 'search_indexer.dart';

/// Source rows per rebuild queue job (6.10.5 — the write queue is not blocked for long).
const int kSearchRebuildChunk = 200;

/// Rows per statement of an `IN (…)` list.
const int _inChunk = 500;

String _marks(int n) => List.filled(n, '?').join(', ');

/// The blob key prefix of the search index, and of its pdf glyph boxes.
const String kSearchBlobRoot = 'si/';
const String kSearchPdfBlobRoot = 'si/pdf/';

final class DriftSearchIndex implements SearchIndex {
  DriftSearchIndex(this.s, this.blobs) : indexer = SearchIndexer(s.db) {
    indexer.onPendingChanged = _emit;
  }

  final DriftNoteStore s;

  /// The asset blob store (IndexedDB on the web, files on native — 6.15.3).
  final BlobStore blobs;

  /// The rows written inside the write transactions (the write queue's index hooks).
  final SearchIndexer indexer;

  NoteDatabase get _db => s.db;

  int _rebuilds = 0;
  EpochMillis? _lastRebuildAt;
  SearchIndexStatus _status = const SearchIndexStatus();
  final StreamController<SearchIndexStatus> _statusCtrl =
      StreamController.broadcast(sync: true);
  Future<void>? _cleaned;

  /// Tests: the blob and commit steps of the writer in the order they happened —
  /// `put <key>`, `commit <ownerKey>`, `delete <key>`, `orphan <key>`.
  @visibleForTesting
  final List<String> debugLog = [];

  /// Store open: the pending count and kv values; a changed normalizer version schedules a
  /// full rebuild, pending owners one queue job (its transaction end retries them). Neither
  /// blocks the open.
  Future<void> opened() async {
    await indexer.opened();
    final rows =
        await (_db.select(_db.kv)..where(
              (t) => t.key.isIn([
                KvKeys.searchNormalizerVersion,
                KvKeys.searchLastRebuildAt,
              ]),
            ))
            .get();
    final kv = {for (final r in rows) r.key: r.value};
    _lastRebuildAt = int.tryParse(kv[KvKeys.searchLastRebuildAt] ?? '');
    _status = _current();
    if (kv[KvKeys.searchNormalizerVersion] !=
        '${SearchText.normalizerVersion}') {
      unawaited(rebuild().then<void>((_) {}, onError: (Object _) {}));
    } else if (indexer.pendingOwners > 0) {
      unawaited(
        s.queue.run((_) async {}).then<void>((_) {}, onError: (Object _) {}),
      );
    }
  }

  // ---- status ---------------------------------------------------------------------------

  SearchIndexStatus _current() => SearchIndexStatus(
    pendingOwners: indexer.pendingOwners,
    rebuilding: _rebuilds > 0,
    lastRebuildAt: _lastRebuildAt,
  );

  void _emit() {
    final next = _current();
    if (next == _status) return;
    _status = next;
    if (!_statusCtrl.isClosed) _statusCtrl.add(next);
  }

  @override
  Stream<SearchIndexStatus> get status => Stream.multi((c) {
    c.add(_status);
    final sub = _statusCtrl.stream.listen(c.add);
    c.onCancel = sub.cancel;
  });

  Future<void> close() => _statusCtrl.close();

  // ---- SearchIndexWriter ----------------------------------------------------------------

  @override
  Future<String?> sourceRevOf(SearchSource source, String ownerKey) async {
    final o = _db.searchOwners;
    final row =
        await (_db.selectOnly(o)
              ..addColumns([o.sourceRev])
              ..where(
                o.source.equals(source.name) & o.ownerKey.equals(ownerKey),
              ))
            .getSingleOrNull();
    return row?.read(o.sourceRev);
  }

  /// One query over the owner table (P5 — a feeder's start-up catch-up).
  @override
  Future<Map<String, String>> sourceRevs(SearchSource source) async {
    final o = _db.searchOwners;
    final rows =
        await (_db.selectOnly(o)
              ..addColumns([o.ownerKey, o.sourceRev])
              ..where(o.source.equals(source.name)))
            .get();
    return {for (final r in rows) r.read(o.ownerKey)!: r.read(o.sourceRev)!};
  }

  @override
  Future<void> replaceUnits(
    SearchSource source,
    String ownerKey,
    List<SearchUnitDraft> units, {
    required String sourceRev,
  }) async {
    checkSearchWriterOwner(source, ownerKey);
    checkSearchUnits(units, sourceRev);
    final (assetId, pdfIndex) = splitPdfOwnerKey(ownerKey);
    await _cleanOnce();
    // ① the glyph boxes, each under a key no other call uses.
    final token = generateNodeId();
    final written = <String>[];
    final List<String> old;
    try {
      final rows = <SearchUnitRowDraft>[];
      for (final (seq, u) in units.indexed) {
        String? ref;
        if (u.rects.isNotEmpty) {
          ref =
              '$kSearchPdfBlobRoot$assetId/$pdfIndex/'
              '$token-${seq.toString().padLeft(4, '0')}';
          await blobs.put(ref, SearchRectsCodec.encode(u.rects));
          written.add(ref);
          debugLog.add('put $ref');
        }
        rows.add((
          body: u.body,
          rect: null,
          rectsRef: ref,
          pdfAspect: u.pdfPageAspect,
        ));
      }
      // ② one queue job: old units out, new units and the owner in.
      old = await s.queue.run((tx) async {
        final old = await indexer.writeOwnerRows(
          source: source,
          ownerKey: ownerKey,
          assetId: assetId,
          pdfIndex: pdfIndex,
          sourceRev: sourceRev,
          units: rows,
        );
        tx.afterCommit(() => debugLog.add('commit $ownerKey'));
        return old;
      });
    } on Object {
      // ② failed (or ① part way): the new boxes are not referenced — best effort.
      await _deleteBlobs(written);
      rethrow;
    }
    // ③ after the commit: the old boxes.
    await _deleteBlobs(old);
  }

  @override
  Future<void> removeOwner(SearchSource source, String ownerKey) async {
    checkSearchWriterOwner(source, ownerKey);
    await _cleanOnce();
    final old = await s.queue.run(
      (tx) => indexer.removeOwnerRows(source, ownerKey),
    );
    await _deleteBlobs(old);
  }

  Future<void> _deleteBlobs(Iterable<String> keys) async {
    for (final k in keys) {
      try {
        await blobs.delete(k);
        debugLog.add('delete $k');
      } on Object {
        // Left as an orphan: removed on the first writer use after the next open.
      }
    }
  }

  /// First writer use after the store opened: blobs under [kSearchBlobRoot] that no unit row
  /// references (a cut replaceUnits) are removed. Every writer call waits for it before its
  /// own blob puts, so it never sees a call's boxes before their rows. A failure leaves the
  /// orphans for the next open.
  Future<void> _cleanOnce() => _cleaned ??= () async {
    try {
      final keys = await blobs.keys(kSearchBlobRoot);
      if (keys.isEmpty) return;
      final u = _db.searchUnits;
      final used = {
        for (final r
            in await (_db.selectOnly(u)
                  ..addColumns([u.rectsRef])
                  ..where(u.rectsRef.isNotNull()))
                .get())
          r.read(u.rectsRef)!,
      };
      for (final k in keys) {
        if (used.contains(k)) continue;
        await blobs.delete(k);
        debugLog.add('orphan $k');
      }
    } on Object {
      // Tried again at the next open.
    }
  }();

  // ---- rebuild (6.10.5) -----------------------------------------------------------------

  @override
  Future<void> rebuild({Set<SearchSource>? sources}) async {
    final which = sources ?? SearchSource.values.toSet();
    _rebuilds++;
    _emit();
    try {
      await _cleanOnce();
      final refs = await s.queue.run((tx) => indexer.dropSources(which));
      await _deleteBlobs(refs);
      if (which.contains(SearchSource.text) ||
          which.contains(SearchSource.math)) {
        String? after;
        while (true) {
          final chunk = await s.queue.run(
            (tx) => indexer.indexObjectChunk(which, after, kSearchRebuildChunk),
          );
          if (chunk.count < kSearchRebuildChunk) break;
          after = chunk.last;
        }
      }
      if (which.contains(SearchSource.ink)) {
        String? after;
        while (true) {
          final chunk = await s.queue.run(
            (tx) => indexer.indexHandwritingChunk(after, kSearchRebuildChunk),
          );
          if (chunk.count < kSearchRebuildChunk) break;
          after = chunk.last;
        }
      }
      final at = s.clock.now().millisecondsSinceEpoch;
      await s.queue.run((tx) async {
        await _putKv(KvKeys.searchLastRebuildAt, '$at');
        if (which.length == SearchSource.values.length) {
          await _putKv(
            KvKeys.searchNormalizerVersion,
            '${SearchText.normalizerVersion}',
          );
        }
      });
      _lastRebuildAt = at;
    } finally {
      _rebuilds--;
      _emit();
    }
  }

  Future<void> _putKv(String key, String value) => _db
      .into(_db.kv)
      .insertOnConflictUpdate(KvCompanion.insert(key: key, value: value));

  // ---- queries (6.10.4) -----------------------------------------------------------------

  /// Tests: the SQL of each candidate query (step 1 reads neither body nor rects_ref).
  @visibleForTesting
  final List<String> debugCandidateSql = [];

  static const String _candidateColumns =
      'u.id, u.source, u.owner_key, u.seq, u.note_id, u.page_id, u.asset_id, '
      'u.pdf_index, u.norm';

  @override
  Future<List<PageSearchHit>> searchPages(
    String query, {
    int limit = 100,
    NoteId? withinNote,
  }) async => (await search(query, limit: limit, withinNote: withinNote)).hits;

  /// [searchPages] plus whether the candidate cap or [limit] cut the result
  /// (LibrarySearchResult.pagesTruncated — CP-14).
  Future<({List<PageSearchHit> hits, bool truncated})> search(
    String query, {
    required int limit,
    NoteId? withinNote,
  }) async {
    final q = SearchText.normalize(query);
    const none = (hits: <PageSearchHit>[], truncated: false);
    if (q.isEmpty || limit <= 0) return none;
    final owner = s.ownerId;
    // A live page of the current owner's active note (withinNote: that note only).
    final within = withinNote == null ? '' : ' AND n.id = ?';
    final livePage =
        'p.deleted_at IS NULL AND n.deleted_at IS NULL AND n.owner_id = ?$within';
    final liveVars = <Variable<Object>>[
      Variable<String>(owner),
      if (withinNote != null) Variable<String>(withinNote),
    ];
    final alive =
        "(CASE WHEN u.source = 'pdf' THEN EXISTS (SELECT 1 FROM pages p "
        'JOIN notes n ON n.id = p.note_id WHERE p.bg_asset_id = u.asset_id '
        'AND p.bg_pdf_index = u.pdf_index AND $livePage) '
        'ELSE EXISTS (SELECT 1 FROM pages p JOIN notes n ON n.id = p.note_id '
        'WHERE p.id = u.page_id AND $livePage) END)';

    // 1) candidates: live units, most recent first, at most the cap (+1 to see it is hit).
    final match = SearchText.matchQuery(q);
    final String sql;
    final List<Variable<Object>> vars;
    if (match == null) {
      final runs = searchRunsOf(q);
      if (runs.isEmpty) return none;
      sql =
          'SELECT $_candidateColumns FROM search_units u WHERE '
          '${[for (final _ in runs) r"u.norm LIKE ? ESCAPE '\'"].join(' AND ')} '
          'AND $alive ORDER BY u.id DESC LIMIT ${kSearchCandidateCap + 1}';
      vars = [
        for (final r in runs) Variable<String>(likeContains(r.text)),
        ...liveVars,
        ...liveVars,
      ];
    } else {
      sql =
          'SELECT $_candidateColumns FROM search_fts JOIN search_units u '
          'ON u.id = search_fts.rowid WHERE search_fts MATCH ? AND $alive '
          'ORDER BY search_fts.rowid DESC LIMIT ${kSearchCandidateCap + 1}';
      vars = [Variable<String>(match), ...liveVars, ...liveVars];
    }
    debugCandidateSql.add(sql);
    final rows = await _db.customSelect(sql, variables: vars).get();
    final capped = rows.length > kSearchCandidateCap;
    final candidates = [
      for (final r in capped ? rows.take(kSearchCandidateCap) : rows)
        SearchCandidate(
          id: r.read<int>('id'),
          source: SearchSource.values.byName(r.read<String>('source')),
          ownerKey: r.read<String>('owner_key'),
          seq: r.read<int>('seq'),
          norm: r.read<String>('norm'),
          noteId: r.readNullable<String>('note_id'),
          pageId: r.readNullable<String>('page_id'),
          assetId: r.readNullable<String>('asset_id'),
          pdfIndex: r.readNullable<int>('pdf_index'),
        ),
    ];
    if (candidates.isEmpty) return none;

    // 2) pdf expansion and note recency, each read once, then the shared ranking.
    final pdfPages = <(AssetId, int), List<SearchPageRef>>{};
    final assets = {
      for (final c in candidates)
        if (c.source == SearchSource.pdf) c.assetId!,
    }.toList();
    for (var i = 0; i < assets.length; i += _inChunk) {
      final chunk = assets.sublist(i, math.min(i + _inChunk, assets.length));
      for (final r
          in await _db
              .customSelect(
                'SELECT p.id, p.note_id, p.bg_asset_id, p.bg_pdf_index '
                'FROM pages p JOIN notes n ON n.id = p.note_id '
                'WHERE p.bg_asset_id IN (${_marks(chunk.length)}) AND $livePage '
                'ORDER BY p.id',
                variables: [
                  for (final a in chunk) Variable<String>(a),
                  ...liveVars,
                ],
              )
              .get()) {
        (pdfPages[(
                  r.read<String>('bg_asset_id'),
                  r.read<int>('bg_pdf_index'),
                )] ??=
                [])
            .add((
              noteId: r.read<String>('note_id'),
              pageId: r.read<String>('id'),
            ));
      }
    }
    final noteIds = {
      for (final c in candidates) ?c.noteId,
      for (final refs in pdfPages.values)
        for (final ref in refs) ref.noteId,
    }.toList();
    final updatedAt = <NoteId, int>{};
    for (var i = 0; i < noteIds.length; i += _inChunk) {
      final chunk = noteIds.sublist(i, math.min(i + _inChunk, noteIds.length));
      final n = _db.notes;
      for (final r
          in await (_db.selectOnly(n)
                ..addColumns([n.id, n.updatedAt])
                ..where(n.id.isIn(chunk)))
              .get()) {
        updatedAt[r.read(n.id)!] = r.read(n.updatedAt)!;
      }
    }
    final ranked = rankSearchCandidates(
      candidates,
      q,
      pdfPages: (c) => pdfPages[(c.assetId!, c.pdfIndex!)] ?? const [],
      noteUpdatedAt: (id) => updatedAt[id] ?? 0,
      limit: limit,
    );
    if (ranked.pages.isEmpty) {
      return (hits: const <PageSearchHit>[], truncated: capped || ranked.more);
    }

    // 3) the returned pages only: bodies of their representative units, rects, boxes.
    final bestIds = {for (final p in ranked.pages) p.best.id};
    final otherIds = {
      for (final p in ranked.pages)
        for (final u in p.units)
          if (u.source != SearchSource.pdf &&
              u.source == p.best.source &&
              !bestIds.contains(u.id))
            u.id,
    };
    final details = <int, SearchUnitDetail>{};
    final refs = <int, String>{};
    final u = _db.searchUnits;
    for (final (ids, withBody) in [
      (bestIds.toList(), true),
      (otherIds.toList(), false),
    ]) {
      for (var i = 0; i < ids.length; i += _inChunk) {
        final chunk = ids.sublist(i, math.min(i + _inChunk, ids.length));
        final rowsOf =
            await (_db.selectOnly(u)
                  ..addColumns([
                    u.id,
                    if (withBody) ...[u.body, u.rectsRef, u.pdfAspect],
                    u.rectL,
                    u.rectT,
                    u.rectR,
                    u.rectB,
                  ])
                  ..where(u.id.isIn(chunk)))
                .get();
        for (final r in rowsOf) {
          final id = r.read(u.id)!;
          final l = r.read(u.rectL);
          details[id] = (
            body: withBody ? r.read(u.body)! : '',
            rect: l == null
                ? null
                : PageRect(
                    l,
                    r.read(u.rectT)!,
                    r.read(u.rectR)!,
                    r.read(u.rectB)!,
                  ),
            pdfRects: const <PageRect>[],
            pdfAspect: withBody ? r.read(u.pdfAspect) : null,
          );
          if (withBody) {
            if (r.read(u.rectsRef) case final ref?) refs[id] = ref;
          }
        }
      }
    }
    // The boxes of the representative pdf units: one blob read; a missing blob = no boxes.
    if (refs.isNotEmpty) {
      final ids = refs.keys.toList();
      List<Uint8List?> blobsRead;
      try {
        blobsRead = await blobs.getMany([for (final id in ids) refs[id]!]);
      } on Object {
        blobsRead = List<Uint8List?>.filled(ids.length, null);
      }
      for (final (i, id) in ids.indexed) {
        final bytes = blobsRead[i];
        if (bytes == null) continue;
        final List<PageRect> boxes;
        try {
          boxes = SearchRectsCodec.decode(bytes);
        } on Object {
          continue;
        }
        final d = details[id]!;
        details[id] = (
          body: d.body,
          rect: d.rect,
          pdfRects: boxes,
          pdfAspect: d.pdfAspect,
        );
      }
    }
    final sizes = <PageId, (double, double)>{};
    final pageIds = [for (final p in ranked.pages) p.pageId];
    final pg = _db.pages;
    for (var i = 0; i < pageIds.length; i += _inChunk) {
      final chunk = pageIds.sublist(i, math.min(i + _inChunk, pageIds.length));
      for (final r
          in await (_db.selectOnly(pg)
                ..addColumns([pg.id, pg.width, pg.height])
                ..where(pg.id.isIn(chunk)))
              .get()) {
        sizes[r.read(pg.id)!] = (r.read(pg.width)!, r.read(pg.height)!);
      }
    }
    const noDetail = (
      body: '',
      rect: null,
      pdfRects: <PageRect>[],
      pdfAspect: null,
    );
    final hits = [
      for (final p in ranked.pages)
        searchHitOf(
          p,
          q,
          detail: (c) => details[c.id] ?? noDetail,
          pageWidth: sizes[p.pageId]?.$1 ?? 0,
          pageHeight: sizes[p.pageId]?.$2 ?? 0,
        ),
    ];
    return (
      hits: List<PageSearchHit>.unmodifiable(hits),
      truncated: capped || ranked.more,
    );
  }
}
