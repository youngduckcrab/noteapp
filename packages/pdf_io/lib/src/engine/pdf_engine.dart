// lib/src/engine/pdf_engine.dart — 06-pdf 4.3. pdf_io never uses pdfrx directly; it goes
// through this port (tests use FakePdfEngine, 4.14).
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../tuning.dart';
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

/// Internal (not exported): '%PDF-' within the first PdfTuning.pdfMagicSearchBytes bytes
/// (6.3 step 3). Engines and the import service reject other bytes with notPdf.
bool hasPdfMagic(Uint8List bytes) {
  const magic = [0x25, 0x50, 0x44, 0x46, 0x2D]; // %PDF-
  final end = bytes.length < PdfTuning.pdfMagicSearchBytes
      ? bytes.length
      : PdfTuning.pdfMagicSearchBytes;
  outer:
  for (var i = 0; i + magic.length <= end; i++) {
    for (var j = 0; j < magic.length; j++) {
      if (bytes[i + j] != magic[j]) continue outer;
    }
    return true;
  }
  return false;
}
