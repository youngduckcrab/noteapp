// lib/src/render/stroke_painter.dart — INTERNAL.
//
// Foundation step B3 (03-ink 4.15): every stroke is painted as a polyline
// (width = style.width, round caps / joins, alpha = opacity). Filled outlines
// (6.8), the highlighter group composite (6.10) and pencil grain (6.11) come
// with INK T07 / T08 / T10.
import 'dart:ui';

import 'package:note_core/note_core.dart' as core;

import '../edit/selection_geometry.dart';
import '../interop/core_interop.dart' as interop;

/// Stroke color with alpha = opacity (arithmetic only, 7.4.3; K-5: the stored alpha is
/// always 0xFF, transparency comes from opacity).
Color inkColor(int argb, double opacity) {
  final alpha = (opacity.clamp(0.0, 1.0) * 255).round();
  return Color(alpha * 0x1000000 + argb % 0x1000000);
}

Paint _paintFor(core.StrokeStyle style, double width, int? colorArgb) => Paint()
  ..isAntiAlias = true
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..color = inkColor(colorArgb ?? style.colorArgb, style.opacity);

/// Paints a CORE stroke (page pt). [transform] maps the points (width as
/// core.Stroke.transformed would scale it); [colorArgb] overrides the color.
void paintStrokePolyline(
  Canvas canvas,
  core.Stroke stroke, {
  core.Affine2? transform,
  int? colorArgb,
}) {
  final p = stroke.points;
  final n = p.length;
  if (n == 0) return;
  Offset at(int i) {
    final o = Offset(p.x(i), p.y(i));
    return transform == null ? o : interop.applyAffine(transform, o);
  }

  final width = transform == null
      ? stroke.style.width
      : SelectionGeometry.transformedWidth(stroke.style.width, transform);
  _paintPoints(canvas, n, at, stroke.style, width, colorArgb);
}

/// Paints live sample positions (page pt) with [style].
void paintLivePolyline(
  Canvas canvas,
  List<Offset> points,
  core.StrokeStyle style,
) {
  if (points.isEmpty) return;
  _paintPoints(
    canvas,
    points.length,
    (i) => points[i],
    style,
    style.width,
    null,
  );
}

void _paintPoints(
  Canvas canvas,
  int n,
  Offset Function(int i) at,
  core.StrokeStyle style,
  double width,
  int? colorArgb,
) {
  final paint = _paintFor(style, width, colorArgb);
  final first = at(0);
  var isDot = true;
  final path = Path()..moveTo(first.dx, first.dy);
  for (var i = 1; i < n; i++) {
    final o = at(i);
    if (o != first) isDot = false;
    path.lineTo(o.dx, o.dy);
  }
  if (isDot) {
    canvas.drawCircle(
      first,
      width / 2,
      paint
        ..style = PaintingStyle.fill
        ..strokeWidth = 0,
    );
  } else {
    canvas.drawPath(path, paint);
  }
}
