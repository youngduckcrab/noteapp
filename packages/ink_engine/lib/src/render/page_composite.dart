// lib/src/render/page_composite.dart — INTERNAL (m5-7/03-ink 6.20 step 4, K-8, T41).
//
// The committed content of one page in the L-1 order the page layers stack it
// (thumbnails — the renderer and the InkPageThumbnail widget):
//   underlay (image objects) → highlighter groups → the ink layer (ink strokes
//   and shapes z-mixed by compareOrder, the same items as the ink chunks) →
//   annotation (text boxes, formulas, unknown objects) → cover (tapes, always
//   covered — K-9).
// Objects are drawn by the page painter (object_painter.dart): an image or a
// formula that is not ready is its placeholder.
import 'dart:ui' as ui;

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

import '../geometry/stroke_outline.dart';
import '../math/math_raster_cache.dart' show MathRaster;
import '../model/ink_layer.dart';
import '../model/ink_stroke.dart';
import '../object/object_painter.dart';
import '../object/object_view.dart';
import 'ink_page_content.dart';
import 'layer_painters.dart';
import 'stroke_painter.dart';

/// Paints [strokes] and [objects] (each in compareOrder, without deleted elements) in page
/// pt (see the file comment) on paper [paperColorArgb]. [onePx] = one output px in pt
/// (placeholder hairlines); [marginPt] as paintStrokeLayers. [imageOf] / [mathRasterOf]
/// give the decoded image / formula raster to draw now (null → the placeholder).
@internal
void paintPageComposite(
  ui.Canvas canvas, {
  required List<InkStroke> strokes,
  required List<core.PageObject> objects,
  required int paperColorArgb,
  required StrokeOutline Function(InkStroke stroke) outlineOf,
  required double onePx,
  ui.Image? grain,
  double marginPt = 0,
  ui.Image? Function(core.ImageObject o)? imageOf,
  MathRaster? Function(core.MathObject o)? mathRasterOf,
}) {
  void object(core.PageObject o) => paintObjectSimple(
    canvas,
    o,
    paperArgb: paperColorArgb,
    onePx: onePx,
    imageOf: imageOf,
    mathRasterOf: mathRasterOf,
  );
  final shapes = <InkObjectView>[];
  final annotation = <core.PageObject>[];
  for (final o in objects) {
    switch (objectLayerOf(o)) {
      case InkObjectLayer.underlay:
        object(o);
      case InkObjectLayer.ink:
        shapes.add(InkObjectView.of(o));
      case InkObjectLayer.annotation:
        annotation.add(o);
    }
  }
  paintStrokeLayer(
    canvas,
    strokes,
    layer: InkLayer.highlighter,
    paperColorArgb: paperColorArgb,
    outlineOf: outlineOf,
    marginPt: marginPt,
  );
  for (final item in mergeInkLayer(strokes, shapes)) {
    switch (item) {
      case InkStrokeItem(:final stroke):
        paintFillStroke(canvas, stroke, outlineOf(stroke), grain: grain);
      case InkObjectView(object: final o):
        object(o);
    }
  }
  annotation.forEach(object);
  paintStrokeLayer(
    canvas,
    strokes,
    layer: InkLayer.cover,
    paperColorArgb: paperColorArgb,
    outlineOf: outlineOf,
    marginPt: marginPt,
  );
}
