// lib/src/shapes/shape_classifier.dart — (internal, pure) m5-7/05-library
// 6.17.1: the geometric classifier — the improved E-L2 / E-L3 prototype (7.3,
// lib/shape_fit.dart) moved into the package with every threshold read from
// ShapeFitTuning (4.4.5).
//
//  1. (in GeometricShapeFitter) fewer than 4 points / a non-finite point /
//     bounds diagonal × viewScale < minDiagonalLogicalPx → no shape;
//  2. smoothing: 128 samples by path length → moving average of radius
//     smoothRadius (end points kept) → resampleCount samples;
//  3. line: chord / path ≥ lineMinStraightness and the largest distance to
//     the chord / chord ≤ lineMaxDeviation;
//  4. closed: end gap / path ≤ closedMaxGap and total turning within
//     [minTurnDeg, maxTurnDeg] (a scribble or two turns → no shape);
//  5. ellipse: PCA of the points — a = √(2λ₁), b = √(2λ₂), the angle; error =
//     mean |r − 1| of the normalised radius; b / a ≥ circleMinAxisRatio → a
//     circle;
//  6. corners: RDP (ε = diagonal × rdpEpsilon) on the two halves split at
//     the point farthest from the start, corners turning < cornerMinTurnDeg
//     dropped, corners nearer than minEdgeFraction × perimeter merged;
//     polygon error = mean point–edge distance / diagonal;
//  7. the ellipse wins when its error ≤ ellipseMaxError and (corners < 3, or
//     > 6, or ellipse error × ellipseOverPolygonFactor < polygon error);
//  8. weak corners: 4 corners whose weakest turns < weakCornerTriangleDeg and
//     whose triangle without it fits within weakCornerErrorFactor × → a
//     triangle; 5 corners whose weakest turns < weakCornerQuadDeg, the other
//     four 90° ± rightAngleToleranceDeg, within the factor → a rectangle (a
//     closing hook);
//  9. 3 corners → triangle; 4 → rectangle when every angle is 90° ± the
//     tolerance, else a quadrilateral; 5–8 → a polygon when its error ≤
//     polygonMaxError; otherwise the ellipse when it fits, else nothing.
// Everything is deterministic; no exception for finite input.
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:meta/meta.dart';

import 'shape_fit_tuning.dart';

/// 6.17.1 step 2: samples before the moving average.
const int kShapePreResample = 128;

/// What the classifier found (before the 6.17.2 beautifier).
enum ShapeClass { line, circle, ellipse, triangle, rectangle, quad, polygon }

/// One classification (page pt).
@immutable
final class ShapeClassification {
  const ShapeClassification(
    this.kind, {
    this.vertices = const [],
    this.center = Offset.zero,
    this.rx = 0,
    this.ry = 0,
    this.angle = 0,
    required this.error,
  });

  final ShapeClass kind;

  /// line: its two ends (smoothed); polygons: the corners in path order.
  final List<Offset> vertices;

  /// ellipse / circle: centre, semi-axes (a circle: both (a + b) / 2) and
  /// the angle of the a axis (radians).
  final Offset center;
  final double rx, ry, angle;

  /// The kind's error measure (line: deviation / chord; ellipse: mean
  /// |r − 1|; polygons: mean distance / diagonal).
  final double error;

  @override
  String toString() =>
      'ShapeClassification(${kind.name}, error ${error.toStringAsFixed(4)}, '
      '${vertices.length} vertices)';
}

double _dist(Offset a, Offset b) => (a - b).distance;

/// [n] points evenly spaced along the path of [pts] by length (the first
/// point kept; short paths padded with the last point).
List<Offset> resamplePath(List<Offset> pts, int n) {
  var total = 0.0;
  for (var i = 1; i < pts.length; i++) {
    total += _dist(pts[i], pts[i - 1]);
  }
  if (total == 0) return List.filled(n, pts.first);
  final step = total / (n - 1);
  final out = <Offset>[pts.first];
  var acc = 0.0;
  var prev = pts.first;
  var i = 1;
  while (i < pts.length && out.length < n) {
    final cur = pts[i];
    final d = _dist(prev, cur);
    if (acc + d >= step && d > 0) {
      final t = (step - acc) / d;
      final q = prev + (cur - prev) * t;
      out.add(q);
      prev = q;
      acc = 0;
    } else {
      acc += d;
      prev = cur;
      i++;
    }
  }
  while (out.length < n) {
    out.add(pts.last);
  }
  return out;
}

double _pathLength(List<Offset> p) {
  var l = 0.0;
  for (var i = 1; i < p.length; i++) {
    l += _dist(p[i], p[i - 1]);
  }
  return l;
}

/// Distance from [p] to the segment [a]–[b].
double segmentDistance(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (l2 == 0) return _dist(p, a);
  var t = ((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / l2;
  t = t.clamp(0.0, 1.0);
  return _dist(p, a + ab * t);
}

List<Offset> _rdp(List<Offset> p, double eps) {
  if (p.length < 3) return List.of(p);
  var maxD = 0.0;
  var idx = 0;
  for (var i = 1; i < p.length - 1; i++) {
    final d = segmentDistance(p[i], p.first, p.last);
    if (d > maxD) {
      maxD = d;
      idx = i;
    }
  }
  if (maxD <= eps) return [p.first, p.last];
  final left = _rdp(p.sublist(0, idx + 1), eps);
  final right = _rdp(p.sublist(idx), eps);
  return [...left.sublist(0, left.length - 1), ...right];
}

/// The turn at [b] on the way [a] → [b] → [c], degrees (0 = straight on).
double turnDegrees(Offset a, Offset b, Offset c) {
  final u = b - a, v = c - b;
  final cross = u.dx * v.dy - u.dy * v.dx;
  final dot = u.dx * v.dx + u.dy * v.dy;
  return (math.atan2(cross, dot) * 180 / math.pi).abs();
}

/// 6.17.1 step 6 on a closed [loop].
List<Offset> _corners(List<Offset> loop, double eps, ShapeFitTuning tuning) {
  final p0 = loop.first;
  var far = 0;
  var farD = 0.0;
  for (var i = 0; i < loop.length; i++) {
    final d = _dist(loop[i], p0);
    if (d > farD) {
      farD = d;
      far = i;
    }
  }
  final a = _rdp(loop.sublist(0, far + 1), eps);
  final b = _rdp([...loop.sublist(far), p0], eps);
  final v = [...a.sublist(0, a.length - 1), ...b.sublist(0, b.length - 1)];
  var changed = true;
  while (changed && v.length > 2) {
    changed = false;
    for (var i = 0; i < v.length; i++) {
      final prev = v[(i - 1 + v.length) % v.length];
      final next = v[(i + 1) % v.length];
      if (turnDegrees(prev, v[i], next) < tuning.cornerMinTurnDeg) {
        v.removeAt(i);
        changed = true;
        break;
      }
    }
  }
  // Corners too close together (a closing overshoot / hook).
  changed = true;
  while (changed && v.length > 3) {
    changed = false;
    var per = 0.0;
    for (var i = 0; i < v.length; i++) {
      per += _dist(v[i], v[(i + 1) % v.length]);
    }
    for (var i = 0; i < v.length; i++) {
      final j = (i + 1) % v.length;
      if (_dist(v[i], v[j]) < tuning.minEdgeFraction * per) {
        // drop the one that turns less
        final ti = turnDegrees(v[(i - 1 + v.length) % v.length], v[i], v[j]);
        final tj = turnDegrees(v[i], v[j], v[(j + 1) % v.length]);
        v.removeAt(ti < tj ? i : j);
        changed = true;
        break;
      }
    }
  }
  return v;
}

double _polygonError(List<Offset> pts, List<Offset> poly, double diag) {
  var s = 0.0;
  for (final p in pts) {
    var best = double.infinity;
    for (var i = 0; i < poly.length; i++) {
      best = math.min(
        best,
        segmentDistance(p, poly[i], poly[(i + 1) % poly.length]),
      );
    }
    s += best;
  }
  return s / pts.length / diag;
}

ShapeClassification _fitEllipse(List<Offset> pts, ShapeFitTuning tuning) {
  var cx = 0.0, cy = 0.0;
  for (final p in pts) {
    cx += p.dx;
    cy += p.dy;
  }
  cx /= pts.length;
  cy /= pts.length;
  var sxx = 0.0, syy = 0.0, sxy = 0.0;
  for (final p in pts) {
    final dx = p.dx - cx, dy = p.dy - cy;
    sxx += dx * dx;
    syy += dy * dy;
    sxy += dx * dy;
  }
  sxx /= pts.length;
  syy /= pts.length;
  sxy /= pts.length;
  final tr = sxx + syy;
  final det = sxx * syy - sxy * sxy;
  final disc = math.sqrt(math.max(0, tr * tr / 4 - det));
  final l1 = tr / 2 + disc, l2 = math.max(1e-9, tr / 2 - disc);
  final ang = 0.5 * math.atan2(2 * sxy, sxx - syy);
  // Points spread evenly along an ellipse: variance ≈ a² / 2.
  final a = math.sqrt(2 * l1), b = math.sqrt(2 * l2);
  final c = math.cos(ang), s = math.sin(ang);
  var err = 0.0;
  for (final p in pts) {
    final dx = p.dx - cx, dy = p.dy - cy;
    final u = dx * c + dy * s, v = -dx * s + dy * c;
    err += (math.sqrt((u / a) * (u / a) + (v / b) * (v / b)) - 1).abs();
  }
  err /= pts.length;
  final circle = b / a >= tuning.circleMinAxisRatio;
  return ShapeClassification(
    circle ? ShapeClass.circle : ShapeClass.ellipse,
    center: Offset(cx, cy),
    rx: circle ? (a + b) / 2 : a,
    ry: circle ? (a + b) / 2 : b,
    angle: ang,
    error: err,
  );
}

List<Offset> _smooth(List<Offset> p, int k) {
  final out = <Offset>[];
  for (var i = 0; i < p.length; i++) {
    final a = math.max(0, i - k), b = math.min(p.length - 1, i + k);
    var x = 0.0, y = 0.0;
    for (var j = a; j <= b; j++) {
      x += p[j].dx;
      y += p[j].dy;
    }
    final n = b - a + 1;
    out.add(Offset(x / n, y / n));
  }
  out[0] = p.first;
  out[out.length - 1] = p.last;
  return out;
}

/// (L2-06 addition) Each corner moved to the loop point between its two
/// neighbouring corners that lies farthest from their chord (two passes).
/// The split at the point farthest from the start forces a corner there;
/// on a tall rectangle that starts in the middle of a short side the
/// farthest point is on the far short side ~13 pt beside the rounded corner
/// (the distance barely falls along that side), and the quad misses the
/// right-angle test. Corners stay in path order; null when a corner is not a
/// loop point.
List<Offset>? _reseatCorners(List<Offset> loop, List<Offset> corners) {
  final n = loop.length;
  final idx = [for (final c in corners) loop.indexOf(c)];
  if (idx.any((i) => i < 0)) return null;
  for (var pass = 0; pass < 2; pass++) {
    for (var k = 0; k < idx.length; k++) {
      final a = idx[(k - 1 + idx.length) % idx.length];
      final b = idx[(k + 1) % idx.length];
      var best = idx[k];
      var bestD = -1.0;
      for (var j = (a + 1) % n; j != b; j = (j + 1) % n) {
        final d = segmentDistance(loop[j], loop[a], loop[b]);
        if (d > bestD) {
          bestD = d;
          best = j;
        }
      }
      idx[k] = best;
    }
  }
  return [for (final i in idx) loop[i]];
}

bool _rightAngles(List<Offset> quad, ShapeFitTuning tuning) {
  for (var i = 0; i < 4; i++) {
    final t = turnDegrees(quad[(i + 3) % 4], quad[i], quad[(i + 1) % 4]);
    if ((t - 90).abs() > tuning.rightAngleToleranceDeg) return false;
  }
  return true;
}

/// 6.17.1 steps 2–9 for [raw] (≥ 4 finite points); null = stays ink.
ShapeClassification? classifyShape(
  List<Offset> raw, {
  ShapeFitTuning tuning = const ShapeFitTuning(),
}) {
  if (raw.length < 4) return null;
  final pts = resamplePath(
    _smooth(resamplePath(raw, kShapePreResample), tuning.smoothRadius),
    tuning.resampleCount,
  );
  final len = _pathLength(pts);
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final p in pts) {
    minX = math.min(minX, p.dx);
    minY = math.min(minY, p.dy);
    maxX = math.max(maxX, p.dx);
    maxY = math.max(maxY, p.dy);
  }
  final diag = Offset(maxX - minX, maxY - minY).distance;
  if (!(diag > 0) || !(len > 0)) return null;

  // 3. A straight line.
  final chord = _dist(pts.first, pts.last);
  if (chord / len >= tuning.lineMinStraightness) {
    var maxDev = 0.0;
    for (final p in pts) {
      maxDev = math.max(maxDev, segmentDistance(p, pts.first, pts.last));
    }
    if (maxDev / chord <= tuning.lineMaxDeviation) {
      return ShapeClassification(
        ShapeClass.line,
        vertices: [pts.first, pts.last],
        error: maxDev / chord,
      );
    }
  }

  // 4. Closed outlines only: total turning near ±360°.
  if (chord / len > tuning.closedMaxGap) return null;
  final loop = pts.sublist(0, pts.length - 1);
  var turning = 0.0;
  for (var i = 1; i < loop.length - 1; i++) {
    final u = loop[i] - loop[i - 1], w = loop[i + 1] - loop[i];
    turning += math.atan2(u.dx * w.dy - u.dy * w.dx, u.dx * w.dx + u.dy * w.dy);
  }
  final turnDeg = (turning * 180 / math.pi).abs();
  if (turnDeg < tuning.minTurnDeg || turnDeg > tuning.maxTurnDeg) return null;

  // 5–7. Ellipse against the corner outline.
  final ellipse = _fitEllipse(loop, tuning);
  final corners = _corners(loop, tuning.rdpEpsilon * diag, tuning);
  final polyErr = corners.length >= 3
      ? _polygonError(loop, corners, diag)
      : double.infinity;
  final ellipseFits = ellipse.error <= tuning.ellipseMaxError;
  if (ellipseFits &&
      (corners.length < 3 ||
          corners.length > 6 ||
          ellipse.error * tuning.ellipseOverPolygonFactor < polyErr)) {
    return ellipse;
  }

  // 8. Weak corners: a triangle with an overshoot hook…
  if (corners.length == 4) {
    var weakest = -1;
    var weakTurn = double.infinity;
    for (var i = 0; i < 4; i++) {
      final t = turnDegrees(
        corners[(i + 3) % 4],
        corners[i],
        corners[(i + 1) % 4],
      );
      if (t < weakTurn) {
        weakTurn = t;
        weakest = i;
      }
    }
    final tri = [
      for (var i = 0; i < 4; i++)
        if (i != weakest) corners[i],
    ];
    final triErr = _polygonError(loop, tri, diag);
    if (weakTurn < tuning.weakCornerTriangleDeg &&
        triErr <= polyErr * tuning.weakCornerErrorFactor) {
      return ShapeClassification(
        ShapeClass.triangle,
        vertices: tri,
        error: triErr,
      );
    }
  }
  // … and a quadrilateral with a closing hook.
  if (corners.length == 5) {
    var weakest = -1;
    var weakTurn = double.infinity;
    for (var i = 0; i < 5; i++) {
      final t = turnDegrees(
        corners[(i + 4) % 5],
        corners[i],
        corners[(i + 1) % 5],
      );
      if (t < weakTurn) {
        weakTurn = t;
        weakest = i;
      }
    }
    final quad = [
      for (var i = 0; i < 5; i++)
        if (i != weakest) corners[i],
    ];
    final quadErr = _polygonError(loop, quad, diag);
    if (_rightAngles(quad, tuning) &&
        weakTurn < tuning.weakCornerQuadDeg &&
        quadErr <= polyErr * tuning.weakCornerErrorFactor) {
      return ShapeClassification(
        ShapeClass.rectangle,
        vertices: quad,
        error: quadErr,
      );
    }
  }

  // 9. By the number of corners.
  switch (corners.length) {
    case 3:
      return ShapeClassification(
        ShapeClass.triangle,
        vertices: corners,
        error: polyErr,
      );
    case 4:
      if (_rightAngles(corners, tuning)) {
        return ShapeClassification(
          ShapeClass.rectangle,
          vertices: corners,
          error: polyErr,
        );
      }
      // (L2-06) Not square as found: the corners moved onto the outline's
      // corners, then the right-angle test once more.
      final reseated = _reseatCorners(loop, corners);
      if (reseated != null && _rightAngles(reseated, tuning)) {
        return ShapeClassification(
          ShapeClass.rectangle,
          vertices: reseated,
          error: _polygonError(loop, reseated, diag),
        );
      }
      return ShapeClassification(
        ShapeClass.quad,
        vertices: corners,
        error: polyErr,
      );
    case 5 || 6 || 7 || 8:
      if (polyErr > tuning.polygonMaxError) return null;
      return ShapeClassification(
        ShapeClass.polygon,
        vertices: corners,
        error: polyErr,
      );
    default:
      return ellipseFits ? ellipse : null;
  }
}
