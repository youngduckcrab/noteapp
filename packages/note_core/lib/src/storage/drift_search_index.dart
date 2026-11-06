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
// Queries (searchPages): CORE T33b.
import 'dart:async';

import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../assets/blob_store.dart';
import '../common/hlc.dart';
import '../common/ids.dart';
import '../search/search_rects.dart';
import '../search/search_text.dart';
import '../search/search_types.dart';
import '../search/search_writer_checks.dart';
import 'db/note_database.dart';
import 'drift_note_store.dart';
import 'kv_keys.dart';
import 'search_indexer.dart';

/// Source rows per rebuild queue job (6.10.5 — the write queue is not blocked for long).
const int kSearchRebuildChunk = 200;

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

  // ---- queries (CORE T33b) --------------------------------------------------------------

  @override
  Future<List<PageSearchHit>> searchPages(
    String query, {
    int limit = 100,
    NoteId? withinNote,
  }) async => const [];
}
