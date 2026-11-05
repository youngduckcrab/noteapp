// lib/src/text/hangul_jamo.dart — internal (not exported), 06-pdf 4.8, 6.10.1.
//
// Foundation step B4 (T0): signature only; the composition comes with PDF T1.

abstract final class HangulJamo {
  /// Step 4 of 6.10.1 only: L (U+1100..U+1112) + V (U+1161..U+1175) [+ T (U+11A8..U+11C2)]
  /// and LV syllable + T → precomposed syllable. Other text unchanged.
  static String compose(String text) =>
      throw UnimplementedError('HangulJamo.compose (PDF T1)');
}
