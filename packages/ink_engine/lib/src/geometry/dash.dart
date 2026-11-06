// lib/src/geometry/dash.dart — INTERNAL (m5-7/03-ink 6.5 D1–D5, 6.9.2).
//
// The shared dash splitter of the dashed pen (T29 — dashedStrokePieces, over
// the stored InkPoints) and the dashed / dotted shapes (T33 — dashPieces):
//   D1 arc length   the cumulative length of the centerline (PolylineMeasure)
//   D2 intervals    the pattern (pt: on, off, on, off…, phase 0 = the start of
//                   an `on` at the path start) gives the visible intervals
//                   [a_k, b_k]; an interval is cut at the path end
//   D2' pieces      with round caps of radius r: b − a ≥ 2r → the centerline
//                   piece [a + r, b − r] (a capsule whose visible length is
//                   b − a), otherwise a dot of radius r at (a + b) / 2
//   D3 piece points the ends interpolated on their segment, the points between
//                   them the original ones
//   D5 cap          more than InkTuning.dashMaxSegments intervals → the whole
//                   pattern is stretched by one factor until it fits
// Every piece point lies on the centerline, so a piece's capsule (or dot) is
// inside the union of disk(p, r) along it — the K-1 / K-6 argument of the
// round-cap outline is unchanged.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../model/ink_points.dart';
import '../tuning.dart';

/// A visible interval of a dash pattern along a path, in arc length (pt).
typedef DashInterval = ({double start, double end});

/// One dash of a centerline: a capsule centerline ([points], ≥ 2 points) or a dot
/// ([points] has one point).
typedef DashPiece = List<ui.Offset>;

/// D2 + D5: the visible intervals of [pattern] (on, off, on, off… in pt) along a path of
/// [length] pt. An odd-length pattern repeats twice (on/off alternate); a pattern that is
/// empty, negative, not finite or has no positive period → one interval [0, length] (solid).
/// A zero-length path → one interval [0, 0].
List<DashInterval> dashIntervals(
  double length,
  List<double> pattern, {
  int maxSegments = InkTuning.dashMaxSegments,
}) {
  if (!(length > 0) || !length.isFinite) {
    return [(start: 0, end: 0)];
  }
  final p = pattern.length.isOdd ? [...pattern, ...pattern] : pattern;
  var period = 0.0;
  var valid = p.isNotEmpty;
  for (final v in p) {
    if (!v.isFinite || v < 0) valid = false;
    period += v;
  }
  if (!valid || !(period > 0) || !period.isFinite) {
    return [(start: 0, end: length)];
  }
  final onPerPeriod = p.length ~/ 2;
  final cap = maxSegments < 1 ? 1 : maxSegments;
  // D5: stretch so that at most [cap] intervals start inside the path
  var scale = 1.0;
  final estimate = (length / period).ceil() * onPerPeriod;
  if (estimate > cap) scale = estimate / cap;
  while (true) {
    final out = <DashInterval>[];
    var s = 0.0;
    var i = 0;
    var tooMany = false;
    do {
      final on = p[i] * scale, off = p[i + 1] * scale;
      final end = s + on;
      out.add((start: s, end: end < length ? end : length));
      if (out.length > cap) {
        tooMany = true;
        break;
      }
      s = end + off;
      i = (i + 2) % p.length;
    } while (s < length);
    if (!tooMany) return out;
    scale *= 1.0 + 1.0 / cap + 1e-9;
  }
}

/// D1: arc length along a polyline (non-finite points are skipped).
final class PolylineMeasure {
  PolylineMeasure(List<ui.Offset> points)
    : points = [
        for (final p in points)
          if (p.isFinite) p,
      ] {
    final n = this.points.length;
    _cum = Float64List(n < 1 ? 1 : n);
    for (var i = 1; i < n; i++) {
      _cum[i] = _cum[i - 1] + (this.points[i] - this.points[i - 1]).distance;
    }
  }

  final List<ui.Offset> points;
  late final Float64List _cum;

  /// The total length (0 for fewer than two points).
  double get length => points.length < 2 ? 0 : _cum[points.length - 1];

  /// Arc length at point [i].
  double lengthAt(int i) => _cum[i];

  /// The point at arc length [s] (clamped to the path).
  ui.Offset at(double s) {
    final n = points.length;
    if (n == 0) return ui.Offset.zero;
    if (n == 1 || s <= 0) return points.first;
    if (s >= length) return points.last;
    final i = _segmentOf(s);
    final a = _cum[i], b = _cum[i + 1];
    final t = b > a ? (s - a) / (b - a) : 0.0;
    return ui.Offset.lerp(points[i], points[i + 1], t)!;
  }

  /// D3: the centerline from arc length [a] to [b] (a ≤ b): the interpolated ends and the
  /// original points between them.
  List<ui.Offset> between(double a, double b) {
    if (points.isEmpty) return const [];
    final start = at(a), end = at(b);
    final out = <ui.Offset>[start];
    for (var i = 0; i < points.length; i++) {
      final c = _cum[i];
      if (c > a && c < b) out.add(points[i]);
    }
    out.add(end);
    return out;
  }

  /// The segment index i with cum[i] ≤ s < cum[i + 1] (binary search).
  int _segmentOf(double s) {
    var lo = 0, hi = points.length - 2;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (_cum[mid] <= s) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }
}

/// D2' + D3: the dash pieces of [centerline] for [pattern] (pt) with round caps of radius
/// [radius]: capsule centerlines (≥ 2 points) and dots (one point).
List<DashPiece> dashPieces(
  PolylineMeasure centerline,
  List<double> pattern, {
  required double radius,
  int maxSegments = InkTuning.dashMaxSegments,
}) {
  if (centerline.points.isEmpty) return const [];
  final r = radius.isFinite && radius > 0 ? radius : 0.0;
  final out = <DashPiece>[];
  for (final iv in dashIntervals(
    centerline.length,
    pattern,
    maxSegments: maxSegments,
  )) {
    if (iv.end - iv.start >= 2 * r && iv.end - iv.start > 0) {
      out.add(centerline.between(iv.start + r, iv.end - r));
    } else {
      out.add([centerline.at((iv.start + iv.end) / 2)]);
    }
  }
  return out;
}

/// D2 with a lead (live dashes, 6.5 'live'): the visible intervals along a path of
/// [length] pt whose first `on` starts at arc length [lead] ≥ 0 (nothing before it);
/// none when [lead] ≥ [length]. [lead] 0 is [dashIntervals].
List<DashInterval> dashIntervalsAfter(
  double length,
  List<double> pattern, {
  double lead = 0,
  int maxSegments = InkTuning.dashMaxSegments,
}) {
  if (!(lead > 0)) {
    return dashIntervals(length, pattern, maxSegments: maxSegments);
  }
  if (!(lead < length)) return const [];
  return [
    for (final iv in dashIntervals(
      length - lead,
      pattern,
      maxSegments: maxSegments,
    ))
      (start: iv.start + lead, end: iv.end + lead),
  ];
}

/// D3 of a stroke: the fractional point index at arc length [s] along the centerline
/// whose cumulative lengths are [cum] (InkPoints.cumulativeLengths) — the index
/// InkPoints.lerpAt takes. Clamped to [0, n − 1].
double fractionalIndexAt(Float64List cum, double s) {
  final n = cum.length;
  if (n < 2 || !(s > 0)) return 0;
  if (s >= cum[n - 1]) return (n - 1).toDouble();
  var lo = 0, hi = n - 2;
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2;
    if (cum[mid] <= s) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  final a = cum[lo], b = cum[lo + 1];
  return b > a ? lo + (s - a) / (b - a) : lo.toDouble();
}

/// D2' + D3 of a stroke (6.5, the dashed pen): the dash pieces of [points] for
/// [pattern] (pt — style.dashPattern × width) with round caps of [radius]. A piece is
/// the centerline [a + r, b − r] of a visible interval — its ends InkPoints.lerpAt at
/// the fractional index of that arc length (every channel interpolated, like the
/// partial eraser's cut points), the stored points strictly between them — or, when
/// b − a < 2r, the one point at (a + b) / 2 (a dot). [lead]: see [dashIntervalsAfter].
List<InkPoints> dashedStrokePieces(
  InkPoints points,
  List<double> pattern, {
  required double radius,
  double lead = 0,
  int maxSegments = InkTuning.dashMaxSegments,
}) {
  if (points.isEmpty) return const [];
  final cum = points.cumulativeLengths();
  final length = cum[cum.length - 1];
  final r = radius.isFinite && radius > 0 ? radius : 0.0;
  final out = <InkPoints>[];
  for (final iv in dashIntervalsAfter(
    length,
    pattern,
    lead: lead,
    maxSegments: maxSegments,
  )) {
    if (iv.end - iv.start >= 2 * r && iv.end - iv.start > 0) {
      out.add(_between(points, cum, iv.start + r, iv.end - r));
    } else {
      final at = fractionalIndexAt(cum, (iv.start + iv.end) / 2);
      final data = Float32List(InkPoints.stride);
      _writePoint(data, 0, points, at);
      out.add(InkPoints.fromRaw(data));
    }
  }
  return out;
}

/// The centerline from arc length [a] to [b] (a ≤ b): lerpAt ends, stored points between.
InkPoints _between(InkPoints points, Float64List cum, double a, double b) {
  final ia = fractionalIndexAt(cum, a), ib = fractionalIndexAt(cum, b);
  final inner = <int>[
    for (var i = ia.floor() + 1; i < ib.ceil() && i < points.length; i++)
      if (cum[i] > a && cum[i] < b) i,
  ];
  const stride = InkPoints.stride;
  final data = Float32List((inner.length + 2) * stride);
  _writePoint(data, 0, points, ia);
  for (var k = 0; k < inner.length; k++) {
    data.setRange(
      (k + 1) * stride,
      (k + 2) * stride,
      points.raw,
      inner[k] * stride,
    );
  }
  _writePoint(data, inner.length + 1, points, ib);
  return InkPoints.fromRaw(data);
}

void _writePoint(Float32List data, int slot, InkPoints points, double at) {
  final p = points.lerpAt(at);
  final o = slot * InkPoints.stride;
  data[o] = p.x;
  data[o + 1] = p.y;
  data[o + 2] = p.widthQ;
  data[o + 3] = p.tilt;
  data[o + 4] = p.azimuth;
  data[o + 5] = p.t;
}

/// The number of segments a dashed / dotted ellipse is sampled with (6.9.2):
/// clamp(⌈perimeter / 2 pt⌉, 32, 256), Ramanujan's perimeter of semi-axes [a], [b].
int ellipseDashSegments(double a, double b) {
  final x = a.abs(), y = b.abs();
  if (!x.isFinite || !y.isFinite) return 32;
  final perimeter =
      math.pi * (3 * (x + y) - math.sqrt((3 * x + y) * (x + 3 * y)));
  final n = (perimeter / 2).ceil();
  return n < 32 ? 32 : (n > 256 ? 256 : n);
}
