// m5-7/03-ink 6.18 '맞춘 뒤 조절' (contract v2.12 C212-01): adjustShape, the pure
// drag of a snapped shape — every ShapeGeometry kind the fitter makes:
// - line / arrow: the far end stays, the held end follows the pen; 15° snap
//   within 3° (the fitter's step); a minimum length; open polylines of 3+
//   points turn and scale about the fixed end; (review) adjustLeavesOpenShape:
//   turned more than 30° about the fixed end → the stroke goes on;
// - circle: center fixed, radius follows the pen's distance 1:1;
// - ellipse: center and rotation fixed, both axes × the distance ratio;
// - rectangle / quad (closed 4 points): the corner nearest the anchor follows,
//   the opposite one stays; axis-aligned stays axis-aligned, rotated stays a
//   rectangle in its own frame; sides clamp at the minimum, never flip;
//   (review) held nearer an edge's midpoint: only that edge moves; a concave
//   quad scales uniformly;
// - triangle / polygon / star: uniform scale about the vertex mean, no turn;
// - pen == anchor → the same geometry; a non-finite pen → the snapped one;
//   nothing grows past ElementFrame.maxSide; (review) a drag overflowing to
//   infinity or a NaN minimum never gives NaN / zero-length geometry; the
//   minimum holds for the smaller side of a uniform scale.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/shape/shape_adjust.dart';
import 'package:note_core/note_core.dart' as core;

InkShapeFit _fit(core.ShapeKind kind, core.ShapeGeometry g) =>
    InkShapeFit(kind: kind, geometry: g, score: 0.9);

core.ShapeGeometry _adjust(
  InkShapeFit fit,
  Offset anchor,
  Offset pen, {
  double min = 8,
}) => adjustShape(fit, anchor: anchor, pen: pen, minSizePt: min);

List<Offset> _pts(core.ShapeGeometry g) => [
  for (final p in (g as core.PolylineGeometry).points) Offset(p.x, p.y),
];

Matcher _near(Offset o, [double tol = 1e-6]) => isA<Offset>()
    .having((p) => p.dx, 'dx', closeTo(o.dx, tol))
    .having((p) => p.dy, 'dy', closeTo(o.dy, tol));

double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

void main() {
  group('line / arrow', () {
    final line = _fit(
      core.ShapeKind.line,
      core.ShapeGeometry.line(
        const core.PagePoint(10, 10),
        const core.PagePoint(110, 30),
      ),
    );

    test('the start stays, the held end moves by (pen − anchor)', () {
      // (130, 90) from (10, 10): 33.7°, not near a multiple of 15°
      final g = _adjust(line, const Offset(110, 30), const Offset(130, 90));
      final p = _pts(g);
      expect(p[0], const Offset(10, 10));
      expect(p[1], _near(const Offset(130, 90)));
      expect((g as core.PolylineGeometry).closed, isFalse);
    });

    test('held at the first point: the last point stays', () {
      final g = _adjust(line, const Offset(12, 11), const Offset(-20, 40));
      final p = _pts(g);
      expect(p[1], const Offset(110, 30));
      expect(p[0], _near(const Offset(-22, 39)));
    });

    test('within 3° of a multiple of 15° it lies on it, length kept; 5° '
        'off it does not', () {
      // from (10, 10): (110, 15) is 2.86° below 0°
      final g = _adjust(line, const Offset(110, 30), const Offset(110, 15));
      final p = _pts(g);
      final len = (const Offset(110, 15) - const Offset(10, 10)).distance;
      expect(p[1], _near(Offset(10 + len, 10)));
      // 45°: (80, 77) is 1.7° off
      final d = _pts(
        _adjust(line, const Offset(110, 30), const Offset(80, 77)),
      )[1];
      expect((d - const Offset(10, 10)).direction, closeTo(math.pi / 4, 1e-9));
      // (review) 30° like the fitter: 31.5° from (10, 10) lies on 30°
      final at30 = _pts(
        _adjust(
          line,
          const Offset(110, 30),
          const Offset(10, 10) + Offset.fromDirection(31.5 * math.pi / 180, 90),
        ),
      )[1];
      expect(
        (at30 - const Offset(10, 10)).direction,
        closeTo(math.pi / 6, 1e-9),
      );
      expect((at30 - const Offset(10, 10)).distance, closeTo(90, 1e-9));
      // 5°: kept as is
      final off = Offset(
        10 + 100 * math.cos(0.0873),
        10 + 100 * math.sin(0.0873),
      );
      expect(_pts(_adjust(line, const Offset(110, 30), off))[1], _near(off));
    });

    test('the arrow snaps too; a minimum length keeps the direction and '
        'never collapses', () {
      final arrow = _fit(core.ShapeKind.arrow, line.geometry);
      final g = _adjust(arrow, const Offset(110, 30), const Offset(13, 11));
      final p = _pts(g);
      expect((p[1] - p[0]).distance, closeTo(8, 1e-9));
      // onto the start exactly: the snapped direction, minimum length
      final z = _pts(
        _adjust(arrow, const Offset(110, 30), const Offset(10, 10)),
      );
      expect((z[1] - z[0]).distance, closeTo(8, 1e-9));
      final dir = const Offset(100, 20) / const Offset(100, 20).distance;
      expect(z[1], _near(const Offset(10, 10) + dir * 8));
    });

    test('a line shorter than the minimum is not made longer', () {
      final short = _fit(
        core.ShapeKind.line,
        core.ShapeGeometry.line(
          const core.PagePoint(0, 0),
          const core.PagePoint(4, 0),
        ),
      );
      final p = _pts(_adjust(short, const Offset(4, 0), const Offset(1, 0)));
      expect((p[1] - p[0]).distance, closeTo(4, 1e-9));
    });

    test('an open polyline of 3 points turns and scales about the fixed '
        'end', () {
      final open = _fit(
        core.ShapeKind.polygon,
        const core.PolylineGeometry([
          core.PagePoint(0, 0),
          core.PagePoint(10, 10),
          core.PagePoint(20, 0),
        ], closed: false),
      );
      // the last end moves from (20, 0) to (0, 40): × 2, turned 90°
      final p = _pts(_adjust(open, const Offset(20, 0), const Offset(0, 40)));
      expect(p[0], _near(Offset.zero));
      expect(p[1], _near(const Offset(-20, 20)));
      expect(p[2], _near(const Offset(0, 40)));
    });

    test('(review) adjustLeavesOpenShape: turned past 30° about the fixed '
        'end (or through it) → true; closed shapes never', () {
      bool leaves(InkShapeFit f, Offset pen) =>
          adjustLeavesOpenShape(f, anchor: const Offset(110, 30), pen: pen);
      // the line points at 11.3°; the held end along it or turned 15°: adjust
      expect(leaves(line, const Offset(150, 40)), isFalse);
      expect(
        leaves(
          line,
          const Offset(10, 10) + Offset.fromDirection(26 * math.pi / 180, 100),
        ),
        isFalse,
      );
      // a triangle's next edge (back up-left) or ㄱ's down stroke: drawing on
      expect(leaves(line, const Offset(60, -60)), isTrue);
      expect(leaves(line, const Offset(110, 120)), isTrue);
      // through the fixed end
      expect(leaves(line, const Offset(-40, 0)), isTrue);
      expect(leaves(line, const Offset(10, 10)), isTrue);
      final arrow = _fit(core.ShapeKind.arrow, line.geometry);
      expect(leaves(arrow, const Offset(110, 120)), isTrue);
      final rect = _fit(
        core.ShapeKind.rectangle,
        core.ShapeGeometry.rectangle(const core.PageRect(0, 0, 110, 30)),
      );
      expect(leaves(rect, const Offset(-200, 300)), isFalse);
      expect(leaves(line, const Offset(double.nan, 0)), isFalse);
    });

    test('(review) a drag overflowing to infinity or a NaN minimum never '
        'gives NaN or a zero-length line', () {
      final l = _fit(
        core.ShapeKind.line,
        core.ShapeGeometry.line(
          const core.PagePoint(0, 0),
          const core.PagePoint(100, 0),
        ),
      );
      final huge = _pts(
        adjustShape(
          l,
          anchor: const Offset(100, 0),
          pen: const Offset(1e308, 1e308),
          minSizePt: 8,
        ),
      );
      for (final q in huge) {
        expect(q.isFinite, isTrue);
      }
      final z = _pts(
        adjustShape(
          l,
          anchor: const Offset(100, 0),
          pen: Offset.zero,
          minSizePt: double.nan,
        ),
      );
      expect((z[1] - z[0]).distance, greaterThan(0));
    });
  });

  group('circle / ellipse', () {
    final circle = _fit(
      core.ShapeKind.ellipse,
      core.ShapeGeometry.ellipse(const core.PageRect(50, 50, 150, 150)),
    );

    test('circle: center fixed, radius follows the distance 1:1', () {
      // anchor at the top (r 50), pen 30 pt farther out (and around)
      final g = _adjust(
        circle,
        const Offset(100, 50),
        const Offset(180, 100),
      ) as core.EllipseGeometry;
      final f = g.ellipseFrame;
      expect(f.center, const core.PagePoint(100, 100));
      expect(f.rect.width, closeTo(160, 1e-9));
      expect(f.rect.height, closeTo(160, 1e-9));
      // the anchor 2 pt inside the circle: the radius still changes by the move
      final g2 = _adjust(
        circle,
        const Offset(100, 52),
        const Offset(100, 42),
      ) as core.EllipseGeometry;
      expect(g2.ellipseFrame.rect.width, closeTo(120, 1e-9));
    });

    test('circle: the diameter clamps at the minimum', () {
      final g = _adjust(
        circle,
        const Offset(100, 50),
        const Offset(100, 100),
      ) as core.EllipseGeometry;
      expect(g.ellipseFrame.rect.width, closeTo(8, 1e-9));
      expect(g.ellipseFrame.rect.height, closeTo(8, 1e-9));
      expect(g.ellipseFrame.center, const core.PagePoint(100, 100));
    });

    test('ellipse: center and rotation fixed, proportions kept', () {
      final e = _fit(
        core.ShapeKind.ellipse,
        core.ShapeGeometry.ellipse(
          const core.PageRect(0, 40, 200, 160),
          rotation: 0.3,
        ),
      );
      final c = const Offset(100, 100);
      final anchor = c + Offset.fromDirection(0.3, 100); // the a-axis end
      final pen = c + Offset.fromDirection(1.0, 150); // 1.5 × as far
      final g = _adjust(e, anchor, pen) as core.EllipseGeometry;
      final f = g.ellipseFrame;
      expect(f.rotation, 0.3);
      expect(f.center.x, closeTo(100, 1e-9));
      expect(f.center.y, closeTo(100, 1e-9));
      expect(f.rect.width, closeTo(300, 1e-9));
      expect(f.rect.height, closeTo(180, 1e-9));
      // shrinking toward the center: (review) the SMALLER side clamps at 8 —
      // a thin ellipse never becomes a hairline — no flip
      final tiny = _adjust(e, anchor, c) as core.EllipseGeometry;
      expect(tiny.ellipseFrame.rect.height, closeTo(8, 1e-9));
      expect(tiny.ellipseFrame.rect.width, closeTo(8 * 200 / 120, 1e-9));
      final thin = _fit(
        core.ShapeKind.ellipse,
        core.ShapeGeometry.ellipse(const core.PageRect(0, 95, 100, 105)),
      );
      final t = _adjust(
        thin,
        const Offset(100, 100),
        const Offset(51, 100),
      ) as core.EllipseGeometry;
      expect(t.ellipseFrame.rect.height, closeTo(8, 1e-9));
      expect(t.ellipseFrame.rect.width, closeTo(80, 1e-9));
    });
  });

  group('rectangle / quad', () {
    final rect = _fit(
      core.ShapeKind.rectangle,
      core.ShapeGeometry.rectangle(const core.PageRect(60, 50, 240, 250)),
    );

    test('axis-aligned: the nearest corner follows, the opposite one stays, '
        'still axis-aligned and clockwise from the top-left', () {
      final g = _adjust(rect, const Offset(238, 248), const Offset(300, 200));
      expect(_pts(g), [
        _near(const Offset(60, 50)),
        _near(const Offset(302, 50)),
        _near(const Offset(302, 202)),
        _near(const Offset(60, 202)),
      ]);
      expect((g as core.PolylineGeometry).closed, isTrue);
      // exact axis alignment (no rounding drift)
      final p = _pts(g);
      expect(p[0].dy, p[1].dy);
      expect(p[1].dx, p[2].dx);
    });

    test('dragging past the fixed corner clamps every side at the minimum, '
        'never inside out', () {
      final g = _adjust(rect, const Offset(60, 50), const Offset(400, 400));
      final p = _pts(g);
      expect(p[2], _near(const Offset(240, 250)), reason: 'fixed corner');
      expect(p[0], _near(const Offset(232, 242)));
      expect((p[1] - p[0]).distance, closeTo(8, 1e-9));
      expect((p[3] - p[0]).distance, closeTo(8, 1e-9));
    });

    test('rotated: resizes in its own frame — still a rectangle with the '
        'same direction', () {
      final r = _fit(
        core.ShapeKind.rectangle,
        core.ShapeGeometry.rectangle(
          const core.PageRect(0, 0, 100, 60),
          rotation: 0.5,
        ),
      );
      final before = _pts(r.geometry);
      final g = _adjust(r, before[1], before[1] + const Offset(10, 30));
      final p = _pts(g);
      expect(p[3], _near(before[3]), reason: 'the opposite corner');
      expect(p[1], _near(before[1] + const Offset(10, 30)));
      expect(_dot(p[1] - p[0], p[3] - p[0]), closeTo(0, 1e-6));
      expect(_dot(p[1] - p[2], p[3] - p[2]), closeTo(0, 1e-6));
      expect(
        (p[1] - p[0]).direction,
        closeTo((before[1] - before[0]).direction, 1e-9),
      );
    });

    test('a quad (polygon of 4 points): the nearest corner follows, the '
        'opposite one stays', () {
      final q = _fit(
        core.ShapeKind.polygon,
        const core.PolylineGeometry([
          core.PagePoint(0, 0),
          core.PagePoint(100, 10),
          core.PagePoint(90, 80),
          core.PagePoint(-10, 70),
        ], closed: true),
      );
      final g = _adjust(q, const Offset(90, 80), const Offset(120, 100));
      final p = _pts(g);
      expect(p[0], _near(Offset.zero));
      expect(p[2], _near(const Offset(120, 100)));
    });

    test('(review) held nearer an edge midpoint than a corner: only that edge '
        'moves, along its own direction', () {
      // mid-top (150, 50), dragged right and up: only the top edge moves up
      final g = _adjust(rect, const Offset(150, 50), const Offset(190, 30));
      expect(_pts(g), [
        _near(const Offset(60, 30)),
        _near(const Offset(240, 30)),
        _near(const Offset(240, 250)),
        _near(const Offset(60, 250)),
      ]);
      // mid-right (240, 150) dragged inward past the left edge: clamps at 8
      final r = _adjust(rect, const Offset(240, 150), const Offset(0, 170));
      expect(_pts(r), [
        _near(const Offset(60, 50)),
        _near(const Offset(68, 50)),
        _near(const Offset(68, 250)),
        _near(const Offset(60, 250)),
      ]);
      // a rotated rectangle: the edge moves along its normal, still a rectangle
      final rot = _fit(
        core.ShapeKind.rectangle,
        core.ShapeGeometry.rectangle(
          const core.PageRect(0, 0, 100, 60),
          rotation: 0.5,
        ),
      );
      final b = _pts(rot.geometry);
      final mid = (b[1] + b[2]) / 2;
      final p = _pts(_adjust(rot, mid, mid + const Offset(30, 5)));
      expect(p[0], _near(b[0]));
      expect(p[3], _near(b[3]));
      expect(_dot(p[1] - p[0], p[3] - p[0]), closeTo(0, 1e-6));
      expect(_dot(p[2] - p[1], p[1] - p[0]), closeTo(0, 1e-6));
    });

    test('(review) a concave quad scales uniformly about its vertex mean '
        '(no affine stretch)', () {
      final q = _fit(
        core.ShapeKind.polygon,
        const core.PolylineGeometry([
          core.PagePoint(0, 0),
          core.PagePoint(100, 50),
          core.PagePoint(0, 100),
          core.PagePoint(30, 50),
        ], closed: true),
      );
      final before = _pts(q.geometry);
      var c = Offset.zero;
      for (final o in before) {
        c += o;
      }
      c /= 4;
      final p = _pts(_adjust(q, const Offset(100, 50), const Offset(150, 50)));
      final s = (p[1] - c).distance / (before[1] - c).distance;
      expect(s, greaterThan(1));
      for (var i = 0; i < 4; i++) {
        expect(p[i], _near(c + (before[i] - c) * s));
      }
    });
  });

  group('triangle / polygon / star', () {
    test('triangle: uniform scale about the centroid by the distance ratio, '
        'no rotation', () {
      final t = _fit(
        core.ShapeKind.triangle,
        core.ShapeGeometry.triangle(const core.PageRect(0, 0, 120, 90)),
      );
      final before = _pts(t.geometry);
      final c = (before[0] + before[1] + before[2]) / 3;
      // anchor at the apex, pen twice as far, in another direction
      final anchor = before[0];
      final pen = c + Offset.fromDirection(2.0, (anchor - c).distance * 2);
      final p = _pts(_adjust(t, anchor, pen));
      for (var i = 0; i < 3; i++) {
        expect(p[i], _near(c + (before[i] - c) * 2));
      }
    });

    test('star and pentagon: the same; (review) the smaller side clamps at '
        'the minimum', () {
      for (final g in [
        core.ShapeGeometry.star(const core.PageRect(0, 0, 100, 100)),
        core.ShapeGeometry.regularPolygon(
          const core.PageRect(0, 0, 100, 100),
          5,
        ),
      ]) {
        final fit = _fit(core.ShapeKind.polygon, g);
        final before = _pts(g);
        var c = Offset.zero;
        for (final q in before) {
          c += q;
        }
        c /= before.length.toDouble();
        final top = before[0];
        final half = _pts(_adjust(fit, top, c + (top - c) * 0.5));
        for (var i = 0; i < before.length; i++) {
          expect(half[i], _near(c + (before[i] - c) * 0.5));
        }
        final tiny = _adjust(fit, top, c) as core.PolylineGeometry;
        final r = tiny.frame.rect;
        expect(math.min(r.width, r.height), closeTo(8, 1e-6));
      }
    });
  });

  group('guards', () {
    final shapes = [
      _fit(
        core.ShapeKind.line,
        core.ShapeGeometry.line(
          const core.PagePoint(0, 0),
          const core.PagePoint(50, 0),
        ),
      ),
      _fit(
        core.ShapeKind.ellipse,
        core.ShapeGeometry.ellipse(const core.PageRect(0, 0, 50, 30)),
      ),
      _fit(
        core.ShapeKind.rectangle,
        core.ShapeGeometry.rectangle(const core.PageRect(0, 0, 50, 30)),
      ),
      _fit(
        core.ShapeKind.triangle,
        core.ShapeGeometry.triangle(const core.PageRect(0, 0, 50, 30)),
      ),
    ];

    test('pen == anchor → the same geometry; a non-finite pen → the '
        'snapped one', () {
      for (final f in shapes) {
        expect(
          identical(
            _adjust(f, const Offset(50, 0), const Offset(50, 0)),
            f.geometry,
          ),
          isTrue,
        );
        expect(
          _adjust(f, const Offset(50, 0), const Offset(double.nan, 1)),
          f.geometry,
        );
      }
    });

    test('nothing grows past ElementFrame.maxSide', () {
      for (final f in shapes) {
        final g = _adjust(f, const Offset(50, 0), const Offset(1e9, 1e9));
        final b = g is core.EllipseGeometry
            ? g.ellipseFrame.rect
            : g.frame.rect;
        expect(
          math.max(b.width, b.height),
          lessThanOrEqualTo(core.ElementFrame.maxSide + 1e-6),
          reason: f.kind.name,
        );
      }
    });
  });
}
