// lib/src/export/export_types.dart — 06-pdf 4.9, 6.11; (2차) object warnings, m5-7/06-pdf 4.1.5.

import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

sealed class PdfExportRange {
  const PdfExportRange();
}

final class PdfExportAllPages extends PdfExportRange {
  const PdfExportAllPages();
}

final class PdfExportCurrentPage extends PdfExportRange {
  const PdfExportCurrentPage(this.pageId);
  final core.PageId pageId;
}

final class PdfExportSelectedPages extends PdfExportRange {
  /// exported in NOTE order, not list order
  const PdfExportSelectedPages(this.pageIds);
  final List<core.PageId> pageIds;
}

/// PDF pages whose original bytes are not on this device (6.11.2). Default blankPage + warning
/// (1차 Q12 답, PDF-S2); fail is kept for callers that must not produce partial files.
enum PdfMissingAssetPolicy { fail, blankPage }

@immutable
final class PdfExportOptions {
  const PdfExportOptions({
    this.range = const PdfExportAllPages(),
    this.includeInk = true,
    this.includeTemplates = true,
    this.missingAssetPolicy = PdfMissingAssetPolicy.blankPage,
    this.fileName,
  });
  final PdfExportRange range;
  final bool includeInk; // false = original pages only (F-15 '원본만')
  /// false = blank/template pages become plain white pages
  final bool includeTemplates;
  final PdfMissingAssetPolicy missingAssetPolicy;
  final String? fileName; // null → PdfFileNaming.forExport

  PdfExportOptions copyWith({
    PdfExportRange? range,
    bool? includeInk,
    bool? includeTemplates,
    PdfMissingAssetPolicy? missingAssetPolicy,
    String? fileName,
  }) => PdfExportOptions(
    range: range ?? this.range,
    includeInk: includeInk ?? this.includeInk,
    includeTemplates: includeTemplates ?? this.includeTemplates,
    missingAssetPolicy: missingAssetPolicy ?? this.missingAssetPolicy,
    fileName: fileName ?? this.fileName,
  );
}

sealed class PdfExportWarning {
  const PdfExportWarning();
}

/// Shown on the result sheet: '{pages}쪽은 원본이 없어 빈 페이지로 넣었어요' (6.14).
final class PdfExportBlankedMissingAsset extends PdfExportWarning {
  const PdfExportBlankedMissingAsset(this.notePageNumbers);
  final List<int> notePageNumbers; // 1-based, ascending
}

// (2차, m5-7/06-pdf 4.1.5) object warnings — R2-B4 declares them; the export service reports
// them from PDF T26 (switch only inside PDF — the result sheet). Like 1차, no ==.

/// '{pages}쪽의 이미지는 이 기기에 원본이 없거나 읽지 못해 빠졌어요'
final class PdfExportMissingImages extends PdfExportWarning {
  const PdfExportMissingImages(this.notePageNumbers);
  final List<int>
  notePageNumbers; // 1-based, ascending (1차 PdfExportBlankedMissingAsset과 같음)
}

/// '{pages}쪽의 텍스트 상자 일부는 그림으로 넣었어요 — PDF에서 검색되지 않아요'
final class PdfExportRasterizedText extends PdfExportWarning {
  const PdfExportRasterizedText(this.notePageNumbers);
  final List<int> notePageNumbers;
}

/// '{pages}쪽의 수식 일부를 그리지 못해 빠졌어요'
final class PdfExportSkippedFormulas extends PdfExportWarning {
  const PdfExportSkippedFormulas(this.notePageNumbers);
  final List<int> notePageNumbers;
}

/// Holds the PDF bytes → NO ==/hashCode override: identity equality (contract 7.4.4 value
/// equality is for state classes; PdfJobSucceeded of PdfExportResult compares this object).
/// The same holds for PdfBatchExportItem and PdfBatchExportResult below.
@immutable
final class PdfExportResult {
  const PdfExportResult({
    required this.bytes,
    required this.fileName,
    required this.pageCount,
    required this.elapsed,
    this.warnings = const [],
  });
  final Uint8List bytes;
  final String fileName; // ends with '.pdf'
  final int pageCount;
  final Duration elapsed;
  final List<PdfExportWarning> warnings;
  String get mimeType => 'application/pdf';
}
