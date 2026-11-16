// lib/src/shapes/shape_classifier.dart — (internal, pure) m5-7/05-library
// 6.17.1: the geometric classifier — the improved E-L2 / E-L3 prototype (7.3,
// lib/shape_fit.dart) moved into the package with every threshold read from
// ShapeFitTuning (4.4.5).
//
//  1. (in GeometricShapeFitter) fewer than 4 points / a non-finite point /
//     bounds diagonal × viewScale < minDiagonalLogicalPx → no shape; (6.17.5)
//     the hold tail cut (trimHoldTail — holdTailLogicalPx; no shape → once
//     more with holdTailRetryLogicalPx);
//  2. smoothing: 128 samples by path length → moving average of radius
//     smoothRadius (end points kept) → resampleCount samples;
//  3. line: chord / path ≥ lineMinStraightness and the largest distance to
//     the chord / chord ≤ lineMaxDeviation;
//  4. closed: the open path turns at most maxTurnDeg (two laps → no shape);
//     (6.17.5) the outline cut where it closes (_closure: an overshoot, a
//     crossing hook, a start hook), then gap / kept path ≤ closedMaxGap, the
//     CLOSED loop's total turning within [minTurnDeg, maxTurnDeg] and its
//     Σ|turn| ≤ maxAbsTurnDeg (a scribble, a letter's bowl with its stem);
//     the loop resampled to resampleCount points;
//  5. ellipse: PCA centre and axis, then (6.17.5) a least-squares fit of the
//     axes and a centre shift; error = mean point–ellipse distance ÷ mean
//     semi-axis; b / a ≥ circleMinAxisRatio → a circle;
//  6. corners: RDP (ε = diagonal × rdpEpsilon) on the two halves split at
//     the point farthest from the start, corners turning < cornerMinTurnDeg
//     dropped, corners nearer than minEdgeFraction × perimeter merged;
//     polygon error = mean point–edge distance / diagonal;
//  7. the ellipse wins when its error ≤ ellipseMaxError and (corners < 3, or
//     > 6, or ellipse error × ellipseOverPolygonFactor < polygon error);
//  8. weak corners: 4 corners whose weakest turns < weakCornerTriangleDeg and
//     whose triangle without it fits within weakCornerErrorFactor × → a
//     triangle; (6.17.5) 4 corners, not a rectangle, one edge ≤
//     roundedCornerMaxEdge × perimeter whose ends merged into one corner fit
//     within the factor → a triangle (a rounded corner found twice); 5
//     corners whose weakest turns < weakCornerQuadDeg, the other four 90° ±
//     rightAngleToleranceDeg, within the factor → a rectangle (a closing
//     hook);
//  9. 3 corners → triangle; 4 → rectangle when every angle is 90° ± the
//     tolerance, else a quadrilateral; 5–8 → a polygon when its error ≤
//     polygonMaxError; otherwise the ellipse when it fits, else nothing;
// 10. (review fixes) a closed outline that is not a rectangle and whose
//     box is thin (short ÷ long ≤ thinBoxMaxAspect) with two flat ends and
//     straight long sides on the raw points → a rectangle (thinBox).
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
  /// distance / mean semi-axis; polygons: mean distance / diagonal).
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

/// (review fixes) [raw] as a thin box, or null. In the PCA frame of [raw]
/// resampled to kThinBoxSamples by length (no smoothing), with the 2nd and
/// 98th percentiles as the box (a closing flick or the hold do not stretch
/// it): short ÷ long ≤ thinBoxMaxAspect; at each end the points within
/// 0.2 × the short side of it span ≥ thinBoxMinEndCover of the short side
/// (a flat end — an ellipse's round end spans ≲ 0.45); and every point in
/// the middle 70 % of the long side lies within 0.25 × the short side of the
/// top or the bottom (two straight sides, not a lens or a zigzag). The
/// corners are the box's.
ShapeClassification? thinBox(List<Offset> raw, ShapeFitTuning tuning) {
  final pts = resamplePath(raw, kThinBoxSamples);
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
  final ang = 0.5 * math.atan2(2 * sxy, sxx - syy);
  final c = math.cos(ang), s = math.sin(ang);
  final us = <double>[], vs = <double>[];
  for (final p in pts) {
    final dx = p.dx - cx, dy = p.dy - cy;
    us.add(dx * c + dy * s);
    vs.add(-dx * s + dy * c);
  }
  // Most outlines are far from thin: out before any sorting.
  var uMin = double.infinity, uMax = -double.infinity;
  var vMin = double.infinity, vMax = -double.infinity;
  for (var i = 0; i < us.length; i++) {
    uMin = math.min(uMin, us[i]);
    uMax = math.max(uMax, us[i]);
    vMin = math.min(vMin, vs[i]);
    vMax = math.max(vMax, vs[i]);
  }
  if (!(uMax > uMin) ||
      (vMax - vMin) / (uMax - uMin) > 2 * tuning.thinBoxMaxAspect) {
    return null;
  }
  final su = [...us]..sort(), sv = [...vs]..sort();
  double pct(List<double> sorted, double q) =>
      sorted[((sorted.length - 1) * q).round()];

  final u0 = pct(su, 0.02), u1 = pct(su, 0.98);
  final v0 = pct(sv, 0.02), v1 = pct(sv, 0.98);
  final long = u1 - u0, short = v1 - v0;
  if (!(short > 0) || !(long > 0) || short / long > tuning.thinBoxMaxAspect) {
    return null;
  }
  for (final end in [u0, u1]) {
    var lo = double.infinity, hi = -double.infinity;
    for (var i = 0; i < pts.length; i++) {
      if ((us[i] - end).abs() <= 0.2 * short) {
        lo = math.min(lo, vs[i]);
        hi = math.max(hi, vs[i]);
      }
    }
    if (!((hi - lo) / short >= tuning.thinBoxMinEndCover)) return null;
  }
  final mid = (u0 + u1) / 2;
  for (var i = 0; i < pts.length; i++) {
    if ((us[i] - mid).abs() > 0.35 * long) continue;
    final d = math.min((vs[i] - v0).abs(), (vs[i] - v1).abs());
    if (d > 0.25 * short) return null;
  }
  Offset at(double u, double v) =>
      Offset(cx + u * c - v * s, cy + u * s + v * c);
  final corners = [at(u0, v0), at(u1, v0), at(u1, v1), at(u0, v1)];
  final diag = (corners[2] - corners[0]).distance;
  return ShapeClassification(
    ShapeClass.rectangle,
    vertices: corners,
    error: _polygonError(pts, corners, diag),
  );
}

/// thinBox: samples along the raw stroke.
const int kThinBoxSamples = 400;

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

/// 6.17.1 step 5: the ellipse of the closed [pts]. PCA gives the centre and
/// the axis direction; the axes (and a centre shift along them) are then a
/// least-squares fit of A·u² + B·v² + D·u + E·v = 1 in that frame — the
/// curve, not the point spread (√(2λ) assumes points evenly spread by angle,
/// and a hand's points are spread by path length: a 0.3 ellipse came out
/// with a 0.1 error and as a polygon). error = mean distance of the points to
/// the ellipse (|F| ÷ |∇F|) ÷ the mean semi-axis (for a circle: mean |r − 1|).
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
  var ang = 0.5 * math.atan2(2 * sxy, sxx - syy);
  // Points spread evenly along an ellipse: variance ≈ a² / 2 (the fallback).
  var a = math.sqrt(2 * l1), b = math.sqrt(2 * l2);
  final c = math.cos(ang), s = math.sin(ang);
  final ls = _axisFit(pts, Offset(cx, cy), c, s, a);
  if (ls != null) {
    final (du, dv, la, lb) = ls;
    cx += du * c - dv * s;
    cy += du * s + dv * c;
    a = la;
    b = lb;
    if (b > a) {
      (a, b) = (b, a);
      ang += math.pi / 2;
    }
  }
  final ca = math.cos(ang), sa = math.sin(ang);
  var err = 0.0;
  for (final p in pts) {
    final dx = p.dx - cx, dy = p.dy - cy;
    final u = dx * ca + dy * sa, v = -dx * sa + dy * ca;
    final f = (u * u) / (a * a) + (v * v) / (b * b) - 1;
    final gx = 2 * u / (a * a), gy = 2 * v / (b * b);
    final g = math.sqrt(gx * gx + gy * gy);
    err += g > 1e-12 ? math.min(f.abs() / g, a) : b;
  }
  err /= pts.length * (a + b) / 2;
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

/// Least squares of A·u² + B·v² + D·u + E·v = 1 for [pts] in the frame at
/// [center] with axis (c, s); coordinates scaled by [scale] for conditioning.
/// (centre shift u, centre shift v, a, b) or null when degenerate.
(double, double, double, double)? _axisFit(
  List<Offset> pts,
  Offset center,
  double c,
  double s,
  double scale,
) {
  if (!(scale > 0)) return null;
  // Normal equations M·x = r for x = (A, B, D, E).
  final m = List.generate(4, (_) => List.filled(4, 0.0));
  final r = List.filled(4, 0.0);
  for (final p in pts) {
    final dx = p.dx - center.dx, dy = p.dy - center.dy;
    final u = (dx * c + dy * s) / scale, v = (-dx * s + dy * c) / scale;
    final row = [u * u, v * v, u, v];
    for (var i = 0; i < 4; i++) {
      r[i] += row[i];
      for (var j = 0; j < 4; j++) {
        m[i][j] += row[i] * row[j];
      }
    }
  }
  final x = _solve4(m, r);
  if (x == null) return null;
  final [aa, bb, dd, ee] = x;
  if (!(aa > 0) || !(bb > 0)) return null;
  final u0 = -dd / (2 * aa), v0 = -ee / (2 * bb);
  final g = 1 + aa * u0 * u0 + bb * v0 * v0;
  if (!(g > 0)) return null;
  final a = math.sqrt(g / aa) * scale, b = math.sqrt(g / bb) * scale;
  if (!a.isFinite || !b.isFinite || !(b > 0)) return null;
  return (u0 * scale, v0 * scale, a, b);
}

/// Gaussian elimination with partial pivoting; null when singular.
List<double>? _solve4(List<List<double>> m, List<double> r) {
  const n = 4;
  for (var k = 0; k < n; k++) {
    var piv = k;
    for (var i = k + 1; i < n; i++) {
      if (m[i][k].abs() > m[piv][k].abs()) piv = i;
    }
    if (!(m[piv][k].abs() > 1e-12)) return null;
    if (piv != k) {
      final row = m[k], rk = r[k];
      m[k] = m[piv];
      m[piv] = row;
      r[k] = r[piv];
      r[piv] = rk;
    }
    for (var i = k + 1; i < n; i++) {
      final f = m[i][k] / m[k][k];
      for (var j = k; j < n; j++) {
        m[i][j] -= f * m[k][j];
      }
      r[i] -= f * r[k];
    }
  }
  final x = List.filled(n, 0.0);
  for (var i = n - 1; i >= 0; i--) {
    var v = r[i];
    for (var j = i + 1; j < n; j++) {
      v -= m[i][j] * x[j];
    }
    x[i] = v / m[i][i];
  }
  return x.every((v) => v.isFinite) ? x : null;
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

/// (6.17.5) The 4 [corners] as a triangle with one short edge (≤
/// roundedCornerMaxEdge × perimeter) collapsed to the point where the lines
/// of its two neighbouring edges meet — that point within one short-edge
/// length of the edge's middle. The best such triangle and its error, or
/// null.
(List<Offset>, double)? _mergeRoundedCorner(
  List<Offset> loop,
  List<Offset> corners,
  double diag,
  ShapeFitTuning tuning,
) {
  var per = 0.0;
  for (var i = 0; i < 4; i++) {
    per += _dist(corners[i], corners[(i + 1) % 4]);
  }
  (List<Offset>, double)? best;
  for (var k = 0; k < 4; k++) {
    final a = corners[k], b = corners[(k + 1) % 4];
    final edge = _dist(a, b);
    if (edge > tuning.roundedCornerMaxEdge * per) continue;
    final p = corners[(k + 3) % 4], q = corners[(k + 2) % 4];
    final x = _lineIntersection(p, a, q, b);
    if (x == null || _dist(x, (a + b) / 2) > edge) continue;
    final tri = [
      for (var i = 0; i < 4; i++)
        if (i == k) x else if (i != (k + 1) % 4) corners[i],
    ];
    final err = _polygonError(loop, tri, diag);
    if (best == null || err < best.$2) best = (tri, err);
  }
  return best;
}

/// Where the line through [p0]–[p1] meets the line through [q0]–[q1]; null
/// when (nearly) parallel.
Offset? _lineIntersection(Offset p0, Offset p1, Offset q0, Offset q1) {
  final r = p1 - p0, s = q1 - q0;
  final den = r.dx * s.dy - r.dy * s.dx;
  if (den.abs() < 1e-9 * r.distance * s.distance || den == 0) return null;
  final t = ((q0.dx - p0.dx) * s.dy - (q0.dy - p0.dy) * s.dx) / den;
  return p0 + r * t;
}

bool _rightAngles(List<Offset> quad, ShapeFitTuning tuning) {
  for (var i = 0; i < 4; i++) {
    final t = turnDegrees(quad[(i + 3) % 4], quad[i], quad[(i + 1) % 4]);
    if ((t - 90).abs() > tuning.rightAngleToleranceDeg) return false;
  }
  return true;
}

/// 6.17.1 step 1b: the hold tail. INK asks for a fit after the pen has
/// rested ~500 ms, so the stroke ends in a cluster of tremor samples; after
/// resampling by length they zigzag (turning noise, a fake corner). The
/// trailing samples within [radius] (pt) of the mean of the last 8 become
/// that mean. [raw] unchanged when nothing is trimmed.
List<Offset> trimHoldTail(List<Offset> raw, double radius) {
  if (raw.length < 8 || !(radius > 0)) return raw;
  var ax = 0.0, ay = 0.0;
  for (var i = raw.length - 8; i < raw.length; i++) {
    ax += raw[i].dx / 8;
    ay += raw[i].dy / 8;
  }
  final anchor = Offset(ax, ay);
  var i = raw.length - 1;
  while (i > 0 && _dist(raw[i], anchor) <= radius) {
    i--;
  }
  if (i >= raw.length - 2) return raw;
  return [...raw.sublist(0, i + 1), anchor];
}

/// 6.17.1 step 4: where the outline closes on the smoothed path [p] — the
/// pair (start i in the first 15 %, end j in the last 40 %) nearest to each
/// other, so an overshoot past the start, a crossing hook or a hook at the
/// start are cut off. Every cut-off point must stay within 12 % of the
/// diagonal [diag] of the kept part (an overshoot runs along the outline; the
/// stem of a 6 or a 9 does not) — else the whole path (0, last).
(int, int) _closure(List<Offset> p, double diag) {
  final n = p.length;
  var bi = 0, bj = n - 1;
  var best = _dist(p.first, p.last);
  final iMax = (n * 0.15).floor(), jMin = (n * 0.6).ceil();
  for (var i = 0; i <= iMax; i++) {
    for (var j = jMin; j < n; j++) {
      final d = _dist(p[i], p[j]);
      if (d < best) {
        best = d;
        bi = i;
        bj = j;
      }
    }
  }
  if (bi == 0 && bj == n - 1) return (bi, bj);
  final keep = p.sublist(bi, bj + 1);
  bool near(Offset q) {
    for (var k = 1; k < keep.length; k++) {
      if (segmentDistance(q, keep[k - 1], keep[k]) <= 0.12 * diag) return true;
    }
    return false;
  }

  for (var k = 0; k < bi; k++) {
    if (!near(p[k])) return (0, n - 1);
  }
  for (var k = bj + 1; k < n; k++) {
    if (!near(p[k])) return (0, n - 1);
  }
  return (bi, bj);
}

/// 6.17.1 steps 2–9 for [raw] (≥ 4 finite points, the hold tail already
/// trimmed — trimHoldTail); null = stays ink.
///
/// (review fixes) A closed outline that is no rectangle is also tried as a
/// thin box (thinBox): at 64 samples a box round a heading (short side
/// ~ 0.1 of the long one) has ~3 samples per short side and the smoothing
/// rounds them into a cap, so it came out an ellipse or a triangle.
ShapeClassification? classifyShape(
  List<Offset> raw, {
  ShapeFitTuning tuning = const ShapeFitTuning(),
}) {
  if (raw.length < 4) return null;
  final first = _classifyPass(raw, tuning);
  if (first == null || first.kind == ShapeClass.rectangle) return first;
  return thinBox(raw, tuning) ?? first;
}

ShapeClassification? _classifyPass(List<Offset> raw, ShapeFitTuning tuning) {
  final smooth = _smooth(
    resamplePath(raw, kShapePreResample),
    tuning.smoothRadius,
  );
  final pts = resamplePath(smooth, tuning.resampleCount);
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

  // 4. Closed outlines only: the overshoot / hooks cut off where the
  // outline closes, then the gap and the total turning of the CLOSED loop
  // (the turn at the closing point counts — a triangle started at a corner
  // turned only 240° on the open path).
  // Two laps (shading a dot, a spiral) stay ink even when the second lap
  // runs along the first: the open path's own turning is capped too.
  var openTurning = 0.0;
  for (var i = 1; i < pts.length - 1; i++) {
    final u = pts[i] - pts[i - 1], w = pts[i + 1] - pts[i];
    openTurning += math.atan2(
      u.dx * w.dy - u.dy * w.dx,
      u.dx * w.dx + u.dy * w.dy,
    );
  }
  if ((openTurning * 180 / math.pi).abs() > tuning.maxTurnDeg) return null;
  final (ci, cj) = _closure(smooth, diag);
  final kept = smooth.sublist(ci, cj + 1);
  final keptLen = _pathLength(kept);
  if (!(keptLen > 0) ||
      _dist(kept.first, kept.last) / keptLen > tuning.closedMaxGap) {
    return null;
  }
  final loop = resamplePath([
    ...kept,
    kept.first,
  ], tuning.resampleCount + 1).sublist(0, tuning.resampleCount);
  var turning = 0.0, absTurning = 0.0;
  for (var i = 0; i < loop.length; i++) {
    final a = loop[(i - 1 + loop.length) % loop.length];
    final b = loop[i], c = loop[(i + 1) % loop.length];
    final u = b - a, w = c - b;
    final t = math.atan2(u.dx * w.dy - u.dy * w.dx, u.dx * w.dx + u.dy * w.dy);
    turning += t;
    absTurning += t.abs();
  }
  final turnDeg = (turning * 180 / math.pi).abs();
  if (turnDeg < tuning.minTurnDeg || turnDeg > tuning.maxTurnDeg) return null;
  if (absTurning * 180 / math.pi > tuning.maxAbsTurnDeg) return null;

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
  // (6.17.5) … or a rounded corner that RDP found as two: the ends of a
  // short edge merged where the edges beside it meet (never on a quad that
  // is, or reseats to, a rectangle).
  if (corners.length == 4 && !_rightAngles(corners, tuning)) {
    final reseated = _reseatCorners(loop, corners);
    if (reseated == null || !_rightAngles(reseated, tuning)) {
      final tri = _mergeRoundedCorner(loop, corners, diag, tuning);
      if (tri != null && tri.$2 <= polyErr * tuning.weakCornerErrorFactor) {
        return ShapeClassification(
          ShapeClass.triangle,
          vertices: tri.$1,
          error: tri.$2,
        );
      }
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
