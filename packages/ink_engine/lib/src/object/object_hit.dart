// lib/src/object/object_hit.dart — INTERNAL (m5-7/03-ink 6.14, 6.9.5, T37a).
//
// The exact "does this object take the tap" rules of hitTestObject:
// - text boxes, formulas, images and unknown objects: the (rotated) frame
//   contains the point within the tolerance (CORE ElementFrame.contains);
// - shapes: the distance from the point to the outline's centerline is at most
//   tolerance + w / 2 (the drawn stroke reaches w / 2 from it, round caps and
//   joins), or the point lies within the tolerance of an arrow head triangle,
//   or — a filled shape (fillColorArgb != null: the drawn fill exists) — the
//   point is inside the fill (nonzero winding for closed polylines, the
//   ellipse). The centerline is the one the painter strokes (shape_path.dart:
//   a polyline trimmed at the arrow heads' base midpoints, the dash pieces'
//   ellipse samples); a dashed or dotted outline counts as a whole, gaps
//   included (the same rule as the dashed pen — 6.5: simple and predictable).
//   A solid ellipse uses the exact point–ellipse distance (Eberly's
//   bisection), not a sampled polygon. An unfilled shape's inside is not hit.
// (T37b, 6.15) The eraser's swept capsule a → b of radius R touches a shape by
// the same geometry: the centerline within R + w / 2 of the segment a → b
// (segment–segment distances; a solid ellipse: 0 when the segment crosses the
// curve, the nearer end when it lies inside — the distance to the boundary is
// concave there — else the golden-section minimum of the exact point–ellipse
// distance, convex outside the convex region), a head triangle within R, or an
// end of the segment inside the fill (a segment that enters the fill otherwise
// crosses the outline and is caught by the first test).
// Non-finite input never hits; nothing here throws (4.0).
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

import '../edit/hit_test.dart';
import 'shape_path.dart';

@internal
abstract final class ObjectHitTest {
  /// 6.14: does [o] take a tap at [p] within [tolerance] pt (≥ 0)?
  static bool hits(core.PageObject o, Offset p, double tolerance) {
    if (!p.isFinite) return false;
    final tol = tolerance > 0 && tolerance.isFinite ? tolerance : 0.0;
    return switch (o) {
      core.ShapeObject() => shapeHits(o, p, tol),
      _ => o.frame.contains(core.PagePoint(p.dx, p.dy), tolerance: tol),
    };
  }

  /// The shape rule of [hits] (see the file comment).
  static bool shapeHits(core.ShapeObject o, Offset p, double tolerance) {
    final g = shapeGeometryOf(o);
    if (outlineDistance(o, p) <= tolerance + g.width / 2) return true;
    for (final head in g.heads) {
      if (polygonDistance(head, p) <= tolerance) return true;
    }
    return g.fill != null && fillContains(o, p);
  }

  /// 6.15: does the eraser capsule [a] → [b] of [radius] touch the shape [o] (see the file
  /// comment)? a == b is the disc around a.
  static bool shapeTouchesCapsule(
    core.ShapeObject o,
    Offset a,
    Offset b,
    double radius,
  ) {
    if (!a.isFinite || !b.isFinite || !(radius >= 0) || !radius.isFinite) {
      return false;
    }
    final g = shapeGeometryOf(o);
    if (outlineSegmentDistance(o, a, b) <= radius + g.width / 2) return true;
    for (final head in g.heads) {
      if (polygonSegmentDistance(head, a, b) <= radius) return true;
    }
    return g.fill != null && (fillContains(o, a) || fillContains(o, b));
  }

  /// The distance from the segment [a] → [b] to the centerline the painter strokes; +∞
  /// when the shape has no drawable outline.
  static double outlineSegmentDistance(core.ShapeObject o, Offset a, Offset b) {
    final g = shapeGeometryOf(o);
    if (g.oval != null) {
      final geometry = o.geometry;
      if (geometry is core.EllipseGeometry) {
        return ellipseSegmentDistance(geometry.ellipseFrame, a, b);
      }
    }
    final pts = g.centerline;
    if (pts.isEmpty) return double.infinity;
    if (pts.length == 1) return segmentPointDistance(a, b, pts.single);
    var best = double.infinity;
    for (var i = 0; i + 1 < pts.length; i++) {
      final d = segmentSegmentDistance(a, b, pts[i], pts[i + 1]);
      if (d < best) best = d;
    }
    return best;
  }

  /// Distance from the segment [a] → [b] to the filled polygon [poly] (0 when they meet).
  static double polygonSegmentDistance(List<Offset> poly, Offset a, Offset b) {
    if (poly.isEmpty) return double.infinity;
    if (poly.length >= 3 && windingNumber(poly, a) != 0) return 0;
    if (poly.length == 1) return segmentPointDistance(a, b, poly.single);
    var best = double.infinity;
    for (var i = 0; i < poly.length; i++) {
      final d = segmentSegmentDistance(
        a,
        b,
        poly[i],
        poly[(i + 1) % poly.length],
      );
      if (d < best) best = d;
    }
    return best;
  }

  /// Distance from [p] to the segment [a] → [b].
  static double segmentPointDistance(Offset a, Offset b, Offset p) =>
      InkHitTest.pointSegmentDistance(p.dx, p.dy, a.dx, a.dy, b.dx, b.dy);

  /// Distance between the segments [a] → [b] and [c] → [d] (0 when they cross or touch).
  static double segmentSegmentDistance(Offset a, Offset b, Offset c, Offset d) {
    final d1 = _cross(c, d, a), d2 = _cross(c, d, b);
    final d3 = _cross(a, b, c), d4 = _cross(a, b, d);
    if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
      return 0;
    }
    // touching and collinear overlaps put an end point on the other segment
    return math.min(
      math.min(segmentPointDistance(c, d, a), segmentPointDistance(c, d, b)),
      math.min(segmentPointDistance(a, b, c), segmentPointDistance(a, b, d)),
    );
  }

  /// The exact distance from the segment [a] → [b] to the ellipse curve inscribed in
  /// [frame] (rotated with it; see the file comment).
  static double ellipseSegmentDistance(
    core.ElementFrame frame,
    Offset a,
    Offset b,
  ) {
    final (x0, y0) = _local(frame, a);
    final (x1, y1) = _local(frame, b);
    final ea = frame.rect.width / 2, eb = frame.rect.height / 2;
    if (![x0, y0, x1, y1, ea, eb].every((v) => v.isFinite)) {
      return double.infinity;
    }
    final la = Offset(x0, y0), lb = Offset(x1, y1);
    if (!(ea > 0) || !(eb > 0)) {
      // a flat ellipse is the segment on its long axis (a zero one: its center)
      final h = ea > 0 ? Offset(ea, 0) : Offset(0, eb > 0 ? eb : 0);
      return segmentSegmentDistance(la, lb, -h, h);
    }
    // q(u) = (x(u) / ea)² + (y(u) / eb)² − 1 along the segment: ≤ 0 inside
    final dx = x1 - x0, dy = y1 - y0;
    final ia = 1 / (ea * ea), ib = 1 / (eb * eb);
    final alpha = dx * dx * ia + dy * dy * ib;
    final beta = 2 * (x0 * dx * ia + y0 * dy * ib);
    final gamma = x0 * x0 * ia + y0 * y0 * ib - 1;
    final q1 = alpha + beta + gamma;
    if ((gamma <= 0) != (q1 <= 0)) return 0; // one end inside, one outside
    double at(Offset p) => _ellipseDistanceLocal(ea, eb, p.dx, p.dy);
    if (gamma <= 0) return math.min(at(la), at(lb)); // inside: concave
    if (alpha > 0) {
      final u = -beta / (2 * alpha);
      if (u > 0 && u < 1 && alpha * u * u + beta * u + gamma <= 0) return 0;
    }
    // outside the convex region all along: the distance is convex in u
    return InkHitTest.minimize((u) => at(Offset.lerp(la, lb, u)!)).gap;
  }

  /// The distance from [p] to the centerline the painter strokes (w / 2 not taken
  /// off); +∞ when the shape has no drawable outline.
  static double outlineDistance(core.ShapeObject o, Offset p) {
    final g = shapeGeometryOf(o);
    if (g.oval != null) {
      final geometry = o.geometry;
      if (geometry is core.EllipseGeometry) {
        return ellipseDistance(geometry.ellipseFrame, p);
      }
    }
    return polylineDistance(g.centerline, p);
  }

  /// Is [p] inside the fill area of [o] (closed polyline: nonzero winding; ellipse:
  /// the closed ellipse)? false for open polylines and invalid geometry. The fill
  /// color is not looked at (callers check that the fill is drawn).
  static bool fillContains(core.ShapeObject o, Offset p) {
    switch (o.geometry) {
      case core.PolylineGeometry(:final points, :final closed):
        final pts = [
          for (final q in points)
            if (q.x.isFinite && q.y.isFinite) Offset(q.x, q.y),
        ];
        if (!closed || pts.length < 3) return false;
        return windingNumber(pts, p) != 0;
      case core.EllipseGeometry(:final ellipseFrame):
        final (x, y) = _local(ellipseFrame, p);
        final a = ellipseFrame.rect.width / 2, b = ellipseFrame.rect.height / 2;
        if (!(a > 0) || !(b > 0) || !x.isFinite || !y.isFinite) return false;
        final u = x / a, v = y / b;
        return u * u + v * v <= 1;
    }
  }

  /// Distance from [p] to the polyline [pts] (one point: to that point; empty: +∞).
  static double polylineDistance(List<Offset> pts, Offset p) {
    if (pts.isEmpty) return double.infinity;
    if (pts.length == 1) return (pts.single - p).distance;
    var best = double.infinity;
    for (var i = 0; i + 1 < pts.length; i++) {
      final a = pts[i], b = pts[i + 1];
      final d = InkHitTest.pointSegmentDistance(
        p.dx,
        p.dy,
        a.dx,
        a.dy,
        b.dx,
        b.dy,
      );
      if (d < best) best = d;
    }
    return best;
  }

  /// Distance from [p] to the filled polygon [poly] (0 inside, nonzero winding).
  static double polygonDistance(List<Offset> poly, Offset p) {
    if (poly.length >= 3 && windingNumber(poly, p) != 0) return 0;
    return polylineDistance([...poly, if (poly.isNotEmpty) poly.first], p);
  }

  /// The winding number of the closed polygon [poly] around [p] (points on an edge
  /// count as inside: ±1 or the side the edge's direction gives).
  static int windingNumber(List<Offset> poly, Offset p) {
    var w = 0;
    final n = poly.length;
    for (var i = 0; i < n; i++) {
      final a = poly[i], b = poly[(i + 1) % n];
      if (a.dy <= p.dy) {
        if (b.dy > p.dy && _cross(a, b, p) > 0) w++;
      } else if (b.dy <= p.dy && _cross(a, b, p) < 0) {
        w--;
      }
    }
    if (w == 0) {
      // the closed polygon includes its boundary
      for (var i = 0; i < n; i++) {
        final a = poly[i], b = poly[(i + 1) % n];
        if (InkHitTest.pointSegmentDistance(
              p.dx,
              p.dy,
              a.dx,
              a.dy,
              b.dx,
              b.dy,
            ) <=
            1e-9) {
          return 1;
        }
      }
    }
    return w;
  }

  static double _cross(Offset a, Offset b, Offset p) =>
      (b.dx - a.dx) * (p.dy - a.dy) - (p.dx - a.dx) * (b.dy - a.dy);

  /// [p] in the frame's unrotated coordinates relative to its center.
  static (double, double) _local(core.ElementFrame frame, Offset p) {
    final c = frame.center;
    final rot = frame.rotation.isFinite ? frame.rotation : 0.0;
    final cr = math.cos(rot), sr = math.sin(rot);
    final dx = p.dx - c.x, dy = p.dy - c.y;
    return (cr * dx + sr * dy, -sr * dx + cr * dy);
  }

  /// The exact distance from [p] to the ellipse inscribed in [frame] (rotated with it).
  /// A flat frame is a segment, a zero frame a point.
  static double ellipseDistance(core.ElementFrame frame, Offset p) {
    final (x, y) = _local(frame, p);
    return _ellipseDistanceLocal(
      frame.rect.width / 2,
      frame.rect.height / 2,
      x,
      y,
    );
  }

  /// The distance from (x, y) to the axis-aligned ellipse of semi-axes [a], [b] centered
  /// at the origin.
  static double _ellipseDistanceLocal(double a, double b, double x, double y) {
    if (!x.isFinite || !y.isFinite || !a.isFinite || !b.isFinite) {
      return double.infinity;
    }
    var y0 = x.abs(), y1 = y.abs();
    if (a < b) {
      (a, b) = (b, a);
      (y0, y1) = (y1, y0);
    }
    // now a ≥ b ≥ 0, the point in the first quadrant
    if (!(b > 0)) {
      // a segment [−a, a] on the major axis (or the center point)
      final dx = math.max(y0 - a, 0.0);
      return math.sqrt(dx * dx + y1 * y1);
    }
    return _distanceFirstQuadrant(a, b, y0, y1);
  }

  /// Eberly, "Distance from a Point to an Ellipse" (robust bisection): e0 ≥ e1 > 0,
  /// y0, y1 ≥ 0.
  static double _distanceFirstQuadrant(
    double e0,
    double e1,
    double y0,
    double y1,
  ) {
    if (y1 > 0) {
      if (y0 > 0) {
        final z0 = y0 / e0, z1 = y1 / e1;
        final g = z0 * z0 + z1 * z1 - 1;
        if (g == 0) return 0;
        final r0 = (e0 / e1) * (e0 / e1);
        final s = _root(r0, z0, z1, g);
        final x0 = r0 * y0 / (s + r0), x1 = y1 / (s + 1);
        final dx = x0 - y0, dy = x1 - y1;
        return math.sqrt(dx * dx + dy * dy);
      }
      return (y1 - e1).abs();
    }
    final numer0 = e0 * y0, denom0 = e0 * e0 - e1 * e1;
    if (numer0 < denom0) {
      final xde0 = numer0 / denom0;
      final x0 = e0 * xde0, x1 = e1 * math.sqrt(math.max(0.0, 1 - xde0 * xde0));
      final dx = x0 - y0;
      return math.sqrt(dx * dx + x1 * x1);
    }
    return (y0 - e0).abs();
  }

  static double _root(double r0, double z0, double z1, double g) {
    final n0 = r0 * z0;
    var s0 = z1 - 1;
    var s1 = g < 0 ? 0.0 : math.sqrt(n0 * n0 + z1 * z1) - 1;
    var s = 0.0;
    for (var i = 0; i < 160; i++) {
      s = (s0 + s1) / 2;
      if (s == s0 || s == s1) break;
      final ratio0 = n0 / (s + r0), ratio1 = z1 / (s + 1);
      final v = ratio0 * ratio0 + ratio1 * ratio1 - 1;
      if (v > 0) {
        s0 = s;
      } else if (v < 0) {
        s1 = s;
      } else {
        break;
      }
    }
    return s;
  }
}
