// lib/src/compose/compose_backend_stub.dart — platforms without dart:ffi or
// dart:js_interop (6.15): isSupported == false, begin → unsupportedPlatform.
import '../config.dart';
import '../errors.dart';
import '../export/compose_plan.dart';
import 'compose_backend.dart';

/// Web: dedicated Worker (pdfrx pdfium_worker.js + pdf_io_compose_ext.js), chunk 16 pages.
/// VM/native: FFI interpreter on the pdfrx background isolate, chunk 8 pages. Other: unsupported.
PdfComposeBackend createPlatformComposeBackend(PdfIoConfig config) =>
    const _UnsupportedComposeBackend();

final class _UnsupportedComposeBackend implements PdfComposeBackend {
  const _UnsupportedComposeBackend();

  @override
  bool get isSupported => false;

  @override
  Future<PdfComposeJob> begin(PdfComposePlan plan) =>
      Future<PdfComposeJob>.error(
        const PdfIoException(
          PdfErrorCode.unsupportedPlatform,
          detail: 'no PDF compose backend on this platform',
        ),
      );

  @override
  Future<void> dispose() async {}
}
