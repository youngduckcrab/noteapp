// PdfSearchUnitBuilder (m5-7/06-pdf 4.1.1, 6.4.1; 8.2 T27): fractions of the displayed page,
// a 90°-rotated page (displayed size), PageRect.zero for characters without a box,
// rects.length == body.length in every unit, pdfPageAspect = displayed width / height, a page
// over 30,000 code units cut at line breaks (and at the limit without one — never inside a
// surrogate pair), empty / blank pages, the owner key and the sourceRev tail ':x1'.
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/search_index/unit_builder.dart';

PdfPageTextData _text(String text, List<ui.Rect> rects) =>
    PdfPageTextData(pageIndex: 0, text: text, charRects: rects);

/// [text] with one 6 × 10 pt box per code unit, in a row from (10, 20); line breaks get none.
PdfPageTextData _boxed(String text) => _text(text, [
  for (var i = 0; i < text.length; i++)
    text[i] == '\r' || text[i] == '\n'
        ? ui.Rect.zero
        : ui.Rect.fromLTWH(10 + 6.0 * (i % 80), 20, 6, 10),
]);

void main() {
  test('fractions of the displayed page, PageRect.zero without a box', () {
    final units = PdfSearchUnitBuilder.build(
      _text('AB\r\nC', [
        const ui.Rect.fromLTRB(60, 80, 120, 160),
        const ui.Rect.fromLTRB(120, 80, 180, 160),
        ui.Rect.zero,
        ui.Rect.zero,
        const ui.Rect.fromLTRB(0, 400, 6, 0 + 410),
      ]),
      const ui.Size(600, 800),
    );
    final unit = units.single;
    expect(unit.body, 'AB\r\nC');
    expect(unit.rects, hasLength(unit.body.length));
    expect(unit.rects[0], const core.PageRect(0.1, 0.1, 0.2, 0.2));
    expect(unit.rects[1], const core.PageRect(0.2, 0.1, 0.3, 0.2));
    expect(unit.rects[2], core.PageRect.zero);
    expect(unit.rects[3], core.PageRect.zero);
    expect(unit.rects[4].left, 0);
    expect(unit.rects[4].top, 0.5);
    expect(unit.pdfPageAspect, 600 / 800);
  });

  test(
    'a 90° page: fractions of the displayed (turned) size, aspect w / h',
    () {
      // a portrait page shown landscape: the engine gives displayed pt and size
      const shown = ui.Size(842, 595);
      final unit = PdfSearchUnitBuilder.build(
        _text('x', [const ui.Rect.fromLTRB(421, 297.5, 842, 595)]),
        shown,
      ).single;
      expect(unit.rects.single, const core.PageRect(0.5, 0.5, 1, 1));
      expect(unit.pdfPageAspect, closeTo(842 / 595, 1e-12));
    },
  );

  test('zero-width boxes and boxes outside the page', () {
    final unit = PdfSearchUnitBuilder.build(
      _text('abc', [
        const ui.Rect.fromLTRB(50, 50, 50, 60), // zero width
        const ui.Rect.fromLTRB(-20, -10, 30, 40), // partly outside → clamped
        const ui.Rect.fromLTRB(700, 900, 720, 920), // wholly outside
      ]),
      const ui.Size(600, 800),
    ).single;
    expect(unit.rects[0], core.PageRect.zero);
    expect(unit.rects[1], const core.PageRect(0, 0, 0.05, 0.05));
    expect(unit.rects[2], core.PageRect.zero);
  });

  test('fewer boxes than code units → the rest PageRect.zero', () {
    final unit = PdfSearchUnitBuilder.build(
      _text('abcd', [const ui.Rect.fromLTRB(0, 0, 6, 10)]),
      const ui.Size(600, 800),
    ).single;
    expect(unit.rects, hasLength(4));
    expect(unit.rects.skip(1), everyElement(core.PageRect.zero));
  });

  test('empty and blank pages have no units', () {
    expect(
      PdfSearchUnitBuilder.build(_text('', const []), const ui.Size(600, 800)),
      isEmpty,
    );
    expect(
      PdfSearchUnitBuilder.build(_boxed(' \r\n \t'), const ui.Size(600, 800)),
      isEmpty,
    );
  });

  test('a page over 30,000 code units is cut after line breaks', () {
    final line = '${'가나다라마바사아자차' * 9}abcdefghij\r\n'; // 102 code units
    final body = line * 700; // 71,400
    final units = PdfSearchUnitBuilder.build(
      _boxed(body),
      const ui.Size(600, 800),
    );
    expect(units.length, 3);
    expect(units.map((u) => u.body).join(), body);
    for (final unit in units) {
      expect(unit.body.length, lessThanOrEqualTo(30000));
      expect(unit.rects, hasLength(unit.body.length));
      expect(unit.pdfPageAspect, 600 / 800);
    }
    expect(units[0].body.endsWith('\n'), isTrue);
    expect(units[1].body.endsWith('\n'), isTrue);
    expect(units[0].body.length, 30000 - 30000 % 102);
    // the rects follow their characters
    expect(units[1].rects.first, isNot(core.PageRect.zero));
  });

  test('a piece without a line break is cut at the limit, never inside a '
      'surrogate pair', () {
    final body = '${'a' * 9}\u{1F600}${'b' * 10}'; // pair at 9..10
    final units = PdfSearchUnitBuilder.build(
      _boxed(body),
      const ui.Size(100, 100),
      maxCodeUnits: 10,
    );
    expect(units.map((u) => u.body).toList(), [
      'a' * 9,
      '\u{1F600}${'b' * 8}',
      'bb',
    ]);
    for (final unit in units) {
      expect(unit.rects, hasLength(unit.body.length));
    }
  });

  test('owner key and sourceRev (CP-PDF-2 tail :x1)', () {
    const id =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    expect(PdfSearchUnitBuilder.ownerKeyOf(id, 3), '$id#3');
    expect(
      PdfSearchUnitBuilder.sourceRevOf(id),
      '$id:${core.SearchText.normalizerVersion}:x1',
    );
    expect(PdfTuning.indexExtractorVersion, 1);
    expect(PdfTuning.indexMaxUnitCodeUnits, 30000);
    expect(PdfTuning.indexSliceGap, const Duration(milliseconds: 150));
  });
}
