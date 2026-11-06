// lib/src/render/tape_painter.dart — INTERNAL (m5-7/03-ink 6.7-3, 6.7-4, T31).
//
// The memorization tape on the cover layer:
//   covered   the outline (square caps, 6.7-1) filled with the tape color,
//             always opaque — style.opacity is not used (a see-through tape
//             would not cover, and K-9 'playback never changes a covered tape'
//             relies on it); striped → 45° stripes on top, clipped to the
//             outline: spacing tapeStripeSpacingPt, width tapeStripeWidthPt,
//             the tape color 15 % darker (computed). The stripes are fixed to
//             the page (lines x + y = k · spacing · √2), like the pencil grain,
//             so a moved tape shows the same pattern as a newly written one.
//   revealed  the outline path stroked with a [lineWidthPt] line (1 logical
//             px = 1 / viewScale pt on screen) in the tape color at
//             tapeRevealedBorderOpacity: the writing under it shows.
// Thumbnails, vectors and pen previews always draw the covered shape (K-9).
import 'dart:math' as math;
import 'dart:ui';

import '../geometry/stroke_outline.dart';
import '../model/ink_stroke.dart';
import '../pen/style_ink.dart';
import '../tuning.dart';

/// The tape color with alpha 0xFF (style alpha is always 0xFF — K-5).
Color tapeColor(int argb) => Color(0xFF000000 | (argb & 0x00FFFFFF));

/// The stripe color: every channel of [argb] × 0.85 (15 % darker), opaque.
Color tapeStripeColor(int argb) {
  int d(int shift) => (((argb >> shift) & 0xFF) * 0.85).round();
  return Color.fromARGB(0xFF, d(16), d(8), d(0));
}

/// Paints the covered tape [stroke] from [outline] (cover layer, thumbnails,
/// previews). [colorArgb] replaces the color (recolor preview).
void paintTapeCovered(
  Canvas canvas,
  InkStroke stroke,
  StrokeOutline outline, {
  int? colorArgb,
}) => paintTapeCoveredPaths(
  canvas,
  [outline.toPath()],
  colorArgb: colorArgb ?? stroke.style.colorArgb,
  striped: stroke.style.tapeStyle == InkTapeStyle.striped,
  bounds: outline.bounds,
);

/// The covered look of fill [paths] of one tape (the live stroke: frozen
/// chunks + tail). [bounds] contains them (the stripes cover it).
void paintTapeCoveredPaths(
  Canvas canvas,
  List<Path> paths, {
  required int colorArgb,
  required bool striped,
  required Rect bounds,
}) {
  final fill = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill
    ..color = tapeColor(colorArgb);
  for (final p in paths) {
    canvas.drawPath(p, fill);
  }
  if (!striped || bounds.isEmpty || !bounds.isFinite) return;
  final stripes = tapeStripesPath(bounds);
  final line = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeWidth = InkTuning.tapeStripeWidthPt
    ..strokeCap = StrokeCap.butt
    ..color = tapeStripeColor(colorArgb);
  for (final p in paths) {
    canvas
      ..save()
      ..clipPath(p)
      ..drawPath(stripes, line)
      ..restore();
  }
}

/// The 45° stripe lines x + y = k · spacing · √2 that cross [bounds] (page-fixed).
Path tapeStripesPath(Rect bounds) {
  final step = InkTuning.tapeStripeSpacingPt * math.sqrt2;
  final pad = InkTuning.tapeStripeWidthPt;
  final top = bounds.top - pad, bottom = bounds.bottom + pad;
  final from = ((bounds.left + bounds.top - 2 * pad) / step).floor();
  final to = ((bounds.right + bounds.bottom + 2 * pad) / step).ceil();
  final path = Path();
  for (var k = from; k <= to; k++) {
    final c = k * step;
    path
      ..moveTo(c - top, top)
      ..lineTo(c - bottom, bottom);
  }
  return path;
}

/// Paints the revealed tape [stroke]: its outline stroked [lineWidthPt] wide in the
/// tape color at tapeRevealedBorderOpacity.
void paintTapeRevealed(
  Canvas canvas,
  InkStroke stroke,
  StrokeOutline outline, {
  required double lineWidthPt,
  int? colorArgb,
}) {
  final argb = colorArgb ?? stroke.style.colorArgb;
  final alpha = (InkTuning.tapeRevealedBorderOpacity * 255).round();
  canvas.drawPath(
    outline.toPath(),
    Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidthPt > 0 && lineWidthPt.isFinite ? lineWidthPt : 1
      ..strokeJoin = StrokeJoin.miter
      ..color = Color((alpha << 24) | (argb & 0x00FFFFFF)),
  );
}
