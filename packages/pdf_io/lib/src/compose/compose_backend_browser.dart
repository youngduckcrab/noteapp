// lib/src/compose/compose_backend_browser.dart — web compose backend (dedicated Worker,
// 06-pdf 6.11.6). Only *_browser.dart files may import dart:js_interop / package:web
// (contract 7.4.3); loaded only through compose_backend_factory.dart.
//
// Foundation step B4 (T0): placeholder; the worker backend comes with PDF T14.
import '../config.dart';
import 'compose_backend.dart';

/// Web: dedicated Worker (pdfrx pdfium_worker.js + pdf_io_compose_ext.js), chunk 16 pages.
/// VM/native: FFI interpreter on the pdfrx background isolate, chunk 8 pages. Other: unsupported.
PdfComposeBackend createPlatformComposeBackend(PdfIoConfig config) =>
    throw UnimplementedError('createPlatformComposeBackend (web, PDF T14)');
