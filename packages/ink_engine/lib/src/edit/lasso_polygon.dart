// lib/src/edit/lasso_polygon.dart — INTERNAL (03-ink 6.21 L2–L5, INK T17).
//
// The lasso inclusion rule is a CONTRACT (LassoOptions doc comment, 4.7):
//  * L2: the collected path is closed end → start and simplified with RDP
//    (tolerance simplifyPx / viewScale pt). Fewer than 3 vertices or
//    |area| < minAreaPt2 → degenerate → no selection (EDITOR treats it as a
//    tap);
//  * L3: inside = NONZERO winding number. A y-band index (band height
//    max(InkTuning.lassoBandMinPt, polygon height / 64)) lists, per band, the
//    edges whose y range meets the band, so a point only tests the edges of
//    its own band;
//  * L5: a stroke is selected iff Σ(length of its centerline segments whose
//    MIDPOINT is inside) / centerline length >= coverage; a dot (one point or
//    zero length) iff its point is inside.
//
// |area| is the winding-weighted area ∫|w| dA. It equals the shoelace |area|
// whenever the winding number keeps one sign (every simple polygon, a loop
// wound twice the same way) and adds the loops of a figure 8 instead of
// cancelling them — a symmetric figure 8 has a shoelace area of 0 but must
// select both loops (the same contract comment).
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
      _bandHeight = InkTuning.lassoBandMinPt;
      _bandCount = 1;
      _bandStart = Int32List(2);
      _bandEdges = Int32List(0);
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

    final height = bottom - top;
    _bandHeight = math.max(InkTuning.lassoBandMinPt, height / 64);
    _bandCount = math.max(1, (height / _bandHeight).ceil());
    // CSR layout: the edges of band b are _bandEdges[_bandStart[b] ..
    // _bandStart[b + 1]).
    final start = Int32List(_bandCount + 1);
    for (var i = 0; i < n; i++) {
      final j = i + 1 == n ? 0 : i + 1;
      final b0 = _bandOf(math.min(_ys[i], _ys[j]));
      final b1 = _bandOf(math.max(_ys[i], _ys[j]));
      for (var b = b0; b <= b1; b++) {
        start[b + 1]++;
      }
    }
    for (var b = 0; b < _bandCount; b++) {
      start[b + 1] += start[b];
    }
    final edges = Int32List(start[_bandCount]);
    final fill = Int32List.fromList(start);
    for (var i = 0; i < n; i++) {
      final j = i + 1 == n ? 0 : i + 1;
      final b0 = _bandOf(math.min(_ys[i], _ys[j]));
      final b1 = _bandOf(math.max(_ys[i], _ys[j]));
      for (var b = b0; b <= b1; b++) {
        edges[fill[b]++] = i;
      }
    }
    _bandStart = start;
    _bandEdges = edges;
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
  late final double _bandHeight;
  late final int _bandCount;
  late final Int32List _bandStart;
  late final Int32List _bandEdges;

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
  double get bandHeight => _bandHeight;
  int get bandCount => _bandCount;

  /// Number of edges registered in band [b] (diagnostics, tests).
  @visibleForTesting
  int edgesInBand(int b) => _bandStart[b + 1] - _bandStart[b];

  int _bandOf(double y) {
    final b = ((y - _top) / _bandHeight).floor();
    if (b < 0) return 0;
    if (b >= _bandCount) return _bandCount - 1;
    return b;
  }

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

  /// L3: winding number of (x, y) — only the edges of its y band are tested
  /// (0 outside the bounds).
  int windingNumber(double x, double y) {
    if (_xs.isEmpty) return 0;
    if (!(y >= _top && y <= _bottom && x >= _left && x <= _right)) return 0;
    final n = _xs.length;
    final b = _bandOf(y);
    var wn = 0;
    for (var k = _bandStart[b]; k < _bandStart[b + 1]; k++) {
      final i = _bandEdges[k];
      final j = i + 1 == n ? 0 : i + 1;
      wn += _crossing(_xs[i], _ys[i], _xs[j], _ys[j], x, y);
    }
    return wn;
  }

  /// Nonzero rule.
  bool contains(double x, double y) => windingNumber(x, y) != 0;

  /// The winding contribution of edge a → b for the point (px, py): +1 for an
  /// upward crossing with the point on its left, −1 for a downward crossing
  /// with the point on its right (Sunday's winding-number test).
  static int _crossing(
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
  static bool selects(InkStroke stroke, LassoPolygon polygon, double coverage) {
    final p = stroke.points;
    if (p.isEmpty) return false;
    if (stroke.isDot) return polygon.contains(p.x(0), p.y(0));
    final total = p.arcLength();
    var inside = 0.0;
    for (var i = 1; i < p.length; i++) {
      final x0 = p.x(i - 1), y0 = p.y(i - 1), x1 = p.x(i), y1 = p.y(i);
      final dx = x1 - x0, dy = y1 - y0;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len > 0 && polygon.contains((x0 + x1) / 2, (y0 + y1) / 2)) {
        inside += len;
        if (inside / total >= coverage) return true;
      }
    }
    return inside / total >= coverage;
  }
}
