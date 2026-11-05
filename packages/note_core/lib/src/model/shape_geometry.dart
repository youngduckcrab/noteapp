// lib/src/model/shape_geometry.dart — (v2.0) 2nd-round contract 7.2.2 / 02-core 4.2, 6.2.2.
// ShapeKind, LineDash, ArrowHeads, ShapeGeometry (sealed) with PolylineGeometry and
// EllipseGeometry, and the shape templates (EDITOR's shape tool and the shape fitter).
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../common/geometry.dart';
import '../common/pending.dart';

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
  factory ShapeGeometry.fromJson(Object? json) =>
      notYet('T20a', 'ShapeGeometry.fromJson');

  // Templates (pure geometry, used by EDITOR's shape tool and the shape fitter):
  static PolylineGeometry line(PagePoint a, PagePoint b) =>
      notYet('T20b', 'ShapeGeometry.line');

  // 4 points, clockwise from top-left
  static PolylineGeometry rectangle(PageRect r, {double rotation = 0}) =>
      notYet('T20b', 'ShapeGeometry.rectangle');
  static EllipseGeometry ellipse(PageRect r, {double rotation = 0}) =>
      notYet('T20b', 'ShapeGeometry.ellipse');

  // isosceles, apex up
  static PolylineGeometry triangle(PageRect r) =>
      notYet('T20b', 'ShapeGeometry.triangle');

  // 3..12
  static PolylineGeometry regularPolygon(
    PageRect r,
    int sides, {
    double rotation = 0,
  }) => notYet('T20b', 'ShapeGeometry.regularPolygon');

  // 2·points vertices
  static PolylineGeometry star(
    PageRect r, {
    int points = 5,
    double innerRatio = 0.5,
  }) => notYet('T20b', 'ShapeGeometry.star');
}

final class PolylineGeometry extends ShapeGeometry {
  const PolylineGeometry(this.points, {required this.closed});
  final List<PagePoint> points; // 2..PageObjectLimits.maxPolylinePoints
  final bool closed;

  @override
  ShapeGeometry transformed(Affine2 m) =>
      notYet('T20b', 'PolylineGeometry.transformed');

  @override
  ElementFrame get frame => notYet('T20b', 'PolylineGeometry.frame');

  @override
  Object toJson() => notYet('T20a', 'PolylineGeometry.toJson');

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

  @override
  ShapeGeometry transformed(Affine2 m) =>
      notYet('T20b', 'EllipseGeometry.transformed');

  @override
  ElementFrame get frame => ellipseFrame;

  @override
  Object toJson() => notYet('T20a', 'EllipseGeometry.toJson');

  // CORE 4.3: ==, hashCode (1차 7.4.4)
  @override
  bool operator ==(Object other) =>
      other is EllipseGeometry && other.ellipseFrame == ellipseFrame;

  @override
  int get hashCode => ellipseFrame.hashCode;

  @override
  String toString() => 'EllipseGeometry($ellipseFrame)';
}
