// PDFium hyphen joins → soft hyphens (contract v2.6 C26-04; lib/src/engine/pdfium_text.dart): the
// cases of unit/pdfium_text_test.dart and its browser twin web/pure_logic_browser_test.dart (the
// lookbehind / \p{…} RegExp must give the same result under dart2js). Real PDFium: pdfium/
// pdfrx_engine_test.dart ('IN-' / 'DEXING'), pdfium/search_real_test.dart (1차 searchNote) and
// support/search_indexer_core_scenarios.dart (v2 index).
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/src/engine/pdfium_text.dart';
import 'package:pdf_io/testing.dart';

/// A page whose first line ends in 'IN-' and whose next line starts with 'DEXING' (size 18, 22 pt
/// apart): PDFium joins them into one run 'IN\u0002DEXING' with no line break (T29).
const PdfFixturePage hyphenatedWordPage = PdfFixturePage(
  texts: [
    PdfFixtureText('Text IN-', x: 72, y: 100),
    PdfFixtureText('DEXING works', x: 72, y: 122),
  ],
);

void pdfiumTextCases() {
  test('U+0002 between two word characters → U+00AD, same length', () {
    for (final (raw, want) in [
      ('IN\u0002DEXING', 'IN­DEXING'),
      ('in\u0002dexing and hy\u0002phen', 'in­dexing and hy­phen'),
      ('2\u00020', '2­0'), // digits are word characters
      ('검\u0002색', '검­색'), // Hangul syllables
      ('é\u0002x', 'é­x'), // a combining mark before it
      ('ά\u0002β', 'ά­β'),
      (
        '𝐀\u0002b',
        '𝐀­b',
      ), // a letter outside the BMP (two code units) before it
    ]) {
      final got = softenPdfiumHyphenJoins(raw);
      expect(got, want, reason: raw.runes.toList().toString());
      expect(got.length, raw.length);
    }
  });

  test('any other U+0002 is left as PDFium gave it', () {
    for (final raw in [
      '\u0002',
      '\u0002abc',
      'abc\u0002',
      'ab \u0002cd',
      'ab\u0002 cd',
      'ab-\u0002cd',
      'ab\u0002\u0002cd',
      'ab\r\n\u0002cd',
      'no join here',
      '',
    ]) {
      expect(
        softenPdfiumHyphenJoins(raw),
        raw,
        reason: raw.codeUnits.toString(),
      );
    }
  });

  test("CORE's search normalisation then finds the whole word (1:1 position table)", () {
    final text = softenPdfiumHyphenJoins('The IN\u0002DEXING step');
    expect(core.SearchText.normalize(text), contains('indexing'));
    final mapped = core.SearchText.normalizeMapped(text);
    final at = mapped.text.indexOf('indexing');
    expect(at, isNot(-1));
    // the eight letters map back to the eight letters around the soft hyphen
    final sources = [for (var i = at; i < at + 8; i++) mapped.sourceStart[i]];
    expect(sources, [4, 5, 7, 8, 9, 10, 11, 12]);
    // and the raw U+0002 alone is not found (what C26-04 fixes)
    expect(
      core.SearchText.normalize('The IN\u0002DEXING step'),
      isNot(contains('indexing')),
    );
  });
}
