// lib/src/common/progress.dart — 06-pdf 4.2.
import 'package:flutter/foundation.dart';

import '../ui/strings_ko.dart';

enum PdfJobPhase {
  // import
  readingFile,
  openingPdf,
  storingPdf,
  creatingPages,
  coverThumbnail,
  // export
  preparingExport,
  composing,
  finishingExport,
}

@immutable
final class PdfProgress {
  const PdfProgress(this.phase, {this.done = 0, this.total = 0});
  final PdfJobPhase phase;
  final int done;
  final int total; // 0 = indeterminate

  /// null when total == 0
  double? get fraction => total == 0 ? null : done / total;

  /// Korean, e.g. 'PDF 여는 중', '페이지 합성 중 (12/40)'
  String get label => PdfStringsKo.progressLabel(this);

  /// phase, done, total
  @override
  bool operator ==(Object other) =>
      other is PdfProgress &&
      other.phase == phase &&
      other.done == done &&
      other.total == total;

  @override
  int get hashCode => Object.hash(phase, done, total);

  @override
  String toString() => 'PdfProgress(${phase.name}, $done/$total)';
}

typedef PdfProgressCallback = void Function(PdfProgress progress);

/// Bulk export progress (exportNotes, 4.9).
@immutable
final class PdfBatchProgress {
  const PdfBatchProgress({
    required this.noteIndex,
    required this.noteCount,
    required this.current,
  });
  final int noteIndex; // 0-based index of the note being exported
  final int noteCount;
  final PdfProgress current; // progress inside that note

  /// (noteIndex + (current.fraction ?? 0)) / noteCount.
  double get fraction => (noteIndex + (current.fraction ?? 0)) / noteCount;

  /// '노트 2/5 · 페이지 합성 중 (12/40)'
  String get label => PdfStringsKo.batchProgressLabel(this);

  /// noteIndex, noteCount, current
  @override
  bool operator ==(Object other) =>
      other is PdfBatchProgress &&
      other.noteIndex == noteIndex &&
      other.noteCount == noteCount &&
      other.current == current;

  @override
  int get hashCode => Object.hash(noteIndex, noteCount, current);

  @override
  String toString() =>
      'PdfBatchProgress(note ${noteIndex + 1}/$noteCount, $current)';
}

typedef PdfBatchProgressCallback = void Function(PdfBatchProgress progress);
