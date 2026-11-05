// E-02: PageLayout (04-editor 6.3.2) — vertical and horizontal, mixed sizes,
// binary-search boundaries, a point in a gap → null, the empty list.
import 'dart:ui';

import 'package:feature_editor/src/viewport/page_layout.dart';
import 'package:feature_editor/src/viewport/viewport_constants.dart';
import 'package:flutter_test/flutter_test.dart';

const a4 = Size(595.2756, 841.8898);
const a4Landscape = Size(841.8898, 595.2756);
const small = Size(300, 400);

void main() {
  group('vertical', () {
    final layout = PageLayout.compute(
      pageSizes: const [a4, a4Landscape, small],
      axis: LayoutAxis.vertical,
    );

    test('pages are stacked with gaps and centred on the widest page', () {
      const gap = ViewportConstants.pageGap;
      const lead = ViewportConstants.leadingPadding;
      expect(layout.length, 3);
      expect(layout.crossExtent, a4Landscape.width);
      expect(
        layout.rectOf(0),
        Rect.fromLTWH(
          (a4Landscape.width - a4.width) / 2,
          lead,
          a4.width,
          a4.height,
        ),
      );
      expect(layout.rectOf(1).left, 0);
      expect(layout.rectOf(1).top, lead + a4.height + gap);
      expect(layout.rectOf(2).top, layout.rectOf(1).bottom + gap);
      expect(layout.rectOf(2).left, (a4Landscape.width - small.width) / 2);
      expect(
        layout.contentSize,
        Size(
          a4Landscape.width,
          layout.rectOf(2).bottom + ViewportConstants.trailingPadding,
        ),
      );
    });

    test('pageIndexAt: inside, edges, gaps, outside', () {
      final r0 = layout.rectOf(0);
      final r1 = layout.rectOf(1);
      expect(layout.pageIndexAt(r0.center), 0);
      expect(layout.pageIndexAt(r0.topLeft), 0);
      expect(layout.pageIndexAt(r0.bottomRight), 0);
      expect(layout.pageIndexAt(r1.topLeft), 1);
      // The gap between page 0 and page 1.
      expect(layout.pageIndexAt(Offset(r0.center.dx, r0.bottom + 1)), isNull);
      expect(layout.pageIndexAt(Offset(r1.center.dx, r1.top - 0.001)), isNull);
      // Leading padding, beside a narrower page, after the last page.
      expect(layout.pageIndexAt(const Offset(300, 10)), isNull);
      expect(layout.pageIndexAt(Offset(r0.left - 1, r0.center.dy)), isNull);
      expect(
        layout.pageIndexAt(Offset(100, layout.rectOf(2).bottom + 5)),
        isNull,
      );
      expect(layout.pageIndexAt(layout.rectOf(2).center), 2);
    });

    test('nearestPageIndex: gaps go to the closer neighbour', () {
      final r0 = layout.rectOf(0);
      final r1 = layout.rectOf(1);
      expect(layout.nearestPageIndex(const Offset(0, -100)), 0);
      expect(layout.nearestPageIndex(Offset(0, r0.bottom + 2)), 0);
      expect(layout.nearestPageIndex(Offset(0, r1.top - 2)), 1);
      expect(layout.nearestPageIndex(Offset(0, (r0.bottom + r1.top) / 2)), 0);
      expect(layout.nearestPageIndex(const Offset(0, 1e9)), 2);
      expect(layout.nearestPageIndex(Offset(-500, r1.center.dy)), 1);
    });

    test('rangeIntersecting: overlap, touching, gap only, outside', () {
      final r0 = layout.rectOf(0);
      final r1 = layout.rectOf(1);
      final r2 = layout.rectOf(2);
      expect(layout.rangeIntersecting(Rect.fromLTRB(0, 0, 10, r0.center.dy)), (
        first: 0,
        last: 0,
      ));
      expect(
        layout.rangeIntersecting(Rect.fromLTRB(0, r0.center.dy, 10, r2.top)),
        (first: 0, last: 2),
      );
      expect(
        layout.rangeIntersecting(
          Rect.fromLTRB(0, r0.bottom + 1, 10, r1.top - 1),
        ),
        isNull,
      );
      expect(layout.rangeIntersecting(Rect.fromLTRB(0, r1.top, 10, r1.top)), (
        first: 1,
        last: 1,
      ));
      expect(
        layout.rangeIntersecting(Rect.fromLTRB(0, r2.bottom + 1, 10, 1e9)),
        isNull,
      );
      expect(
        layout.rangeIntersecting(const Rect.fromLTRB(0, -9, 1, 1)),
        isNull,
      );
    });
  });

  group('horizontal', () {
    final layout = PageLayout.compute(
      pageSizes: const [a4, a4Landscape, small],
      axis: LayoutAxis.horizontal,
    );

    test('pages go left to right, centred vertically on the tallest', () {
      expect(layout.crossExtent, a4.height);
      expect(layout.rectOf(0).left, ViewportConstants.leadingPadding);
      expect(layout.rectOf(0).top, 0);
      expect(
        layout.rectOf(1).left,
        layout.rectOf(0).right + ViewportConstants.pageGap,
      );
      expect(layout.rectOf(1).top, (a4.height - a4Landscape.height) / 2);
      expect(
        layout.contentSize,
        Size(
          layout.rectOf(2).right + ViewportConstants.trailingPadding,
          a4.height,
        ),
      );
    });

    test('lookups use the x axis', () {
      final r0 = layout.rectOf(0);
      final r1 = layout.rectOf(1);
      expect(layout.pageIndexAt(r1.center), 1);
      expect(layout.pageIndexAt(Offset(r0.right + 3, r0.center.dy)), isNull);
      expect(layout.nearestPageIndex(Offset(r1.left - 1, 0)), 1);
      expect(
        layout.rangeIntersecting(Rect.fromLTRB(r0.right - 1, 0, r1.left, 1)),
        (first: 0, last: 1),
      );
    });
  });

  test('many equal pages: every boundary of the binary search', () {
    final layout = PageLayout.compute(
      pageSizes: List.filled(101, a4),
      axis: LayoutAxis.vertical,
    );
    for (var i = 0; i < layout.length; i++) {
      final r = layout.rectOf(i);
      expect(layout.pageIndexAt(r.topCenter), i);
      expect(layout.pageIndexAt(r.bottomCenter), i);
      expect(layout.pageIndexAt(r.bottomCenter + const Offset(0, 1)), isNull);
      expect(layout.nearestPageIndex(r.center), i);
      expect(layout.rangeIntersecting(r.deflate(1)), (first: i, last: i));
    }
  });

  test('empty list', () {
    final layout = PageLayout.compute(
      pageSizes: const [],
      axis: LayoutAxis.vertical,
    );
    expect(layout.length, 0);
    expect(layout.crossExtent, 0);
    expect(
      layout.contentSize,
      const Size(
        0,
        ViewportConstants.leadingPadding + ViewportConstants.trailingPadding,
      ),
    );
    expect(layout.pageIndexAt(Offset.zero), isNull);
    expect(
      layout.rangeIntersecting(const Rect.fromLTRB(0, 0, 100, 100)),
      isNull,
    );
    expect(() => layout.nearestPageIndex(Offset.zero), throwsStateError);
  });

  test('value equality', () {
    PageLayout make() => PageLayout.compute(
      pageSizes: const [a4, small],
      axis: LayoutAxis.vertical,
    );
    expect(make(), make());
    expect(make().hashCode, make().hashCode);
    expect(
      make(),
      isNot(
        PageLayout.compute(
          pageSizes: const [a4, small],
          axis: LayoutAxis.horizontal,
        ),
      ),
    );
  });
}
