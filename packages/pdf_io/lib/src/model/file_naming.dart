// lib/src/model/file_naming.dart — 06-pdf 4.9, 6.11.10.
import '../export/export_types.dart';
import '../tuning.dart';

abstract final class PdfFileNaming {
  /// Rules 6.11.10. [currentPageNumber] is 1-based (for PdfExportCurrentPage).
  ///
  /// [selectedCount] defaults to the number of selected page ids. A current-page export
  /// without [currentPageNumber] gets no suffix.
  static String forExport(
    String noteTitle,
    PdfExportRange range, {
    int? currentPageNumber,
    int? selectedCount,
  }) {
    final base = sanitize(noteTitle);
    final suffix = switch (range) {
      PdfExportAllPages() => '',
      PdfExportCurrentPage() =>
        currentPageNumber == null ? '' : ' (p$currentPageNumber)',
      PdfExportSelectedPages(:final pageIds) =>
        ' (선택 ${selectedCount ?? pageIds.length}쪽)',
    };
    return '$base$suffix.pdf';
  }

  static final RegExp _forbidden = RegExp(r'[\\/:*?"<>|\u0000-\u001F]');
  static final RegExp _spaces = RegExp(r'\s+');
  static final RegExp _edges = RegExp(r'^[\s.]+|[\s.]+$');

  /// 6.11.10 rule 1: `\ / : * ? " < > |` and U+0000..U+001F → '_', runs of spaces → one,
  /// leading / trailing spaces and dots removed, at most PdfTuning.maxFileNameRunes runes,
  /// '' → '노트'. No extension is added.
  static String sanitize(String name) {
    var out = name.replaceAll(_forbidden, '_').replaceAll(_spaces, ' ');
    out = out.replaceAll(_edges, '');
    final runes = out.runes;
    if (runes.length > PdfTuning.maxFileNameRunes) {
      out = String.fromCharCodes(runes.take(PdfTuning.maxFileNameRunes));
      out = out.replaceAll(_edges, '');
    }
    return out.isEmpty ? '노트' : out;
  }

  /// Batch: second 'a.pdf' → 'a (2).pdf', third → 'a (3).pdf' (case-insensitive compare).
  ///
  /// A generated name never repeats a name used earlier in the list.
  static List<String> deduplicate(List<String> fileNames) {
    final used = <String>{};
    final out = <String>[];
    for (final name in fileNames) {
      if (used.add(name.toLowerCase())) {
        out.add(name);
        continue;
      }
      final dot = name.lastIndexOf('.');
      final stem = dot > 0 ? name.substring(0, dot) : name;
      final ext = dot > 0 ? name.substring(dot) : '';
      for (var n = 2; ; n++) {
        final candidate = '$stem ($n)$ext';
        if (used.add(candidate.toLowerCase())) {
          out.add(candidate);
          break;
        }
      }
    }
    return out;
  }
}
