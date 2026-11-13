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
// without a run of two or more code points), live units only, most recent
// (highest id) first, at most kSearchCandidateCap — reading neither bodies nor rects, and
// with each one's liveness read also giving its note's updatedAt / its pdf pages; then the
// shared search_pipeline steps (judgement, pdf expansion, grouping, scores, order) and, for the
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
import '../search/search_spacing.dart';
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
                KvKeys.searchInkTermsVersion,
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
    } else if (kv[KvKeys.searchInkTermsVersion] != '$kInkTermsVersion' &&
        await _hasInkOwners()) {
      // (ink spacing) ink rows written before the compact terms: once, ink only. Without
      // ink rows nothing is done (every new ink row gets the terms).
      unawaited(
        rebuild(sources: const {SearchSource.ink})
            .then<void>((_) {}, onError: (Object _) {}),
      );
    } else if (indexer.pendingOwners > 0) {
      unawaited(
        s.queue.run((_) async {}).then<void>((_) {}, onError: (Object _) {}),
      );
    }
  }

  Future<bool> _hasInkOwners() async {
    final o = _db.searchOwners;
    final row =
        await (_db.selectOnly(o)
              ..addColumns([o.ownerKey])
              ..where(o.source.equals(SearchSource.ink.name))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
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
        if (which.contains(SearchSource.ink)) {
          await _putKv(KvKeys.searchInkTermsVersion, '$kInkTermsVersion');
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
    // Per candidate, one correlated read that is both the liveness test and what step 2 needs
    // (CORE T33b — PF-3): a non-pdf unit → its note's updated_at; a pdf unit → every live
    // note page showing its PDF page as 'pageId noteId updatedAt …' (U+001F between the
    // fields; their order does not matter — step 2 orders pages fully). NULL = not live.
    final live =
        "CASE WHEN u.source = 'pdf' THEN (SELECT group_concat(p.id || char(31) || "
        'p.note_id || char(31) || n.updated_at, char(31)) FROM pages p '
        'JOIN notes n ON n.id = p.note_id WHERE p.bg_asset_id = u.asset_id '
        'AND p.bg_pdf_index = u.pdf_index AND $livePage) '
        'ELSE (SELECT n.updated_at FROM pages p JOIN notes n ON n.id = p.note_id '
        'WHERE p.id = u.page_id AND $livePage) END';

    // 1) candidates: live units, most recent first, at most the cap (+1 to see it is hit).
    // The inner query runs as a co-routine in rowid order (LIMIT -1 keeps it from being
    // flattened, so `live` is computed once per row); the outer one keeps the live rows.
    final match = SearchText.matchQuery(q);
    final String from;
    final List<Variable<Object>> vars;
    if (match == null) {
      final runs = searchRunsOf(q);
      if (runs.isEmpty) return none;
      from =
          'FROM search_units u WHERE '
          '${[for (final _ in runs) r"u.norm LIKE ? ESCAPE '\'"].join(' AND ')} '
          'ORDER BY u.id DESC';
      vars = [
        ...liveVars,
        ...liveVars,
        for (final r in runs) Variable<String>(likeContains(r.text)),
      ];
    } else {
      from =
          'FROM search_fts JOIN search_units u ON u.id = search_fts.rowid '
          'WHERE search_fts MATCH ? ORDER BY search_fts.rowid DESC';
      vars = [...liveVars, ...liveVars, Variable<String>(match)];
    }
    final sql =
        'SELECT * FROM (SELECT $_candidateColumns, $live AS live $from '
        'LIMIT -1) WHERE live IS NOT NULL LIMIT ${kSearchCandidateCap + 1}';
    debugCandidateSql.add(sql);
    final rows = await _db.customSelect(sql, variables: vars).get();
    final capped = rows.length > kSearchCandidateCap;
    final candidates = <SearchCandidate>[];
    final pdfPages = <(AssetId, int), List<SearchPageRef>>{};
    final updatedAt = <NoteId, int>{};
    for (final r in capped ? rows.take(kSearchCandidateCap) : rows) {
      final data = r.data;
      final source = SearchSource.values.byName(data['source']! as String);
      final c = SearchCandidate(
        id: data['id']! as int,
        source: source,
        ownerKey: data['owner_key']! as String,
        seq: data['seq']! as int,
        norm: data['norm']! as String,
        noteId: data['note_id'] as String?,
        pageId: data['page_id'] as String?,
        assetId: data['asset_id'] as String?,
        pdfIndex: data['pdf_index'] as int?,
      );
      candidates.add(c);
      final liveValue = data['live']!;
      if (source == SearchSource.pdf) {
        final key = (c.assetId!, c.pdfIndex!);
        if (pdfPages.containsKey(key)) continue;
        final parts = (liveValue as String).split('\x1f');
        pdfPages[key] = [
          for (var i = 0; i + 2 < parts.length; i += 3)
            (noteId: parts[i + 1], pageId: parts[i]),
        ];
        for (var i = 0; i + 2 < parts.length; i += 3) {
          updatedAt[parts[i + 1]] = int.parse(parts[i + 2]);
        }
      } else {
        updatedAt[c.noteId!] = liveValue as int;
      }
    }
    if (candidates.isEmpty) return none;

    // 2) the shared ranking (judgement, pdf expansion, grouping, scores, order).
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
    final sizes = <PageId, (double, double)>{};
    // One statement per chunk: the representative units with body / rects_ref / pdf_aspect,
    // the other units of their source with the rect only, and the page sizes (raw SQL — the
    // query builder's typed rows cost more than the reads here).
    final best = bestIds.toList();
    final other = otherIds.toList();
    final pageIds = [for (final p in ranked.pages) p.pageId];
    final most = math.max(math.max(best.length, other.length), pageIds.length);
    for (var i = 0; i < most; i += _inChunk) {
      final b = best.sublist(
        math.min(i, best.length),
        math.min(i + _inChunk, best.length),
      );
      final o = other.sublist(
        math.min(i, other.length),
        math.min(i + _inChunk, other.length),
      );
      final pg = pageIds.sublist(
        math.min(i, pageIds.length),
        math.min(i + _inChunk, pageIds.length),
      );
      final rowsOf = await _db
          .customSelect(
            'SELECT 0 AS k, u.id AS id, NULL AS pid, u.body AS body, '
            'u.rects_ref AS ref, u.pdf_aspect AS aspect, u.rect_l AS l, u.rect_t AS t, '
            'u.rect_r AS r, u.rect_b AS b FROM search_units u WHERE u.id IN (${_marks(b.length)}) '
            'UNION ALL SELECT 1, u.id, NULL, NULL, NULL, NULL, u.rect_l, u.rect_t, u.rect_r, '
            'u.rect_b FROM search_units u WHERE u.id IN (${_marks(o.length)}) '
            'UNION ALL SELECT 2, NULL, p.id, NULL, NULL, NULL, p.width, p.height, NULL, NULL '
            'FROM pages p WHERE p.id IN (${_marks(pg.length)})',
            variables: [
              for (final id in b) Variable<int>(id),
              for (final id in o) Variable<int>(id),
              for (final id in pg) Variable<String>(id),
            ],
          )
          .get();
      for (final row in rowsOf) {
        final r = row.data;
        final l = r['l'] as num?;
        if (r['k'] == 2) {
          sizes[r['pid']! as String] = (
            l!.toDouble(),
            (r['t']! as num).toDouble(),
          );
          continue;
        }
        final id = r['id']! as int;
        details[id] = (
          body: (r['body'] as String?) ?? '',
          rect: l == null
              ? null
              : PageRect(
                  l.toDouble(),
                  (r['t']! as num).toDouble(),
                  (r['r']! as num).toDouble(),
                  (r['b']! as num).toDouble(),
                ),
          pdfRects: const <PageRect>[],
          pdfAspect: (r['aspect'] as num?)?.toDouble(),
        );
        if (r['ref'] case final String ref) refs[id] = ref;
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
          boxes = SearchRectsCodec.view(bytes);
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
