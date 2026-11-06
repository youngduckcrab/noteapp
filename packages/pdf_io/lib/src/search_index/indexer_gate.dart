// lib/src/search_index/indexer_gate.dart — m5-7/06-pdf 4.1.1, 6.4.3 (src only — not exported,
// v2.1 PDF-M9: no new public type).
//
// When the next PdfSearchIndexer slice may run. The app gate (AppIndexerGate — app visible, no
// import / export running, render queue empty, on the web no other PDF document open, at least
// PdfTuning.indexSliceGap after the previous slice) and the test gates (always open / opened by
// hand) implement it. The indexer itself also waits while the search index rebuilds (6.4.2 —
// with every gate, the always-open one included).
//
// (T27) nextSlot takes [releaseDocument]: a gate that waits because the indexer's document
// should not stay open (web S-8 — another PDF document is open on screen) calls it once before
// it waits; the indexer then gives its lease back and borrows the document again when the slot
// comes (its page progress is kept).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../common/job_state.dart';
import '../providers.dart';
import '../tuning.dart';

/// When the next slice may run (6.4.3). The app gate (AppIndexerGate) and the test gates
/// (always open / opened by hand) implement it. Not exported.
abstract interface class IndexerGate {
  /// Completes when the next slice may run. [releaseDocument]: called (at most once per call)
  /// when the gate waits for the indexer's own document to be closed (web S-8).
  Future<void> nextSlot({void Function()? releaseDocument});
}

/// The gate of the public constructor PdfSearchIndexer(store): every slot is free at once.
/// PdfSearchIndexer itself still waits while SearchIndex.status.rebuilding is true.
final class AlwaysOpenIndexerGate implements IndexerGate {
  const AlwaysOpenIndexerGate();

  @override
  Future<void> nextSlot({void Function()? releaseDocument}) =>
      Future<void>.value();
}

/// Why the app gate is closed.
@visibleForTesting
enum IndexerGateClosed { hidden, pdfJob, rendering, otherDocument }

/// The gate pdfSearchIndexerProvider gives the indexer (6.4.3): the app is visible, no PDF
/// import / export is running, the PDF render queue is empty and — on the web — no other PDF
/// document is open (the indexer's own counts once: leased, or idle in the pool once given
/// back); at least PdfTuning.indexSliceGap after the previous slot. While closed it looks again
/// every indexSliceGap (a few provider reads — no work is done while it waits).
final class AppIndexerGate implements IndexerGate {
  AppIndexerGate(this.ref, {bool? web}) : web = web ?? kIsWeb;

  /// The provider's ref (pdfSearchIndexerProvider) — the conditions are read through it.
  final Ref ref;

  /// The web rule S-8 applies.
  final bool web;

  Stopwatch? _sinceLast;

  /// Why a slot would not be given now; null = open.
  @visibleForTesting
  IndexerGateClosed? closedBecause() {
    final life = WidgetsBinding.instance.lifecycleState;
    if (life != null && life != AppLifecycleState.resumed) {
      return IndexerGateClosed.hidden;
    }
    if (ref.read(pdfImportJobProvider) is PdfJobRunning ||
        ref.read(pdfExportJobProvider) is PdfJobRunning ||
        ref.read(pdfBatchExportJobProvider) is PdfJobRunning) {
      return IndexerGateClosed.pdfJob;
    }
    final stats = ref.read(pdfRenderStatsProvider).value;
    if (stats.queued + stats.inflight > 0) return IndexerGateClosed.rendering;
    if (web && stats.openDocuments > 1) return IndexerGateClosed.otherDocument;
    return null;
  }

  @override
  Future<void> nextSlot({void Function()? releaseDocument}) async {
    const gap = PdfTuning.indexSliceGap;
    final since = _sinceLast?.elapsed;
    if (since != null && since < gap) await Future<void>.delayed(gap - since);
    var released = false;
    while (true) {
      final closed = closedBecause();
      if (closed == null) break;
      if (closed == IndexerGateClosed.otherDocument &&
          !released &&
          releaseDocument != null) {
        released = true;
        releaseDocument();
        continue;
      }
      await Future<void>.delayed(gap);
    }
    _sinceLast = Stopwatch()..start();
  }
}
