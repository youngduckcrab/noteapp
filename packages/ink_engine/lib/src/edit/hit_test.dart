// lib/src/edit/hit_test.dart — INTERNAL (03-ink 6.18, INK T14).
//
// Exact "does the ink touch this shape" tests. A stroke segment p_i → p_{i+1}
// with radii r_i → r_{i+1} is the union of the discs centred at p(u) with
// radius r(u) (u ∈ [0, 1], both linear) — the convex hull of the two end discs.
// Against a convex shape S (the eraser capsule a → b of radius R, a point, a
// rectangle):
//
//   g(u) = dist(p(u), S) − (R + r(u))
//
// The distance to a convex set is convex along a line and −r(u) is linear, so
// g is convex: its minimum is found by golden-section search
// (InkTuning.goldenSectionIterations steps, plus both ends), and the ink
// touches S iff min g ≤ 0. Segments whose bounds (radius included) miss the
// shape's bounds are skipped. A dot stroke (one point or zero-length
// centerline) is one disc of radius maxRadius. Highlighter radius = width / 2
// (the square-cap extension is ignored) — InkStroke.radiusAt.
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:meta/meta.dart';

import '../model/ink_stroke.dart';
import '../tuning.dart';

/// The minimum of g over one segment: [u] in [0, 1] and the value [gap].
typedef SegmentMinimum = ({double u, double gap});

@internal
abstract final class InkHitTest {
  static const double _invPhi = 0.6180339887498949;

  /// Minimum of a convex [g] on [0, 1]: golden-section search
  /// ([iterations] bracket reductions) plus both ends.
  static SegmentMinimum minimize(
    double Function(double u) g, {
    int iterations = InkTuning.goldenSectionIterations,
  }) {
    var bestU = 0.0;
    var best = g(0);
    final atEnd = g(1);
    if (atEnd < best) {
      best = atEnd;
      bestU = 1;
    }
    var lo = 0.0, hi = 1.0;
    var x1 = hi - _invPhi * (hi - lo), x2 = lo + _invPhi * (hi - lo);
    var f1 = g(x1), f2 = g(x2);
    for (var i = 0; i < iterations; i++) {
      if (f1 <= f2) {
        hi = x2;
        x2 = x1;
        f2 = f1;
        x1 = hi - _invPhi * (hi - lo);
        f1 = g(x1);
      } else {
        lo = x1;
        x1 = x2;
        f1 = f2;
        x2 = lo + _invPhi * (hi - lo);
        f2 = g(x2);
      }
    }
    if (f1 < best) {
      best = f1;
      bestU = x1;
    }
    if (f2 < best) {
      best = f2;
      bestU = x2;
    }
    return (u: bestU, gap: best);
  }

  /// Distance from (px, py) to the segment (ax, ay) → (bx, by) (a point if a == b).
  static double pointSegmentDistance(
    double px,
    double py,
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    final abx = bx - ax, aby = by - ay;
    final len2 = abx * abx + aby * aby;
    var t = 0.0;
    if (len2 > 0) {
      t = ((px - ax) * abx + (py - ay) * aby) / len2;
      if (t < 0) {
        t = 0;
      } else if (t > 1) {
        t = 1;
      }
    }
    final dx = ax + abx * t - px, dy = ay + aby * t - py;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Distance from (px, py) to the closed rectangle [r] (0 inside).
  static double pointRectDistance(double px, double py, Rect r) {
    final dx = math.max(math.max(r.left - px, 0.0), px - r.right);
    final dy = math.max(math.max(r.top - py, 0.0), py - r.bottom);
    return math.sqrt(dx * dx + dy * dy);
  }

  /// g(u) of the segment (x0, y0, r0) → (x1, y1, r1) against the capsule
  /// a → b of radius [radius], at [u].
  static double capsuleGapAt(
    double u,
    double x0,
    double y0,
    double r0,
    double x1,
    double y1,
    double r1,
    Offset a,
    Offset b,
    double radius,
  ) =>
      pointSegmentDistance(
        x0 + (x1 - x0) * u,
        y0 + (y1 - y0) * u,
        a.dx,
        a.dy,
        b.dx,
        b.dy,
      ) -
      (radius + r0 + (r1 - r0) * u);

  /// min g of one segment against the capsule a → b of radius [radius].
  static SegmentMinimum segmentVsCapsule(
    double x0,
    double y0,
    double r0,
    double x1,
    double y1,
    double r1,
    Offset a,
    Offset b,
    double radius,
  ) => minimize((u) => capsuleGapAt(u, x0, y0, r0, x1, y1, r1, a, b, radius));

  /// min g of one segment against the closed rectangle [rect].
  static SegmentMinimum segmentVsRect(
    double x0,
    double y0,
    double r0,
    double x1,
    double y1,
    double r1,
    Rect rect,
  ) => minimize(
    (u) =>
        pointRectDistance(x0 + (x1 - x0) * u, y0 + (y1 - y0) * u, rect) -
        (r0 + (r1 - r0) * u),
  );

  /// The smallest g over every segment of [s] against the capsule a → b of
  /// radius [radius] (no bounds pruning): ≤ 0 iff the ink touches the capsule,
  /// otherwise the gap between them in pt. +∞ for a stroke without points.
  static double capsuleGap(InkStroke s, Offset a, Offset b, double radius) {
    final p = s.points;
    final n = p.length;
    if (n == 0) return double.infinity;
    if (s.isDot) {
      return pointSegmentDistance(p.x(0), p.y(0), a.dx, a.dy, b.dx, b.dy) -
          (radius + s.maxRadius);
    }
    var best = double.infinity;
    for (var i = 0; i + 1 < n; i++) {
      final m = segmentVsCapsule(
        p.x(i),
        p.y(i),
        s.radiusAt(i),
        p.x(i + 1),
        p.y(i + 1),
        s.radiusAt(i + 1),
        a,
        b,
        radius,
      );
      if (m.gap < best) best = m.gap;
    }
    return best;
  }

  /// Does the ink of [s] touch the capsule a → b of radius [radius]
  /// (a == b: the disc around a)? 6.18 / 6.19.
  static bool capsuleTouches(InkStroke s, Offset a, Offset b, double radius) {
    final p = s.points;
    final n = p.length;
    if (n == 0 || !(radius >= 0)) return false;
    final left = math.min(a.dx, b.dx) - radius;
    final right = math.max(a.dx, b.dx) + radius;
    final top = math.min(a.dy, b.dy) - radius;
    final bottom = math.max(a.dy, b.dy) + radius;
    if (s.isDot) {
      return pointSegmentDistance(p.x(0), p.y(0), a.dx, a.dy, b.dx, b.dy) <=
          radius + s.maxRadius;
    }
    for (var i = 0; i + 1 < n; i++) {
      final x0 = p.x(i), y0 = p.y(i), x1 = p.x(i + 1), y1 = p.y(i + 1);
      final r0 = s.radiusAt(i), r1 = s.radiusAt(i + 1);
      final rm = math.max(r0, r1);
      if (math.min(x0, x1) - rm > right ||
          math.max(x0, x1) + rm < left ||
          math.min(y0, y1) - rm > bottom ||
          math.max(y0, y1) + rm < top) {
        continue;
      }
      if (segmentVsCapsule(x0, y0, r0, x1, y1, r1, a, b, radius).gap <= 0) {
        return true;
      }
    }
    return false;
  }

  /// Does the ink of [s] meet the closed rectangle [rect]?
  static bool rectTouches(InkStroke s, Rect rect) {
    final p = s.points;
    final n = p.length;
    if (n == 0 || rect.left > rect.right || rect.top > rect.bottom) {
      return false;
    }
    if (s.isDot) {
      return pointRectDistance(p.x(0), p.y(0), rect) <= s.maxRadius;
    }
    for (var i = 0; i + 1 < n; i++) {
      final x0 = p.x(i), y0 = p.y(i), x1 = p.x(i + 1), y1 = p.y(i + 1);
      final r0 = s.radiusAt(i), r1 = s.radiusAt(i + 1);
      final rm = math.max(r0, r1);
      if (math.min(x0, x1) - rm > rect.right ||
          math.max(x0, x1) + rm < rect.left ||
          math.min(y0, y1) - rm > rect.bottom ||
          math.max(y0, y1) + rm < rect.top) {
        continue;
      }
      if (segmentVsRect(x0, y0, r0, x1, y1, r1, rect).gap <= 0) return true;
    }
    return false;
  }

  /// 6.18 topmostAt: of [candidates], the one with the largest [zOf] whose ink
  /// lies within [tolerance] pt of [point]; null if none.
  static InkStroke? topmostAt(
    Iterable<InkStroke> candidates,
    Offset point,
    double tolerance, {
    required int Function(InkStroke s) zOf,
  }) {
    final ordered = candidates.toList()
      ..sort((x, y) => zOf(y).compareTo(zOf(x)));
    final radius = tolerance > 0 ? tolerance : 0.0;
    for (final s in ordered) {
      if (capsuleTouches(s, point, point, radius)) return s;
    }
    return null;
  }
}
