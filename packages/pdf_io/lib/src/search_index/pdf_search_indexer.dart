// lib/src/search_index/pdf_search_indexer.dart — m5-7/06-pdf 4.1.1, 6.4 (contract 7.2.12).
//
// The barrel exports PdfSearchIndexer only (`show PdfSearchIndexer`). createPdfSearchIndexer
// lives in the same library so it can reach the private constructor; it is src only (v2.1,
// PDF-M9 — CP-PDF-1 rejected: no new public type, the document pool and the schedule gate are
// injected inside pdf_io).
//
// 2차 foundation step R2-B4 (T20, contract 7.6.2): the contract constructor, start() that
// does nothing (idempotent; nothing after dispose()) and an idempotent dispose(). PDF T27
// adds the catch-up (one sourceRevs(pdf) query + listAssets(hasLocalBytes: true)), the queue,
// AssetStore.bytesArrived, the SearchIndex.status rebuild rules and the units (6.4).
import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

import '../render/document_pool.dart';
import 'indexer_gate.dart';

/// Library-wide PDF text index (1차 7.8 이후 항목): watches PDF assets / PdfBackground pages,
/// extracts with PdfTextService, writes core.SearchIndexWriter (source pdf, rects as page
/// fractions). Skips owners whose sourceRev is current. Idle-time, one PDF page per slice.
/// (v2.1) Pauses while SearchIndex.status.rebuilding is true (drops its queue) and re-judges every
/// asset afterwards. The public constructor stays as below — CP-PDF-1 rejected: the document pool
/// and the schedule gate are injected inside pdf_io (provider / src-only factory), no new public
/// type. dispose() is idempotent.
final class PdfSearchIndexer {
  /// 원문 생성자: its own document pool (DefaultPdfDocumentPool over CorePdfNoteGateway(store)
  /// and PdfrxEngine.shared(), made on the first slice — PDF T27) and the always-open gate
  /// (closed while the index rebuilds — T27). Builds nothing and subscribes to nothing.
  PdfSearchIndexer(core.NoteStore store)
    : this._(store, null, const AlwaysOpenIndexerGate());

  PdfSearchIndexer._(this._store, this._pool, this._gate);

  final core.NoteStore _store;

  /// The injected pool (pdfSearchIndexerProvider — not disposed here); null = own pool (T27).
  final PdfDocumentPool? _pool;
  final IndexerGate _gate;
  bool _started = false;
  bool _disposed = false;

  /// Idempotent; does nothing after dispose(). Waits while SearchIndex.status.rebuilding is true,
  /// then schedules the catch-up (one sourceRevs(pdf) query + listAssets(hasLocalBytes: true)) and
  /// listens to AssetStore.bytesArrived (a new PDF asset is queued) and SearchIndex.status
  /// (v2.1: rebuilding true ⇒ stop and drop the queue; false ⇒ catch-up again, re-judging every
  /// asset — 6.4.2).
  ///
  /// R2-B4 (contract 7.6.2): records that it was started and does nothing else (PDF T27).
  void start() {
    if (_disposed || _started) return;
    _started = true;
  }

  /// Idempotent and safe to call again or after a failed start (01-infra R-3). Cancels the
  /// listeners, lets the slice in flight finish (≤ one PDF page) and returns; never waits for a
  /// CORE commit that is being retried (1차 7.2.9 v1.2 쓰기 Future 규칙).
  ///
  /// R2-B4: nothing to cancel yet.
  Future<void> dispose() async {
    _disposed = true;
  }
}

/// pdfSearchIndexerProvider and the package's own tests build the indexer through this.
/// The [pool] stays the caller's (the indexer never disposes it).
PdfSearchIndexer createPdfSearchIndexer(
  core.NoteStore store, {
  required PdfDocumentPool pool,
  required IndexerGate gate,
}) => PdfSearchIndexer._(store, pool, gate);

/// Tests only (src, not exported): what [indexer] was built with and its lifecycle flags.
@visibleForTesting
({
  core.NoteStore store,
  PdfDocumentPool? pool,
  IndexerGate gate,
  bool started,
  bool disposed,
})
debugPdfSearchIndexerState(PdfSearchIndexer indexer) => (
  store: indexer._store,
  pool: indexer._pool,
  gate: indexer._gate,
  started: indexer._started,
  disposed: indexer._disposed,
);
