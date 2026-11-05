// lib/src/export/batch_export.dart — F-01 bulk export (contract 7.8), 06-pdf 4.9, 6.11.11.
// Both types hold export results (bytes) → identity equality, no ==/hashCode override (4.9).
import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

import '../errors.dart';
import 'export_types.dart';

@immutable
final class PdfBatchExportItem {
  const PdfBatchExportItem({
    required this.noteId,
    required this.title,
    this.result,
    this.error,
  });
  final core.NoteId noteId;
  final String title; // note title at export time ('' when the note is missing)
  /// fileName already de-duplicated within the batch
  final PdfExportResult? result;
  final PdfIoException? error; // noteNotFound / assetMissing / exportFailed ...
  bool get succeeded => result != null; // result != null
}

@immutable
final class PdfBatchExportResult {
  const PdfBatchExportResult({
    required this.requestedCount,
    required this.items,
    this.cancelled = false,
    this.stoppedAtSizeLimit = false,
  });
  final int requestedCount;

  /// input order; notes not reached are absent
  final List<PdfBatchExportItem> items;
  final bool cancelled;

  /// web: results reached PdfTuning.batchMaxTotalBytesWeb
  final bool stoppedAtSizeLimit;

  /// succeeded results, input order
  List<PdfExportResult> get files => [for (final item in items) ?item.result];

  /// requestedCount - items.length
  int get notReachedCount => requestedCount - items.length;
}
