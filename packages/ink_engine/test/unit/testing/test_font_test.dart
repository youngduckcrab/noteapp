// T26a (m5-7/03-ink 4.12): useInkTestFonts — idempotent, measures without
// rootBundle, the coverage table stays the real subset's, and the bundled test
// font is small (≤ 64 KiB) and has the glyphs of the plans' test sentences.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/testing/ink_test_font.dart';
import 'package:ink_engine/src/text/fonts.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(() => debugSetInkFontSource(null));

  test('useInkTestFonts twice is fine; NoteSans is then loaded', () async {
    await useInkTestFonts();
    final source = InkFontsDebug.source;
    expect(InkFontsDebug.isLoaded, isTrue);
    await useInkTestFonts();
    expect(identical(InkFontsDebug.source, source), isTrue);
    expect(InkFontsDebug.isLoaded, isTrue);
  });

  test('measure answers at once; bold asks get the same bytes', () async {
    await useInkTestFonts();
    final size = await InkTextLayout.measure(
      '안녕 hello',
      const core.TextBoxStyle(),
      widthPt: 300,
    ).timeout(const Duration(seconds: 1));
    expect(size.height, greaterThan(0));
    final regular = await InkFonts.noteSansBytes();
    final bold = await InkFonts.noteSansBytes(bold: true);
    expect(bold, regular);
  });

  test('covers() still reads the real subset table', () async {
    await useInkTestFonts();
    expect(InkFonts.covers('똠'), isFalse);
    expect(InkFonts.covers('흙'), isTrue); // in KS X 1001, not in the test font
  });

  test('the test font is small and decodes', () {
    final bytes = base64Decode(inkTestFontBase64);
    expect(bytes.length, lessThanOrEqualTo(64 * 1024));
    expect(inkTestFontBase64.length, lessThanOrEqualTo(88 * 1024));
    // TrueType magic 0x00010000
    expect(bytes.sublist(0, 4), [0, 1, 0, 0]);
  });
}
