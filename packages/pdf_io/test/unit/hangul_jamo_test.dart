// HangulJamo.compose (06-pdf 4.8, 6.10.1 step 4, 8 T1) — internal, imported by path.
// (2차, T28) It lives in text_normalizer.dart now and composes through CORE's
// SearchText.normalize; these 1차 vectors stay as they were.
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/src/text/text_normalizer.dart';

void main() {
  test('ᄀ + ᅡ → 가', () {
    expect(HangulJamo.compose('가'), '가');
  });

  test('ᄀ + ᅡ + ᆨ → 각', () {
    expect(HangulJamo.compose('각'), '각');
  });

  test('가 + ᆨ → 각 (LV syllable + T)', () {
    expect(HangulJamo.compose('각'), '각');
  });

  test('whole words, edges of the jamo blocks', () {
    // 강의 in conjoining jamo (NFD, as macOS file names arrive).
    expect(HangulJamo.compose('강의'), '강의');
    // Last L, V and T: ᄒ + ᅵ + ᇂ → 힣.
    expect(HangulJamo.compose('힣'), '힣');
    // T after a syllable that already has a final consonant stays as it is.
    expect(HangulJamo.compose('각ᆨ'), '각ᆨ');
  });

  test('non-Hangul text and lone jamo stay unchanged', () {
    expect(HangulJamo.compose('abc 123'), 'abc 123');
    expect(HangulJamo.compose('강의'), '강의');
    expect(HangulJamo.compose('ᄀ'), 'ᄀ');
    expect(HangulJamo.compose('ᅡx'), 'ᅡx');
    expect(HangulJamo.compose('😀가😀'), '😀가😀');
    expect(HangulJamo.compose(''), '');
  });
}
