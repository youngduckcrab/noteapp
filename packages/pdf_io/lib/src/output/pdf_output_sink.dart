// lib/src/output/pdf_output_sink.dart — 06-pdf 4.10, 6.12. The port only; the platform
// implementation is picked by output_sink_factory.dart (6.15). Results come as a LIST so
// bulk export can share several files at once; a single export passes [result].
import '../export/export_types.dart';

enum PdfOutputAction { share, download, openInNewTab }

enum PdfOutputOutcome {
  done,
  dismissedByUser,
  needsUserGesture,
  failed,
  unsupported,
}

abstract interface class PdfOutputSink {
  /// share: navigator.canShare({files: every result}) is true. download / openInNewTab: only
  /// when results.length == 1. iPad Safari, one file: {share, download, openInNewTab};
  /// desktop Chrome without file share: {download, openInNewTab}.
  Set<PdfOutputAction> availableActions(List<PdfExportResult> results);

  /// Web: MUST be called synchronously from a tap handler (navigator.share / window.open
  /// need transient user activation). ArgumentError when [action] is not available.
  Future<PdfOutputOutcome> deliver(
    List<PdfExportResult> results,
    PdfOutputAction action,
  );
}
