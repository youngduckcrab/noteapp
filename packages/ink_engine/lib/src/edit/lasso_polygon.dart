// lib/src/edit/lasso_polygon.dart — INTERNAL (03-ink 6.21 L2–L5, INK T17).
//
// The lasso inclusion rule is a CONTRACT (LassoOptions doc comment, 4.7):
//  * L2: the collected path is closed end → start and simplified with RDP
//    (tolerance simplifyPx / viewScale pt). Fewer than 3 vertices or
//    ∫|winding| dA < minAreaPt2 (= shoelace |area| for simple polygons; a
//    figure 8 adds its loops) → degenerate → no selection (EDITOR treats it
//    as a tap);
//  * L3: inside = NONZERO winding number. A y-band index (band height
//    max(InkTuning.lassoBandMinPt, polygon height / 64)) lists, per band, the
//    edges whose y range meets the band, so a point only tests the edges of
//    its own band;
//  * L5: a stroke is selected iff Σ(length of its centerline segments whose
//    MIDPOINT is inside) / centerline length >= coverage; a dot (one point or
//    zero length) iff its point is inside.
//
// ∫|winding| dA (∫|w| dA below) equals the shoelace |area| whenever the
// winding number keeps one sign (every simple polygon, a loop wound twice the
// same way) and adds the loops of a figure 8 instead of cancelling them — a
// symmetric figure 8 has a shoelace area of 0 but must select both loops (the
// same contract comment).
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:meta/meta.dart';

import '../geometry/rdp.dart';
import '../model/ink_stroke.dart';
import '../tuning.dart';

/// The closed lasso polygon (page pt) with its y-band edge index.
@internal
final class LassoPolygon {
  LassoPolygon._(this._xs, this._ys) {
    final n = _xs.length;
    if (n == 0) {
      _yBands = _xBands = _Bands.empty();
      return;
    }
    var left = _xs[0], right = _xs[0], top = _ys[0], bottom = _ys[0];
    var area2 = 0.0;
    for (var i = 0; i < n; i++) {
      final x = _xs[i], y = _ys[i];
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
      final j = i + 1 == n ? 0 : i + 1;
      area2 += x * _ys[j] - _xs[j] * y;
    }
    _left = left;
    _top = top;
    _right = right;
    _bottom = bottom;
    _signedArea = area2 / 2;

    // L3: y bands (the ray of a point runs to +x) and, T22 B6, x bands (the
    // same test on the coordinates rotated by −90°, (u, v) = (y, −x): the
    // ray runs to +y). A point uses whichever of its two bands holds fewer
    // edges — the winding number does not depend on the ray.
    _yBands = _Bands(_xs, _ys, top, bottom);
    final us = Float64List(n), vs = Float64List(n);
    for (var i = 0; i < n; i++) {
      us[i] = _ys[i];
      vs[i] = -_xs[i];
    }
    _xBands = _Bands(us, vs, -right, -left);
  }

  /// [vertices] as given (no simplification): non-finite points, consecutive
  /// duplicates and a closing copy of the first vertex are dropped.
  factory LassoPolygon.of(List<Offset> vertices) =>
      LassoPolygon.simplified(vertices, tolerancePt: 0);

  /// L2: [path] closed end → start, simplified with RDP of [tolerancePt]
  /// (none when it is not > 0 and finite). Non-finite points, consecutive
  /// duplicates and a closing copy of the first point are dropped first.
  factory LassoPolygon.simplified(
    List<Offset> path, {
    required double tolerancePt,
  }) {
    final pts = <Offset>[];
    for (final p in path) {
      if (!p.isFinite) continue;
      if (pts.isNotEmpty && pts.last == p) continue;
      pts.add(p);
    }
    while (pts.length > 1 && pts.last == pts.first) {
      pts.removeLast();
    }
    var kept = pts;
    if (tolerancePt > 0 && tolerancePt.isFinite && pts.length > 2) {
      final keep = List<bool>.filled(pts.length, false);
      rdpMark(keep, 0, pts.length - 1, (a, b, i) {
        final p = pts[i], pa = pts[a], pb = pts[b];
        return segmentDistance(p.dx, p.dy, pa.dx, pa.dy, pb.dx, pb.dy) /
            tolerancePt;
      });
      kept = [
        for (var i = 0; i < pts.length; i++)
          if (keep[i]) pts[i],
      ];
    }
    final xs = Float64List(kept.length), ys = Float64List(kept.length);
    for (var i = 0; i < kept.length; i++) {
      xs[i] = kept[i].dx;
      ys[i] = kept[i].dy;
    }
    return LassoPolygon._(xs, ys);
  }

  final Float64List _xs;
  final Float64List _ys;
  double _left = 0, _top = 0, _right = 0, _bottom = 0;
  double _signedArea = 0;
  late final _Bands _yBands;
  late final _Bands _xBands;

  int get vertexCount => _xs.length;
  Offset vertex(int i) => Offset(_xs[i], _ys[i]);
  List<Offset> get vertices => [
    for (var i = 0; i < _xs.length; i++) Offset(_xs[i], _ys[i]),
  ];

  /// Bounds of the vertices (Rect.zero when empty).
  Rect get bounds => Rect.fromLTRB(_left, _top, _right, _bottom);

  /// Shoelace area (sign = orientation) = ∫w dA.
  double get signedArea => _signedArea;

  /// Height of one y band (L3) and the number of bands.
  double get bandHeight => _yBands.height;
  int get bandCount => _yBands.count;

  /// Number of edges registered in y band [b] (diagnostics, tests).
  @visibleForTesting
  int edgesInBand(int b) => _yBands.edgesIn(b);

  /// L2: fewer than 3 vertices or ∫|w| dA < [minAreaPt2].
  bool isDegenerate(double minAreaPt2) {
    if (_xs.length < 3) return true;
    // ∫|w| dA ≥ |∫w dA|: a large shoelace area settles it.
    if (_signedArea.abs() >= minAreaPt2) return false;
    return absWindingArea(stopAt: minAreaPt2) < minAreaPt2;
  }

  /// ∫|w| dA (pt²), exact up to rounding: the plane is cut into horizontal
  /// slabs at the y of every vertex and every edge crossing; inside one slab
  /// the same edges cross it in the same x order, so the covered length is
  /// linear in y and its value at the slab middle gives the slab's area.
  /// Stops early once the sum reaches [stopAt].
  double absWindingArea({double stopAt = double.infinity}) {
    final n = _xs.length;
    if (n < 3) return 0;
    final cuts = <double>[for (var i = 0; i < n; i++) _ys[i]];
    for (var i = 0; i < n; i++) {
      final i1 = i + 1 == n ? 0 : i + 1;
      final ax = _xs[i], ay = _ys[i];
      final rx = _xs[i1] - ax, ry = _ys[i1] - ay;
      for (var j = i + 1; j < n; j++) {
        final j1 = j + 1 == n ? 0 : j + 1;
        final cx = _xs[j], cy = _ys[j];
        final sx = _xs[j1] - cx, sy = _ys[j1] - cy;
        final den = rx * sy - ry * sx;
        if (den == 0) continue; // parallel (or a zero-length edge)
        final t = ((cx - ax) * sy - (cy - ay) * sx) / den;
        final u = ((cx - ax) * ry - (cy - ay) * rx) / den;
        if (t > 0 && t < 1 && u > 0 && u < 1) cuts.add(ay + t * ry);
      }
    }
    cuts.sort();
    var area = 0.0;
    final xs = <double>[];
    final dirs = <int>[];
    final order = <int>[];
    for (var k = 0; k + 1 < cuts.length; k++) {
      final y0 = cuts[k], y1 = cuts[k + 1];
      if (!(y1 > y0)) continue;
      final ym = (y0 + y1) / 2;
      xs.clear();
      dirs.clear();
      for (var i = 0; i < n; i++) {
        final i1 = i + 1 == n ? 0 : i + 1;
        final ay = _ys[i], by = _ys[i1];
        if (ay < ym && by > ym || ay > ym && by < ym) {
          final ax = _xs[i];
          xs.add(ax + (ym - ay) * (_xs[i1] - ax) / (by - ay));
          dirs.add(by > ay ? 1 : -1);
        }
      }
      order
        ..clear()
        ..addAll([for (var i = 0; i < xs.length; i++) i]);
      order.sort((a, b) => xs[a].compareTo(xs[b]));
      var w = 0;
      var length = 0.0;
      var prevX = 0.0;
      for (final i in order) {
        if (w != 0) length += w.abs() * (xs[i] - prevX);
        w += dirs[i];
        prevX = xs[i];
      }
      area += length * (y1 - y0);
      if (area >= stopAt) return area;
    }
    return area;
  }

  /// L3: winding number of (x, y) — only the edges of one band are tested:
  /// its y band or, when that holds more edges, its x band (T22 B6) (0
  /// outside the bounds).
  int windingNumber(double x, double y) {
    if (_xs.isEmpty) return 0;
    if (!(y >= _top && y <= _bottom && x >= _left && x <= _right)) return 0;
    final yb = _yBands.bandOf(y), xb = _xBands.bandOf(-x);
    return _yBands.edgesIn(yb) <= _xBands.edgesIn(xb)
        ? _yBands.windingAt(yb, x, y)
        : _xBands.windingAt(xb, y, -x);
  }

  /// Nonzero rule.
  bool contains(double x, double y) => windingNumber(x, y) != 0;

  /// [r] (closed) against the polygon: [rectInside] when every point of r
  /// has a nonzero winding number, [rectOutside] when none has, [rectMixed]
  /// when an edge meets r. With no edge meeting r the winding number is the
  /// same all over r, so one point decides. Only the edges of the y bands r
  /// spans are tested (L3).
  int classifyRect(Rect r) => classifyLTRB(r.left, r.top, r.right, r.bottom);

  /// [classifyRect] of Rect.fromLTRB([l], [t], [r], [b]).
  int classifyLTRB(double l, double t, double r, double b) {
    if (_xs.isEmpty) return rectOutside;
    if (r < _left || l > _right || b < _top || t > _bottom) return rectOutside;
    final bands = _yBands;
    final b0 = bands.bandOf(math.max(t, _top));
    final b1 = bands.bandOf(math.min(b, _bottom));
    for (var band = b0; band <= b1; band++) {
      for (var k = bands.start[band]; k < bands.start[band + 1]; k++) {
        if (bands.maxU[k] < l) break; // the rest of the band ends left of r
        if (_segmentMeetsRect(
          bands.au[k],
          bands.av[k],
          bands.bu[k],
          bands.bv[k],
          l,
          t,
          r,
          b,
        )) {
          return rectMixed;
        }
      }
    }
    return windingNumber((l + r) / 2, (t + b) / 2) != 0
        ? rectInside
        : rectOutside;
  }

  static const int rectOutside = 0;
  static const int rectInside = 1;
  static const int rectMixed = -1;

  /// Segment a → b vs the closed rectangle [r] (separating axes: x, y and the
  /// segment normal; touching counts as meeting).
  static bool _segmentMeetsRect(
    double ax,
    double ay,
    double bx,
    double by,
    double l,
    double t,
    double r,
    double b,
  ) {
    if ((ax > bx ? ax : bx) < l ||
        (ax < bx ? ax : bx) > r ||
        (ay > by ? ay : by) < t ||
        (ay < by ? ay : by) > b) {
      return false;
    }
    final dx = bx - ax, dy = by - ay;
    final s0 = dx * (t - ay) - dy * (l - ax);
    final s1 = dx * (t - ay) - dy * (r - ax);
    final s2 = dx * (b - ay) - dy * (r - ax);
    final s3 = dx * (b - ay) - dy * (l - ax);
    if (s0 > 0 && s1 > 0 && s2 > 0 && s3 > 0) return false;
    if (s0 < 0 && s1 < 0 && s2 < 0 && s3 < 0) return false;
    return true;
  }
}

/// L5 — the contract's inclusion rule.
@internal
abstract final class LassoSelector {
  /// Σ(length of the centerline segments of [stroke] whose midpoint is inside
  /// [polygon]) / centerline length; a dot → 1 when its point is inside,
  /// else 0; an empty stroke → 0.
  static double coverageOf(InkStroke stroke, LassoPolygon polygon) {
    final p = stroke.points;
    if (p.isEmpty) return 0;
    if (stroke.isDot) return polygon.contains(p.x(0), p.y(0)) ? 1 : 0;
    var total = 0.0, inside = 0.0;
    for (var i = 1; i < p.length; i++) {
      final x0 = p.x(i - 1), y0 = p.y(i - 1), x1 = p.x(i), y1 = p.y(i);
      final dx = x1 - x0, dy = y1 - y0;
      final len = math.sqrt(dx * dx + dy * dy);
      total += len;
      if (len > 0 && polygon.contains((x0 + x1) / 2, (y0 + y1) / 2)) {
        inside += len;
      }
    }
    return inside / total;
  }

  /// coverageOf(stroke, polygon) >= [coverage] (stops as soon as the inside
  /// share reaches [coverage]; the inside sum only grows, so the answer is
  /// the same).
  ///
  /// T22 B6: the segments are taken [_run] at a time; when the bounds of a
  /// run's points are wholly inside / outside the polygon (no edge meets
  /// them) every midpoint of the run is too, so no point is tested. The
  /// lengths are still added one by one in order — the same sums as testing
  /// every midpoint. It also stops with false once the rest of the stroke
  /// could not reach [coverage] any more.
  static bool selects(InkStroke stroke, LassoPolygon polygon, double coverage) {
    final p = stroke.points;
    if (p.isEmpty) return false;
    if (stroke.isDot) return polygon.contains(p.x(0), p.y(0));
    switch (polygon.classifyRect(stroke.bounds)) {
      case LassoPolygon.rectInside:
        return 1 >= coverage;
      case LassoPolygon.rectOutside:
        return 0 >= coverage;
    }
    final total = p.arcLength();
    final n = p.length;
    final need = coverage * total - 1e-9 * total;
    var inside = 0.0, done = 0.0;
    for (var start = 1; start < n; start += _run) {
      final end = math.min(n, start + _run);
      var minX = p.x(start - 1), maxX = minX;
      var minY = p.y(start - 1), maxY = minY;
      for (var i = start; i < end; i++) {
        final x = p.x(i), y = p.y(i);
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
      final side = polygon.classifyLTRB(minX, minY, maxX, maxY);
      for (var i = start; i < end; i++) {
        final x0 = p.x(i - 1), y0 = p.y(i - 1), x1 = p.x(i), y1 = p.y(i);
        final dx = x1 - x0, dy = y1 - y0;
        final len = math.sqrt(dx * dx + dy * dy);
        done += len;
        if (len > 0 &&
            side != LassoPolygon.rectOutside &&
            (side == LassoPolygon.rectInside ||
                polygon.contains((x0 + x1) / 2, (y0 + y1) / 2))) {
          inside += len;
          if (inside / total >= coverage) return true;
        }
      }
      if (inside + (total - done) < need) return false;
    }
    return inside / total >= coverage;
  }

  /// Segments per bounds test in [selects].
  static const int _run = 16;
}

/// The winding contribution of edge a → b for the point (px, py): +1 for an
/// upward crossing with the point on its left, −1 for a downward crossing
/// with the point on its right (Sunday's winding-number test; the ray runs
/// to +x).
int _crossing(
  double ax,
  double ay,
  double bx,
  double by,
  double px,
  double py,
) {
  final cross = (bx - ax) * (py - ay) - (px - ax) * (by - ay);
  if (ay <= py) {
    if (by > py && cross > 0) return 1;
  } else {
    if (by <= py && cross < 0) return -1;
  }
  return 0;
}

/// L3 band index of the closed polygon (us[i], vs[i]): bands of height
/// max(lassoBandMinPt, extent / 64) along v; CSR — the edges of band b are
/// slots start[b] .. start[b + 1], each slot holding the edge's end points
/// (au, av) → (bu, bv) and its larger u, sorted by it (largest first) so a
/// ray to +u stops at the first edge that ends before the point.
final class _Bands {
  _Bands(Float64List us, Float64List vs, this.origin, double far)
    : height = math.max(InkTuning.lassoBandMinPt, (far - origin) / 64) {
    final n = us.length;
    count = math.max(1, ((far - origin) / height).ceil());
    final s = Int32List(count + 1);
    for (var i = 0; i < n; i++) {
      final j = i + 1 == n ? 0 : i + 1;
      final b0 = bandOf(math.min(vs[i], vs[j]));
      final b1 = bandOf(math.max(vs[i], vs[j]));
      for (var b = b0; b <= b1; b++) {
        s[b + 1]++;
      }
    }
    for (var b = 0; b < count; b++) {
      s[b + 1] += s[b];
    }
    final edges = Int32List(s[count]);
    final fill = Int32List.fromList(s);
    for (var i = 0; i < n; i++) {
      final j = i + 1 == n ? 0 : i + 1;
      final b0 = bandOf(math.min(vs[i], vs[j]));
      final b1 = bandOf(math.max(vs[i], vs[j]));
      for (var b = b0; b <= b1; b++) {
        edges[fill[b]++] = i;
      }
    }
    double maxUOf(int i) => math.max(us[i], us[i + 1 == n ? 0 : i + 1]);
    for (var b = 0; b < count; b++) {
      final band = edges.sublist(s[b], s[b + 1])
        ..sort((p, q) => maxUOf(q).compareTo(maxUOf(p)));
      edges.setRange(s[b], s[b + 1], band);
    }
    final slots = edges.length;
    au = Float64List(slots);
    av = Float64List(slots);
    bu = Float64List(slots);
    bv = Float64List(slots);
    maxU = Float64List(slots);
    for (var k = 0; k < slots; k++) {
      final i = edges[k];
      final j = i + 1 == n ? 0 : i + 1;
      au[k] = us[i];
      av[k] = vs[i];
      bu[k] = us[j];
      bv[k] = vs[j];
      maxU[k] = math.max(us[i], us[j]);
    }
    start = s;
  }

  _Bands.empty()
    : origin = 0,
      height = InkTuning.lassoBandMinPt,
      count = 1,
      start = Int32List(2),
      au = Float64List(0),
      av = Float64List(0),
      bu = Float64List(0),
      bv = Float64List(0),
      maxU = Float64List(0);

  final double origin;
  final double height;
  late final int count;
  late final Int32List start;
  late final Float64List au, av, bu, bv, maxU;

  int bandOf(double v) {
    final b = ((v - origin) / height).floor();
    if (b < 0) return 0;
    if (b >= count) return count - 1;
    return b;
  }

  int edgesIn(int b) => start[b + 1] - start[b];

  /// Σ Sunday crossings of band [b]'s edges for (pu, pv).
  int windingAt(int b, double pu, double pv) {
    var wn = 0;
    for (var k = start[b]; k < start[b + 1]; k++) {
      // an edge wholly before pu never crosses the ray to +u
      if (maxU[k] < pu) break;
      wn += _crossing(au[k], av[k], bu[k], bv[k], pu, pv);
    }
    return wn;
  }
}
