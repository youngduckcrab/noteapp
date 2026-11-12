// lib/src/output/pdf_output_sink.dart — 06-pdf 4.10, 6.12. The port only; the platform
// implementation is picked by output_sink_factory.dart (6.15). Results come as a LIST so
// bulk export can share several files at once; a single export passes [result].
//
// Native app (Android / iOS): the sink offers download as '저장' (the system save dialog —
// file_picker) and share through a [PdfShareFiles] the app provides (pdfShareFilesProvider):
// pdf_io may not add a plugin of its own (contract 7.4.1, R16), so the share plugin lives in
// the app.
import '../export/export_types.dart';

enum PdfOutputAction { share, download, openInNewTab }

enum PdfOutputOutcome {
  done,
  dismissedByUser,
  needsUserGesture,
  failed,
  unsupported,
}

/// Native share of every result at once (the app's share sheet plugin). Completes with
/// done / dismissedByUser / failed; may throw (the sink answers failed).
typedef PdfShareFiles = Future<PdfOutputOutcome> Function(
  List<PdfExportResult> results,
);

/// Internal (not exported): a sink that names its own buttons — the native sink shows
/// [PdfOutputAction.download] as '저장'. The result sheet falls back to its labels for
/// other sinks (web: '다운로드').
abstract interface class PdfOutputActionLabels {
  String labelOf(PdfOutputAction action);
}

abstract interface class PdfOutputSink {
  /// share: navigator.canShare({files: every result}) is true. download / openInNewTab: only
  /// when results.length == 1. iPad Safari, one file: {share, download, openInNewTab};
  /// desktop Chrome without file share: {download, openInNewTab}. Native: {share} when the
  /// app provides a [PdfShareFiles], plus download ('저장') when results.length == 1.
  Set<PdfOutputAction> availableActions(List<PdfExportResult> results);

  /// Web: MUST be called synchronously from a tap handler (navigator.share / window.open
  /// need transient user activation). ArgumentError when [action] is not available.
  Future<PdfOutputOutcome> deliver(
    List<PdfExportResult> results,
    PdfOutputAction action,
  );
}
