// m5-7/04-editor 8.2 E2-12, 6.12.2 step 3, 6.12.3, 6.13.2: ObjectPlacement —
// the size and place of an inserted image (the visible part, the page
// clamp, a tall image sized by its height, an image bigger than the page,
// an empty visible part → the whole page), visibleRectPt from the
// viewport, and the orientation of an image page.
import 'dart:ui' show Offset, Rect, Size;

import 'package:feature_editor/src/objects/object_placement.dart';
import 'package:feature_editor/src/viewport/viewport_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;

const core.PageSize _a4 = core.PageSize.a4Portrait;

/// A page with round numbers for the size rules.
const core.PageSize _p = core.PageSize(600, 800);

void _expectRect(Rect actual, Rect expected) {
  expect(actual.left, closeTo(expected.left, 1e-6), reason: 'left');
  expect(actual.top, closeTo(expected.top, 1e-6), reason: 'top');
  expect(actual.width, closeTo(expected.width, 1e-6), reason: 'width');
  expect(actual.height, closeTo(expected.height, 1e-6), reason: 'height');
}

bool _onPage(Rect r, core.PageSize page) =>
    r.left >= -1e-9 &&
    r.top >= -1e-9 &&
    r.right <= page.width + 1e-9 &&
    r.bottom <= page.height + 1e-9;

core.Page _page(String id, core.PageSize size) => core.Page(
  id: id,
  noteId: 'note',
  sortKey: id,
  size: size,
  background: const core.BlankBackground(),
  createdAt: 0,
  updatedAt: 0,
  contentRevision: 0,
);

void main() {
  group('forImage', () {
    test('width = min(px × 0.5, visible × 0.6, page × 0.8), height by the '
        'pixel aspect, centred on the visible part', () {
      const visible = Rect.fromLTWH(100, 100, 400, 300);
      // 400 × 300 px: min(200, 240, 480) = 200 → 150 high (≤ 180, ≤ 640).
      _expectRect(
        ObjectPlacement.forImage(
          pageSize: _p,
          visibleRectPt: visible,
          pixelWidth: 400,
          pixelHeight: 300,
        ),
        Rect.fromCenter(center: visible.center, width: 200, height: 150),
      );
      // 1000 × 500 px: min(500, 240, 480) = 240 → 120 high.
      _expectRect(
        ObjectPlacement.forImage(
          pageSize: _p,
          visibleRectPt: visible,
          pixelWidth: 1000,
          pixelHeight: 500,
        ),
        Rect.fromCenter(center: visible.center, width: 240, height: 120),
      );
    });

    test('the visible part is clipped to the page and the image moved onto '
        'the page', () {
      // Only the page's top-left corner is on screen.
      const visible = Rect.fromLTRB(-300, -200, 100, 100); // ∩ page = 100×100
      final r = ObjectPlacement.forImage(
        pageSize: _p,
        visibleRectPt: visible,
        pixelWidth: 400,
        pixelHeight: 400,
      );
      // min(200, 60, 480) = 60 → 60 × 60 centred on (50, 50).
      _expectRect(
        r,
        Rect.fromCenter(center: const Offset(50, 50), width: 60, height: 60),
      );
      // An explicit centre near the corner → moved so it is on the page.
      final corner = ObjectPlacement.forImage(
        pageSize: _p,
        visibleRectPt: const Rect.fromLTWH(0, 0, 600, 800),
        pixelWidth: 400,
        pixelHeight: 300,
        center: const Offset(10, 790),
      );
      _expectRect(corner, const Rect.fromLTWH(0, 650, 200, 150));
      expect(_onPage(corner, _p), isTrue);
      // The far corner too.
      final far = ObjectPlacement.forImage(
        pageSize: _p,
        visibleRectPt: const Rect.fromLTWH(0, 0, 600, 800),
        pixelWidth: 400,
        pixelHeight: 300,
        center: const Offset(900, -40),
      );
      _expectRect(far, const Rect.fromLTWH(400, 0, 200, 150));
    });

    test('a tall image is sized by its height (visible height × 0.6)', () {
      const visible = Rect.fromLTWH(0, 0, 600, 800);
      // 300 × 1200 px: width min(150, 360, 480) = 150 → 600 high > min(480,
      // 640) → 480 high, 120 wide.
      final r = ObjectPlacement.forImage(
        pageSize: _p,
        visibleRectPt: visible,
        pixelWidth: 300,
        pixelHeight: 1200,
      );
      expect(r.height, closeTo(480, 1e-6));
      expect(r.width, closeTo(120, 1e-6));
      expect(r.center.dx, closeTo(visible.center.dx, 1e-6));
      expect(r.center.dy, closeTo(visible.center.dy, 1e-6));
      // A short visible part limits the height too.
      final short = ObjectPlacement.forImage(
        pageSize: _p,
        visibleRectPt: const Rect.fromLTWH(0, 300, 600, 200),
        pixelWidth: 300,
        pixelHeight: 1200,
      );
      expect(short.height, closeTo(120, 1e-6));
      expect(short.width, closeTo(30, 1e-6));
    });

    test('an image bigger than the page stays within 80 % of it and keeps its '
        'aspect', () {
      // A 16:9 page fully visible, a 6000 × 8000 px photo.
      const page = core.PageSize.widescreen16x9;
      final r = ObjectPlacement.forImage(
        pageSize: page,
        visibleRectPt: const Rect.fromLTWH(0, 0, 960, 540),
        pixelWidth: 6000,
        pixelHeight: 8000,
      );
      // width min(3000, 576, 768) = 576 → 768 high > min(324, 432) → 324.
      expect(r.height, closeTo(324, 1e-6));
      expect(r.width, closeTo(243, 1e-6));
      expect(r.width / r.height, closeTo(6000 / 8000, 1e-9));
      expect(_onPage(r, page), isTrue);
      // A huge wide one on a zoomed-out page (all of it visible).
      final wide = ObjectPlacement.forImage(
        pageSize: _p,
        visibleRectPt: const Rect.fromLTWH(-500, -500, 2000, 2000),
        pixelWidth: 20000,
        pixelHeight: 2000,
      );
      expect(wide.width, closeTo(360, 1e-6)); // visible = the page
      expect(wide.height, closeTo(36, 1e-6));
      expect(_onPage(wide, _p), isTrue);
    });

    test('an empty visible part (off the page or zero) → the whole page', () {
      final expected = ObjectPlacement.forImage(
        pageSize: _p,
        visibleRectPt: const Rect.fromLTWH(0, 0, 600, 800),
        pixelWidth: 400,
        pixelHeight: 300,
      );
      for (final visible in const [
        Rect.zero,
        Rect.fromLTWH(1000, 1000, 300, 300),
        Rect.fromLTWH(100, -400, 300, 300),
      ]) {
        _expectRect(
          ObjectPlacement.forImage(
            pageSize: _p,
            visibleRectPt: visible,
            pixelWidth: 400,
            pixelHeight: 300,
          ),
          expected,
        );
      }
      expect(expected.center, const Offset(300, 400));
      expect(
        ObjectPlacement.clipToPage(Rect.zero, _p),
        const Rect.fromLTWH(0, 0, 600, 800),
      );
    });

    test('a zero pixel size counts as 1 px (no NaN)', () {
      final r = ObjectPlacement.forImage(
        pageSize: _p,
        visibleRectPt: const Rect.fromLTWH(0, 0, 600, 800),
        pixelWidth: 0,
        pixelHeight: 0,
      );
      expect(r.width, closeTo(0.5, 1e-9));
      expect(r.height, closeTo(0.5, 1e-9));
      expect(r.center.dx.isFinite && r.center.dy.isFinite, isTrue);
    });
  });

  testWidgets('visibleRectPt: the viewport ∩ the page in page pt; a page off '
      'screen → the whole page', (tester) async {
    final viewport = ViewportController()
      ..updatePages([for (var i = 0; i < 4; i++) _page('p$i', _a4)])
      ..updateViewportSize(const Size(1032, 1376))
      ..restore(null);
    final visible = ObjectPlacement.visibleRectPt(viewport, 0);
    final screenTopLeft = viewport.pageToScreen(0, visible.topLeft);
    final screenBottomRight = viewport.pageToScreen(0, visible.bottomRight);
    // Page 0 at the top: its whole width; from its top to the screen bottom.
    expect(visible.left, closeTo(0, 1e-6));
    expect(visible.right, closeTo(_a4.width, 1e-6));
    expect(visible.top, closeTo(0, 1e-6));
    expect(screenBottomRight.dy, closeTo(1376, 1e-3));
    expect(screenTopLeft.dy, greaterThanOrEqualTo(0));
    expect(visible.bottom, lessThan(_a4.height));

    // Zoomed ×2 about the screen centre: half as wide.
    viewport.zoomBy(2, const Offset(516, 688));
    final zoomed = ObjectPlacement.visibleRectPt(viewport, 0);
    expect(zoomed.width, closeTo(1032 / viewport.camera.scale, 1e-6));
    expect(zoomed.width, lessThan(visible.width));
    expect(viewport.pageToScreen(0, zoomed.topLeft).dx, closeTo(0, 1e-6));

    // Page 3 is below the screen → the whole page; out of range → zero.
    expect(
      ObjectPlacement.visibleRectPt(viewport, 3),
      Rect.fromLTWH(0, 0, _a4.width, _a4.height),
    );
    expect(ObjectPlacement.visibleRectPt(viewport, 9), Rect.zero);
    await tester.pump(const Duration(milliseconds: 200)); // the settle timer
    viewport.dispose();
  });

  test('imagePageSize: the current size turned to the image orientation; '
      'near-square (0.9 ≤ w/h ≤ 1.1) keeps it', () {
    final landscapeA4 = _a4.landscape;
    expect(landscapeA4.isLandscape, isTrue);
    // A wide image → landscape.
    expect(ObjectPlacement.imagePageSize(_a4, 1600, 900), landscapeA4);
    expect(ObjectPlacement.imagePageSize(landscapeA4, 1600, 900), landscapeA4);
    // A tall image → portrait.
    expect(ObjectPlacement.imagePageSize(landscapeA4, 900, 1600), _a4);
    expect(ObjectPlacement.imagePageSize(_a4, 900, 1600), _a4);
    // Near-square → the current orientation (both ends included).
    for (final (w, h) in const [(1000, 1000), (900, 1000), (1100, 1000)]) {
      expect(ObjectPlacement.imagePageSize(_a4, w, h), _a4);
      expect(ObjectPlacement.imagePageSize(landscapeA4, w, h), landscapeA4);
    }
    // Just outside.
    expect(ObjectPlacement.imagePageSize(_a4, 1110, 1000), landscapeA4);
    expect(ObjectPlacement.imagePageSize(landscapeA4, 890, 1000), _a4);
    // A degenerate size keeps the current size.
    expect(ObjectPlacement.imagePageSize(landscapeA4, 0, 10), landscapeA4);
  });
}
