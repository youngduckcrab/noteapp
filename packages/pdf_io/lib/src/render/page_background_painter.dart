// lib/src/render/page_background_painter.dart — 06-pdf 6.8 drawing order (PDF T9). Internal.
//
// All coordinates are NOTE page pt (6.5.1) under canvas.scale(viewScale): ① opaque paper over
// the whole box, ② the base image in its PdfPageFit box, ③ tiles (older bucket first), ④
// search highlights (PdfTuning colors only — contract 7.4.11 v1.2 exception, no literal).
// The status display (⑤) is a widget overlay in logical px (page_background_view.dart).
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../tuning.dart';
import 'render_service.dart';
import 'tile_math.dart';

final class PdfPageBackgroundPainter extends CustomPainter {
  PdfPageBackgroundPainter({
    required this.snapshot,
    required this.paperColorArgb,
    required this.viewScale,
    this.highlightRects = const [],
    this.currentRects = const [],
  });

  final PdfRenderSnapshot snapshot;
  final int paperColorArgb;

  /// Logical px per note pt (layout scale only — never ancestorScale, 6.8).
  final double viewScale;

  /// Note pt (PdfSearchState.rectsFor / currentRectsFor of params.pageId).
  final List<ui.Rect> highlightRects;
  final List<ui.Rect> currentRects;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Color(opaquePaperArgb(paperColorArgb)),
    );
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..scale(viewScale);
    final imagePaint = Paint()..filterQuality = FilterQuality.medium;
    final base = snapshot.base;
    if (base != null) {
      canvas.drawImageRect(base.image, base.srcRect, base.pageRect, imagePaint);
    }
    for (final tile in snapshot.tiles) {
      canvas.drawImageRect(tile.image, tile.srcRect, tile.pageRect, imagePaint);
    }
    if (highlightRects.isNotEmpty) {
      final fill = Paint()..color = Color(PdfTuning.searchHighlightArgb);
      for (final rect in highlightRects) {
        canvas.drawRect(rect, fill);
      }
    }
    if (currentRects.isNotEmpty) {
      final fill = Paint()..color = Color(PdfTuning.searchCurrentArgb);
      final outline = Paint()
        ..color = Color(PdfTuning.searchCurrentArgb)
        ..style = PaintingStyle.stroke
        ..strokeWidth = PdfTuning.searchCurrentOutlinePt;
      for (final rect in currentRects) {
        canvas
          ..drawRect(rect, fill)
          ..drawRect(rect, outline);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(PdfPageBackgroundPainter old) =>
      !identical(old.snapshot, snapshot) ||
      old.paperColorArgb != paperColorArgb ||
      old.viewScale != viewScale ||
      !_sameRects(old.highlightRects, highlightRects) ||
      !_sameRects(old.currentRects, currentRects);

  static bool _sameRects(List<ui.Rect> a, List<ui.Rect> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
