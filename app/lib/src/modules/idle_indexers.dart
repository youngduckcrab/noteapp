/// Start / stop seam of the two indexers (docs/plans/m5-7/01-infra.md 4.6.4,
/// 6.5; (v2.1) D2-16 / CD2-17).
///
/// Both indexers are `final class` (contract 7.2.11 · 7.2.12), so tests never
/// override their providers with fakes; they pass a recording
/// IndexerHandleReader to the module constructor instead.
library;

import 'package:ink_recognition/ink_recognition.dart'
    show handwritingIndexerProvider;
import 'package:pdf_io/pdf_io.dart' show pdfSearchIndexerProvider;

import '../bootstrap/idle_tasks.dart';

typedef IndexerHandle = ({
  void Function() start,
  Future<void> Function() dispose,
});
typedef IndexerHandleReader = IndexerHandle? Function(AppIdleContext context);

/// (start: indexer.start, dispose: indexer.dispose) of
/// context.read(pdfSearchIndexerProvider). Reading it builds the CORE gateway
/// and the document pool (it needs noteStoreProvider); it opens no document.
IndexerHandle? readPdfSearchIndexer(AppIdleContext context) {
  final indexer = context.read(pdfSearchIndexerProvider);
  return (start: indexer.start, dispose: indexer.dispose);
}

/// Same over context.read(handwritingIndexerProvider); null when that
/// provider is null (web, no recognizer).
IndexerHandle? readHandwritingIndexer(AppIdleContext context) {
  final indexer = context.read(handwritingIndexerProvider);
  if (indexer == null) return null;
  return (start: indexer.start, dispose: indexer.dispose);
}

/// Shared body of both idle tasks: h = reader(c); null → nothing; else
/// h.start(); c.onDispose(h.dispose). A start() throw is logged by the runner
/// (no dispose registered). dispose() is idempotent (contract 7.2.11 ·
/// 7.2.12 v2.1), so the provider's own onDispose may call it too.
Future<void> runIndexerTask(
  AppIdleContext context,
  IndexerHandleReader reader,
) async {
  final handle = reader(context);
  if (handle == null) return;
  handle.start();
  context.onDispose(handle.dispose);
}
