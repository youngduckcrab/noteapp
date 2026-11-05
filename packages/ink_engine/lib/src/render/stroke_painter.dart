// lib/src/render/stroke_painter.dart — INTERNAL (03-ink 6.8 O8–O9, 6.11, 6.12 R5).
//
// Fill pens (ballpoint, fountain, pencil, marker, P1 → ballpoint): the 6.8
// outline as ONE nonzero path — a stroke that crosses itself is painted once
// (no darker overlap at opacity < 1). The pencil adds the page-fixed grain
// shader (6.11) and a per-stroke opacity loss from its tilt. The highlighter
// is a stroked centerline (O9) and is always painted inside its group
// composite (highlighter_compositor.dart, 6.10).
import 'dart:typed_data';
import 'dart:ui';

import 'package:note_core/note_core.dart' as core;

import '../geometry/stroke_outline.dart';
import '../model/ink_points.dart';
import '../model/ink_stroke.dart';
import '../pen/pen_profile.dart';
import '../stroke/width_factor.dart' show tiltK;
import '../tuning.dart';

/// Stroke color with alpha = opacity (arithmetic only, 7.4.3; K-5: the stored alpha is
/// always 0xFF, transparency comes from opacity).
Color inkColor(int argb, double opacity) {
  final o = opacity.isNaN ? 1.0 : opacity.clamp(0.0, 1.0);
  final alpha = (o * 255).round();
  return Color(alpha * 0x1000000 + argb % 0x1000000);
}

/// Mean K4 tilt weight k̄ of the stored points (6.11).
double meanTiltK(InkPoints points) {
  final n = points.length;
  if (n == 0) return 0;
  var sum = 0.0;
  for (var i = 0; i < n; i++) {
    sum += tiltK(points.tilt(i));
  }
  return sum / n;
}

/// Per-stroke opacity factor of the pencil: 1 − tiltOpacityLoss · k̄ (6.11);
/// 1 for pens without tilt opacity loss.
double tiltOpacityFactor(PenProfile profile, double meanK) {
  if (profile.tiltOpacityLoss <= 0) return 1;
  return (1 - profile.tiltOpacityLoss * meanK).clamp(0.0, 1.0).toDouble();
}

/// The opacity a committed stroke is painted with: style.opacity × the
/// pencil's tilt factor.
double strokeOpacity(InkStroke stroke) {
  final profile = stroke.profile;
  if (profile.tiltOpacityLoss <= 0) return stroke.style.opacity;
  return stroke.style.opacity *
      tiltOpacityFactor(profile, meanTiltK(stroke.points));
}

/// Grain texel → page pt: one texel is InkTuning.grainTexelPt pt, anchored at
/// the page origin, so overlapping strokes continue the same pattern (6.11).
final Float64List _grainMatrix = Float64List.fromList([
  InkTuning.grainTexelPt, 0, 0, 0, //
  0, InkTuning.grainTexelPt, 0, 0, //
  0, 0, 1, 0, //
  0, 0, 0, 1, //
]);

/// Fill paint of a fill pen (O8: anti-aliased; the path carries nonZero).
/// A textured pen with [grain] gets ImageShader(grain, repeated) and
/// ColorFilter.mode([color], srcIn): the pen color, alpha × grain (6.11).
Paint inkFillPaint(PenProfile profile, Color color, {Image? grain}) {
  final paint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill;
  if (profile.textured && grain != null) {
    paint
      ..shader = ImageShader(
        grain,
        TileMode.repeated,
        TileMode.repeated,
        _grainMatrix,
        filterQuality: FilterQuality.low,
      )
      ..filterQuality = FilterQuality.low
      ..colorFilter = ColorFilter.mode(color, BlendMode.srcIn);
  } else {
    paint.color = color;
  }
  return paint;
}

/// Paints one committed fill-pen stroke from its [outline] (6.8). [colorArgb]
/// replaces the color (recolor preview).
void paintFillStroke(
  Canvas canvas,
  InkStroke stroke,
  StrokeOutline outline, {
  int? colorArgb,
  Image? grain,
}) {
  final opacity = strokeOpacity(stroke);
  if (opacity <= 0) return;
  final paint = inkFillPaint(
    stroke.profile,
    inkColor(colorArgb ?? stroke.style.colorArgb, opacity),
    grain: grain,
  );
  canvas.drawPath(outline.toPath(), paint);
}

/// Paints fill paths that belong to one stroke (live chunks, R5): with
/// [opacity] 1 each path is drawn directly; below 1 they are drawn opaque
/// inside saveLayer([bounds], alpha) so their overlaps are not darker.
void paintFillPaths(
  Canvas canvas,
  Iterable<Path> paths, {
  required PenProfile profile,
  required int colorArgb,
  required double opacity,
  required Rect bounds,
  Image? grain,
}) {
  if (opacity <= 0) return;
  final layered = opacity < 1;
  if (layered) canvas.saveLayer(bounds, Paint()..color = inkColor(0, opacity));
  final paint = inkFillPaint(profile, inkColor(colorArgb, 1), grain: grain);
  for (final p in paths) {
    canvas.drawPath(p, paint);
  }
  if (layered) canvas.restore();
}

/// O9 stroke paint of the highlighter: width, square caps, round joins.
Paint highlighterLinePaint(double width, Color color) => Paint()
  ..isAntiAlias = true
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.square
  ..strokeJoin = StrokeJoin.round
  ..color = color;

/// Draws a highlighter centerline (x,y pairs) with [paint]
/// (highlighterLinePaint). A zero-length line is the square its caps would
/// make: side = strokeWidth, axis-aligned.
void drawHighlighterLine(Canvas canvas, Float32List xy, Paint paint) {
  final n = xy.length ~/ 2;
  if (n == 0) return;
  final x0 = xy[0], y0 = xy[1];
  var zero = true;
  final path = Path()..moveTo(x0, y0);
  for (var i = 1; i < n; i++) {
    final x = xy[2 * i], y = xy[2 * i + 1];
    if (x != x0 || y != y0) zero = false;
    path.lineTo(x, y);
  }
  if (zero) {
    final h = paint.strokeWidth / 2;
    canvas.drawRect(
      Rect.fromLTRB(x0 - h, y0 - h, x0 + h, y0 + h),
      Paint()
        ..isAntiAlias = true
        ..color = paint.color,
    );
    return;
  }
  canvas.drawPath(path, paint);
}

/// The paper-dependent highlighter blend (6.10-4): multiply on light paper
/// (dark text stays dark, "under the text"), srcOver on dark paper.
BlendMode highlighterBlendFor(int paperColorArgb) =>
    core.PaperColors.isDark(paperColorArgb)
    ? BlendMode.srcOver
    : BlendMode.multiply;
