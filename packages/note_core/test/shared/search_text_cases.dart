// Shared body (m5-7/02-core 6.10.1, 6.9.2, 6.10.4, 6.10.3): SearchText.normalize vectors,
// normalizeMapped(x).text == normalize(x), HandwritingText.sourceRevOf fixed vectors, the score
// bits and the rects blob bytes — identical on the VM (test/search/search_text_test.dart) and in
// Chrome (test/web/search_text_browser_test.dart). Web-safe.
import 'package:note_core/note_core.dart';
import 'package:note_core/src/search/search_ranking.dart';
import 'package:note_core/src/search/search_rects.dart';
import 'package:test/test.dart';

/// (input, SearchText.normalize(input)) — PDF copies this table to compare PdfTextNormalizer
/// (C2-27).
const List<(String, String)> kSearchTextVectors = [
  // Hangul: conjoining jamo (NFD) → syllables; LV syllable + T.
  ('한글', '한글'),
  ('한', '한'),
  ('하', '하'),
  // Line-end hyphenation between letters / digits (\n and \r\n); other hyphens stay.
  ('회의-\n록', '회의록'),
  ('ab-\r\ncd', 'abcd'),
  ('3-\n4', '34'),
  ('a -\nb', 'a - b'),
  ('well-known', 'well-known'),
  // Zero-width / soft hyphen / BOM dropped.
  ('x­y​z‌‍﻿', 'xyz'),
  // Whitespace runs (NBSP, ideographic space, tabs, line breaks) → one space; trimmed.
  ('  Hello 　World  ', 'hello world'),
  ('line1\nline2\tend', 'line1 line2 end'),
  ('a ​ b', 'a b'),
  (' a ', 'a'),
  ('', ''),
  ('   ', ''),
  // Lowercase per code point: Turkish İ → i (every platform), Greek Σ → σ (no final sigma).
  ('İSTANBUL', 'istanbul'),
  ('ΟΔΟΣ', 'οδοσ'),
  ('ÀÉÎ Café', 'àéî café'),
  // Emoji (a surrogate pair) and fullwidth Latin (lowercased, not folded to ASCII).
  ('😀 Ａ Café', '😀 ａ café'),
  ('MEETING Notes', 'meeting notes'),
];

void defineSearchTextCases() {
  group('SearchText.normalize (6.10.1)', () {
    test('vectors', () {
      for (final (input, expected) in kSearchTextVectors) {
        expect(
          SearchText.normalize(input),
          expected,
          reason: '${input.codeUnits}',
        );
      }
    });

    test(
      'normalizeMapped(x).text == normalize(x); ranges inside the input',
      () {
        for (final (input, _) in kSearchTextVectors) {
          final m = SearchText.normalizeMapped(input);
          expect(m.text, SearchText.normalize(input), reason: input);
          expect(m.sourceStart.length, m.text.length);
          expect(m.sourceEnd.length, m.text.length);
          for (var i = 0; i < m.text.length; i++) {
            expect(m.sourceStart[i], lessThan(m.sourceEnd[i]));
            expect(m.sourceEnd[i], lessThanOrEqualTo(input.length));
            if (i > 0) {
              expect(
                m.sourceStart[i],
                greaterThanOrEqualTo(m.sourceStart[i - 1]),
              );
            }
          }
        }
      },
    );

    test('the mapping points back at the source text', () {
      const input = '  오늘 한meet-\ning';
      final m = SearchText.normalizeMapped(input);
      expect(m.text, '오늘 한meeting');
      // '한' was composed from 3 jamo.
      final han = m.text.indexOf('한');
      expect(input.substring(m.sourceStart[han], m.sourceEnd[han]), '한');
      // The space between the words maps to the one source space.
      expect(m.sourceStart[2], 4);
      expect(m.sourceEnd[2], 5);
      // 'i' after the joined hyphen maps to the 'i' of the source.
      final i = m.text.indexOf('i');
      expect(input[m.sourceStart[i]], 'i');
    });

    test('normalizerVersion', () {
      expect(SearchText.normalizerVersion, 1);
    });
  });

  group('HandwritingText.sourceRevOf fixed vectors (6.9.2)', () {
    Stroke s(String id, int updatedAt) => Stroke(
      id: id,
      pageId: 'p',
      style: StrokeStyle.defaultsFor(PenTool.ballpoint),
      points: StrokePoints.fromList(const [
        StrokePoint(0, 0, widthQ: 0.5, t: 0),
      ]),
      createdAt: 1,
      updatedAt: updatedAt,
    );

    test('empty → the empty string hash', () {
      expect(HandwritingText.sourceRevOf(const []), 'e3b0c44298fc1c14');
    });

    test('sorted by id (UTF-16 order), "id:updatedAt;" joined', () {
      expect(
        HandwritingText.sourceRevOf([s('b', 2), s('a', 1)]),
        'd88dae0dd0361833',
      );
      expect(
        HandwritingText.sourceRevOf([s('a', 1), s('b', 2)]),
        'd88dae0dd0361833',
      );
      expect(
        HandwritingText.sourceRevOf([
          s('0193f1d2-7c4a-7b1e-9a2f-000000000002', 1793750400000),
          s('0193f1d2-7c4a-7b1e-9a2f-000000000001', 1793750400005),
        ]),
        '2d3d23551d506c14',
      );
      // 'Z' (0x5A) < '_' (0x5F) < 'a' (0x61).
      expect(
        HandwritingText.sourceRevOf([s('a', 1), s('_', 1), s('Z', 1)]),
        'e4143669b0c6d9dd',
      );
      // updatedAt is part of the value.
      expect(
        HandwritingText.sourceRevOf([s('a', 2), s('b', 2)]),
        isNot('d88dae0dd0361833'),
      );
    });
  });

  group('scores are bit-identical on every platform (6.10.4)', () {
    const doc = '오늘 회의록을 정리했다 meeting notes';
    test('unit and page scores', () {
      final norm = SearchText.normalize(doc);
      expect(unitScore(SearchSource.text, norm, '회의'), 1.3485);
      expect(unitScore(SearchSource.text, norm, '정'), 1.346);
      expect(unitScore(SearchSource.text, norm, 'meet'), 1.3435000000000001);
      expect(unitScore(SearchSource.pdf, 'abc abc xabc', 'abc'), 1.25);
      expect(unitScore(SearchSource.math, 'xxabcxx', 'abc'), 0.999);
      expect(
        pageScore(unitScore(SearchSource.ink, '회의 회의 회의', '회의'), 3),
        1.3900000000000001,
      );
    });
  });

  group('SearchRectsCodec bytes (6.10.3)', () {
    test('the same blob on every platform', () {
      final bytes = SearchRectsCodec.encode(const [
        PageRect(0.1, 0.2, 0.15, 0.25),
        PageRect(0.15, 0.2, 0.2, 0.25),
        PageRect.zero,
        PageRect(0.5, 0.3, 0.6, 0.35),
      ]);
      expect(bytes, [
        83, 82, 1, 4, 0, 0, 0, 3, 0, 0, 0, //
        0, 0, 0, 0, 2, 0, 0, 0, 51, 51, 0, 64, //
        2, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, //
        3, 0, 0, 0, 1, 0, 0, 0, 205, 76, 153, 89, //
        154, 25, 102, 38, 102, 38, 51, 51, 0, 0, 0, 0, 0, 128, 153, 153,
      ]);
    });
  });
}
