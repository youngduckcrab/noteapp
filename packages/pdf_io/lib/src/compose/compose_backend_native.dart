// lib/src/compose/compose_backend_native.dart — VM / native compose backend (FFI
// interpreter on the pdfrx background isolate, 06-pdf 6.11.7). Only this file may import
// dart:ffi / package:ffi / package:pdfium_dart (contract 7.4.3); loaded only through
// compose_backend_factory.dart.
//
// Foundation step B4 (T0): placeholder; the FFI backend comes with PDF T13.
import '../config.dart';
import 'compose_backend.dart';

/// Web: dedicated Worker (pdfrx pdfium_worker.js + pdf_io_compose_ext.js), chunk 16 pages.
/// VM/native: FFI interpreter on the pdfrx background isolate, chunk 8 pages. Other: unsupported.
PdfComposeBackend createPlatformComposeBackend(PdfIoConfig config) =>
    throw UnimplementedError('createPlatformComposeBackend (native, PDF T13)');
