// lib/src/compose/compose_backend_factory.dart (conditional export, 06-pdf 4.9, 6.15) —
// only declares createPlatformComposeBackend:
//
//   /// Web: dedicated Worker (pdfrx pdfium_worker.js + pdf_io_compose_ext.js), chunk 16 pages.
//   /// VM/native: FFI interpreter on the pdfrx background isolate, chunk 8 pages. Other: unsupported.
//   PdfComposeBackend createPlatformComposeBackend(PdfIoConfig config);
export 'compose_backend_stub.dart'
    if (dart.library.js_interop) 'compose_backend_browser.dart'
    if (dart.library.ffi) 'compose_backend_native.dart';
