// lib/src/render/layer_painters.dart — INTERNAL (03-ink 6.10, 6.12).
//
// Paints committed strokes the way the page layers stack them: the
// highlighter groups (6.10) under the ink strokes (fill outlines, 6.8).
// Used by the page controller layers and the thumbnails.
import 'dart:ui';

import '../geometry/stroke_outline.dart';
import '../model/ink_layer.dart';
import '../model/ink_stroke.dart';
import 'highlighter_compositor.dart';
import 'stroke_painter.dart';

/// Paints the [layer] strokes of [zOrdered]: highlighter → group composites
/// on [paperColorArgb]; ink → one fill per stroke from [outlineOf] (pencil
/// with [grain] when given).
void paintStrokeLayer(
  Canvas canvas,
  Iterable<InkStroke> zOrdered, {
  required InkLayer layer,
  required int paperColorArgb,
  required StrokeOutline Function(InkStroke stroke) outlineOf,
  Image? grain,
  double marginPt = 0,
}) {
  switch (layer) {
    case InkLayer.highlighter:
      paintHighlighterGroups(
        canvas,
        groupHighlighters(zOrdered.where((s) => s.layer == layer)),
        paperColorArgb: paperColorArgb,
        marginPt: marginPt,
      );
    case InkLayer.ink || InkLayer.cover:
      // (v2.0) cover: no pen gives it yet (tape draws as ballpoint until T31)
      for (final s in zOrdered) {
        if (s.layer != layer) continue;
        paintFillStroke(canvas, s, outlineOf(s), grain: grain);
      }
  }
}

/// Every layer, highlighter first (thumbnails, previews).
void paintStrokeLayers(
  Canvas canvas,
  Iterable<InkStroke> zOrdered, {
  required int paperColorArgb,
  required StrokeOutline Function(InkStroke stroke) outlineOf,
  Image? grain,
  double marginPt = 0,
}) {
  for (final layer in InkLayer.values) {
    paintStrokeLayer(
      canvas,
      zOrdered,
      layer: layer,
      paperColorArgb: paperColorArgb,
      outlineOf: outlineOf,
      grain: grain,
      marginPt: marginPt,
    );
  }
}
