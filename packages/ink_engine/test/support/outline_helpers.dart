// Helpers for the outline tests (T07): raw point builders and polygon maths.
// Shared by test/unit (VM) and test/web (the Chrome wrappers).
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/src/geometry/stroke_outline.dart';
import 'package:ink_engine/src/model/ink_points.dart';
import 'package:ink_engine/src/pen/pen_profile.dart';

/// InkPoints from (x, y) positions with one widthQ (tilt, azimuth, t = 0).
InkPoints pointsOf(List<ui.Offset> xy, {double widthQ = 0.25}) {
  final raw = Float32List(xy.length * InkPoints.stride);
  for (var i = 0; i < xy.length; i++) {
    raw[i * InkPoints.stride] = xy[i].dx;
    raw[i * InkPoints.stride + 1] = xy[i].dy;
    raw[i * InkPoints.stride + 2] = widthQ;
  }
  return InkPoints.fromRaw(raw);
}

/// Points every [step] pt along [f] for u in [0, 1] (both ends included).
List<ui.Offset> sampleCurve(
  ui.Offset Function(double u) f, {
  required double length,
  double step = 1,
}) {
  final n = math.max(2, (length / step).ceil() + 1);
  return [for (var i = 0; i < n; i++) f(i / (n - 1))];
}

/// Outline of [xy] for a fill pen (ballpoint profile).
StrokeOutline outlineFor(
  List<ui.Offset> xy, {
  double width = 4,
  double widthQ = 0.25,
  PenProfile profile = PenProfile.ballpoint,
  OutlineOptions options = const OutlineOptions(),
}) => OutlineGenerator.outlineOf(
  pointsOf(xy, widthQ: widthQ),
  width: width,
  profile: profile,
  options: options,
);

/// Shoelace area (positive in the 6.8 O7 orientation).
double polygonArea(Float32List poly) => OutlineGenerator.signedArea(poly);

/// Winding number of the polygons around (px, py) (crossing count, signed).
int windingNumber(List<Float32List> polygons, double px, double py) {
  var w = 0;
  for (final poly in polygons) {
    final m = poly.length ~/ 2;
    for (var i = 0; i < m; i++) {
      final j = i + 1 == m ? 0 : i + 1;
      final x0 = poly[2 * i], y0 = poly[2 * i + 1];
      final x1 = poly[2 * j], y1 = poly[2 * j + 1];
      final cross = (x1 - x0) * (py - y0) - (px - x0) * (y1 - y0);
      if (y0 <= py) {
        if (y1 > py && cross > 0) w++;
      } else {
        if (y1 <= py && cross < 0) w--;
      }
    }
  }
  return w;
}

/// Distance of (px, py) to the polyline [xy].
double distanceToPolyline(List<ui.Offset> xy, double px, double py) {
  var best = double.infinity;
  for (var i = 0; i + 1 < xy.length; i++) {
    final a = xy[i], b = xy[i + 1];
    final dx = b.dx - a.dx, dy = b.dy - a.dy;
    final len2 = dx * dx + dy * dy;
    var u = len2 > 0 ? ((px - a.dx) * dx + (py - a.dy) * dy) / len2 : 0.0;
    u = u.clamp(0.0, 1.0);
    final ex = px - (a.dx + u * dx), ey = py - (a.dy + u * dy);
    best = math.min(best, math.sqrt(ex * ex + ey * ey));
  }
  if (xy.length == 1) {
    best = (ui.Offset(px, py) - xy.first).distance;
  }
  return best;
}

/// Every coordinate of the outline is finite (no NaN / infinity).
bool outlineIsFinite(StrokeOutline o) {
  for (final p in o.polygons) {
    for (final v in p) {
      if (!v.isFinite) return false;
    }
  }
  final b = o.bounds;
  return b.left.isFinite &&
      b.top.isFinite &&
      b.right.isFinite &&
      b.bottom.isFinite &&
      o.dotRadius.isFinite;
}
