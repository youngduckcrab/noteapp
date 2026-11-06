// The PDF char box blob (m5-7/02-core 6.10.3 SearchRectsCodec), the per-line merge and the
// fraction → pt conversion (6.10.4). The cross-platform bytes are in
// test/shared/search_text_cases.dart. Web-safe.
import 'dart:typed_data';

import 'package:note_core/note_core.dart';
import 'package:note_core/src/search/search_rects.dart';
import 'package:test/test.dart';

void main() {
  test('round trip at 1/65535 precision', () {
    const rects = [
      PageRect(0.1, 0.2, 0.15, 0.25),
      PageRect(0.15, 0.2, 0.2, 0.25),
      PageRect(0.123456789, 0.3, 0.987654321, 0.35),
      PageRect(0, 0, 1, 1),
    ];
    final back = SearchRectsCodec.decode(SearchRectsCodec.encode(rects));
    expect(back, hasLength(4));
    for (var i = 0; i < rects.length; i++) {
      expect(back[i].left, closeTo(rects[i].left, 0.5 / 65535));
      expect(back[i].top, closeTo(rects[i].top, 0.5 / 65535));
      expect(back[i].right, closeTo(rects[i].right, 0.5 / 65535));
      expect(back[i].bottom, closeTo(rects[i].bottom, 0.5 / 65535));
    }
    expect(back[3], const PageRect(0, 0, 1, 1));
    expect((back[2].left * 65535).round(), (0.123456789 * 65535).round());
  });

  test(
    'PageRect.zero is kept as zeros; empty list; size ≈ 4 B/char + 12 B/line',
    () {
      final back = SearchRectsCodec.decode(
        SearchRectsCodec.encode(const [
          PageRect.zero,
          PageRect(0.1, 0.1, 0.2, 0.2),
        ]),
      );
      expect(back.first, PageRect.zero);
      expect(
        SearchRectsCodec.decode(SearchRectsCodec.encode(const [])),
        isEmpty,
      );
      final line = [
        for (var i = 0; i < 100; i++)
          PageRect(i / 200, 0.1, (i + 1) / 200, 0.12),
      ];
      expect(SearchRectsCodec.encode(line).length, 11 + 12 + 400);
    },
  );

  test('a damaged blob is a FormatException', () {
    final good = SearchRectsCodec.encode(const [PageRect(0.1, 0.1, 0.2, 0.2)]);
    expect(() => SearchRectsCodec.decode(Uint8List(3)), throwsFormatException);
    expect(
      () => SearchRectsCodec.decode(Uint8List.fromList([...good, 0])),
      throwsFormatException,
    );
    final badVersion = Uint8List.fromList(good)..[2] = 9;
    expect(() => SearchRectsCodec.decode(badVersion), throwsFormatException);
  });

  test('mergeLineRects: per text line, zero boxes skipped', () {
    const rects = [
      PageRect(0.1, 0.1, 0.2, 0.2),
      PageRect(0.2, 0.1, 0.3, 0.2),
      PageRect.zero,
      PageRect(0.3, 0.1, 0.4, 0.2),
      PageRect(0.1, 0.3, 0.2, 0.4),
    ];
    expect(mergeLineRects(rects, 0, 5), const [
      PageRect(0.1, 0.1, 0.4, 0.2),
      PageRect(0.1, 0.3, 0.2, 0.4),
    ]);
    expect(mergeLineRects(rects, 1, 3), const [PageRect(0.2, 0.1, 0.3, 0.2)]);
    expect(mergeLineRects(rects, 2, 3), isEmpty);
  });

  test('fractionToPagePt: contain + centered by the PDF aspect, else fill', () {
    const f = PageRect(0, 0, 1, 1);
    expect(fractionToPagePt(f, 600, 800), const PageRect(0, 0, 600, 800));
    // A landscape PDF (2:1) on a 600 × 800 page: 600 × 300 centered vertically.
    expect(
      fractionToPagePt(f, 600, 800, pdfPageAspect: 2),
      const PageRect(0, 250, 600, 550),
    );
    // A narrow PDF (1:2): 400 × 800 centered horizontally.
    expect(
      fractionToPagePt(
        const PageRect(0.5, 0.5, 1, 1),
        600,
        800,
        pdfPageAspect: 0.5,
      ),
      const PageRect(300, 400, 500, 800),
    );
  });
}
