// lib/src/stroke/centerline.dart — INTERNAL (not exported): 03-ink 6.3 (merge),
// 6.7 F2 (subdivide), F3 (hooks), F4 (dot).
//
// The centerline of a stroke being finished is a list of mutable
// [CenterPoint]s: position (page pt), width factor f (K1–K4 at input time,
// multiplied by the K5 taper at finish), tilt, azimuth and t (ms since pen
// down). F8 packs them into the interleaved [x, y, widthQ, tilt, azimuth, t]
// data (stroke_builder.dart).
import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../input/ink_sample.dart';
import '../tuning.dart';

/// One centerline point (page pt). Mutable: the finish steps adjust it in place.
final class CenterPoint {
  CenterPoint(
    this.x,
    this.y, {
    this.factor = 1,
    this.tilt = 0,
    this.azimuth = 0,
    this.t = 0,
  });

  double x;
  double y;

  /// Width factor f (> 0). widthQ = clamp(f / core.kMaxWidthFactor, 0, 1) (K6).
  double factor;
  double tilt;
  double azimuth;

  /// ms since pen down.
  double t;

  Offset get position => Offset(x, y);

  CenterPoint copy() =>
      CenterPoint(x, y, factor: factor, tilt: tilt, azimuth: azimuth, t: t);

  /// Linear interpolation of every channel at [u] in [0, 1] (azimuth on the
  /// shortest arc). [x] / [y] replace the interpolated position (curves).
  static CenterPoint lerp(
    CenterPoint a,
    CenterPoint b,
    double u, {
    double? x,
    double? y,
  }) => CenterPoint(
    x ?? a.x + (b.x - a.x) * u,
    y ?? a.y + (b.y - a.y) * u,
    factor: a.factor + (b.factor - a.factor) * u,
    tilt: a.tilt + (b.tilt - a.tilt) * u,
    azimuth: lerpAngle(a.azimuth, b.azimuth, u),
    t: a.t + (b.t - a.t) * u,
  );

  @override
  String toString() => 'CenterPoint($x, $y, f: $factor, t: $t)';
}

/// Angle in (−π, π].
double normalizeAngle(double a) {
  if (!a.isFinite) return 0;
  var r = a % (2 * math.pi); // [0, 2π)
  if (r > math.pi) r -= 2 * math.pi;
  return r;
}

/// Interpolates two angles on the shortest arc; the result is in (−π, π].
double lerpAngle(double a, double b, double u) {
  final d = normalizeAngle(b - a);
  return normalizeAngle(a + d * u);
}

// --- 6.3 step 2: duplicate merge ---------------------------------------------

/// 6.3 rule 2: [next] is a duplicate of [prev] when it is closer than
/// minSampleDistancePx screen px (= 0.15 / viewScale pt; viewScale has no
/// devicePixelRatio, contract 7.2.15 v1.1) AND less than mergeWindowUs later.
/// The builder then drops its position and keeps only its pressure.
bool isDuplicateSample(InkSample prev, InkSample next, double viewScale) =>
    (next.position - prev.position).distance * viewScale <
        InkTuning.minSampleDistancePx &&
    next.timeUs - prev.timeUs < InkTuning.mergeWindowUs;

// --- arc length ----------------------------------------------------------------

/// Cumulative polyline lengths: [0] = 0, [i] = length up to point i.
List<double> cumulativeLengthsOf(List<CenterPoint> pts) {
  final out = List<double>.filled(pts.length, 0);
  for (var i = 1; i < pts.length; i++) {
    final dx = pts[i].x - pts[i - 1].x, dy = pts[i].y - pts[i - 1].y;
    out[i] = out[i - 1] + math.sqrt(dx * dx + dy * dy);
  }
  return out;
}

/// Polyline length.
double lengthOf(List<CenterPoint> pts) {
  var s = 0.0;
  for (var i = 1; i < pts.length; i++) {
    final dx = pts[i].x - pts[i - 1].x, dy = pts[i].y - pts[i - 1].y;
    s += math.sqrt(dx * dx + dy * dy);
  }
  return s;
}

/// The point at arc length [s] (clamped), every channel interpolated.
/// [cum] = cumulativeLengthsOf(pts).
CenterPoint pointAtLength(List<CenterPoint> pts, List<double> cum, double s) {
  if (s <= 0) return pts.first.copy();
  if (s >= cum.last) return pts.last.copy();
  var lo = 0, hi = cum.length - 1; // cum[lo] <= s < cum[hi]
  while (hi - lo > 1) {
    final mid = (lo + hi) ~/ 2;
    if (cum[mid] <= s) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  final span = cum[hi] - cum[lo];
  final u = span > 0 ? (s - cum[lo]) / span : 0.0;
  return CenterPoint.lerp(pts[lo], pts[hi], u);
}

// --- F2: centripetal Catmull-Rom subdivision -----------------------------------

/// maxSeg = clamp(0.5 · width, 0.75, 3.0) pt (F2).
double maxSegmentFor(double width) => (InkTuning.subdivideWidthRatio * width)
    .clamp(InkTuning.subdivideMinPt, InkTuning.subdivideMaxPt)
    .toDouble();

/// F2: a new list through every point of [pts] (the same objects) where no
/// gap exceeds [maxSeg]. Inserted points lie on the centripetal Catmull-Rom
/// curve (α = 0.5); widthQ (f), tilt, azimuth and t are interpolated linearly.
/// The end segments use reflected control points (2·p0 − p1).
List<CenterPoint> subdivide(List<CenterPoint> pts, double maxSeg) {
  final n = pts.length;
  if (n < 2) return List.of(pts);
  final out = <CenterPoint>[pts.first];
  for (var i = 0; i < n - 1; i++) {
    final p1 = pts[i], p2 = pts[i + 1];
    final p0 = i > 0 ? pts[i - 1].position : p1.position * 2 - p2.position;
    final p3 = i + 2 < n ? pts[i + 2].position : p2.position * 2 - p1.position;
    subdivideSegment(p0, p1, p2, p3, maxSeg, out);
    out.add(p2);
  }
  return out;
}

/// Appends the points inserted strictly between [p1] and [p2] to [out]
/// ([p0] / [p3] = neighbouring control positions). Nothing when |p2 − p1| ≤
/// [maxSeg]. Every gap of the result is ≤ [maxSeg] (falls back to the chord if
/// the curve cannot be split finely enough).
void subdivideSegment(
  Offset p0,
  CenterPoint p1,
  CenterPoint p2,
  Offset p3,
  double maxSeg,
  List<CenterPoint> out,
) {
  final a = p1.position, b = p2.position;
  final chord = (b - a).distance;
  if (!(chord > maxSeg)) return;
  final curve = _CentripetalSegment(p0, a, b, p3);
  var pieces = (chord / maxSeg).ceil();
  for (var attempt = 0; attempt < 8; attempt++) {
    final positions = <Offset>[
      for (var k = 1; k < pieces; k++) curve.at(k / pieces),
    ];
    var prev = a, worst = 0.0, ok = true;
    for (final q in [...positions, b]) {
      if (!q.dx.isFinite || !q.dy.isFinite) {
        ok = false;
        break;
      }
      worst = math.max(worst, (q - prev).distance);
      prev = q;
    }
    if (ok && worst <= maxSeg + 1e-9) {
      for (var k = 1; k < pieces; k++) {
        final q = positions[k - 1];
        out.add(CenterPoint.lerp(p1, p2, k / pieces, x: q.dx, y: q.dy));
      }
      return;
    }
    if (!ok) break;
    pieces = math.max(pieces + 1, (pieces * worst / maxSeg).ceil());
  }
  // Chord fallback (never expected): evenly spaced points on the segment.
  final m = (chord / maxSeg).ceil();
  for (var k = 1; k < m; k++) {
    out.add(CenterPoint.lerp(p1, p2, k / m));
  }
}

/// Barry–Goldman evaluation of the centripetal Catmull-Rom segment p1 → p2.
final class _CentripetalSegment {
  _CentripetalSegment(this.p0, this.p1, this.p2, this.p3) {
    t1 = _knot(p0, p1);
    t2 = t1 + _knot(p1, p2);
    t3 = t2 + _knot(p2, p3);
  }

  final Offset p0, p1, p2, p3;
  static const double t0 = 0;
  late final double t1, t2, t3;

  /// |q − p|^0.5, at least 1e-4 so coincident control points do not divide by 0.
  static double _knot(Offset p, Offset q) =>
      math.max(math.sqrt((q - p).distance), 1e-4);

  static Offset _mix(Offset a, Offset b, double ta, double tb, double t) {
    final span = tb - ta;
    return a * ((tb - t) / span) + b * ((t - ta) / span);
  }

  /// The curve at [u] in [0, 1] (u = 0 → p1, u = 1 → p2).
  Offset at(double u) {
    final t = t1 + (t2 - t1) * u;
    final a1 = _mix(p0, p1, t0, t1, t);
    final a2 = _mix(p1, p2, t1, t2, t);
    final a3 = _mix(p2, p3, t2, t3, t);
    final b1 = _mix(a1, a2, t0, t2, t);
    final b2 = _mix(a2, a3, t1, t3, t);
    return _mix(b1, b2, t1, t2, t);
  }
}

// --- F3: hook removal ----------------------------------------------------------

/// End window W = max(1.5 pt, width).
double endHookWindowFor(double width) => math.max(_endHookMinPt, width);

/// Start window W = max(1.0 pt, 0.75 · width).
double startHookWindowFor(double width) =>
    math.max(_startHookMinPt, _startHookWidthRatio * width);

const double _endHookMinPt = 1.5;
const double _startHookMinPt = 1.0;
const double _startHookWidthRatio = 0.75;

/// F3: cuts a pen-down / pen-lift hook. At the end: when the window of the
/// last W pt holds ≤ hookMaxPoints points, the stroke before it is at least
/// 3W long, and the window direction (S−W → S) turns back against the
/// direction before it (S−3W → S−W) — dot < hookCos (about 110° or more) — the
/// window is cut and the stroke ends at the interpolated point at S − W.
/// The start is the mirror image with W = startHookWindowFor(width).
/// [start] / [end] false skip that side (rollover joins, 6.7 F8). Applied to
/// the input points before F2, so "points" are samples. Returns a new list.
List<CenterPoint> removeHooks(
  List<CenterPoint> pts, {
  required double width,
  bool start = true,
  bool end = true,
}) {
  var out = List.of(pts);
  if (start) out = _cutStartHook(out, startHookWindowFor(width));
  if (end) out = _cutEndHook(out, endHookWindowFor(width));
  return out;
}

List<CenterPoint> _cutEndHook(List<CenterPoint> pts, double w) {
  if (pts.length < 3) return pts;
  final cum = cumulativeLengthsOf(pts);
  final total = cum.last;
  if (total - w < 3 * w) return pts;
  var inWindow = 0;
  for (var i = pts.length - 1; i >= 0 && cum[i] > total - w; i--) {
    inWindow++;
  }
  if (inWindow > InkTuning.hookMaxPoints) return pts;
  final a = pointAtLength(pts, cum, total - 3 * w);
  final b = pointAtLength(pts, cum, total - w);
  if (!_turnsBack(a.position, b.position, pts.last.position)) return pts;
  final kept = [
    for (var i = 0; i < pts.length; i++)
      if (cum[i] <= total - w) pts[i],
  ];
  if (cum[kept.length - 1] < total - w) kept.add(b);
  return kept;
}

List<CenterPoint> _cutStartHook(List<CenterPoint> pts, double w) {
  if (pts.length < 3) return pts;
  final cum = cumulativeLengthsOf(pts);
  final total = cum.last;
  if (total - w < 3 * w) return pts;
  var inWindow = 0;
  for (var i = 0; i < pts.length && cum[i] < w; i++) {
    inWindow++;
  }
  if (inWindow > InkTuning.hookMaxPoints) return pts;
  final a = pointAtLength(pts, cum, w);
  final b = pointAtLength(pts, cum, 3 * w);
  // window direction first → a, then a → b
  if (!_turnsBack(b.position, a.position, pts.first.position)) return pts;
  final firstKept = cum.indexWhere((s) => s >= w);
  return [
    if (cum[firstKept] > w) a,
    for (var i = firstKept; i < pts.length; i++) pts[i],
  ];
}

/// dot(unit(b − a), unit(c − b)) < hookCos.
bool _turnsBack(Offset a, Offset b, Offset c) {
  final d1 = b - a, d2 = c - b;
  final l1 = d1.distance, l2 = d2.distance;
  if (l1 < 1e-9 || l2 < 1e-9) return false;
  return (d1.dx * d2.dx + d1.dy * d2.dy) / (l1 * l2) < InkTuning.hookCos;
}

// --- F4: dot strokes -----------------------------------------------------------

/// A stroke shorter than max(0.3 pt, 0.25 · width) is a dot (F4).
double dotLengthFor(double width) =>
    math.max(InkTuning.dotLengthMinPt, InkTuning.dotWidthRatio * width);

/// F4: true when the polyline through [pts] is shorter than dotLengthFor(width).
bool isDotStroke(List<CenterPoint> pts, double width) =>
    pts.isNotEmpty && lengthOf(pts) < dotLengthFor(width);

/// F4: the single point of a dot — mean sample position, the largest width
/// factor (tilt / azimuth of that sample), t = 0.
CenterPoint dotOf(List<CenterPoint> pts) {
  var sx = 0.0, sy = 0.0;
  var widest = pts.first;
  for (final p in pts) {
    sx += p.x;
    sy += p.y;
    if (p.factor > widest.factor) widest = p;
  }
  return CenterPoint(
    sx / pts.length,
    sy / pts.length,
    factor: widest.factor,
    tilt: widest.tilt,
    azimuth: widest.azimuth,
    t: 0,
  );
}
