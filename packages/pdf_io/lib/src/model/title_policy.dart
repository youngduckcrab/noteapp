// lib/src/model/title_policy.dart — internal (not exported), 06-pdf 4.6.
import '../text/hangul_jamo.dart';
import '../tuning.dart';

abstract final class PdfTitlePolicy {
  static final RegExp _pdfExtension = RegExp(r'\.pdf$', caseSensitive: false);

  /// Note title from a file name (6.3): strip a trailing '.pdf' (any case), compose Hangul
  /// conjoining jamo (HangulJamo.compose = step 4 of 6.10.1, no lower-casing), trim,
  /// '' → 'PDF 문서', cut to 200 UTF-16 units without splitting a surrogate pair.
  static String fromFileName(String fileName) {
    var title = fileName.trim().replaceFirst(_pdfExtension, '');
    title = HangulJamo.compose(title).trim();
    if (title.isEmpty) return PdfTuning.defaultTitle;
    const max = PdfTuning.maxTitleLength;
    if (title.length > max) {
      var cut = max;
      final last = title.codeUnitAt(cut - 1);
      // A high surrogate at the cut: keep the pair whole.
      if (last >= 0xD800 && last <= 0xDBFF) cut--;
      title = title.substring(0, cut).trimRight();
    }
    return title.isEmpty ? PdfTuning.defaultTitle : title;
  }
}
