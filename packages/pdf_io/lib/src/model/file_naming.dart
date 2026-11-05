// lib/src/model/file_naming.dart — 06-pdf 4.9, 6.11.10.
//
// Foundation step B4 (T0): signatures only; the rules come with PDF T1.
import '../export/export_types.dart';

abstract final class PdfFileNaming {
  /// Rules 6.11.10. [currentPageNumber] is 1-based (for PdfExportCurrentPage).
  static String forExport(
    String noteTitle,
    PdfExportRange range, {
    int? currentPageNumber,
    int? selectedCount,
  }) => throw UnimplementedError('PdfFileNaming.forExport (PDF T1)');

  static String sanitize(String name) =>
      throw UnimplementedError('PdfFileNaming.sanitize (PDF T1)');

  /// Batch: second 'a.pdf' → 'a (2).pdf', third → 'a (3).pdf' (case-insensitive compare).
  static List<String> deduplicate(List<String> fileNames) =>
      throw UnimplementedError('PdfFileNaming.deduplicate (PDF T1)');
}
