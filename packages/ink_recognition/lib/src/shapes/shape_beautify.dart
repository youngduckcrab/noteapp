// lib/src/shapes/shape_beautify.dart — (internal, pure) m5-7/05-library
// 6.17.2: a classification → the straightened CORE geometry INK draws.
//
//   line       → ShapeKind.line, both ends of the RAW stroke turned about
//                their middle to SelectionGeometry.snapAngle (15°, ±3°)
//   circle     → ShapeKind.ellipse, a square frame (radius (a + b) / 2),
//                rotation 0
//   ellipse    → ShapeKind.ellipse, centre · a · b · angle; within ±axisSnapDeg
//                of an axis → that axis. Centre, a and b: the classifier's
//                least-squares fit (6.17.1 step 5 — on the closed loop, so a
//                closing overlap or the hold tail does not pull them)
//   rectangle  → ShapeKind.rectangle, the direction of the longest edge
//                (within ±axisSnapDeg of an axis → the axis); each side =
//                the median perpendicular coordinate of the RAW points in the
//                middle 70 % of that side (< 2 points → the corner bounds) —
//                the corners alone sit up to a resample step inside (E-L8)
//   triangle   → ShapeKind.triangle, the 3 corners clockwise
//   quad / 5–8 → ShapeKind.polygon, the corners clockwise
//                (review fixes) triangle and polygon corners put back under
//                the pen: where the least-squares lines of the RAW points in
//                the middle 70 % of their two edges meet
//                (refinePolygonCorners)
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
    geometry: _ellipse(c, tuning),
    score: _score(c.error, tuning.ellipseMaxError),
  ),
  ShapeClass.rectangle => ink.InkShapeFit(
    kind: core.ShapeKind.rectangle,
    geometry: _rectangle(c.vertices, raw, tuning),
    score: _score(c.error, tuning.polygonMaxError),
  ),
  ShapeClass.triangle => ink.InkShapeFit(
    kind: core.ShapeKind.triangle,
    geometry: _polyline(refinePolygonCorners(c.vertices, raw)),
    score: _score(c.error, tuning.polygonMaxError),
  ),
  ShapeClass.quad || ShapeClass.polygon => ink.InkShapeFit(
    kind: core.ShapeKind.polygon,
    geometry: _polyline(refinePolygonCorners(c.vertices, raw)),
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

core.ShapeGeometry _ellipse(ShapeClassification c, ShapeFitTuning tuning) {
  final center = c.center;
  if (c.kind == ShapeClass.circle) {
    final r = c.rx;
    return core.ShapeGeometry.ellipse(
      core.PageRect(center.dx - r, center.dy - r, center.dx + r, center.dy + r),
    );
  }
  // The a axis turned into (−45°, 45°]: an odd number of quarter turns
  // puts the b axis along the frame's width.
  final (normalized, quarters) = _quarterNormalized(c.angle);
  final (rx, ry) = quarters.isOdd ? (c.ry, c.rx) : (c.rx, c.ry);
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

/// (review fixes) The corners of a triangle or polygon put back under the
/// pen: each edge becomes the least-squares line through the RAW points in
/// its middle 70 % (kRectangleSideEndCut at each end), and each corner the
/// point where the lines of its two edges meet. The classifier's corners
/// come from the smoothed 64-point loop, which cuts every corner — a sharp
/// triangle snapped about 4 % smaller than drawn (8 pt median, up to 30 pt;
/// 14 pt on the 330 pt one in shape_fitter_test).
/// A corner whose edge has fewer than 2 points, whose edges are (nearly)
/// parallel, or that would move more than kCornerRefineMaxMove × the shorter
/// of its edges stays where it was.
List<Offset> refinePolygonCorners(List<Offset> corners, List<Offset> raw) {
  final n = corners.length;
  if (n < 3) return corners;
  final bins = List.generate(n, (_) => <Offset>[]);
  for (final p in raw) {
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < n; i++) {
      final d = segmentDistance(p, corners[i], corners[(i + 1) % n]);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    final a = corners[best], d = corners[(best + 1) % n] - a;
    final l2 = d.dx * d.dx + d.dy * d.dy;
    if (l2 == 0) continue;
    final t = ((p.dx - a.dx) * d.dx + (p.dy - a.dy) * d.dy) / l2;
    if (t < kRectangleSideEndCut || t > 1 - kRectangleSideEndCut) continue;
    bins[best].add(p);
  }
  // Edge i (corners[i] → corners[i + 1]) as a point and a direction.
  final lines = <(Offset, Offset)?>[
    for (var i = 0; i < n; i++) _lineFit(bins[i]),
  ];
  return [
    for (var i = 0; i < n; i++)
      () {
        final before = lines[(i - 1 + n) % n], after = lines[i];
        if (before == null || after == null) return corners[i];
        final x = _meet(before, after);
        final limit =
            kCornerRefineMaxMove *
            math.min(
              (corners[i] - corners[(i - 1 + n) % n]).distance,
              (corners[(i + 1) % n] - corners[i]).distance,
            );
        return x != null && (x - corners[i]).distance <= limit ? x : corners[i];
      }(),
  ];
}

/// 6.17.2 polygons: how far a corner may move (× its shorter edge).
const double kCornerRefineMaxMove = 0.25;

/// The total-least-squares line through [pts]: (centroid, unit direction);
/// null for fewer than 2 points or no spread.
(Offset, Offset)? _lineFit(List<Offset> pts) {
  if (pts.length < 2) return null;
  var cx = 0.0, cy = 0.0;
  for (final p in pts) {
    cx += p.dx / pts.length;
    cy += p.dy / pts.length;
  }
  var sxx = 0.0, syy = 0.0, sxy = 0.0;
  for (final p in pts) {
    final dx = p.dx - cx, dy = p.dy - cy;
    sxx += dx * dx;
    syy += dy * dy;
    sxy += dx * dy;
  }
  if (!(sxx + syy > 0)) return null;
  final ang = 0.5 * math.atan2(2 * sxy, sxx - syy);
  return (Offset(cx, cy), Offset(math.cos(ang), math.sin(ang)));
}

/// Where two lines (point, unit direction) meet; null when nearly parallel
/// (under ~6°).
Offset? _meet((Offset, Offset) a, (Offset, Offset) b) {
  final (p, r) = a;
  final (q, s) = b;
  final den = r.dx * s.dy - r.dy * s.dx;
  if (den.abs() < 0.1) return null;
  final t = ((q.dx - p.dx) * s.dy - (q.dy - p.dy) * s.dx) / den;
  final x = p + r * t;
  return x.dx.isFinite && x.dy.isFinite ? x : null;
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
