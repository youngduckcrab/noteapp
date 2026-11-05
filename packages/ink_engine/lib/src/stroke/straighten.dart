// lib/src/stroke/straighten.dart — INTERNAL (not exported): 03-ink 6.7 F6.
//
// Highlighter straightening (style.highlighterStraightening = extras['hlStraight']):
//  * alwaysStraight: start → end, two points (live: start → current position);
//  * snapOnLift: chord L ≥ 2 · width AND the largest perpendicular deviation
//    ≤ max(0.6 · width, 0.04 · L) → two points;
//  * both: a line within ±axisSnapDeg of horizontal / vertical is snapped to
//    the axis (the start stays, the end moves onto the axis through it).
import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../pen/style_ink.dart';
import '../tuning.dart';
import 'centerline.dart';

/// [end] snapped onto the horizontal / vertical through [start] when the line
/// is within ±axisSnapDeg of that axis; otherwise [end].
Offset axisSnapped(Offset start, Offset end) {
  final d = end - start;
  final tol = math.tan(InkTuning.axisSnapDeg * math.pi / 180);
  if (d.dy.abs() <= tol * d.dx.abs()) return Offset(end.dx, start.dy);
  if (d.dx.abs() <= tol * d.dy.abs()) return Offset(start.dx, end.dy);
  return end;
}

/// The live alwaysStraight line: start → current (axis snapped).
(Offset, Offset) straightLine(Offset start, Offset current) =>
    (start, axisSnapped(start, current));

/// Largest distance of [pts] from the line through the first and last point.
double maxDeviation(List<CenterPoint> pts) {
  final a = pts.first.position, b = pts.last.position;
  final d = b - a;
  final len = d.distance;
  var worst = 0.0;
  for (final p in pts) {
    final v = p.position - a;
    final dev = len > 1e-9
        ? (v.dx * d.dy - v.dy * d.dx).abs() / len
        : v.distance;
    if (dev > worst) worst = dev;
  }
  return worst;
}

/// snapOnLift test: L ≥ 2 · width and deviation ≤ max(0.6 · width, 0.04 · L).
bool isNearlyStraight(List<CenterPoint> pts, double width) {
  if (pts.length < 2) return false;
  final chord = (pts.last.position - pts.first.position).distance;
  if (chord < 2 * width) return false;
  return maxDeviation(pts) <=
      math.max(
        InkTuning.straightenDevWidthRatio * width,
        InkTuning.straightenDevLengthRatio * chord,
      );
}

/// F6: the highlighter centerline after straightening. [pts] unchanged
/// (the same list) when [mode] is off or the stroke is not straight enough.
List<CenterPoint> straighten(
  List<CenterPoint> pts, {
  required HighlighterStraightening mode,
  required double width,
}) {
  if (pts.length < 2) return pts;
  switch (mode) {
    case HighlighterStraightening.off:
      return pts;
    case HighlighterStraightening.snapOnLift:
      if (!isNearlyStraight(pts, width)) return pts;
    case HighlighterStraightening.alwaysStraight:
      break;
  }
  final first = pts.first.copy(), last = pts.last.copy();
  final end = axisSnapped(first.position, last.position);
  last
    ..x = end.dx
    ..y = end.dy;
  return [first, last];
}
