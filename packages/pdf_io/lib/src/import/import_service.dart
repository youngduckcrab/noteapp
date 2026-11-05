// lib/src/import/import_service.dart — 06-pdf 4.6, 6.3, 6.4.
//
// Foundation step B4 (T0): signatures only; the service comes with PDF T5.
import 'package:note_core/note_core.dart' as core;

import '../common/cancel_signal.dart';
import '../common/progress.dart';
import '../config.dart';
import '../engine/page_info.dart';
import '../engine/pdf_engine.dart';
import '../files/pdf_file_source.dart';
import '../gateway/pdf_note_gateway.dart';
import '../model/page_range.dart';
import '../render/document_pool.dart';
import '../render/render_service.dart';
import 'import_types.dart';

abstract interface class PdfImportService {
  /// Reads and opens the file (password prompts via [onPassword]); checks limits and the
  /// user-password policy. Throws notPdf / tooLarge / tooManyPages / passwordCancelled /
  /// userPasswordRefused / corrupt / pickerFailed / engineUnavailable.
  Future<PdfImportSession> open(
    PickedPdfFile file, {
    PdfPasswordCallback? onPassword,
    PdfProgressCallback? onProgress,
    PdfCancelSignal? cancel,
  });
}

/// An opened, not yet committed import. Keeps the bytes and the engine document.
abstract interface class PdfImportSession {
  PickedPdfFile get file;
  PdfDocumentInfo get info;
  int get byteLength;
  bool get isLargeFile; // byteLength > limits.warnBytes
  /// info.usedPassword (policy storeDecryptedCopy)
  bool get willStoreDecryptedCopy;
  String get suggestedTitle; // PdfTitlePolicy.fromFileName(file.name)

  /// Stores the asset, creates the pages, hands the opened document to the pool, writes the
  /// new note's cover (6.3). Cancellable until pages are created: the putPdf wait is raced
  /// with [cancel] (PdfCancelSignal.raceCancel → cancelled at once); once createNote /
  /// insertPages is called it is not cancellable.
  /// While CORE retries a failed commit (putPdf's metadata commit, createNote, the session
  /// open / page loads of insertPages) this Future stays pending — no completion, no error
  /// (contract 7.2.9 v1.2); the progress dialog shows the delay text and '닫기' (6.3).
  /// Throws storageFailed (put byte-chunk write / other NoteCoreException — 4.4) /
  /// noteNotFound / readOnlyNote / cancelled.
  Future<PdfImportResult> commit(
    PdfImportTarget target, {
    PdfPageRange range = const PdfPageRange.all(),
    PdfProgressCallback? onProgress,
    PdfCancelSignal? cancel,
  });
  Future<void> dispose(); // idempotent; closes the document if not committed
}

final class DefaultPdfImportService implements PdfImportService {
  /// [thumbnailRenderer] = core.pageThumbnailRendererProvider (INK renderer from INFRA, or null).
  DefaultPdfImportService({
    required PdfEngine engine,
    required PdfNoteGateway gateway,
    required PdfDocumentPool pool,
    required PdfPageRenderer renderer,
    required PdfIoConfig config,
    core.PageThumbnailRenderer? thumbnailRenderer,
  });

  @override
  Future<PdfImportSession> open(
    PickedPdfFile file, {
    PdfPasswordCallback? onPassword,
    PdfProgressCallback? onProgress,
    PdfCancelSignal? cancel,
  }) => throw UnimplementedError('DefaultPdfImportService.open (PDF T5)');
}
