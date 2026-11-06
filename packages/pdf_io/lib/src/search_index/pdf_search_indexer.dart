// lib/src/search_index/pdf_search_indexer.dart — m5-7/06-pdf 4.1.1, 6.4 (contract 7.2.12).
//
// The barrel exports PdfSearchIndexer only (`show PdfSearchIndexer`). createPdfSearchIndexer
// lives in the same library so it can reach the private constructor; it is src only (v2.1,
// PDF-M9 — CP-PDF-1 rejected: no new public type, the document pool and the schedule gate are
// injected inside pdf_io).
//
// (PDF T27 — 6.4.2) One PDF page = one owner '<assetId>#<pdfPageIndex>' (PdfSearchUnitBuilder).
// The catch-up reads sourceRevs(pdf) once and listAssets(hasLocalBytes: true) and queues every
// PDF asset whose '#0' is not the current sourceRev (pages already current are skipped), most
// recent first; AssetStore.bytesArrived queues new ones. One page at a time, pages 1 … n−1 and
// '#0' last (the completion mark). SearchIndex.status: rebuilding true → the queue is dropped
// and the job in flight stops at the next page boundary (a new epoch); false → catch-up again,
// re-judging every asset; an asset whose write overlapped a rebuild is 'dirty' (not skipped on
// its '#0') and an overlapped '#0' write is undone at once (removeOwner). Errors: 6.4.4.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

import '../common/error_report.dart';
import '../engine/pdfrx_engine.dart';
import '../errors.dart';
import '../gateway/core_note_gateway.dart';
import '../render/document_pool.dart';
import 'indexer_gate.dart';
import 'unit_builder.dart';

/// Library-wide PDF text index (1차 7.8 이후 항목): watches PDF assets / PdfBackground pages,
/// extracts with PdfTextService, writes core.SearchIndexWriter (source pdf, rects as page
/// fractions). Skips owners whose sourceRev is current. Idle-time, one PDF page per slice.
/// (v2.1) Pauses while SearchIndex.status.rebuilding is true (drops its queue) and re-judges every
/// asset afterwards. The public constructor stays as below — CP-PDF-1 rejected: the document pool
/// and the schedule gate are injected inside pdf_io (provider / src-only factory), no new public
/// type. dispose() is idempotent.
final class PdfSearchIndexer {
  /// 원문 생성자: its own document pool (DefaultPdfDocumentPool over CorePdfNoteGateway(store)
  /// and PdfrxEngine.shared(), made on the first slice and disposed with the indexer) and the
  /// always-open gate (the indexer itself waits while the index rebuilds). Builds nothing and
  /// subscribes to nothing until start().
  PdfSearchIndexer(core.NoteStore store)
    : this._(store, null, const AlwaysOpenIndexerGate());

  PdfSearchIndexer._(this._store, this._pool, this._gate);

  final core.NoteStore _store;

  /// The injected pool (pdfSearchIndexerProvider — not disposed here); null = own pool.
  final PdfDocumentPool? _pool;
  final IndexerGate _gate;
  PdfDocumentPool? _ownPool;
  bool _started = false;
  bool _disposed = false;

  StreamSubscription<core.AssetId>? _arrivals;
  StreamSubscription<core.SearchIndexStatus>? _statusSub;

  /// null until the first status event.
  bool? _rebuilding;
  Completer<void>? _rebuildEnd;

  /// +1 when a rebuild starts: jobs of an older epoch stop at the next page boundary.
  int _epoch = 0;
  final Set<core.AssetId> _dirty = {};
  final Set<core.AssetId> _reported = {};
  final List<_Job> _queue = [];
  _Job? _current;
  bool _running = false;

  /// Idempotent; does nothing after dispose(). Waits while SearchIndex.status.rebuilding is true,
  /// then schedules the catch-up (one sourceRevs(pdf) query + listAssets(hasLocalBytes: true)) and
  /// listens to AssetStore.bytesArrived (a new PDF asset is queued) and SearchIndex.status
  /// (v2.1: rebuilding true ⇒ stop and drop the queue; false ⇒ catch-up again, re-judging every
  /// asset — 6.4.2).
  void start() {
    if (_disposed || _started) return;
    _started = true;
    _arrivals = _store.assets.bytesArrived.listen(
      (id) => unawaited(_onArrived(id)),
      onError: (Object e, StackTrace s) =>
          reportPdfError(e, s, 'pdf search index: bytesArrived'),
    );
    _statusSub = _store.search.status.listen(
      _onStatus,
      onError: (Object e, StackTrace s) =>
          reportPdfError(e, s, 'pdf search index: status'),
    );
  }

  /// Idempotent and safe to call again or after a failed start (01-infra R-3). Cancels the
  /// listeners, lets the slice in flight finish (≤ one PDF page) and returns; never waits for a
  /// CORE commit that is being retried (1차 7.2.9 v1.2 쓰기 Future 규칙).
  ///
  /// T27: the loop sees the flag before its next read or write and ends (the page in flight is
  /// not written — the '#0 last' rule picks it up next time); the own pool is disposed when the
  /// loop has ended.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _queue.clear();
    _completeRebuildEnd();
    unawaited(_arrivals?.cancel());
    unawaited(_statusSub?.cancel());
    _arrivals = null;
    _statusSub = null;
    if (!_running) await _disposeOwnPool();
  }

  // ------------------------------------------------------------------ status · catch-up

  void _onStatus(core.SearchIndexStatus s) {
    if (_disposed) return;
    final was = _rebuilding;
    _rebuilding = s.rebuilding;
    if (s.rebuilding) {
      if (was != true) {
        _epoch++;
        _queue.clear();
        final current = _current;
        if (current != null) _dirty.add(current.assetId);
      }
      return;
    }
    _completeRebuildEnd();
    // the first status, or a rebuild ended
    if (was != false) unawaited(_catchUp());
  }

  void _completeRebuildEnd() {
    final end = _rebuildEnd;
    _rebuildEnd = null;
    if (end != null && !end.isCompleted) end.complete();
  }

  Future<void> _catchUp() async {
    final epoch = _epoch;
    final Map<String, String> revs;
    final List<core.Asset> assets;
    try {
      revs = await _store.search.sourceRevs(core.SearchSource.pdf);
      assets = await _store.assets.listAssets(hasLocalBytes: true);
    } on Object catch (e, s) {
      reportPdfError(e, s, 'pdf search index: catch-up');
      return;
    }
    if (_disposed || epoch != _epoch || _rebuilding != false) return;
    final pdfs = [
      for (final a in assets)
        if (a.type == core.AssetType.pdf) a,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final asset in pdfs) {
      final id = asset.id;
      final want = PdfSearchUnitBuilder.sourceRevOf(id);
      if (!_dirty.contains(id) &&
          revs[PdfSearchUnitBuilder.ownerKeyOf(id, 0)] == want) {
        continue; // done
      }
      final prefix = '$id#';
      _enqueue(id, {
        for (final MapEntry(:key, :value) in revs.entries)
          if (value == want && key.startsWith(prefix))
            if (int.tryParse(key.substring(prefix.length)) case final i?
                when i != 0)
              i,
      });
    }
    _dirty.clear();
    _pump();
  }

  Future<void> _onArrived(core.AssetId id) async {
    if (_disposed || _rebuilding != false || _has(id)) return;
    try {
      final asset = await _store.assets.getAsset(id);
      if (asset == null ||
          asset.type != core.AssetType.pdf ||
          !asset.hasLocalBytes) {
        return;
      }
      final mark = await _store.search.sourceRevOf(
        core.SearchSource.pdf,
        PdfSearchUnitBuilder.ownerKeyOf(id, 0),
      );
      if (!_dirty.contains(id) &&
          mark == PdfSearchUnitBuilder.sourceRevOf(id)) {
        return;
      }
    } on Object catch (e, s) {
      reportPdfError(e, s, 'pdf search index: arrived asset $id');
      return;
    }
    if (_disposed || _rebuilding != false || _has(id)) return;
    _enqueue(id, const {});
    _pump();
  }

  bool _has(core.AssetId id) =>
      _current?.assetId == id || _queue.any((j) => j.assetId == id);

  void _enqueue(core.AssetId id, Set<int> done) {
    if (_has(id)) return;
    _queue.add(_Job(id, {...done}, _epoch));
  }

  // ------------------------------------------------------------------ the loop (6.4.2)

  void _pump() {
    if (_running || _disposed || _queue.isEmpty) return;
    _running = true;
    unawaited(
      _run().whenComplete(() {
        _running = false;
        if (_disposed) {
          unawaited(_disposeOwnPool());
        } else {
          _pump(); // queued while the loop was ending
        }
      }),
    );
  }

  Future<void> _run() async {
    while (!_disposed && _queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      _current = job;
      try {
        if (await _index(job) == _Outcome.stop) {
          _queue.clear(); // the next start() / bytesArrived goes on (6.4.4)
          return;
        }
      } on Object catch (e, s) {
        reportPdfError(e, s, 'pdf search index: ${job.assetId}');
      } finally {
        _current = null;
      }
    }
  }

  PdfDocumentPool _documents() =>
      _pool ??
      (_ownPool ??= DefaultPdfDocumentPool(
        engine: PdfrxEngine.shared(),
        gateway: CorePdfNoteGateway(_store),
      ));

  Future<void> _disposeOwnPool() async {
    final own = _ownPool;
    _ownPool = null;
    if (own == null) return;
    try {
      await own.dispose();
    } on Object catch (e, s) {
      reportPdfError(e, s, 'pdf search index: pool dispose');
    }
  }

  bool _live(_Job job) => !_disposed && job.epoch == _epoch;

  /// The gate's slot, then not rebuilding. [releaseDocument] gives the lease back (web S-8).
  Future<void> _slot({void Function()? releaseDocument}) async {
    await _gate.nextSlot(releaseDocument: releaseDocument);
    while (_rebuilding == true && !_disposed) {
      await (_rebuildEnd ??= Completer<void>()).future;
    }
  }

  void _reportOnce(core.AssetId id, Object e, StackTrace s, String what) {
    if (_reported.add(id)) reportPdfError(e, s, 'pdf search index: $what');
  }

  Future<_Outcome> _index(_Job job) async {
    final id = job.assetId;
    final pool = _documents();
    PdfDocumentLease? lease;
    try {
      lease = await pool.acquire(id);
    } on PdfIoException catch (e, s) {
      return _openFailed(job, e, s);
    }
    try {
      if (!_live(job)) return _Outcome.next;
      final pages = lease.document.info.pages;
      if (pages.isEmpty) {
        _reportOnce(id, StateError('no pages'), StackTrace.current, id);
        return await _markUnreadable(job);
      }
      for (final i in [for (var i = 1; i < pages.length; i++) i, 0]) {
        if (job.done.contains(i)) continue;
        await _slot(
          releaseDocument: () {
            lease?.release();
            lease = null;
          },
        );
        if (!_live(job)) return _Outcome.next;
        if (lease == null) {
          try {
            lease = await pool.acquire(id);
          } on PdfIoException catch (e, s) {
            return await _openFailed(job, e, s);
          }
          if (!_live(job)) return _Outcome.next;
        }
        List<core.SearchUnitDraft> units;
        try {
          final text = await lease!.document.loadText(i);
          final info = pages[i];
          units = PdfSearchUnitBuilder.build(
            text,
            ui.Size(info.width, info.height),
          );
        } on Object catch (e, s) {
          _reportOnce(id, e, s, 'text of $id page $i'); // the page stays empty
          units = const [];
        }
        if (!_live(job)) return _Outcome.next; // stop at the page boundary
        if (!await _write(job, i, units)) return _Outcome.stop;
        job.done.add(i);
      }
      return _Outcome.next;
    } finally {
      lease?.release();
    }
  }

  /// 6.4.4 for acquire: missing bytes → skipped (bytesArrived queues it again); corrupt /
  /// password → '#0' empty + current sourceRev, reported once; engine unavailable → stop.
  Future<_Outcome> _openFailed(_Job job, PdfIoException e, StackTrace s) async {
    switch (e.code) {
      case PdfErrorCode.assetMissing:
      case PdfErrorCode.cancelled:
        return _Outcome.next;
      case PdfErrorCode.engineUnavailable:
        reportPdfError(e, s, 'pdf search index: engine unavailable');
        return _Outcome.stop;
      case PdfErrorCode.corrupt || PdfErrorCode.passwordCancelled:
        _reportOnce(job.assetId, e, s, 'unreadable ${job.assetId}');
        return _markUnreadable(job);
      default:
        _reportOnce(job.assetId, e, s, 'open ${job.assetId}');
        return _Outcome.next;
    }
  }

  /// '#0' with no units and the current sourceRev: not tried again (6.4.4).
  Future<_Outcome> _markUnreadable(_Job job) async {
    await _slot();
    if (!_live(job)) return _Outcome.next;
    return await _write(job, 0, const []) ? _Outcome.next : _Outcome.stop;
  }

  /// replaceUnits, waited for (a CORE commit retry keeps the loop here). A write that
  /// overlapped a rebuild marks the asset dirty; an overlapped '#0' is removed at once
  /// (PDF-M4 ⑥). false = replaceUnits threw (reported; the loop stops).
  Future<bool> _write(
    _Job job,
    int pageIndex,
    List<core.SearchUnitDraft> units,
  ) async {
    final id = job.assetId;
    final key = PdfSearchUnitBuilder.ownerKeyOf(id, pageIndex);
    final epoch = _epoch;
    try {
      await _store.search.replaceUnits(
        core.SearchSource.pdf,
        key,
        units,
        sourceRev: PdfSearchUnitBuilder.sourceRevOf(id),
      );
    } on Object catch (e, s) {
      reportPdfError(e, s, 'pdf search index: replaceUnits $key');
      return false;
    }
    if (epoch != _epoch || _rebuilding == true) {
      _dirty.add(id);
      if (pageIndex == 0) {
        unawaited(
          _store.search
              .removeOwner(core.SearchSource.pdf, key)
              .catchError(
                (Object e, StackTrace s) =>
                    reportPdfError(e, s, 'pdf search index: removeOwner $key'),
              ),
        );
      }
    }
    return true;
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

/// Tests only: whether [indexer]'s loop is running, its queue (asset ids) and the dirty set.
@visibleForTesting
({bool running, List<core.AssetId> queued, Set<core.AssetId> dirty})
debugPdfSearchIndexerQueue(PdfSearchIndexer indexer) => (
  running: indexer._running,
  queued: [
    if (indexer._current case final c?) c.assetId,
    for (final j in indexer._queue) j.assetId,
  ],
  dirty: Set.unmodifiable(indexer._dirty),
);

enum _Outcome { next, stop }

/// One asset to index: the pages already current ([done], never 0) and the epoch it was queued
/// in.
final class _Job {
  _Job(this.assetId, this.done, this.epoch);
  final core.AssetId assetId;
  final Set<int> done;
  final int epoch;
}
