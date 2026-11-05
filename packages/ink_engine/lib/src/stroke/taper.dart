// lib/src/stroke/taper.dart — INTERNAL (not exported): 03-ink 6.7 F5 (= K5).
//
//   Ls = min(taperStart · width, 0.4 · S), Le = min(taperEnd · width, 0.4 · S)
//   ts = easeOutCubic(clamp(s / Ls)), te = easeOutCubic(clamp((S − s) / Le))
//   taperMul = taperMin + (1 − taperMin) · min(ts, te); a side of length 0 → 1
// S = stroke length, s = arc length of the point. The start taper also runs
// live (on the arc length so far); the end taper only at finish.
import 'dart:math' as math;

import '../pen/pen_profile.dart';
import '../tuning.dart';
import 'centerline.dart';

/// 1 − (1 − t)³.
double easeOutCubic(double t) {
  final u = 1 - t;
  return 1 - u * u * u;
}

/// (Ls, Le) of a stroke of [totalLength] pt: min(taper · width, 0.4 · S).
(double, double) taperLengths(
  PenProfile profile,
  double width,
  double totalLength,
) {
  final cap = InkTuning.taperMaxLengthRatio * totalLength;
  return (
    math.min(profile.taperStart * width, cap),
    math.min(profile.taperEnd * width, cap),
  );
}

/// The start-side factor ts (1 when [startLength] is 0).
double startTaper(double s, double startLength) => startLength > 0
    ? easeOutCubic((s / startLength).clamp(0.0, 1.0).toDouble())
    : 1;

/// taperMul at arc length [s] of a stroke of length [total].
double taperMultiplier({
  required double s,
  required double total,
  required double startLength,
  required double endLength,
  required double minFactor,
}) {
  final ts = startTaper(s, startLength);
  final te = endLength > 0
      ? easeOutCubic(((total - s) / endLength).clamp(0.0, 1.0).toDouble())
      : 1.0;
  return minFactor + (1 - minFactor) * math.min(ts, te);
}

/// F5 in place: factor *= taperMul. [start] / [end] false leave that side
/// untapered (rollover joins, 6.7 F8). No-op for pens without taper.
void applyTaper(
  List<CenterPoint> pts, {
  required PenProfile profile,
  required double width,
  bool start = true,
  bool end = true,
}) {
  if (pts.length < 2) return;
  if (profile.taperStart <= 0 && profile.taperEnd <= 0) return;
  final cum = cumulativeLengthsOf(pts);
  final total = cum.last;
  final (ls, le) = taperLengths(profile, width, total);
  for (var i = 0; i < pts.length; i++) {
    pts[i].factor *= taperMultiplier(
      s: cum[i],
      total: total,
      startLength: start ? ls : 0,
      endLength: end ? le : 0,
      minFactor: profile.taperMinFactor,
    );
  }
}
