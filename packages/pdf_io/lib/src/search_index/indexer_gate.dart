// lib/src/search_index/indexer_gate.dart — m5-7/06-pdf 4.1.1, 6.4.3 (src only — not exported,
// v2.1 PDF-M9: no new public type).
//
// When the next PdfSearchIndexer slice may run. The app gate (AppIndexerGate — app visible,
// search index not rebuilding, no import / export running, render queue empty) and the test
// gates (always open / opened by hand) implement it.
//
// 2차 foundation step R2-B4 (T20): the port, the always-open gate and the app gate's shape.
// PdfSearchIndexer.start() does nothing yet, so no gate is asked; PDF T27 gives the app gate
// its conditions (6.4.3) and closes the always-open gate while the index rebuilds (6.4.2).
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// When the next slice may run (6.4.3). The app gate (AppIndexerGate) and the test gates
/// (always open / opened by hand) implement it. Not exported.
abstract interface class IndexerGate {
  Future<void> nextSlot();
}

/// The gate of the public constructor PdfSearchIndexer(store): every slot is free at once.
/// (T27) PdfSearchIndexer itself still waits while SearchIndex.status.rebuilding is true.
final class AlwaysOpenIndexerGate implements IndexerGate {
  const AlwaysOpenIndexerGate();

  @override
  Future<void> nextSlot() => Future<void>.value();
}

/// The gate pdfSearchIndexerProvider gives the indexer (6.4.3): the app is visible, the
/// search index is not rebuilding, no PDF import / export is running and the PDF render
/// queue is empty; at least PdfTuning.indexSliceGap after the previous slice.
final class AppIndexerGate implements IndexerGate {
  AppIndexerGate(this.ref);

  /// The provider's ref (pdfSearchIndexerProvider) — the conditions are read through it.
  final Ref ref;

  /// R2-B4: not asked yet (start() does nothing).
  @override
  Future<void> nextSlot() =>
      throw UnimplementedError('PDF T27: app indexer gate (06-pdf 6.4.3)');
}
