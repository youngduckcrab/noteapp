// lib/src/common/geometry.dart — pure Dart (no dart:ui). INK converts to Rect/Offset.
// Contract 00-overview 7.2.2 / CORE 4.1. (v2.0) PagePoint, ElementFrame — 2nd-round
// contract 7.2.2, 02-core 4.1 / 4.3 / 6.2.1.
import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'json_read.dart';
import 'pending.dart';

@immutable
final class PageRect {
  const PageRect(this.left, this.top, this.right, this.bottom);

  factory PageRect.fromLTWH(
    double left,
    double top,
    double width,
    double height,
  ) => PageRect(left, top, left + width, top + height);

  factory PageRect.fromPoints(double x1, double y1, double x2, double y2) =>
      PageRect(
        math.min(x1, x2),
        math.min(y1, y2),
        math.max(x1, x2),
        math.max(y1, y2),
      );

  static const PageRect zero = PageRect(0, 0, 0, 0);

  final double left, top, right, bottom;

  double get width => right - left;
  double get height => bottom - top;
  bool get isEmpty => width <= 0 || height <= 0; // width <= 0 || height <= 0

  /// Touching edges count as overlap.
  bool overlaps(PageRect other) =>
      left <= other.right &&
      other.left <= right &&
      top <= other.bottom &&
      other.top <= bottom;

  bool containsPoint(double x, double y) =>
      x >= left && x <= right && y >= top && y <= bottom;

  PageRect inflate(double delta) =>
      PageRect(left - delta, top - delta, right + delta, bottom + delta);

  PageRect expandToInclude(PageRect other) => PageRect(
    math.min(left, other.left),
    math.min(top, other.top),
    math.max(right, other.right),
    math.max(bottom, other.bottom),
  );

  Map<String, Object?> toJson() => {
    'l': left,
    't': top,
    'r': right,
    'b': bottom,
  }; // {"l":..,"t":..,"r":..,"b":..}

  factory PageRect.fromJson(Map<String, Object?> json) => PageRect(
    readDouble(json, 'l'),
    readDouble(json, 't'),
    readDouble(json, 'r'),
    readDouble(json, 'b'),
  );

  @override
  bool operator ==(Object other) =>
      other is PageRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'PageRect($left, $top, $right, $bottom)';
}

/// 2D affine transform: x' = a*x + c*y + tx, y' = b*x + d*y + ty.
@immutable
final class Affine2 {
  const Affine2(this.a, this.b, this.c, this.d, this.tx, this.ty);

  static const Affine2 identity = Affine2(1, 0, 0, 1, 0, 0);

  factory Affine2.translation(double dx, double dy) =>
      Affine2(1, 0, 0, 1, dx, dy);

  factory Affine2.scaling(
    double sx,
    double sy, {
    double originX = 0,
    double originY = 0,
  }) => Affine2(sx, 0, 0, sy, originX - sx * originX, originY - sy * originY);

  factory Affine2.rotation(
    double radians, {
    double originX = 0,
    double originY = 0,
  }) {
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    return Affine2(
      cos,
      sin,
      -sin,
      cos,
      originX - cos * originX + sin * originY,
      originY - sin * originX - cos * originY,
    );
  }

  final double a, b, c, d, tx, ty;

  /// Apply this, then next.
  Affine2 then(Affine2 next) => Affine2(
    next.a * a + next.c * b,
    next.b * a + next.d * b,
    next.a * c + next.c * d,
    next.b * c + next.d * d,
    next.a * tx + next.c * ty + next.tx,
    next.b * tx + next.d * ty + next.ty,
  );

  /// null if |det| < 1e-12.
  Affine2? inverse() {
    final det = determinant;
    if (det.abs() < 1e-12) return null;
    return Affine2(
      d / det,
      -b / det,
      -c / det,
      a / det,
      (c * ty - d * tx) / det,
      (b * tx - a * ty) / det,
    );
  }

  (double, double) apply(double x, double y) =>
      (a * x + c * y + tx, b * x + d * y + ty);

  /// Bounds of 4 transformed corners.
  PageRect applyToRect(PageRect rect) {
    final (x1, y1) = apply(rect.left, rect.top);
    final (x2, y2) = apply(rect.right, rect.top);
    final (x3, y3) = apply(rect.left, rect.bottom);
    final (x4, y4) = apply(rect.right, rect.bottom);
    return PageRect(
      math.min(math.min(x1, x2), math.min(x3, x4)),
      math.min(math.min(y1, y2), math.min(y3, y4)),
      math.max(math.max(x1, x2), math.max(x3, x4)),
      math.max(math.max(y1, y2), math.max(y3, y4)),
    );
  }

  double get determinant => a * d - b * c;
  double get uniformScale => math.sqrt(determinant.abs()); // sqrt(|det|)
  double get rotation => math.atan2(b, a); // atan2(b, a)
  bool get isIdentity =>
      a == 1 && b == 0 && c == 0 && d == 1 && tx == 0 && ty == 0;

  List<double> toJson() => [a, b, c, d, tx, ty]; // [a,b,c,d,tx,ty]

  factory Affine2.fromJson(List<Object?> json) {
    if (json.length != 6) {
      throw FormatException('Affine2 needs 6 numbers, got ${json.length}');
    }
    final v = [for (final e in json) asDouble(e, 'Affine2')];
    return Affine2(v[0], v[1], v[2], v[3], v[4], v[5]);
  }

  @override
  bool operator ==(Object other) =>
      other is Affine2 &&
      other.a == a &&
      other.b == b &&
      other.c == c &&
      other.d == d &&
      other.tx == tx &&
      other.ty == ty;

  @override
  int get hashCode => Object.hash(a, b, c, d, tx, ty);

  @override
  String toString() => 'Affine2($a, $b, $c, $d, $tx, $ty)';
}

// lib/src/common/geometry.dart — (v2.0) added
@immutable
final class PagePoint {
  const PagePoint(this.x, this.y); // pt, page coordinates, y down
  final double x, y;
  PagePoint transformed(Affine2 m) => notYet('T20b', 'PagePoint.transformed');

  // CORE 4.3: ==, hashCode (x, y), toString — no JSON of its own (frames and geometry
  // write arrays)
  @override
  bool operator ==(Object other) =>
      other is PagePoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'PagePoint($x, $y)';
}

/// (v2.0) Rotated box in page pt. [rect] is the UNROTATED box; [rotation] (rad, clockwise
/// on screen because y is down) turns it about rect's center.
@immutable
final class ElementFrame {
  const ElementFrame(this.rect, {this.rotation = 0});

  // (v2.1, CP-4) static const double maxSide = 14400 (= PageSize.maxSide; fromJson rejects
  // larger)
  static const double maxSide = 14400;

  // width, height in [0, 14400] (a straight line's frame may be flat)
  final PageRect rect;
  final double rotation; // normalized to (-pi, pi]
  PagePoint get center => notYet('T20b', 'ElementFrame.center');
  // tl, tr, br, bl after rotation
  List<PagePoint> get corners => notYet('T20b', 'ElementFrame.corners');
  PageRect get bounds =>
      notYet('T20b', 'ElementFrame.bounds'); // AABB of corners

  /// Similarity transforms (move / uniform scale / rotate) are exact: center' = m(center),
  /// width·s, height·s, rotation + m.rotation, s = m.uniformScale. Other transforms are
  /// approximated the same way (EDITOR sends non-uniform resizes as UpdateObjects).
  ElementFrame transformed(Affine2 m) =>
      notYet('T20b', 'ElementFrame.transformed');
  bool contains(PagePoint p, {double tolerance = 0}) =>
      notYet('T20b', 'ElementFrame.contains');
  // [left, top, right, bottom, rotation]
  List<double> toJson() => notYet('T20a', 'ElementFrame.toJson');

  /// FormatException on bad input; (v2.1) never normalizes
  factory ElementFrame.fromJson(List<Object?> json) =>
      notYet('T20a', 'ElementFrame.fromJson');

  /// (contract: maxSide, normalized) width / height clamped to [0, maxSide] around the same
  /// center; rotation folded into (-pi, pi] (so -pi → pi, 3·pi → pi). The const constructor and
  /// fromJson keep the given values.
  ElementFrame normalized() => notYet('T20b', 'ElementFrame.normalized');

  // CORE 4.3: ==, hashCode over the raw (rect, rotation):
  // ElementFrame(r, rotation: -pi) != ElementFrame(r, rotation: pi)
  @override
  bool operator ==(Object other) =>
      other is ElementFrame && other.rect == rect && other.rotation == rotation;

  @override
  int get hashCode => Object.hash(rect, rotation);

  @override
  String toString() => 'ElementFrame($rect, rotation: $rotation)';
}
