// lib/src/output/output_sink_stub.dart — platforms without dart:js_interop (06-pdf 4.10,
// 6.15): nothing can be delivered in this scope (native share / print come later, 1.3).
//
// Foundation step B4 (T0): no action is available; deliver comes with PDF T16.
import '../export/export_types.dart';
import 'pdf_output_sink.dart';

/// web: browser sink; others: unsupported
PdfOutputSink createPlatformOutputSink() => const _UnsupportedOutputSink();

final class _UnsupportedOutputSink implements PdfOutputSink {
  const _UnsupportedOutputSink();

  @override
  Set<PdfOutputAction> availableActions(List<PdfExportResult> results) =>
      const <PdfOutputAction>{};

  @override
  Future<PdfOutputOutcome> deliver(
    List<PdfExportResult> results,
    PdfOutputAction action,
  ) => throw UnimplementedError('PdfOutputSink.deliver (stub, PDF T16)');
}
