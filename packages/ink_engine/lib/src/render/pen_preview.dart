// lib/src/render/pen_preview.dart — 03-ink 4.9.
//
// Foundation step B3 (03-ink 4.15): one straight line. The real pipeline with
// the synthetic S curve comes with INK T20.
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:note_core/note_core.dart' as core;

import 'pencil_grain.dart';
import 'stroke_painter.dart';

enum PenPreviewShape { sCurve, line }

/// Draws a sample stroke for a style (F-04 size preview, preset bar icons). Built with the
/// real stroke pipeline from a fixed synthetic sample script (real-pressure S curve).
/// (v1.1) pencilGrain is the PencilGrain itself (ref.watch(pencilGrainProvider)), not its
/// ui.Image; the painter repaints on it (repaint: pencilGrain).
class PenPreviewPainter extends CustomPainter {
  PenPreviewPainter({
    required this.style,
    this.shape = PenPreviewShape.sCurve,
    this.paperColorArgb = core.PaperColors.white,
    this.pencilGrain,
  }) : super(repaint: pencilGrain);
  final core.StrokeStyle style;
  final PenPreviewShape shape;
  final int paperColorArgb;

  /// repaints when the grain becomes ready
  final PencilGrain? pencilGrain;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final width = math.min(style.width, size.height);
    final r = width / 2;
    final y = size.height / 2;
    final from = Offset(math.min(r, size.width / 2), y);
    final to = Offset(math.max(size.width - r, size.width / 2), y);
    canvas.drawLine(
      from,
      to,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..color = inkColor(style.colorArgb, style.opacity),
    );
  }

  /// style / shape / paperColorArgb differ by value, or pencilGrain is another object.
  @override
  bool shouldRepaint(PenPreviewPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.shape != shape ||
      oldDelegate.paperColorArgb != paperColorArgb ||
      !identical(oldDelegate.pencilGrain, pencilGrain);
}
