// lib/src/shape/shape_adjust.dart — INTERNAL, pure (m5-7/03-ink 6.18 '맞춘 뒤 조절',
// contract v2.12 C212-01).
//
// After the hold snapped a stroke to a shape the pen stays down and drags the
// shape: [adjustShape] maps (the fit at snap time, the pen position at snap
// time = anchor, the pen now) to the adjusted geometry. No state: the session
// calls it with the SAME fit and anchor for every sample, so going back to the
// anchor gives the snapped shape back exactly.
//
//  * line / arrow (and any open polyline): the end farther from the anchor
//    stays; the other end moves by (pen − anchor). Two-point lines snap to a
//    multiple of 15° within InkTuning.shapeAdjustAngleSnapDeg (length kept) —
//    the same step as the fitter's beautify (SelectionGeometry.snapAngle).
//    Longer open polylines turn and scale about the fixed end (a similarity).
//    [adjustLeavesOpenShape]: a drag that turns the moving end more than
//    InkTuning.shapeAdjustEscapeDeg about the fixed end is the stroke going on
//    (a corner pause of a triangle, ㄱ) — the session drops back to ink.
//  * circle (EllipseGeometry with a square frame): center fixed, radius +=
//    |pen − c| − |anchor − c| — the radius follows the pen's distance 1:1.
//  * ellipse: center and rotation fixed, both axes × s (proportions kept).
//  * a closed 4-point parallelogram (rectangle, rotated rectangle): the corner
//    nearest the anchor follows the pen, the opposite corner stays; the shape
//    scales along its own two edge directions at that corner (an axis-aligned
//    rectangle stays axis-aligned, a rotated one resizes in its own frame).
//    An anchor nearer an edge's midpoint than any corner moves only that edge
//    along its own direction (the opposite edge stays). A 4-point shape that
//    is not a parallelogram (a concave quad) scales uniformly instead.
//  * other closed polylines (triangle, polygon, star): × s about the vertex
//    mean, no rotation (predictable: the shape never turns under the pen).
// Uniform s = 1 + (|pen − c| − |anchor − c|) / max(|anchor − c|, extent / 8):
// = |pen − c| / |anchor − c| when the anchor is not near the center, and
// continuous (s = 1 at the anchor) when it is.
// Guard rails: nothing shrinks below min(its snapped size, [minSizePt]) — for a
// uniform scale its SMALLER side, so a thin ellipse never becomes a hairline —
// and nothing flips inside out (scales stay positive); nothing grows past
// ElementFrame.maxSide. A non-finite pen (or a drag overflowing to infinity)
// gives the snapped geometry.
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

import '../edit/selection_geometry.dart';
import '../tuning.dart';
import 'shape_assist.dart';

/// The geometry of [fit] dragged from [anchor] (the pen at snap time, page pt)
/// to [pen] (page pt). [minSizePt] = the smallest side / diameter / length a drag
/// may shrink to (page pt). Identical to `fit.geometry` when pen == anchor.
@internal
core.ShapeGeometry adjustShape(
  InkShapeFit fit, {
  required Offset anchor,
  required Offset pen,
  required double minSizePt,
  double angleSnapDeg = InkTuning.shapeAdjustAngleSnapDeg,
}) {
  final g = fit.geometry;
  if (!pen.isFinite || !anchor.isFinite || pen == anchor) return g;
  final minSize = minSizePt.isFinite && minSizePt > 0 ? minSizePt : 0.0;
  return switch (g) {
    core.EllipseGeometry() => _ellipse(g, anchor, pen, minSize),
    core.PolylineGeometry(closed: false) => _open(
      g,
      anchor,
      pen,
      minSize,
      snapRad:
          fit.kind == core.ShapeKind.line || fit.kind == core.ShapeKind.arrow
          ? angleSnapDeg * math.pi / 180
          : 0,
    ),
    core.PolylineGeometry(points: final p)
        when p.length == 4 && _isParallelogram(p) =>
      _corner(g, anchor, pen, minSize) ?? _uniform(g, anchor, pen, minSize),
    core.PolylineGeometry() => _uniform(g, anchor, pen, minSize),
  };
}

/// (C212-01 review) True when [fit] is open (line, arrow, open polyline) and the
/// drag from [anchor] to [pen] turns its moving end more than [escapeDeg] about
/// the fixed end (or through it): the stroke is going on, not the line being
/// adjusted. Closed shapes never escape.
@internal
bool adjustLeavesOpenShape(
  InkShapeFit fit, {
  required Offset anchor,
  required Offset pen,
  double escapeDeg = InkTuning.shapeAdjustEscapeDeg,
}) {
  final g = fit.geometry;
  if (g is! core.PolylineGeometry || g.closed || g.points.length < 2) {
    return false;
  }
  if (!pen.isFinite || !anchor.isFinite) return false;
  final (fixed, moving, _) = _ends(g, anchor);
  final before = moving - fixed;
  final after = moving + (pen - anchor) - fixed;
  final l0 = before.distance, l1 = after.distance;
  if (!(l0 > 0) || !l1.isFinite) return false;
  if (!(l1 > 0)) return true;
  final cos = (before.dx * after.dx + before.dy * after.dy) / (l0 * l1);
  return cos < math.cos(escapeDeg * math.pi / 180);
}

/// The fixed end, the moving end (the one nearer [anchor]) and whether it is the last.
(Offset, Offset, bool) _ends(core.PolylineGeometry g, Offset anchor) {
  final first = _o(g.points.first), last = _o(g.points.last);
  final movingLast = (last - anchor).distance <= (first - anchor).distance;
  return movingLast ? (first, last, true) : (last, first, false);
}

/// The 4 points form a parallelogram (diagonals bisect each other) within 1 %.
bool _isParallelogram(List<core.PagePoint> p) {
  final xs = [for (final q in p) q.x], ys = [for (final q in p) q.y];
  final extent = math.max(
    xs.reduce(math.max) - xs.reduce(math.min),
    ys.reduce(math.max) - ys.reduce(math.min),
  );
  final dx = p[0].x + p[2].x - p[1].x - p[3].x;
  final dy = p[0].y + p[2].y - p[1].y - p[3].y;
  return math.sqrt(dx * dx + dy * dy) <= 0.01 * extent;
}

const double _maxSide = core.ElementFrame.maxSide;

Offset _o(core.PagePoint p) => Offset(p.x, p.y);
core.PagePoint _p(Offset o) => core.PagePoint(o.dx, o.dy);
double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;

/// The uniform scale of a shape of [extent] (its larger side) and [minor] (its
/// smaller side) centered at [c]; the minimum size holds for the smaller side.
double _uniformScale(
  Offset c,
  Offset anchor,
  Offset pen,
  double extent,
  double minor,
  double minSize,
) {
  final dA = (anchor - c).distance, dP = (pen - c).distance;
  final denom = math.max(dA, extent / 8);
  if (!(denom > 0) || !(extent > 0) || !dP.isFinite) return 1;
  final s = 1 + (dP - dA) / denom;
  final small = minor > 0 ? minor : extent;
  final lo = math.min(1.0, minSize / small);
  final hi = math.max(1.0, _maxSide / extent);
  return s.clamp(lo, hi).toDouble();
}

core.ShapeGeometry _ellipse(
  core.EllipseGeometry g,
  Offset anchor,
  Offset pen,
  double minSize,
) {
  final f = g.ellipseFrame;
  final c = _o(f.center);
  final w = f.rect.width, h = f.rect.height;
  final extent = math.max(w, h);
  if (!(extent > 0)) return g;
  final double nw, nh;
  if ((w - h).abs() <= 1e-9 * extent) {
    // circle: the radius follows the pen's distance from the center 1:1
    final r = extent / 2;
    final dr = (pen - c).distance - (anchor - c).distance;
    final lo = math.min(r, minSize / 2), hi = math.max(r, _maxSide / 2);
    final nr = (r + dr).clamp(lo, hi).toDouble();
    nw = nh = 2 * nr;
  } else {
    final s = _uniformScale(c, anchor, pen, extent, math.min(w, h), minSize);
    nw = w * s;
    nh = h * s;
  }
  return core.EllipseGeometry(
    core.ElementFrame(
      core.PageRect(c.dx - nw / 2, c.dy - nh / 2, c.dx + nw / 2, c.dy + nh / 2),
      rotation: f.rotation,
    ),
  );
}

core.ShapeGeometry _open(
  core.PolylineGeometry g,
  Offset anchor,
  Offset pen,
  double minSize, {
  required double snapRad,
}) {
  final pts = g.points;
  if (pts.length < 2) return g;
  // the end the user was holding at moves; the farther one stays
  final (fixed, moving, movingLast) = _ends(g, anchor);
  final before = moving - fixed;
  var v = moving + (pen - anchor) - fixed;
  if (!v.distance.isFinite) return g;
  if (snapRad > 0 && pts.length == 2 && v.distance > 0) {
    // the fitter's step (shape_beautify: 15° within 3°)
    final snapped = SelectionGeometry.snapAngle(
      v.direction,
      threshold: snapRad,
    );
    v = Offset.fromDirection(snapped, v.distance);
  }
  final len0 = before.distance;
  // never zero long (a NaN / zero minSize still keeps 0.1 % of the length)
  final lo = math.max(math.min(len0, minSize), len0 * 1e-3);
  final len = v.distance;
  if (len < lo || len == 0) {
    final dir = len > 0 ? v / len : (len0 > 0 ? before / len0 : null);
    if (dir == null) return g;
    v = dir * lo;
  } else if (len > _maxSide) {
    v = v / len * _maxSide;
  }
  if (pts.length == 2) {
    final moved = _p(fixed + v);
    final points = movingLast ? [pts.first, moved] : [moved, pts.last];
    return core.PolylineGeometry(List.unmodifiable(points), closed: false);
  }
  if (!(len0 > 0)) return g;
  // similarity about the fixed end: z = v / before (complex numbers)
  final d2 = len0 * len0;
  final zr = (v.dx * before.dx + v.dy * before.dy) / d2;
  final zi = (v.dy * before.dx - v.dx * before.dy) / d2;
  return core.PolylineGeometry(
    List.unmodifiable([
      for (final p in pts)
        () {
          final q = _o(p) - fixed;
          return _p(
            fixed + Offset(zr * q.dx - zi * q.dy, zi * q.dx + zr * q.dy),
          );
        }(),
    ]),
    closed: false,
  );
}

/// The corner nearest the anchor follows the pen, the opposite one stays — or, when
/// the anchor is nearer an edge's midpoint than any corner, only that edge moves
/// (along its own direction, the opposite edge stays); null when the edges are
/// degenerate (the caller falls back to [_uniform]).
core.ShapeGeometry? _corner(
  core.PolylineGeometry g,
  Offset anchor,
  Offset pen,
  double minSize,
) {
  final p = [for (final q in g.points) _o(q)];
  var k = 0;
  for (var i = 1; i < 4; i++) {
    if ((p[i] - anchor).distance < (p[k] - anchor).distance) k = i;
  }
  // the edge (m, m + 1) whose midpoint is nearest; it wins over a farther corner
  var m = 0;
  Offset mid(int i) => (p[i] + p[(i + 1) % 4]) / 2;
  for (var i = 1; i < 4; i++) {
    if ((mid(i) - anchor).distance < (mid(m) - anchor).distance) m = i;
  }
  final edgeOnly = (mid(m) - anchor).distance < (p[k] - anchor).distance;
  // edge grab: corner k = m, its edge to m + 1 runs along e2 (see below)
  if (edgeOnly) k = m;
  final oi = (k + 2) % 4;
  final o = p[oi];
  final e1 = p[(oi + 1) % 4] - o;
  final e2 = p[(oi + 3) % 4] - o;
  final det = _cross(e1, e2);
  final l1 = e1.distance, l2 = e2.distance;
  if (!(l1 > 0) || !(l2 > 0) || det.abs() <= 1e-9 * l1 * l2) return null;
  // (u, v) = the coordinates of q in the basis (e1, e2) at o
  (double, double) coords(Offset q) =>
      (_cross(q, e2) / det, _cross(e1, q) / det);
  final (a, b) = coords(p[k] - o);
  if (a.abs() < 1e-9 || b.abs() < 1e-9) return null;
  final (a2, b2) = coords(p[k] + (pen - anchor) - o);
  // the edge along e1 becomes l1 · sx long (along e2: l2 · sy)
  double clampScale(double s, double l) => s
      .clamp(math.min(1.0, minSize / l), math.max(1.0, _maxSide / l))
      .toDouble();
  // p[k + 1] = o + e2: the edge (k, k + 1) is the one at v = b, so an edge grab
  // scales along e2 only
  final sx = edgeOnly ? 1.0 : clampScale(a2 / a, l1);
  final sy = clampScale(b2 / b, l2);
  return core.PolylineGeometry(
    List.unmodifiable([
      for (final q in p)
        () {
          final (u, v) = coords(q - o);
          return _p(o + e1 * (u * sx) + e2 * (v * sy));
        }(),
    ]),
    closed: true,
  );
}

core.ShapeGeometry _uniform(
  core.PolylineGeometry g,
  Offset anchor,
  Offset pen,
  double minSize,
) {
  final pts = g.points;
  if (pts.isEmpty) return g;
  var sx = 0.0, sy = 0.0;
  for (final q in pts) {
    sx += q.x;
    sy += q.y;
  }
  final c = Offset(sx / pts.length, sy / pts.length);
  final r = g.frame.rect;
  final s = _uniformScale(
    c,
    anchor,
    pen,
    math.max(r.width, r.height),
    math.min(r.width, r.height),
    minSize,
  );
  return core.PolylineGeometry(
    List.unmodifiable([for (final q in pts) _p(c + (_o(q) - c) * s)]),
    closed: g.closed,
  );
}
