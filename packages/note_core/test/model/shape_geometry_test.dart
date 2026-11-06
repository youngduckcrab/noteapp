// Shape templates and geometry transforms (m5-7/02-core 6.2.2 table): exact vertices,
// clockwise order in y-down coordinates, argument ranges, the polyline frame. Web-safe.
import 'dart:math' as math;

import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

Matcher _near(PagePoint p, [double eps = 1e-9]) => isA<PagePoint>()
    .having((q) => q.x, 'x', closeTo(p.x, eps))
    .having((q) => q.y, 'y', closeTo(p.y, eps));

/// The signed area of a closed polygon; positive = clockwise on screen (y down).
double _signedArea(List<PagePoint> p) {
  var a = 0.0;
  for (var i = 0; i < p.length; i++) {
    final q = p[(i + 1) % p.length];
    a += p[i].x * q.y - q.x * p[i].y;
  }
  return a / 2;
}

void main() {
  const r = PageRect(100, 200, 300, 300); // center (200, 250), 200 × 100

  test('line', () {
    final g = ShapeGeometry.line(const PagePoint(1, 2), const PagePoint(3, 4));
    expect(g.points, const [PagePoint(1, 2), PagePoint(3, 4)]);
    expect(g.closed, isFalse);
    expect(g.frame, const ElementFrame(PageRect(1, 2, 3, 4)));
  });

  test('rectangle: tl, tr, br, bl, rotated about the center', () {
    final g = ShapeGeometry.rectangle(r);
    expect(g.closed, isTrue);
    expect(g.points, const [
      PagePoint(100, 200),
      PagePoint(300, 200),
      PagePoint(300, 300),
      PagePoint(100, 300),
    ]);
    expect(_signedArea(g.points), greaterThan(0));
    final turned = ShapeGeometry.rectangle(r, rotation: math.pi / 2);
    expect(turned.points, [
      _near(const PagePoint(250, 150)),
      _near(const PagePoint(250, 350)),
      _near(const PagePoint(150, 350)),
      _near(const PagePoint(150, 150)),
    ]);
    // A rotated rectangle's frame is the axis-aligned box of its points (rotation 0).
    expect(turned.frame.rotation, 0);
    expect(turned.frame.rect.width, closeTo(100, 1e-9));
  });

  test('ellipse', () {
    final g = ShapeGeometry.ellipse(r, rotation: 0.5);
    expect(g, const EllipseGeometry(ElementFrame(r, rotation: 0.5)));
    expect(g.frame, const ElementFrame(r, rotation: 0.5));
  });

  test('triangle: apex (cx, top) → (right, bottom) → (left, bottom)', () {
    final g = ShapeGeometry.triangle(r);
    expect(g.points, const [
      PagePoint(200, 200),
      PagePoint(300, 300),
      PagePoint(100, 300),
    ]);
    expect(g.closed, isTrue);
    expect(_signedArea(g.points), greaterThan(0));
  });

  test('regularPolygon: from the top, clockwise; 3..12', () {
    final square = ShapeGeometry.regularPolygon(
      const PageRect(0, 0, 100, 100),
      4,
    );
    expect(square.points, [
      _near(const PagePoint(50, 0)),
      _near(const PagePoint(100, 50)),
      _near(const PagePoint(50, 100)),
      _near(const PagePoint(0, 50)),
    ]);
    final hex = ShapeGeometry.regularPolygon(r, 6);
    expect(hex.points, hasLength(6));
    expect(hex.points.first, _near(const PagePoint(200, 200)));
    expect(_signedArea(hex.points), greaterThan(0));
    final turned = ShapeGeometry.regularPolygon(
      const PageRect(0, 0, 100, 100),
      4,
      rotation: math.pi / 4,
    );
    expect(
      turned.points.first,
      _near(PagePoint(50 + 50 * math.sqrt1_2, 50 - 50 * math.sqrt1_2)),
    );
    for (final sides in [2, 13, 0, -1]) {
      expect(
        () => ShapeGeometry.regularPolygon(r, sides),
        throwsArgumentError,
        reason: '$sides',
      );
    }
    expect(ShapeGeometry.regularPolygon(r, 3).points, hasLength(3));
    expect(ShapeGeometry.regularPolygon(r, 12).points, hasLength(12));
  });

  test(
    'star: 2·points vertices, outer then inner, from the top, clockwise',
    () {
      final g = ShapeGeometry.star(const PageRect(0, 0, 100, 100));
      expect(g.points, hasLength(10));
      expect(g.closed, isTrue);
      expect(g.points[0], _near(const PagePoint(50, 0)));
      // The first inner vertex is 36° clockwise of the top at half the radius.
      final a = -math.pi / 2 + math.pi / 5;
      expect(
        g.points[1],
        _near(PagePoint(50 + 25 * math.cos(a), 50 + 25 * math.sin(a))),
      );
      expect(_signedArea(g.points), greaterThan(0));
      for (var i = 0; i < 10; i += 2) {
        final p = g.points[i];
        expect(
          math.sqrt(math.pow(p.x - 50, 2) + math.pow(p.y - 50, 2)),
          closeTo(50, 1e-9),
        );
      }
      expect(
        ShapeGeometry.star(r, points: 3, innerRatio: 0.1).points,
        hasLength(6),
      );
      expect(
        ShapeGeometry.star(r, points: 12, innerRatio: 0.9).points,
        hasLength(24),
      );
      expect(() => ShapeGeometry.star(r, points: 2), throwsArgumentError);
      expect(() => ShapeGeometry.star(r, points: 13), throwsArgumentError);
      expect(
        () => ShapeGeometry.star(r, innerRatio: 0.05),
        throwsArgumentError,
      );
      expect(
        () => ShapeGeometry.star(r, innerRatio: 0.95),
        throwsArgumentError,
      );
      expect(
        () => ShapeGeometry.star(r, innerRatio: double.nan),
        throwsArgumentError,
      );
    },
  );

  test('template point lists are unmodifiable', () {
    final g = ShapeGeometry.rectangle(r);
    expect(() => g.points.add(const PagePoint(0, 0)), throwsUnsupportedError);
  });

  group('transformed', () {
    test('polyline: every point mapped exactly', () {
      final g = ShapeGeometry.triangle(r);
      final m = Affine2.translation(5, -5);
      final t = g.transformed(m) as PolylineGeometry;
      expect(t.points, const [
        PagePoint(205, 195),
        PagePoint(305, 295),
        PagePoint(105, 295),
      ]);
      expect(t.closed, isTrue);
      final s = g.transformed(Affine2.scaling(2, 2)) as PolylineGeometry;
      expect(s.points.first, const PagePoint(400, 400));
    });

    test('ellipse: its frame transformed (exact for similarity)', () {
      const g = EllipseGeometry(ElementFrame(r));
      final m = Affine2.rotation(math.pi / 2, originX: 200, originY: 250);
      final t = g.transformed(m) as EllipseGeometry;
      expect(t.ellipseFrame.center, _near(const PagePoint(200, 250)));
      expect(t.ellipseFrame.rect.width, closeTo(200, 1e-9));
      expect(t.ellipseFrame.rotation, closeTo(math.pi / 2, 1e-12));
    });
  });

  test('polyline frame: the AABB of the points', () {
    const g = PolylineGeometry([
      PagePoint(5, 9),
      PagePoint(-3, 2),
      PagePoint(7, 4),
    ], closed: true);
    expect(g.frame, const ElementFrame(PageRect(-3, 2, 7, 9)));
  });
}
