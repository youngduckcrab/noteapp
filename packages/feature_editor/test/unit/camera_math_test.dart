// E-02: ViewportCamera / CameraMath (04-editor 6.3.3) — conversion round
// trips (< 1e-9), fixed focal point, centring / range clamps, fit, and one
// gesture split into 100 pieces equals applying it once (< 1e-6).
import 'dart:math' as math;
import 'dart:ui';

import 'package:feature_editor/src/viewport/page_layout.dart';
import 'package:feature_editor/src/viewport/viewport_camera.dart';
import 'package:feature_editor/src/viewport/viewport_constants.dart';
import 'package:flutter_test/flutter_test.dart';

const a4 = Size(595.2756, 841.8898);
const viewport = Size(1032, 1376);
const m = ViewportConstants.sideMargin;

PageLayout verticalA4(int n) => PageLayout.compute(
  pageSizes: List.filled(n, a4),
  axis: LayoutAxis.vertical,
);

Matcher closeOffset(Offset expected, double tolerance) => isA<Offset>().having(
  (o) => (o - expected).distance,
  'distance',
  lessThan(tolerance),
);

void main() {
  test('doc → screen → doc round trips (error < 1e-9)', () {
    final random = math.Random(7);
    for (var i = 0; i < 200; i++) {
      final camera = ViewportCamera(
        scale: 0.1 + random.nextDouble() * 10,
        origin: Offset(
          random.nextDouble() * 4000 - 2000,
          random.nextDouble() * 40000,
        ),
      );
      final doc = Offset(
        random.nextDouble() * 1000,
        random.nextDouble() * 50000,
      );
      final screen = Offset(
        random.nextDouble() * 1032,
        random.nextDouble() * 1376,
      );
      expect(
        camera.screenToDoc(camera.docToScreen(doc)),
        closeOffset(doc, 1e-9),
      );
      expect(
        camera.docToScreen(camera.screenToDoc(screen)),
        closeOffset(screen, 1e-9),
      );
    }
  });

  test('visibleDocRect, pannedBy', () {
    const camera = ViewportCamera(scale: 2, origin: Offset(10, 20));
    expect(
      camera.visibleDocRect(viewport),
      const Rect.fromLTWH(10, 20, 516, 688),
    );
    expect(
      camera.pannedBy(const Offset(40, -20)).origin,
      const Offset(-10, 30),
    );
    expect(camera.pannedBy(const Offset(40, -20)).scale, 2);
  });

  test('zoomedAround keeps the doc point under the focal point', () {
    const camera = ViewportCamera(scale: 1.3, origin: Offset(-12, 345));
    const focal = Offset(400, 900);
    final docUnder = camera.screenToDoc(focal);
    for (final s in [0.4, 1.0, 2.5, 9.0]) {
      final zoomed = camera.zoomedAround(focal, s);
      expect(zoomed.scale, s);
      expect(zoomed.docToScreen(docUnder), closeOffset(focal, 1e-9));
    }
  });

  test('value equality', () {
    expect(
      const ViewportCamera(scale: 1, origin: Offset(1, 2)),
      const ViewportCamera(scale: 1, origin: Offset(1, 2)),
    );
    expect(
      const ViewportCamera(scale: 1, origin: Offset(1, 2)).hashCode,
      const ViewportCamera(scale: 1, origin: Offset(1, 2)).hashCode,
    );
    expect(
      const ViewportCamera(scale: 1, origin: Offset(1, 2)),
      isNot(const ViewportCamera(scale: 2, origin: Offset(1, 2))),
    );
  });

  group('fitScale', () {
    test('vertical: viewport width minus margins over the widest page', () {
      final layout = PageLayout.compute(
        pageSizes: const [a4, Size(800, 600)],
        axis: LayoutAxis.vertical,
      );
      expect(CameraMath.fitScale(layout, viewport), (1032 - 2 * m) / 800);
    });

    test('horizontal: the page fits both ways', () {
      final layout = PageLayout.compute(
        pageSizes: const [a4, Size(2000, 300)],
        axis: LayoutAxis.horizontal,
      );
      expect(
        CameraMath.fitScale(layout, viewport),
        math.min((1032 - 2 * m) / a4.width, (1376 - 2 * m) / a4.height),
      );
      expect(
        CameraMath.fitScale(layout, viewport, pageIndex: 1),
        (1032 - 2 * m) / 2000,
      );
      expect(
        CameraMath.fitScale(layout, const Size(1376, 1032)),
        (1032 - 2 * m) / a4.height,
      );
    });

    test('empty layout → 1', () {
      final empty = PageLayout.compute(
        pageSizes: const [],
        axis: LayoutAxis.vertical,
      );
      expect(CameraMath.fitScale(empty, viewport), 1);
    });
  });

  group('clamp', () {
    final layout = verticalA4(5);
    final fit = CameraMath.fitScale(layout, viewport);

    test('scale is limited to [fit*minZoom, fit*maxZoom]', () {
      const origin = Offset(0, 500);
      expect(
        CameraMath.clamp(
          ViewportCamera(scale: fit * 0.1, origin: origin),
          layout,
          viewport,
          fit,
        ).scale,
        fit * ViewportConstants.minZoom,
      );
      expect(
        CameraMath.clamp(
          ViewportCamera(scale: fit * 100, origin: origin),
          layout,
          viewport,
          fit,
        ).scale,
        fit * ViewportConstants.maxZoom,
      );
    });

    test('at fit the page is centred horizontally whatever origin.x', () {
      for (final x in [-500.0, 0.0, 300.0]) {
        final c = CameraMath.clamp(
          ViewportCamera(scale: fit, origin: Offset(x, 100)),
          layout,
          viewport,
          fit,
        );
        final visW = viewport.width / fit;
        expect(c.origin.dx, closeTo((a4.width - visW) / 2, 1e-9));
        // The page shows with a side margin on both sides.
        expect(c.docToScreen(layout.rectOf(0).topLeft).dx, closeTo(m, 1e-9));
      }
    });

    test('zoomed in: x limited to the page plus a side margin', () {
      final scale = fit * 3;
      final visW = viewport.width / scale;
      final left = CameraMath.clamp(
        ViewportCamera(scale: scale, origin: const Offset(-1000, 100)),
        layout,
        viewport,
        fit,
      );
      expect(left.origin.dx, closeTo(-m / scale, 1e-9));
      final right = CameraMath.clamp(
        ViewportCamera(scale: scale, origin: const Offset(5000, 100)),
        layout,
        viewport,
        fit,
      );
      expect(right.origin.dx, closeTo(a4.width - visW + m / scale, 1e-9));
      final inside = CameraMath.clamp(
        ViewportCamera(scale: scale, origin: const Offset(100, 100)),
        layout,
        viewport,
        fit,
      );
      expect(inside.origin, const Offset(100, 100));
    });

    test('y limited to [0, contentHeight - visibleHeight]', () {
      final visH = viewport.height / fit;
      final top = CameraMath.clamp(
        ViewportCamera(scale: fit, origin: const Offset(0, -300)),
        layout,
        viewport,
        fit,
      );
      expect(top.origin.dy, 0);
      final bottom = CameraMath.clamp(
        ViewportCamera(scale: fit, origin: const Offset(0, 1e7)),
        layout,
        viewport,
        fit,
      );
      expect(bottom.origin.dy, closeTo(layout.contentSize.height - visH, 1e-9));
    });

    test('content shorter than the viewport is centred vertically', () {
      final one = verticalA4(1);
      final scale = fit * ViewportConstants.minZoom;
      final c = CameraMath.clamp(
        ViewportCamera(scale: scale, origin: const Offset(0, 999)),
        one,
        viewport,
        fit,
      );
      final visH = viewport.height / scale;
      expect(c.origin.dy, closeTo((one.contentSize.height - visH) / 2, 1e-9));
    });

    test('horizontal layout swaps the axes', () {
      final h = PageLayout.compute(
        pageSizes: List.filled(4, a4),
        axis: LayoutAxis.horizontal,
      );
      final hFit = CameraMath.fitScale(h, viewport);
      final c = CameraMath.clamp(
        ViewportCamera(scale: hFit, origin: const Offset(-50, 777)),
        h,
        viewport,
        hFit,
      );
      final visH = viewport.height / hFit;
      final visW = viewport.width / hFit;
      // Paged: the lower bound reaches the first page centred (≤ 0).
      final firstCentred = h.rectOf(0).center.dx - visW / 2;
      expect(
        c.origin.dx,
        closeTo(math.min(0, firstCentred), 1e-9),
        reason: 'main axis clamped to the first page centred',
      );
      expect(c.origin.dy, closeTo((a4.height - visH) / 2, 1e-9));
    });

    test('horizontal (paged): the first and the last page can be centred', () {
      final h = PageLayout.compute(
        pageSizes: List.filled(3, a4),
        axis: LayoutAxis.horizontal,
      );
      for (final size in [viewport, const Size(1376, 1032)]) {
        final fit = CameraMath.fitScale(h, size);
        final vis = size.width / fit;
        for (final i in [0, 2]) {
          final centred = h.rectOf(i).center.dx - vis / 2;
          final c = CameraMath.clamp(
            ViewportCamera(scale: fit, origin: Offset(centred, 0)),
            h,
            size,
            fit,
          );
          expect(c.origin.dx, closeTo(centred, 1e-9), reason: 'page $i $size');
        }
        // Beyond them it still stops.
        final c = CameraMath.clamp(
          ViewportCamera(scale: fit, origin: const Offset(-1000, 0)),
          h,
          size,
          fit,
        );
        expect(c.origin.dx, closeTo(h.rectOf(0).center.dx - vis / 2, 1e-9));
      }
      // Zoomed in, the range is the plain [0, content − visible] again.
      final fit = CameraMath.fitScale(h, viewport);
      final c = CameraMath.clamp(
        ViewportCamera(scale: fit * 3, origin: const Offset(-1000, 0)),
        h,
        viewport,
        fit,
      );
      expect(c.origin.dx, 0);
    });
  });

  group('applyGesture', () {
    final layout = verticalA4(20);
    final fit = CameraMath.fitScale(layout, viewport);
    final base = ViewportCamera(
      scale: fit * 2,
      origin: const Offset(100, 3000),
    );

    test('the doc point under the baseline focal ends under the focal', () {
      const baselineFocal = Offset(500, 600);
      const focal = Offset(520, 640);
      final c = CameraMath.applyGesture(
        base: base,
        baselineFocal: baselineFocal,
        focal: focal,
        scaleRatio: 1.5,
        layout: layout,
        viewport: viewport,
        fitScale: fit,
      );
      expect(c.scale, closeTo(base.scale * 1.5, 1e-12));
      expect(
        c.docToScreen(base.screenToDoc(baselineFocal)),
        closeOffset(focal, 1e-9),
      );
    });

    test('100 pieces equal one application (error < 1e-6)', () {
      const start = Offset(400, 500);
      const end = Offset(470, 380);
      const totalRatio = 1.8;
      final once = CameraMath.applyGesture(
        base: base,
        baselineFocal: start,
        focal: end,
        scaleRatio: totalRatio,
        layout: layout,
        viewport: viewport,
        fitScale: fit,
      );
      var camera = base;
      var previousFocal = start;
      final pieceRatio = math.pow(totalRatio, 1 / 100).toDouble();
      for (var i = 1; i <= 100; i++) {
        final focal = Offset.lerp(start, end, i / 100)!;
        camera = CameraMath.applyGesture(
          base: camera,
          baselineFocal: previousFocal,
          focal: focal,
          scaleRatio: pieceRatio,
          layout: layout,
          viewport: viewport,
          fitScale: fit,
        );
        previousFocal = focal;
      }
      expect((camera.scale - once.scale).abs(), lessThan(1e-6));
      expect(camera.origin, closeOffset(once.origin, 1e-6));
    });

    test('scale saturates at the limits', () {
      final c = CameraMath.applyGesture(
        base: base,
        baselineFocal: const Offset(500, 500),
        focal: const Offset(500, 500),
        scaleRatio: 1000,
        layout: layout,
        viewport: viewport,
        fitScale: fit,
      );
      expect(c.scale, fit * ViewportConstants.maxZoom);
    });
  });
}
