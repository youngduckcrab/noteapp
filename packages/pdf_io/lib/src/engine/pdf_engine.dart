// lib/src/engine/pdf_engine.dart — 06-pdf 4.3. pdf_io never uses pdfrx directly; it goes
// through this port (tests use FakePdfEngine, 4.14).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'page_info.dart';

abstract interface class PdfEngine {
  bool get isInitialized;

  /// Idempotent. Web: loads pdfium_client.js and instantiates pdfium.wasm in the pdfrx worker.
  /// Throws PdfIoException(engineUnavailable).
  Future<void> ensureInitialized();

  /// Throws notPdf / corrupt / passwordCancelled / engineUnavailable.
  /// [transferOwnership]: web may detach [bytes] (pass true only if the caller never reads them again).
  Future<PdfEngineDocument> open(
    Uint8List bytes, {
    required String sourceName,
    String fileName = '',
    PdfPasswordCallback? onPassword,
    int maxPasswordAttempts = 5,
    bool transferOwnership = false,
  });
}

abstract interface class PdfEngineDocument {
  String get sourceName;
  PdfDocumentInfo get info;
  bool get isDisposed;

  /// Returns null when cancelled. The caller owns (and must dispose) the image.
  Future<ui.Image?> render(
    PdfRenderRequest request, {
    PdfRenderCancelToken? cancelToken,
  });
  Future<PdfPageTextData> loadText(int pageIndex);

  /// Re-encodes without the security handler (FPDF_SAVE_NO_SECURITY). Used for
  /// user-password PDFs on import (6.4).
  Future<Uint8List> encodeWithoutSecurity();
  Future<void> dispose(); // idempotent
}
