// lib/src/model/shape_geometry.dart — (v2.0) 2nd-round contract 7.2.2 / 02-core 4.2, 6.2.2.
// ShapeKind, LineDash, ArrowHeads, ShapeGeometry (sealed) with PolylineGeometry and
// EllipseGeometry, and the shape templates (EDITOR's shape tool and the shape fitter).
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../common/geometry.dart';
import '../common/json_read.dart';

// --- shapes ---
enum ShapeKind { line, arrow, rectangle, ellipse, triangle, polygon, star }

// INK renders; dash lengths in multiples of strokeWidth
enum LineDash { solid, dashed, dotted }

enum ArrowHeads { none, end, both }

/// Shape geometry in ABSOLUTE page pt. Vertex editing moves PolylineGeometry.points.
@immutable
sealed class ShapeGeometry {
  const ShapeGeometry();
  ShapeGeometry transformed(Affine2 m);

  // polyline: AABB of points (rotation 0); ellipse: its frame
  ElementFrame get frame;

  // {"poly":[x0,y0,…],"closed":bool} | {"ellipse":[l,t,r,b,rot]}
  Object toJson();

  /// (CORE 6.2.2) FormatException when both keys or neither are present, the point array has
  /// an odd length or fewer than 2 points, or a value is not a finite number. The point cap
  /// (64) is a LOCAL command check — reads accept more (a newer app may raise it).
  factory ShapeGeometry.fromJson(Object? json) {
    final map = asMap(json, 'geometry');
    final poly = map['poly'];
    final ellipse = map['ellipse'];
    if ((poly == null) == (ellipse == null)) {
      throw const FormatException(
        'geometry needs exactly one of "poly" and "ellipse"',
      );
    }
    if (ellipse != null) {
      return EllipseGeometry(
        ElementFrame.fromJson(asList(ellipse, 'geometry.ellipse')),
      );
    }
    final v = asFiniteDoubles(poly, 'geometry.poly');
    if (v.length.isOdd || v.length < 4) {
      throw FormatException(
        'geometry.poly needs an even count of numbers for >= 2 points, got '
        '${v.length}',
      );
    }
    return PolylineGeometry(
      List<PagePoint>.unmodifiable([
        for (var i = 0; i < v.length; i += 2) PagePoint(v[i], v[i + 1]),
      ]),
      closed: readBool(map, 'closed'),
    );
  }

  // Templates (pure geometry, used by EDITOR's shape tool and the shape fitter):
  // (CORE 6.2.2 table) 'clockwise' = the direction of growing angles in y-down coordinates.
  static PolylineGeometry line(PagePoint a, PagePoint b) =>
      PolylineGeometry(List.unmodifiable([a, b]), closed: false);

  // 4 points, clockwise from top-left
  static PolylineGeometry rectangle(PageRect r, {double rotation = 0}) =>
      PolylineGeometry(
        List.unmodifiable(ElementFrame(r, rotation: rotation).corners),
        closed: true,
      );
  static EllipseGeometry ellipse(PageRect r, {double rotation = 0}) =>
      EllipseGeometry(ElementFrame(r, rotation: rotation));

  // isosceles, apex up
  static PolylineGeometry triangle(PageRect r) => PolylineGeometry(
    List.unmodifiable([
      PagePoint((r.left + r.right) / 2, r.top),
      PagePoint(r.right, r.bottom),
      PagePoint(r.left, r.bottom),
    ]),
    closed: true,
  );

  // 3..12
  /// α = −π/2 + rotation + 2πk/sides, (cx + (w/2)cos α, cy + (h/2)sin α), k = 0..sides−1 — from
  /// the top, clockwise. ArgumentError when sides is outside 3..12.
  static PolylineGeometry regularPolygon(
    PageRect r,
    int sides, {
    double rotation = 0,
  }) {
    if (sides < 3 || sides > 12) {
      throw ArgumentError.value(sides, 'sides', 'must be in 3..12');
    }
    final cx = (r.left + r.right) / 2, cy = (r.top + r.bottom) / 2;
    final rx = r.width / 2, ry = r.height / 2;
    return PolylineGeometry(
      List.unmodifiable([
        for (var k = 0; k < sides; k++)
          _onEllipse(
            cx,
            cy,
            rx,
            ry,
            -math.pi / 2 + rotation + 2 * math.pi * k / sides,
          ),
      ]),
      closed: true,
    );
  }

  // 2·points vertices
  /// Even vertices on the outer ellipse (w/2, h/2), odd ones at [innerRatio] of it; from the top
  /// outer vertex, clockwise. ArgumentError when points is outside 3..12 or innerRatio outside
  /// 0.1..0.9.
  static PolylineGeometry star(
    PageRect r, {
    int points = 5,
    double innerRatio = 0.5,
  }) {
    if (points < 3 || points > 12) {
      throw ArgumentError.value(points, 'points', 'must be in 3..12');
    }
    if (!(innerRatio >= 0.1 && innerRatio <= 0.9)) {
      throw ArgumentError.value(
        innerRatio,
        'innerRatio',
        'must be in 0.1..0.9',
      );
    }
    final cx = (r.left + r.right) / 2, cy = (r.top + r.bottom) / 2;
    final rx = r.width / 2, ry = r.height / 2;
    return PolylineGeometry(
      List.unmodifiable([
        for (var i = 0; i < 2 * points; i++)
          _onEllipse(
            cx,
            cy,
            i.isEven ? rx : rx * innerRatio,
            i.isEven ? ry : ry * innerRatio,
            -math.pi / 2 + math.pi * i / points,
          ),
      ]),
      closed: true,
    );
  }
}

PagePoint _onEllipse(double cx, double cy, double rx, double ry, double a) =>
    PagePoint(cx + rx * math.cos(a), cy + ry * math.sin(a));

final class PolylineGeometry extends ShapeGeometry {
  const PolylineGeometry(this.points, {required this.closed});
  final List<PagePoint> points; // 2..PageObjectLimits.maxPolylinePoints
  final bool closed;

  /// Every point mapped by [m] (exact).
  @override
  ShapeGeometry transformed(Affine2 m) => PolylineGeometry(
    List.unmodifiable([for (final p in points) p.transformed(m)]),
    closed: closed,
  );

  /// AABB of the points, rotation 0 (CORE 6.2.2).
  @override
  ElementFrame get frame {
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in points) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
    }
    if (points.isEmpty) return const ElementFrame(PageRect.zero);
    return ElementFrame(PageRect(minX, minY, maxX, maxY));
  }

  @override
  Object toJson() => {
    'poly': [
      for (final p in points) ...[p.x, p.y],
    ],
    'closed': closed,
  };

  // CORE 4.3: ==, hashCode (1차 7.4.4)
  @override
  bool operator ==(Object other) =>
      other is PolylineGeometry &&
      other.closed == closed &&
      const ListEquality<PagePoint>().equals(other.points, points);

  @override
  int get hashCode =>
      Object.hash(closed, const ListEquality<PagePoint>().hash(points));

  @override
  String toString() =>
      'PolylineGeometry(${points.length} points${closed ? ', closed' : ''})';
}

final class EllipseGeometry extends ShapeGeometry {
  const EllipseGeometry(this.ellipseFrame);
  final ElementFrame ellipseFrame; // bounding box before rotation

  /// ellipseFrame.transformed(m) — exact for similarity transforms.
  @override
  ShapeGeometry transformed(Affine2 m) =>
      EllipseGeometry(ellipseFrame.transformed(m));

  @override
  ElementFrame get frame => ellipseFrame;

  @override
  Object toJson() => {'ellipse': ellipseFrame.toJson()};

  // CORE 4.3: ==, hashCode (1차 7.4.4)
  @override
  bool operator ==(Object other) =>
      other is EllipseGeometry && other.ellipseFrame == ellipseFrame;

  @override
  int get hashCode => ellipseFrame.hashCode;

  @override
  String toString() => 'EllipseGeometry($ellipseFrame)';
}
