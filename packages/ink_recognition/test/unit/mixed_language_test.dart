// pickMixedCandidates — strategy B (m5-7/05-library 8.2 L2-09, 6.8): a
// Hangul ko top → ko list + en top; Latin only → en list + ko top; the rare
// Hangul en top under a Latin ko top → ko list; empty lists; duplicates are
// not added twice; scores are never compared across models.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/engines/mixed_language.dart';

TextCandidate _ko(String text, [double? score]) =>
    TextCandidate(text, score: score, languageTag: 'ko');
TextCandidate _en(String text, [double? score]) =>
    TextCandidate(text, score: score, languageTag: 'en');

List<String> _texts(List<TextCandidate> list) => [for (final c in list) c.text];

void main() {
  test('a Hangul ko top → the ko list, then the en top', () {
    final out = pickMixedCandidates(
      [_ko('오늘 회의'), _ko('오늘 회외')],
      [_en('ouel hoei'), _en('ouel hoe')],
    );
    expect(_texts(out), ['오늘 회의', '오늘 회외', 'ouel hoei']);
    expect(out.last.languageTag, 'en');
  });

  test('a mixed line with Hangul in the ko top stays on ko', () {
    final out = pickMixedCandidates([_ko('오늘 meeting 정리')], [_en('meeting')]);
    expect(_texts(out), ['오늘 meeting 정리', 'meeting']);
  });

  test('Latin only → the en list, then the ko top', () {
    final out = pickMixedCandidates(
      [_ko('Quarter1y'), _ko('Quarterly')],
      [_en('Quarterly review'), _en('Quarterly revicw')],
    );
    expect(_texts(out), ['Quarterly review', 'Quarterly revicw', 'Quarter1y']);
    expect(out.last.languageTag, 'ko');
  });

  test('a Hangul en top under a Latin ko top (rare) → the ko list', () {
    final out = pickMixedCandidates([_ko('API'), _ko('AP1')], [_en('가피')]);
    expect(_texts(out), ['API', 'AP1']);
  });

  test('empty lists', () {
    expect(pickMixedCandidates(const [], const []), isEmpty);
    expect(_texts(pickMixedCandidates(const [], [_en('notes')])), ['notes']);
    expect(_texts(pickMixedCandidates([_ko('노트')], const [])), ['노트']);
    expect(_texts(pickMixedCandidates([_ko('notes')], const [])), ['notes']);
    expect(_texts(pickMixedCandidates(const [], [_en('노트')])), ['노트']);
  });

  test('duplicates: the other top is added only when its text is new', () {
    expect(_texts(pickMixedCandidates([_ko('회의'), _ko('API')], [_en('API')])), [
      '회의',
      'API',
    ]);
    expect(
      _texts(pickMixedCandidates([_ko('Read')], [_en('Read'), _en('Rcad')])),
      ['Read', 'Rcad'],
    );
  });

  test('scores are never compared across models', () {
    // The en top scores far better — the Hangul ko top still leads.
    final ko = pickMixedCandidates([_ko('회의', 0.01)], [_en('hoei', 99)]);
    expect(_texts(ko), ['회의', 'hoei']);
    // The ko top scores better — Latin only still takes the en list.
    final en = pickMixedCandidates([_ko('Laplace', 99)], [_en('Laplacc', 0)]);
    expect(_texts(en), ['Laplacc', 'Laplace']);
    // Engine order inside a list is kept whatever the scores say.
    final order = pickMixedCandidates([_ko('가', 0.1), _ko('나', 0.9)], const []);
    expect(_texts(order), ['가', '나']);
  });

  test('the result is unmodifiable and keeps the candidates as given', () {
    final top = _en('notes', 0.5);
    final out = pickMixedCandidates(const [], [top]);
    expect(out.single, same(top));
    expect(() => out.add(_ko('x')), throwsUnsupportedError);
  });

  test('hasHangulSyllable: syllables only (not jamo, not Latin)', () {
    expect(hasHangulSyllable('가'), isTrue);
    expect(hasHangulSyllable('힣'), isTrue);
    expect(hasHangulSyllable('abc 1'), isFalse);
    expect(hasHangulSyllable('ㄱㅏ'), isFalse);
    expect(hasHangulSyllable(''), isFalse);
  });
}
