// lib/src/output/output_sink_stub.dart — platforms with neither dart:js_interop nor dart:io
// (06-pdf 4.10, 6.15): nothing can be delivered (the native app gets output_sink_native.dart).
//
// No action is available, so the result sheet shows no delivery button; deliver answers
// PdfOutputOutcome.unsupported (the outcome kept for this sink) instead of throwing.
import '../export/export_types.dart';
import 'document_output.dart';
import 'pdf_output_sink.dart';

/// web: browser sink; native: save dialog + the app's share; others: unsupported
PdfOutputSink createPlatformOutputSink({PdfShareFiles? share}) =>
    const _UnsupportedOutputSink();

final class _UnsupportedOutputSink implements PdfOutputSink {
  const _UnsupportedOutputSink();

  @override
  Set<PdfOutputAction> availableActions(List<PdfExportResult> results) =>
      const <PdfOutputAction>{};

  @override
  Future<PdfOutputOutcome> deliver(
    List<PdfExportResult> results,
    PdfOutputAction action,
  ) => Future.value(PdfOutputOutcome.unsupported);
}

// ---- (v2.17-md, C217M-12) DocumentFileOutput ------------------------------------

DocumentFileOutput createPlatformDocumentOutput({DocumentShareFile? share}) =>
    const _UnsupportedDocumentOutput();

final class _UnsupportedDocumentOutput implements DocumentFileOutput {
  const _UnsupportedDocumentOutput();

  @override
  Set<DocumentOutputAction> availableActions(DocumentFile file) => const {};

  @override
  String labelOf(DocumentOutputAction action) => switch (action) {
    DocumentOutputAction.share => '공유',
    DocumentOutputAction.save => '저장',
  };

  @override
  Future<PdfOutputOutcome> deliver(
    DocumentFile file,
    DocumentOutputAction action,
  ) => Future.value(PdfOutputOutcome.unsupported);
}
