// lib/src/render/lasso_overlay.dart — INTERNAL (03-ink 6.12 R8, INK T17).
//
// The lasso path on the overlay layer: inside filled with
// InkTuning.lassoFillArgb (nonzero, like the selection rule), then a dashed
// line in InkTuning.lassoPathArgb, 1.5 screen px wide, 6 px on / 4 px off.
// The colors are the InkTuning constants (contract 7.4.11 v1.3 exception);
// this painter has no color literal.
import 'dart:math' as math;
import 'dart:ui';

import '../tuning.dart';

/// Line width, dash and gap of the lasso path in logical px.
const double lassoPathWidthPx = 1.5;
const double lassoDashPx = 6;
const double lassoGapPx = 4;

/// Paints [path] (page pt) on a canvas already scaled by [viewScale] logical
/// px per page pt.
void paintLassoOverlay(Canvas canvas, Path path, double viewScale) {
  canvas
    ..drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(InkTuning.lassoFillArgb),
    )
    ..drawPath(
      dashedPath(
        path,
        dash: lassoDashPx / viewScale,
        gap: lassoGapPx / viewScale,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lassoPathWidthPx / viewScale
        ..color = const Color(InkTuning.lassoPathArgb),
    );
}

/// [source] cut into [dash]-long pieces [gap] apart along each contour,
/// starting with a dash at the contour start (the whole path when the
/// lengths are not positive and finite).
Path dashedPath(Path source, {required double dash, required double gap}) {
  if (!(dash > 0 && gap > 0) || !(dash + gap).isFinite) return source;
  final out = Path();
  for (final metric in source.computeMetrics()) {
    for (var d = 0.0; d < metric.length; d += dash + gap) {
      out.addPath(
        metric.extractPath(d, math.min(d + dash, metric.length)),
        Offset.zero,
      );
    }
  }
  return out;
}
