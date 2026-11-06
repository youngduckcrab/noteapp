// Shared cases of PDF T28 (m5-7/06-pdf 6.4.5, C2-27): PdfTextNormalizer equals CORE's
// SearchText.normalize / normalizeMapped on the same input. unit/normalizer_equivalence_test runs
// them on the VM, web/normalizer_equivalence_browser_test under dart2js (the same assertions).
// Web-safe.
//
// kCoreSearchTextVectors is a COPY of note_core test/shared/search_text_cases.dart
// kSearchTextVectors (another package's test/ cannot be imported — 1차 rule), written with
// escapes. When CORE changes its table, PDF changes this copy (progress log '변경 요청').
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/src/text/text_normalizer.dart';

/// (input, SearchText.normalize(input)) — copied from CORE (02-core 6.10.1).
const List<(String, String)> kCoreSearchTextVectors = [
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
  // Lowercase per code point: Turkish U+0130 → i (every platform), Greek U+03A3 → U+03C3
  // (no final sigma).
  ('İSTANBUL', 'istanbul'),
  ('ΟΔΟΣ', 'οδοσ'),
  ('ÀÉÎ Café', 'àéî café'),
  // Emoji (a surrogate pair) and fullwidth Latin (lowercased, not folded to ASCII).
  ('\u{1F600} Ａ Café', '\u{1F600} ａ café'),
  ('MEETING Notes', 'meeting notes'),
];

/// Every input of the 1차 unit/text_normalizer_test, web/pure_logic_browser_test (T11) and the
/// search snippets of unit/search_service_test.
const List<String> kFirstRoundNormalizerInputs = [
  '가',
  '각',
  '각',
  '강의 자료',
  'a \t\r\n b',
  'a 　b',
  '  ab \n',
  'hy­phen',
  '﻿a​b‌c‍d',
  'a ​ b',
  'con-\r\ntinue',
  'con-\ntinue',
  'well-known',
  'a -\r\nb',
  'a-\r\n b',
  '강-\r\n의',
  '강-\r\n의',
  'ABC Ünïcode ΣΑ',
  'xİy',
  'x\u{10400}y',
  'a\u{1F600}b',
  'abc',
  'The Con-\r\ntinue  각­X',
  '',
  '  강의 Notes \n',
  ' \t　',
  'Lecture  NOTES: con-\r\ntinue',
  'notes:',
  'Continue',
  'The Con-\r\ntinue   각­X cafÉ ά-\nβ',
  '  강의　NOTES ',
  'one\n\nTwo  three',
  'to con-\ntinue here',
];

List<(int, int)> _table(List<int> starts, List<int> ends) => [
  for (var i = 0; i < starts.length; i++) (starts[i], ends[i]),
];

/// The ranges of [table] with consecutive repeats removed.
List<(int, int)> _distinct(List<(int, int)> table) => [
  for (var i = 0; i < table.length; i++)
    if (i == 0 || table[i - 1] != table[i]) table[i],
];

void defineNormalizerEquivalenceCases() {
  group('PdfTextNormalizer == SearchText (6.4.5, C2-27)', () {
    test(
      'CORE table: normalizeQuery(x) == SearchText.normalize(x) == the copy',
      () {
        for (final (input, expected) in kCoreSearchTextVectors) {
          final reason = '${input.codeUnits}';
          expect(core.SearchText.normalize(input), expected, reason: reason);
          expect(
            PdfTextNormalizer.normalizeQuery(input),
            core.SearchText.normalize(input),
            reason: reason,
          );
          expect(
            PdfTextNormalizer.normalize(input).text,
            expected,
            reason: reason,
          );
        }
      },
    );

    test('1차 inputs: normalizeQuery(x) == SearchText.normalize(x)', () {
      for (final input in kFirstRoundNormalizerInputs) {
        expect(
          PdfTextNormalizer.normalizeQuery(input),
          core.SearchText.normalize(input),
          reason: '${input.codeUnits}',
        );
      }
    });

    test('normalize(x) == SearchText.normalizeMapped(x): text and table', () {
      for (final input in [
        for (final (input, _) in kCoreSearchTextVectors) input,
        ...kFirstRoundNormalizerInputs,
      ]) {
        final pdf = PdfTextNormalizer.normalize(input);
        final m = core.SearchText.normalizeMapped(input);
        final reason = '${input.codeUnits}';
        expect(pdf.text, m.text, reason: reason);
        expect(pdf.text, core.SearchText.normalize(input), reason: reason);
        expect(
          _table(pdf.sourceStart, pdf.sourceEnd),
          _table(m.sourceStart, m.sourceEnd),
          reason: reason,
        );
      }
    });
  });

  group('normalizeKeepingCase (snippet, 6.10.2 step 5)', () {
    test('the same folding as normalize, in the original case', () {
      const cases = [
        ('The Con-\r\ntinue  각­X', 'The Continue 각X'),
        ('  Hello 　World  ', 'Hello World'),
        ('İSTANBUL', 'İSTANBUL'),
        ('ΟΔΟΣ', 'ΟΔΟΣ'),
        ('x\u{10400}y \u{1F600}', 'x\u{10400}y \u{1F600}'),
        ('one\n\nTwo  three', 'one Two three'),
        ('강의 자료', '강의 자료'),
        ('', ''),
      ];
      for (final (input, expected) in cases) {
        final kept = normalizeKeepingCase(input);
        final reason = '${input.codeUnits}';
        expect(kept.text, expected, reason: reason);
        expect(kept.sourceStart.length, kept.text.length, reason: reason);
        expect(kept.sourceEnd.length, kept.text.length, reason: reason);
      }
    });

    test('the source ranges in order are those of normalizeMapped', () {
      for (final input in [
        for (final (input, _) in kCoreSearchTextVectors) input,
        ...kFirstRoundNormalizerInputs,
      ]) {
        final kept = normalizeKeepingCase(input);
        final m = core.SearchText.normalizeMapped(input);
        expect(
          _distinct(_table(kept.sourceStart, kept.sourceEnd)),
          _distinct(_table(m.sourceStart, m.sourceEnd)),
          reason: '${input.codeUnits}',
        );
      }
    });
  });

  group('HangulJamo.compose (6.3 titles — step 4 only)', () {
    test('composes jamo, leaves everything else (case, spaces) as it is', () {
      const cases = [
        ('가', '가'),
        ('각', '각'),
        ('각', '각'),
        ('강의', '강의'),
        ('힣', '힣'),
        ('각ᆨ', '각ᆨ'),
        ('ABC  강의.PDF', 'ABC  강의.PDF'),
        ('ᄀ', 'ᄀ'),
        ('ᅡx', 'ᅡx'),
        ('\u{1F600}가\u{1F600}', '\u{1F600}가\u{1F600}'),
        (' İ -\n­ ', ' İ -\n­ '),
        ('', ''),
      ];
      for (final (input, expected) in cases) {
        expect(
          HangulJamo.compose(input),
          expected,
          reason: '${input.codeUnits}',
        );
      }
    });
  });
}
