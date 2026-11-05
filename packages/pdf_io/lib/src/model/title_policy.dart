// lib/src/model/title_policy.dart — internal (not exported), 06-pdf 4.6.
//
// Foundation step B4 (T0): signature only; the policy comes with PDF T1.

abstract final class PdfTitlePolicy {
  /// Note title from a file name (6.3): strip a trailing '.pdf' (any case), compose Hangul
  /// conjoining jamo (HangulJamo.compose = step 4 of 6.10.1, no lower-casing), trim,
  /// '' → 'PDF 문서', cut to 200 UTF-16 units without splitting a surrogate pair.
  static String fromFileName(String fileName) =>
      throw UnimplementedError('PdfTitlePolicy.fromFileName (PDF T1)');
}
