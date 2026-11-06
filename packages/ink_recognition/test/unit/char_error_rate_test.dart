// The A-4 lab's CER (m5-7/05-library 8.2 L2-19, 6.20): the same text → 0;
// insertions, deletions and substitutions count 1 each over the target's
// code points; spaces are ignored; conjoining jamo (NFD input) is composed
// first (CORE SearchText.normalize); case folds; a group rate is summed
// distance ÷ summed length; the median of the times.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/src/lab/char_error_rate.dart';
import 'package:ink_recognition/src/lab/lab_sentences.dart';
import 'package:ink_recognition/src/lab/recognition_lab_sheet.dart';

void main() {
  test('the same text → 0', () {
    expect(charErrorRate('오늘 회의록을 정리했다', '오늘 회의록을 정리했다'), 0);
    expect(
      charErrorRate('Quarterly review notes', 'Quarterly review notes'),
      0,
    );
  });

  test('insertion, deletion and substitution count 1 each', () {
    // target '회의록' (3 code points)
    expect(charErrorCounts('회의록', '회의록을'), (distance: 1, length: 3));
    expect(charErrorCounts('회의록', '회록'), (distance: 1, length: 3));
    expect(charErrorCounts('회의록', '회외록'), (distance: 1, length: 3));
    expect(charErrorRate('회의록', '회외록'), closeTo(1 / 3, 1e-12));
    expect(charErrorCounts('kitten', 'sitting'), (distance: 3, length: 6));
    expect(charErrorRate('abc', ''), 1);
    expect(charErrorRate('ab', 'abcdef'), 2); // may pass 1
  });

  test('spaces are ignored (normalized, then removed)', () {
    expect(charErrorRate('오늘 회의록을 정리했다', '오늘회의록을정리했다'), 0);
    expect(charErrorRate('오늘 회의', '  오늘\t\n회의  '), 0);
    expect(cerCodePoints('a b c　d'), 'abcd'.runes.toList());
  });

  test('conjoining jamo (NFD input) is composed before comparing', () {
    // '한글' as conjoining jamo: ᄒ ᅡ ᆫ ᄀ ᅳ ᆯ
    const nfd = '한글';
    expect(nfd.runes, hasLength(6));
    expect(cerCodePoints(nfd), '한글'.runes.toList());
    expect(charErrorRate('한글', nfd), 0);
    expect(charErrorRate(nfd, '한글'), 0);
  });

  test('case folds; code points, not UTF-16 units', () {
    expect(charErrorRate('API 키', 'api 키'), 0);
    expect(charErrorCounts('a😀b', 'ab'), (distance: 1, length: 3));
  });

  test('an empty target: 0 for an empty answer, else 1', () {
    expect(charErrorRate('', ''), 0);
    expect(charErrorRate(' ', 'x'), 1);
  });

  test('a group rate is summed distance ÷ summed length', () {
    final results = List<LabResult?>.filled(kLabSentences.length, null);
    LabResult answered(String ko) => LabResult(
      lines: 1,
      texts: {for (final m in LabMode.values) m: ko},
      ms: {for (final m in LabMode.values) m: 10},
    );
    // Sentence 1 (10 code points without spaces) all right, sentence 2
    // (13) with 2 errors → 2 / 23, not the mean (0 + 2/13) / 2.
    expect(cerCodePoints(kLabSentences[0].text), hasLength(10));
    expect(cerCodePoints(kLabSentences[1].text), hasLength(13));
    results[0] = answered(kLabSentences[0].text);
    results[1] = answered('미분 방정식의 일반해를 구했어');
    final c = charErrorCounts(kLabSentences[1].text, '미분 방정식의 일반해를 구했어');
    expect(c.distance, 2);
    expect(
      labGroupCer(results, LabGroup.korean, LabMode.ko),
      closeTo(2 / 23, 1e-12),
    );
    expect(labGroupCer(results, LabGroup.mixed, LabMode.ko), isNull);
    // A failed sentence does not count.
    results[2] = const LabResult(lines: 1, texts: {}, ms: {}, error: 'x');
    expect(
      labGroupCer(results, LabGroup.korean, LabMode.ko),
      closeTo(2 / 23, 1e-12),
    );
  });

  test('median', () {
    expect(labMedian(const []), isNull);
    expect(labMedian(const [5]), 5);
    expect(labMedian(const [9, 1, 5]), 5);
    expect(labMedian(const [1, 2, 3, 10]), 3); // (2 + 3) / 2 rounded
  });

  test('30 fixed sentences: 10 per group, in group order', () {
    expect(kLabSentences, hasLength(30));
    for (final group in LabGroup.values) {
      expect(kLabSentences.where((s) => s.group == group), hasLength(10));
    }
    expect(kLabSentences.first.text, '오늘 회의록을 정리했다');
    expect(kLabSentences[10].text, '오늘 meeting 내용 정리');
    expect(kLabSentences[20].text, 'Quarterly review notes');
    expect({for (final s in kLabSentences) s.text}, hasLength(30));
  });
}
