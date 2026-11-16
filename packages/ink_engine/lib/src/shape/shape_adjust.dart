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
//    multiple of 45° within InkTuning.shapeAdjustAngleSnapDeg (length kept).
//    Longer open polylines turn and scale about the fixed end (a similarity).
//  * circle (EllipseGeometry with a square frame): center fixed, radius +=
//    |pen − c| − |anchor − c| — the radius follows the pen's distance 1:1.
//  * ellipse: center and rotation fixed, both axes × s (proportions kept).
//  * a closed 4-point polyline (rectangle, quad): the corner nearest the
//    anchor follows the pen, the opposite corner stays; the shape scales along
//    its own two edge directions at that corner (an axis-aligned rectangle
//    stays axis-aligned, a rotated one resizes in its own frame).
//  * other closed polylines (triangle, polygon, star): × s about the vertex
//    mean, no rotation (predictable: the shape never turns under the pen).
// Uniform s = 1 + (|pen − c| − |anchor − c|) / max(|anchor − c|, extent / 8):
// = |pen − c| / |anchor − c| when the anchor is not near the center, and
// continuous (s = 1 at the anchor) when it is.
// Guard rails: nothing shrinks below min(its snapped size, [minSizePt]) and
// nothing flips inside out (scales stay positive); nothing grows past
// ElementFrame.maxSide. A non-finite pen gives the snapped geometry.
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

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
    core.PolylineGeometry(points: final p) when p.length == 4 =>
      _corner(g, anchor, pen, minSize) ?? _uniform(g, anchor, pen, minSize),
    core.PolylineGeometry() => _uniform(g, anchor, pen, minSize),
  };
}

const double _maxSide = core.ElementFrame.maxSide;

Offset _o(core.PagePoint p) => Offset(p.x, p.y);
core.PagePoint _p(Offset o) => core.PagePoint(o.dx, o.dy);
double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;

/// The uniform scale of a shape of [extent] (its larger side) centered at [c].
double _uniformScale(
  Offset c,
  Offset anchor,
  Offset pen,
  double extent,
  double minSize,
) {
  final dA = (anchor - c).distance, dP = (pen - c).distance;
  final denom = math.max(dA, extent / 8);
  if (!(denom > 0) || !(extent > 0)) return 1;
  final s = 1 + (dP - dA) / denom;
  final lo = math.min(1.0, minSize / extent);
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
    final s = _uniformScale(c, anchor, pen, extent, minSize);
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
  final first = _o(pts.first), last = _o(pts.last);
  // the end the user was holding at moves; the farther one stays
  final movingLast = (last - anchor).distance <= (first - anchor).distance;
  final fixed = movingLast ? first : last;
  final moving = movingLast ? last : first;
  final before = moving - fixed;
  var v = moving + (pen - anchor) - fixed;
  if (snapRad > 0 && pts.length == 2 && v.distance > 0) {
    const step = math.pi / 4;
    final a = v.direction;
    final snapped = (a / step).roundToDouble() * step;
    if ((a - snapped).abs() <= snapRad) {
      v = Offset.fromDirection(snapped, v.distance);
    }
  }
  final len0 = before.distance;
  final lo = math.min(len0, minSize);
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

/// The corner nearest the anchor follows the pen, the opposite one stays; null when
/// the corner's edges are degenerate (the caller falls back to [_uniform]).
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
  final sx = clampScale(a2 / a, l1);
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
  final s = _uniformScale(c, anchor, pen, math.max(r.width, r.height), minSize);
  return core.PolylineGeometry(
    List.unmodifiable([for (final q in pts) _p(c + (_o(q) - c) * s)]),
    closed: g.closed,
  );
}
