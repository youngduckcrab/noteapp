// L2-06 (m5-7/05-library 8.2, 6.17.2): the beautifier — a line snaps to 15°
// (±3°, INK SelectionGeometry.snapAngle) about its middle, ellipses and
// rectangles to an axis within ±8°, a circle is a square frame, a rectangle
// is ShapeGeometry.rectangle (corners clockwise from the top-left) whose
// sides come from the raw points (≤ 1 pt on a synthetic rectangle, a closing
// hook does not drag a side, a side without points uses the corner bounds),
// triangles / polygons are closed clockwise polylines; every fit makes a
// ShapeObject with finite bounds.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/testing.dart';
import 'package:material_ui/material_ui.dart' show Rect;
import 'package:note_core/note_core.dart' as core;

import '../shared/shape_cases.dart';

const _fitter = GeometricShapeFitter();

ink.InkShapeFit _fit(List<Offset> points) => _fitter.fit(points, viewScale: 1)!;

/// [points] turned by [degrees] about [about].
List<Offset> _turn(List<Offset> points, double degrees, Offset about) {
  final a = degrees * math.pi / 180, c = math.cos(a), s = math.sin(a);
  return [
    for (final p in points)
      Offset(
        about.dx + c * (p.dx - about.dx) - s * (p.dy - about.dy),
        about.dy + s * (p.dx - about.dx) + c * (p.dy - about.dy),
      ),
  ];
}

/// An ellipse outline (semi-axes [rx], [ry], turned by [degrees]).
List<Offset> _ellipse(
  Offset c,
  double rx,
  double ry, {
  double degrees = 0,
  int n = 120,
}) => _turn(
  [
    for (var i = 0; i <= n; i++)
      Offset(
        c.dx + rx * math.cos(2 * math.pi * i / n),
        c.dy + ry * math.sin(2 * math.pi * i / n),
      ),
  ],
  degrees,
  c,
);

double _shoelace(List<core.PagePoint> p) {
  var s = 0.0;
  for (var i = 0; i < p.length; i++) {
    final a = p[i], b = p[(i + 1) % p.length];
    s += a.x * b.y - b.x * a.y;
  }
  return s / 2;
}

void main() {
  group('line (15°, ±3°)', () {
    test('32° → 30°, the middle and the length kept', () {
      const a = Offset(100, 100);
      final b = a + Offset.fromDirection(32 * math.pi / 180, 200);
      final fit = _fit([
        for (var i = 0; i <= 20; i++) Offset.lerp(a, b, i / 20)!,
      ]);
      expect(fit.kind, core.ShapeKind.line);
      final g = fit.geometry as core.PolylineGeometry;
      expect(g.closed, isFalse);
      final [p, q] = g.points;
      expect(
        math.atan2(q.y - p.y, q.x - p.x) * 180 / math.pi,
        closeTo(30, 1e-6),
      );
      expect(
        math.sqrt(math.pow(q.x - p.x, 2) + math.pow(q.y - p.y, 2)),
        closeTo(200, 1e-6),
      );
      expect((p.x + q.x) / 2, closeTo((a.dx + b.dx) / 2, 1e-6));
      expect((p.y + q.y) / 2, closeTo((a.dy + b.dy) / 2, 1e-6));
    });

    test('37° stays 37° (more than 3° from 30° and 45°)', () {
      const a = Offset(100, 100);
      final b = a + Offset.fromDirection(37 * math.pi / 180, 200);
      final g =
          _fit([for (var i = 0; i <= 20; i++) Offset.lerp(a, b, i / 20)!])
                  .geometry
              as core.PolylineGeometry;
      final [p, q] = g.points;
      expect(
        math.atan2(q.y - p.y, q.x - p.x) * 180 / math.pi,
        closeTo(37, 1e-6),
      );
    });
  });

  group('ellipse and circle', () {
    test('a circle → a square, unrotated frame (radius (a + b) / 2)', () {
      final fit = _fit(_ellipse(const Offset(300, 300), 80, 76));
      expect(fit.kind, core.ShapeKind.ellipse);
      final f = fit.geometry.frame;
      expect(f.rotation, 0);
      expect(f.rect.width, closeTo(f.rect.height, 1e-9));
      expect(f.rect.width / 2, closeTo(78, 2));
      expect(f.center.x, closeTo(300, 0.5));
      expect(f.center.y, closeTo(300, 0.5));
    });

    test('an ellipse 6° off the axis → the axis; 20° → kept', () {
      final near = _fit(_ellipse(const Offset(300, 300), 120, 60, degrees: 6));
      expect(near.geometry.frame.rotation, 0);
      expect(near.geometry.frame.rect.width, closeTo(240, 6));
      expect(near.geometry.frame.rect.height, closeTo(120, 6));
      final off = _fit(_ellipse(const Offset(300, 300), 120, 60, degrees: 20));
      expect(off.geometry.frame.rotation * 180 / math.pi, closeTo(20, 1));
      // a turned by 96° = b along the frame's width, −84° → −84 + 90 = 6 → 0
      final tall = _fit(_ellipse(const Offset(300, 300), 120, 60, degrees: 96));
      expect(tall.geometry.frame.rotation, 0);
      expect(tall.geometry.frame.rect.width, closeTo(120, 6));
      expect(tall.geometry.frame.rect.height, closeTo(240, 6));
    });
  });

  group('rectangle (side refinement)', () {
    test('ShapeGeometry.rectangle: 4 corners clockwise from the top-left; a '
        'synthetic rectangle within 1 pt', () {
      const rect = Rect.fromLTWH(120, 80, 300, 140);
      final fit = _fit(SyntheticShapes.rectanglePath(rect));
      expect(fit.kind, core.ShapeKind.rectangle);
      final g = fit.geometry as core.PolylineGeometry;
      expect(g.closed, isTrue);
      expect(g.points, hasLength(4));
      expect(_shoelace(g.points), greaterThan(0)); // clockwise (y down)
      final [tl, tr, br, bl] = g.points;
      for (final (p, want) in [
        (tl, rect.topLeft),
        (tr, rect.topRight),
        (br, rect.bottomRight),
        (bl, rect.bottomLeft),
      ]) {
        expect(p.x, closeTo(want.dx, 1), reason: '$want');
        expect(p.y, closeTo(want.dy, 1), reason: '$want');
      }
    });

    test('turned 5° → snapped to the axis; turned 20° → rotation 20°, the '
        'sides still within 1 pt', () {
      const rect = Rect.fromLTWH(200, 200, 240, 160);
      final path = SyntheticShapes.rectanglePath(rect);
      List<core.PagePoint> corners(double degrees) =>
          (_fit(_turn(path, degrees, rect.center)).geometry
                  as core.PolylineGeometry)
              .points;
      final near = corners(5);
      expect(near[0].y, closeTo(near[1].y, 1e-9)); // axis aligned
      expect(near[1].x, closeTo(near[2].x, 1e-9));
      final [p0, p1, p2, p3] = corners(20);
      double len(core.PagePoint a, core.PagePoint b) =>
          math.sqrt(math.pow(b.x - a.x, 2) + math.pow(b.y - a.y, 2));
      final edge = math.atan2(p1.y - p0.y, p1.x - p0.x) * 180 / math.pi;
      expect(edge, closeTo(20, 1e-6));
      expect(len(p0, p1), closeTo(240, 1));
      expect(len(p1, p2), closeTo(160, 1));
      expect((p0.x + p2.x) / 2, closeTo(rect.center.dx, 1));
      expect((p1.y + p3.y) / 2, closeTo(rect.center.dy, 1));
    });

    test('a closing hook does not drag a side', () {
      const rect = Rect.fromLTWH(100, 100, 240, 160);
      final path = SyntheticShapes.rectanglePath(rect, pointsPerSide: 32);
      // past the start along the top, then a hook down into the box
      final hook = [
        ...path,
        for (var i = 1; i <= 6; i++) Offset(220 + 4.0 * i, 100),
        for (var i = 1; i <= 4; i++) Offset(244 + 2.0 * i, 100 + 4.0 * i),
      ];
      final fit = _fit(hook);
      expect(fit.kind, core.ShapeKind.rectangle);
      final r = fit.geometry.frame.rect;
      expect(r.left, closeTo(100, 1));
      expect(r.top, closeTo(100, 1));
      expect(r.right, closeTo(340, 1));
      expect(r.bottom, closeTo(260, 1));
    });

    test('a side with fewer than 2 points in its middle 70 % → the corner '
        'bounds there', () {
      // The right side drawn as one long step: no sample between its corners.
      final pts = <Offset>[
        for (var i = 0; i <= 30; i++) Offset(100 + 8.0 * i, 100), // top
        const Offset(340, 260), // straight down the right side
        for (var i = 1; i <= 30; i++) Offset(340 - 8.0 * i, 260), // bottom
        for (var i = 1; i <= 20; i++) Offset(100, 260 - 8.0 * i), // left
      ];
      final fit = _fit(pts);
      expect(fit.kind, core.ShapeKind.rectangle);
      final r = fit.geometry.frame.rect;
      expect(r.left, closeTo(100, 1));
      expect(r.top, closeTo(100, 1));
      expect(r.bottom, closeTo(260, 1));
      // the corner bounds sit at most a resample step inside
      expect(r.right, inInclusiveRange(340 - 12, 340.0 + 1e-9));
    });
  });

  test('triangle and polygon: closed, clockwise from the topmost corner', () {
    final gen = SyntheticShapeGenerator(20261105);
    var triangles = 0, polygons = 0;
    for (final t in [ShapeTruth.triangle, ShapeTruth.pentagon]) {
      for (var i = 0; i < 30; i++) {
        final fit = _fitter.fit(gen.stroke(t), viewScale: 1);
        if (fit == null ||
            (fit.kind != core.ShapeKind.triangle &&
                fit.kind != core.ShapeKind.polygon)) {
          continue;
        }
        final g = fit.geometry as core.PolylineGeometry;
        expect(g.closed, isTrue);
        expect(_shoelace(g.points), greaterThan(0));
        final top = g.points.map((p) => p.y).reduce(math.min);
        expect(g.points.first.y, top);
        if (fit.kind == core.ShapeKind.triangle) {
          expect(g.points, hasLength(3));
          triangles++;
        } else {
          expect(g.points.length, inInclusiveRange(4, 8));
          polygons++;
        }
      }
    }
    expect(triangles, greaterThan(20));
    expect(polygons, greaterThan(20));
  });

  test('every fit makes a ShapeObject with finite bounds (≤ 64 points)', () {
    final gen = SyntheticShapeGenerator(42);
    final kinds = <core.ShapeKind>{};
    for (final t in ShapeTruth.values) {
      for (var i = 0; i < 20; i++) {
        final fit = _fitter.fit(gen.stroke(t), viewScale: 1);
        if (fit == null) continue;
        kinds.add(fit.kind);
        final object = core.ShapeObject(
          id: 'shape_$i',
          pageId: 'page-1',
          shapeKind: fit.kind,
          geometry: fit.geometry,
          style: const core.ShapeStyle(strokeColorArgb: 0xFF1A1A1A),
          createdAt: 1,
        );
        final b = object.bounds;
        expect(
          [b.left, b.top, b.right, b.bottom].every((v) => v.isFinite),
          isTrue,
        );
        if (fit.geometry case core.PolylineGeometry(:final points)) {
          expect(points.length, lessThanOrEqualTo(64));
        }
        expect(fit.score, inInclusiveRange(0, 1));
      }
    }
    expect(
      kinds,
      containsAll(
        core.ShapeKind.values.where(
          (k) => k != core.ShapeKind.arrow && k != core.ShapeKind.star,
        ),
      ),
    );
  });
}
