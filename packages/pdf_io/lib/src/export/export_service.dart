// lib/src/export/export_service.dart — 06-pdf 4.9, 6.11.2, 6.11.11.
//
// Foundation step B4 (T0): signatures only; the export service comes with PDF T15 / T15b.
import 'package:note_core/note_core.dart' as core;

import '../common/cancel_signal.dart';
import '../common/progress.dart';
import '../compose/compose_backend.dart';
import '../gateway/pdf_note_gateway.dart';
import 'batch_export.dart';
import 'export_types.dart';
import 'vectors.dart';

abstract interface class PdfExportService {
  /// Starts with cancel.raceCancel(gateway.flush()) (6.11.2 step 1): pending while CORE
  /// retries a commit (contract 7.2.9 v1.2); cancel() → cancelled at once (nothing composed).
  /// Throws assetMissing (policy fail) / noteNotFound / exportFailed / cancelled /
  /// engineUnavailable / busy.
  Future<PdfExportResult> exportNote(
    core.NoteId noteId,
    PdfExportOptions options, {
    PdfProgressCallback? onProgress,
    PdfCancelSignal? cancel,
  });

  /// Notes one after another in [noteIds] order with options.copyWith(range: all pages)
  /// (6.11.11). Per-note failures are recorded in the items, not thrown. Cancel → result
  /// .cancelled with the files made so far. Throws only busy / engineUnavailable /
  /// unsupportedPlatform.
  Future<PdfBatchExportResult> exportNotes(
    List<core.NoteId> noteIds,
    PdfExportOptions options, {
    PdfBatchProgressCallback? onProgress,
    PdfCancelSignal? cancel,
  });
}

final class DefaultPdfExportService implements PdfExportService {
  DefaultPdfExportService({
    required PdfNoteGateway gateway,
    required PdfInkVectorizer vectorizer,
    required PdfComposeBackend backend,
  });

  @override
  Future<PdfExportResult> exportNote(
    core.NoteId noteId,
    PdfExportOptions options, {
    PdfProgressCallback? onProgress,
    PdfCancelSignal? cancel,
  }) =>
      throw UnimplementedError('DefaultPdfExportService.exportNote (PDF T15)');

  @override
  Future<PdfBatchExportResult> exportNotes(
    List<core.NoteId> noteIds,
    PdfExportOptions options, {
    PdfBatchProgressCallback? onProgress,
    PdfCancelSignal? cancel,
  }) => throw UnimplementedError(
    'DefaultPdfExportService.exportNotes (PDF T15b)',
  );
}
