// lib/src/shapes/shape_beautify.dart — (internal, pure) m5-7/05-library
// 6.17.2: a classification → the straightened CORE geometry INK draws.
//
//   line       → ShapeKind.line, both ends of the RAW stroke turned about
//                their middle to SelectionGeometry.snapAngle (15°, ±3°)
//   circle     → ShapeKind.ellipse, a square frame (radius (a + b) / 2),
//                rotation 0
//   ellipse    → ShapeKind.ellipse, centre · a · b · angle; within ±axisSnapDeg
//                of an axis → that axis. a and b: a least-squares fit of the
//                raw points along the classifier's axes (its √(2λ) values
//                assume points spread by angle — a 2:1 ellipse came out 9 %
//                narrow); the classifier's values when that fit degenerates
//   rectangle  → ShapeKind.rectangle, the direction of the longest edge
//                (within ±axisSnapDeg of an axis → the axis); each side =
//                the median perpendicular coordinate of the RAW points in the
//                middle 70 % of that side (< 2 points → the corner bounds) —
//                the corners alone sit up to a resample step inside (E-L8)
//   triangle   → ShapeKind.triangle, the 3 corners clockwise
//   quad / 5–8 → ShapeKind.polygon, the corners clockwise
// score = clamp(1 − error ÷ the kind's threshold, 0, 1).
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import 'shape_classifier.dart';
import 'shape_fit_tuning.dart';

/// 6.17.2 rectangle sides: the share cut at each end of a side.
const double kRectangleSideEndCut = 0.15;

/// [c] as an InkShapeFit; [raw] = the stroke's points (page pt).
ink.InkShapeFit beautifyShape(
  ShapeClassification c,
  List<Offset> raw,
  ShapeFitTuning tuning,
) => switch (c.kind) {
  ShapeClass.line => ink.InkShapeFit(
    kind: core.ShapeKind.line,
    geometry: _line(raw),
    score: _score(c.error, tuning.lineMaxDeviation),
  ),
  ShapeClass.circle || ShapeClass.ellipse => ink.InkShapeFit(
    kind: core.ShapeKind.ellipse,
    geometry: _ellipse(c, raw, tuning),
    score: _score(c.error, tuning.ellipseMaxError),
  ),
  ShapeClass.rectangle => ink.InkShapeFit(
    kind: core.ShapeKind.rectangle,
    geometry: _rectangle(c.vertices, raw, tuning),
    score: _score(c.error, tuning.polygonMaxError),
  ),
  ShapeClass.triangle => ink.InkShapeFit(
    kind: core.ShapeKind.triangle,
    geometry: _polyline(c.vertices),
    score: _score(c.error, tuning.polygonMaxError),
  ),
  ShapeClass.quad || ShapeClass.polygon => ink.InkShapeFit(
    kind: core.ShapeKind.polygon,
    geometry: _polyline(c.vertices),
    score: _score(c.error, tuning.polygonMaxError),
  ),
};

double _score(double error, double threshold) =>
    threshold > 0 ? (1 - error / threshold).clamp(0.0, 1.0) : 0.0;

core.PagePoint _pagePoint(Offset p) => core.PagePoint(p.dx, p.dy);

/// [radians] within ±[snapDeg] of a multiple of 90° → that multiple.
double _snapToAxis(double radians, double snapDeg) {
  const quarter = math.pi / 2;
  final nearest = (radians / quarter).roundToDouble() * quarter;
  return (radians - nearest).abs() <= snapDeg * math.pi / 180
      ? nearest
      : radians;
}

/// [radians] in (−π/4, π/4] by quarter turns, and how many were taken.
(double, int) _quarterNormalized(double radians) {
  const quarter = math.pi / 2;
  var k = (radians / quarter).roundToDouble();
  var a = radians - k * quarter;
  if (a <= -math.pi / 4) {
    a += quarter;
    k -= 1;
  }
  return (a, k.toInt());
}

core.ShapeGeometry _line(List<Offset> raw) {
  final a = raw.first, b = raw.last;
  final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
  final half = (b - a).distance / 2;
  final angle = ink.SelectionGeometry.snapAngle(
    math.atan2(b.dy - a.dy, b.dx - a.dx),
  );
  final d = Offset(math.cos(angle), math.sin(angle)) * half;
  return core.ShapeGeometry.line(_pagePoint(mid - d), _pagePoint(mid + d));
}

/// The semi-axes along [angle] about [center] that fit [raw] best:
/// least squares of A·u² + B·v² = 1 (A = 1/a², B = 1/b²) — the curve, not
/// the point spread (the classifier's √(2λ) assumes points evenly spread by
/// angle; points spread by path length make a 2:1 ellipse ~9 % too narrow).
/// null when the fit is degenerate.
(double, double)? _leastSquaresAxes(
  List<Offset> raw,
  Offset center,
  double angle,
) {
  final c = math.cos(angle), s = math.sin(angle);
  var suu = 0.0, svv = 0.0, su4 = 0.0, sv4 = 0.0, su2v2 = 0.0;
  for (final p in raw) {
    final dx = p.dx - center.dx, dy = p.dy - center.dy;
    final u2 = math.pow(dx * c + dy * s, 2).toDouble();
    final v2 = math.pow(-dx * s + dy * c, 2).toDouble();
    suu += u2;
    svv += v2;
    su4 += u2 * u2;
    sv4 += v2 * v2;
    su2v2 += u2 * v2;
  }
  final det = su4 * sv4 - su2v2 * su2v2;
  if (!(det.abs() > 0)) return null;
  final a = (suu * sv4 - svv * su2v2) / det;
  final b = (svv * su4 - suu * su2v2) / det;
  if (!(a > 0) || !(b > 0)) return null;
  final rx = 1 / math.sqrt(a), ry = 1 / math.sqrt(b);
  return rx.isFinite && ry.isFinite ? (rx, ry) : null;
}

core.ShapeGeometry _ellipse(
  ShapeClassification c,
  List<Offset> raw,
  ShapeFitTuning tuning,
) {
  final center = c.center;
  final axes = _leastSquaresAxes(raw, center, c.angle);
  if (c.kind == ShapeClass.circle) {
    final r = axes == null ? c.rx : (axes.$1 + axes.$2) / 2;
    return core.ShapeGeometry.ellipse(
      core.PageRect(center.dx - r, center.dy - r, center.dx + r, center.dy + r),
    );
  }
  // The a axis turned into (−45°, 45°]: an odd number of quarter turns
  // puts the b axis along the frame's width.
  final (normalized, quarters) = _quarterNormalized(c.angle);
  final (a, b) = axes ?? (c.rx, c.ry);
  final (rx, ry) = quarters.isOdd ? (b, a) : (a, b);
  final angle = _snapToAxis(normalized, tuning.axisSnapDeg);
  return core.ShapeGeometry.ellipse(
    core.PageRect(
      center.dx - rx,
      center.dy - ry,
      center.dx + rx,
      center.dy + ry,
    ),
    rotation: angle == 0 ? 0.0 : angle, // never -0.0
  );
}

Offset _rotate(Offset p, Offset about, double radians) {
  final c = math.cos(radians), s = math.sin(radians);
  final d = p - about;
  return Offset(about.dx + c * d.dx - s * d.dy, about.dy + s * d.dx + c * d.dy);
}

double _median(List<double> v) {
  v.sort();
  return v[v.length ~/ 2];
}

/// 6.17.2 rectangle: direction from the longest edge, then side refinement
/// on the raw points in the rectangle's own frame.
core.ShapeGeometry _rectangle(
  List<Offset> corners,
  List<Offset> raw,
  ShapeFitTuning tuning,
) {
  var longest = 0.0;
  var direction = 0.0;
  for (var i = 0; i < 4; i++) {
    final d = corners[(i + 1) % 4] - corners[i];
    if (d.distance > longest) {
      longest = d.distance;
      direction = math.atan2(d.dy, d.dx);
    }
  }
  final (normalized, _) = _quarterNormalized(direction);
  final snapped = _snapToAxis(normalized, tuning.axisSnapDeg);
  final angle = snapped == 0 ? 0.0 : snapped; // never -0.0
  final pivot = Offset(
    corners.map((p) => p.dx).reduce((a, b) => a + b) / 4,
    corners.map((p) => p.dy).reduce((a, b) => a + b) / 4,
  );
  // Into the rectangle's frame (axis aligned there).
  final c = [for (final p in corners) _rotate(p, pivot, -angle)];
  final pts = angle == 0
      ? raw
      : [for (final p in raw) _rotate(p, pivot, -angle)];
  var left = c.map((p) => p.dx).reduce(math.min);
  var right = c.map((p) => p.dx).reduce(math.max);
  var top = c.map((p) => p.dy).reduce(math.min);
  var bottom = c.map((p) => p.dy).reduce(math.max);
  final bins = List.generate(4, (_) => <double>[]);
  for (final p in pts) {
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < 4; i++) {
      final d = segmentDistance(p, c[i], c[(i + 1) % 4]);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    final a = c[best], d = c[(best + 1) % 4] - a;
    final l2 = d.dx * d.dx + d.dy * d.dy;
    if (l2 == 0) continue;
    final t = ((p.dx - a.dx) * d.dx + (p.dy - a.dy) * d.dy) / l2;
    if (t < kRectangleSideEndCut || t > 1 - kRectangleSideEndCut) continue;
    bins[best].add(d.dx.abs() > d.dy.abs() ? p.dy : p.dx);
  }
  final cx = c.map((p) => p.dx).reduce((a, b) => a + b) / 4;
  final cy = c.map((p) => p.dy).reduce((a, b) => a + b) / 4;
  for (var i = 0; i < 4; i++) {
    if (bins[i].length < 2) continue;
    final a = c[i], b = c[(i + 1) % 4];
    final v = _median(bins[i]);
    if ((b.dx - a.dx).abs() > (b.dy - a.dy).abs()) {
      if ((a.dy + b.dy) / 2 < cy) {
        top = v;
      } else {
        bottom = v;
      }
    } else if ((a.dx + b.dx) / 2 < cx) {
      left = v;
    } else {
      right = v;
    }
  }
  if (right < left) (left, right) = (right, left);
  if (bottom < top) (top, bottom) = (bottom, top);
  // Back to the page: the refined box's centre turns about the pivot.
  final center = _rotate(
    Offset((left + right) / 2, (top + bottom) / 2),
    pivot,
    angle,
  );
  final w = right - left, h = bottom - top;
  return core.ShapeGeometry.rectangle(
    core.PageRect(
      center.dx - w / 2,
      center.dy - h / 2,
      center.dx + w / 2,
      center.dy + h / 2,
    ),
    rotation: angle,
  );
}

/// The corners in path order made clockwise (y down: a positive shoelace
/// area), from the topmost one (then the leftmost). The path order is kept
/// (not sorted by angle) so a concave outline keeps its edges.
core.ShapeGeometry _polyline(List<Offset> vertices) {
  var area = 0.0;
  for (var i = 0; i < vertices.length; i++) {
    final p = vertices[i], q = vertices[(i + 1) % vertices.length];
    area += p.dx * q.dy - q.dx * p.dy;
  }
  final sorted = area < 0 ? vertices.reversed.toList() : vertices;
  var start = 0;
  for (var i = 1; i < sorted.length; i++) {
    final p = sorted[i], q = sorted[start];
    if (p.dy < q.dy || (p.dy == q.dy && p.dx < q.dx)) start = i;
  }
  return core.PolylineGeometry(
    List.unmodifiable([
      for (var i = 0; i < sorted.length; i++)
        _pagePoint(sorted[(start + i) % sorted.length]),
    ]),
    closed: true,
  );
}
