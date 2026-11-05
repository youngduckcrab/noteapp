// lib/src/text/text_service.dart — 06-pdf 4.8, 6.10.
//
// Foundation step B4 (T0): signatures only; text extraction and search come with PDF T11.
import 'package:note_core/note_core.dart' as core;

import '../common/cancel_signal.dart';
import '../engine/page_info.dart';
import '../gateway/pdf_note_gateway.dart';
import '../render/document_pool.dart';
import '../tuning.dart';
import 'search_types.dart';

abstract interface class PdfTextService {
  /// Cached (LRU PdfTuning.textCachePages). Throws assetMissing / corrupt.
  Future<PdfPageTextData> pageText(core.AssetId assetId, int pdfPageIndex);

  /// Scans PDF-background pages of the note in note order (non-PDF pages are skipped;
  /// totalPages counts PDF pages only). Emits every 10 pages or 100 ms.
  /// Starts with cancel.raceCancel(gateway.flush()) (6.10.2): the flush stays pending while
  /// CORE retries a commit (contract 7.2.9 v1.2); cancel() ends the stream at once (no error).
  Stream<PdfSearchProgress> searchNote(
    core.NoteId noteId,
    String query, {
    PdfCancelSignal? cancel,
    int maxHits = PdfTuning.maxSearchHits,
  });
  void clearCache();
}

final class DefaultPdfTextService implements PdfTextService {
  DefaultPdfTextService({
    required PdfDocumentPool pool,
    required PdfNoteGateway gateway,
  });

  static Never _t11(String member) =>
      throw UnimplementedError('DefaultPdfTextService.$member (PDF T11)');

  @override
  Future<PdfPageTextData> pageText(core.AssetId assetId, int pdfPageIndex) =>
      _t11('pageText');

  @override
  Stream<PdfSearchProgress> searchNote(
    core.NoteId noteId,
    String query, {
    PdfCancelSignal? cancel,
    int maxHits = PdfTuning.maxSearchHits,
  }) => _t11('searchNote');

  @override
  void clearCache() => _t11('clearCache');
}
