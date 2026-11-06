// lib/src/export/vector_export.dart — 03-ink 4.11 (contract 7.2.16, approved).
//
// 6.24: the strokes are taken in z order (core.Stroke.compareOrder — input
// already in that order is kept as is, otherwise a sorted copy; deleted
// strokes are skipped like on screen).
//   highlighter (strokedPolyline) → the 6.10 groups: key (opaque color,
//     opacity in 1/100), ordered by their lowest z; every line is the stored
//     centerline (moveTo + lineTo, the same polyline the screen strokes),
//     width = style.width, square caps (round joins, 6.8 O9). blend =
//     multiply on light paper, normal on dark paper (6.10-4).
//   every other pen → InkFillShape: the screen's L1 outline (6.8, the same
//     OutlineGenerator.outline the page layers fill) as toVectorPath(smooth)
//     — quadratic → cubic, a dot is 4 cubics (k = 0.5523) — nonzero fill,
//     color alpha 0xFF (K-5), opacity = the screen opacity (style.opacity ×
//     the pencil tilt factor, 6.11) × pencilOpacityFactor for the textured
//     pencil (grain cannot be vector).
// Coordinates are page pt, y down (the PDF area flips y). Strokes and groups
// with opacity 0 paint nothing on screen and are left out. A zero-length
// highlighter line (all points equal) becomes a 0.001 pt horizontal segment:
// PDF does not paint a degenerate subpath with square caps, the screen draws
// the axis-aligned square of side width (stroke_painter.dart).
//
// (v2.0, 2nd round contract 7.2.9 — m5-7/03-ink 4.8, 6.21, T42) Vector export
// v2, paint order = L-1 (PDF: underlay → highlighterGroups → inkShapes →
// annotations → cover, K-8), every list in z order:
//   underlay — image objects → InkImageVector(assetId, frame, pixel size);
//   highlighterGroups — as above;
//   inkShapes — the ink layer (InkLayer.ink strokes and ShapeObjects merged by
//     compareOrder, the screen's ink chunks): strokes as above (a dashed stroke
//     = its dash outlines and dots in one path, a stored laser stroke = the
//     ballpoint fallback the screen draws), a shape = its fill piece (closed
//     polyline polygon / ellipse as 4 cubics) then its outline piece (the
//     outline polygons of 6.9.5 with the arrow heads and the dots in one
//     nonzero path), both with objectId = strokeId = the object id and tool =
//     ballpoint (CP-INK-1);
//   annotations — text boxes → InkTextVector(object, the lines of the screen
//     paragraph, frame-local pt; empty until NoteSans is loaded — CP-INK-9),
//     formulas → InkMathVector(object); unknown objects never (CP-INK-10);
//   cover — tape strokes, always covered (opacity 1, whatever the reveal).
// Objects without a drawable frame (a side ≤ 0 or not finite) are left out
// like on screen. bounds = the union of every exported piece (paths, lines,
// object bounds). Every value type compares by value (InkVectorFixtures,
// testing.dart, rebuilds exportPage results field by field).
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

import '../geometry/outline_generator.dart';
import '../geometry/vector_path.dart';
import '../model/ink_layer.dart';
import '../model/ink_stroke.dart';
import '../object/object_painter.dart' show textBoxParagraphOf;
import '../object/object_view.dart';
import '../object/shape_path.dart'
    show ShapeOutlineParts, shapeGeometryOf, shapeOpacity, shapeOutlinePartsOf;
import '../pen/pen_profile.dart';
import '../render/highlighter_compositor.dart';
import '../render/ink_page_content.dart';
import '../render/stroke_painter.dart' show strokeOpacity;
import '../text/fonts.dart';
import '../tuning.dart';

enum InkBlendMode { normal, multiply }

@immutable
final class InkExportOptions {
  const InkExportOptions({
    this.smooth = true,
    this.pencilOpacityFactor = InkTuning.exportPencilOpacityFactor,
    this.paperColorArgb = core.PaperColors.white,
  });
  final bool smooth;

  /// grain cannot be vector → flat color, slightly lighter
  final double pencilOpacityFactor;

  /// decides highlighter blend (6.10)
  final int paperColorArgb;

  @override
  bool operator ==(Object other) =>
      other is InkExportOptions &&
      other.smooth == smooth &&
      other.pencilOpacityFactor == pencilOpacityFactor &&
      other.paperColorArgb == paperColorArgb;

  @override
  int get hashCode => Object.hash(smooth, pencilOpacityFactor, paperColorArgb);
}

/// One filled ink stroke (z-ordered).
/// (v2.1, CP-INK-1) [objectId] — ShapeObject id for shape pieces (then strokeId = object id,
/// tool = core.PenTool.ballpoint placeholder), null for strokes.
final class InkFillShape {
  InkFillShape._({
    required this.strokeId,
    required this.tool,
    required this.path,
    required this.colorArgb,
    required this.opacity,
    this.objectId,
  });
  final String strokeId;
  final core.PenTool tool;

  /// nonzero fill
  final InkVectorPath path;
  final int colorArgb;
  final double opacity;
  final String? objectId;

  @override
  bool operator ==(Object other) =>
      other is InkFillShape &&
      other.strokeId == strokeId &&
      other.tool == tool &&
      _pathEquals(other.path, path) &&
      other.colorArgb == colorArgb &&
      other.opacity == opacity &&
      other.objectId == objectId;

  @override
  int get hashCode => Object.hash(
    strokeId,
    tool,
    _pathHash(path),
    colorArgb,
    opacity,
    objectId,
  );
}

/// One highlighter stroke inside a group.
final class InkHighlighterLine {
  InkHighlighterLine._({
    required this.strokeId,
    required this.centerline,
    required this.width,
    required this.cap,
  });
  final String strokeId;

  /// stroke it
  final InkVectorPath centerline;
  final double width;
  final InkCap cap;

  @override
  bool operator ==(Object other) =>
      other is InkHighlighterLine &&
      other.strokeId == strokeId &&
      _pathEquals(other.centerline, centerline) &&
      other.width == width &&
      other.cap == cap;

  @override
  int get hashCode => Object.hash(strokeId, _pathHash(centerline), width, cap);
}

/// Same color + opacity highlighters. Paint all lines of a group as ONE stroked path
/// with [opacity] and [blend] so overlaps do not darken (6.24).
final class InkHighlighterGroup {
  InkHighlighterGroup._({
    required this.colorArgb,
    required this.opacity,
    required this.blend,
    required this.lines,
  });
  final int colorArgb;
  final double opacity;
  final InkBlendMode blend;
  final List<InkHighlighterLine> lines;

  @override
  bool operator ==(Object other) =>
      other is InkHighlighterGroup &&
      other.colorArgb == colorArgb &&
      other.opacity == opacity &&
      other.blend == blend &&
      _listEquals(other.lines, lines);

  @override
  int get hashCode =>
      Object.hash(colorArgb, opacity, blend, Object.hashAll(lines));
}

// --- vector export v2 (paint order = L-1): 추가 ---
final class InkPageVectors {
  InkPageVectors._({
    required this.highlighterGroups,
    required this.inkShapes,
    required this.bounds,
    this.underlay = const [],
    this.annotations = const [],
    this.cover = const [],
  });

  static final InkPageVectors _empty = InkPageVectors._(
    highlighterGroups: const [],
    inkShapes: const [],
    bounds: Rect.zero,
  );

  /// draw first (below ink)
  final List<InkHighlighterGroup> highlighterGroups;

  /// then these, in order — (v2.0) also ShapeObject outlines / fills and dashed strokes
  /// pre-split into dash segments (PDF needs no dash operator)
  final List<InkFillShape> inkShapes;
  final Rect bounds;

  /// image objects
  final List<InkImageVector> underlay;

  /// text boxes, math (z order)
  final List<InkAnnotationVector> annotations;

  /// tape strokes (always covered in exports)
  final List<InkFillShape> cover;

  bool get isEmpty =>
      highlighterGroups.isEmpty &&
      inkShapes.isEmpty &&
      underlay.isEmpty &&
      annotations.isEmpty &&
      cover.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is InkPageVectors &&
      _listEquals(other.highlighterGroups, highlighterGroups) &&
      _listEquals(other.inkShapes, inkShapes) &&
      other.bounds == bounds &&
      _listEquals(other.underlay, underlay) &&
      _listEquals(other.annotations, annotations) &&
      _listEquals(other.cover, cover);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(highlighterGroups),
    Object.hashAll(inkShapes),
    bounds,
    Object.hashAll(underlay),
    Object.hashAll(annotations),
    Object.hashAll(cover),
  );
}

/// One image object (underlay, z order).
@immutable
final class InkImageVector {
  const InkImageVector._({
    required this.assetId,
    required this.frame,
    required this.pixelWidth,
    required this.pixelHeight,
  });
  final String assetId;
  final core.ElementFrame frame;
  final int pixelWidth, pixelHeight;

  @override
  bool operator ==(Object other) =>
      other is InkImageVector &&
      other.assetId == assetId &&
      other.frame == frame &&
      other.pixelWidth == pixelWidth &&
      other.pixelHeight == pixelHeight;

  @override
  int get hashCode => Object.hash(assetId, frame, pixelWidth, pixelHeight);
}

/// A text box or a formula (annotations, z order).
sealed class InkAnnotationVector {
  const InkAnnotationVector();
  core.ElementFrame get frame;
}

final class InkTextVector extends InkAnnotationVector {
  const InkTextVector._({required this.object, required this.lines});
  final core.TextBoxObject object;

  /// laid out with InkFonts.noteSans, frame-local pt. (v2.1, CP-INK-9) Empty when the fonts
  /// are not loaded (→ PDF raster fallback).
  final List<InkTextLine> lines;

  @override
  core.ElementFrame get frame => object.frame;

  @override
  bool operator ==(Object other) =>
      other is InkTextVector &&
      other.object == object &&
      _listEquals(other.lines, lines);

  @override
  int get hashCode => Object.hash(object, Object.hashAll(lines));
}

@immutable
final class InkTextLine {
  const InkTextLine._({
    required this.text,
    required this.x,
    required this.baselineY,
    required this.width,
  });
  final String text;
  final double x, baselineY, width;

  @override
  bool operator ==(Object other) =>
      other is InkTextLine &&
      other.text == text &&
      other.x == x &&
      other.baselineY == baselineY &&
      other.width == width;

  @override
  int get hashCode => Object.hash(text, x, baselineY, width);
}

final class InkMathVector extends InkAnnotationVector {
  const InkMathVector._({required this.object});
  final core.MathObject object;

  @override
  core.ElementFrame get frame => object.frame;

  @override
  bool operator ==(Object other) =>
      other is InkMathVector && other.object == object;

  @override
  int get hashCode => object.hashCode;
}
// (v2.1, CP-INK-10) UnknownObject is never exported (screen / thumbnail placeholder only).
// (v2.1, CP-INK-9) PDF awaits InkFonts.ensureLoaded() before export; when fonts are not loaded
//   InkTextVector.lines is empty (→ PDF raster fallback).

abstract final class InkVectorExport {
  static InkPageVectors exportStrokes(
    List<InkStroke> strokes, {
    InkExportOptions options = const InkExportOptions(),
  }) {
    final zOrdered = _zOrdered(strokes);
    if (zOrdered.isEmpty) return InkPageVectors._empty;
    return (_PageExport(options)
          ..strokesOutsideInk(zOrdered)
          ..inkItems([
            for (final s in zOrdered)
              if (s.layer == InkLayer.ink) InkStrokeItem.of(s),
          ]))
        .build();
  }

  /// options == null → InkExportOptions(paperColorArgb: content.background.paperColorArgb).
  static InkPageVectors exportPage(
    InkPageContent content, {
    InkExportOptions? options,
  }) {
    if (content.strokes.isEmpty && content.objects.isEmpty) {
      return InkPageVectors._empty;
    }
    final export = _PageExport(
      options ??
          InkExportOptions(paperColorArgb: content.background.paperColorArgb),
    );
    // content.strokes: compareOrder, no deleted strokes (InkPageContent.fromCore)
    return (export
          ..strokesOutsideInk(content.strokes)
          ..inkItems(inkLayerItemsOf(content))
          ..underlay(objectViewsOf(content, InkObjectLayer.underlay))
          ..annotations(objectViewsOf(content, InkObjectLayer.annotation)))
        .build();
  }
}

/// One export run: the lists in L-1 order, filled layer by layer (each in z order).
final class _PageExport {
  _PageExport(this.options)
    : blend = core.PaperColors.isDark(options.paperColorArgb)
          ? InkBlendMode.normal
          : InkBlendMode.multiply;

  final InkExportOptions options;
  final InkBlendMode blend;
  final Map<HighlighterGroupKey, _GroupBuilder> _groups = {};
  final List<_GroupBuilder> _groupOrder = [];
  final List<InkFillShape> _shapes = [];
  final List<InkFillShape> _cover = [];
  final List<InkImageVector> _underlay = [];
  final List<InkAnnotationVector> _annotations = [];
  Rect? _bounds;

  void _include(Rect r) =>
      _bounds = _bounds == null ? r : _bounds!.expandToInclude(r);

  /// The highlighter groups and the cover (tape) shapes of [zOrdered]; the ink-layer
  /// strokes go through [inkItems].
  void strokesOutsideInk(List<InkStroke> zOrdered) {
    for (final s in zOrdered) {
      switch (s.layer) {
        case InkLayer.highlighter:
          _highlighter(s);
        case InkLayer.cover:
          _tape(s);
        case InkLayer.ink:
          break;
      }
    }
  }

  void _highlighter(InkStroke s) {
    final key = HighlighterGroupKey.of(s.style);
    if (key.opacityPercent <= 0) return;
    final line = HighlighterLine.of(s);
    final g = _groups.putIfAbsent(key, () {
      final created = _GroupBuilder(key);
      _groupOrder.add(created);
      return created;
    });
    g.lines.add(
      InkHighlighterLine._(
        strokeId: s.id,
        centerline: _centerline(line.xy),
        width: line.width,
        cap: s.profile.cap,
      ),
    );
    _include(line.bounds);
  }

  /// (m5-7 T31, 6.7-8) a tape: always the covered shape, opaque, whatever the reveal
  /// state on screen (stripes are one color in PDF — 12.2 Q8).
  void _tape(InkStroke s) {
    final outline = OutlineGenerator.outline(s);
    final path = outline.toVectorPath(smooth: options.smooth);
    if (path.verbs.isEmpty) return;
    _cover.add(
      InkFillShape._(
        strokeId: s.id,
        tool: s.style.tool,
        path: path,
        colorArgb: _opaque(s.style.colorArgb),
        opacity: 1,
      ),
    );
    _include(outline.bounds);
  }

  /// The ink layer in z order: strokes (their screen outline — dashed strokes as their
  /// dash outlines in one path) and shapes (fill, then the outline with the heads).
  void inkItems(List<InkLayerItem> items) {
    for (final item in items) {
      switch (item) {
        case InkStrokeItem(:final stroke):
          _stroke(stroke);
        case InkObjectView(:final object):
          if (object is core.ShapeObject) _shape(object);
      }
    }
  }

  void _stroke(InkStroke s) {
    final opacity = _fillOpacity(s, options.pencilOpacityFactor);
    if (opacity <= 0) return;
    final outline = OutlineGenerator.outline(s);
    final path = outline.toVectorPath(smooth: options.smooth);
    if (path.verbs.isEmpty) return;
    _shapes.add(
      InkFillShape._(
        strokeId: s.id,
        tool: s.style.tool,
        path: path,
        colorArgb: _opaque(s.style.colorArgb),
        opacity: opacity,
      ),
    );
    _include(outline.bounds);
  }

  /// 6.9.5 / 6.21: the fill piece (fillColorArgb on a closed polyline or an ellipse —
  /// the screen's fill area), then the outline piece (the outline polygons of every
  /// centerline / dash piece, the dots, the arrow heads — one nonzero path, painted
  /// once). Both carry objectId = strokeId = the object id, tool = ballpoint
  /// (CP-INK-1); a piece with opacity 0 paints nothing on screen and is left out.
  void _shape(core.ShapeObject o) {
    final style = o.style;
    final fillArgb = style.fillColorArgb;
    final fillOpacity = shapeOpacity(style.fillOpacity);
    if (fillArgb != null && fillOpacity > 0) {
      final fill = _shapeFillPath(o);
      if (fill != null) _addShapePiece(o, fill, fillArgb, fillOpacity);
    }
    final strokeOpacity = shapeOpacity(style.strokeOpacity);
    if (strokeOpacity > 0) {
      final parts = shapeOutlinePartsOf(o);
      _addShapePiece(
        o,
        _outlinePath(parts),
        style.strokeColorArgb,
        strokeOpacity,
      );
    }
  }

  void _addShapePiece(
    core.ShapeObject o,
    InkVectorPath path,
    int argb,
    double opacity,
  ) {
    if (path.verbs.isEmpty) return;
    _shapes.add(
      InkFillShape._(
        strokeId: o.id,
        tool: core.PenTool.ballpoint,
        path: path,
        colorArgb: _opaque(argb),
        opacity: opacity,
        objectId: o.id,
      ),
    );
    _include(path.bounds);
  }

  /// Image objects (z order) with a drawable frame.
  void underlay(List<InkObjectView> views) {
    for (final view in views) {
      final o = view.object;
      if (o is! core.ImageObject || !_drawableFrame(o.frame)) continue;
      _underlay.add(
        InkImageVector._(
          assetId: o.assetId,
          frame: o.frame,
          pixelWidth: o.pixelWidth,
          pixelHeight: o.pixelHeight,
        ),
      );
      _include(view.bounds);
    }
  }

  /// Text boxes and formulas (z order) with a drawable frame; unknown objects are never
  /// exported (CP-INK-10).
  void annotations(List<InkObjectView> views) {
    for (final view in views) {
      final o = view.object;
      if (!_drawableFrame(o.frame)) continue;
      switch (o) {
        case core.TextBoxObject():
          _annotations.add(InkTextVector._(object: o, lines: _textLines(o)));
        case core.MathObject():
          _annotations.add(InkMathVector._(object: o));
        case core.ShapeObject() || core.ImageObject() || core.UnknownObject():
          continue;
      }
      _include(view.bounds);
    }
  }

  InkPageVectors build() => InkPageVectors._(
    highlighterGroups: List.unmodifiable([
      for (final g in _groupOrder)
        InkHighlighterGroup._(
          colorArgb: g.key.colorArgb,
          opacity: g.key.opacity,
          blend: blend,
          lines: List.unmodifiable(g.lines),
        ),
    ]),
    inkShapes: List.unmodifiable(_shapes),
    underlay: List.unmodifiable(_underlay),
    annotations: List.unmodifiable(_annotations),
    cover: List.unmodifiable(_cover),
    bounds: _bounds ?? Rect.zero,
  );
}

/// The screen draws a frame only with finite sides > 0 (6.8.4).
bool _drawableFrame(core.ElementFrame frame) {
  final r = frame.rect;
  return r.width > 0 &&
      r.height > 0 &&
      r.width.isFinite &&
      r.height.isFinite &&
      frame.center.x.isFinite &&
      frame.center.y.isFinite;
}

/// The fill area of [o] as drawn on screen (shapeGeometryOf(o).fill): a closed polyline
/// as its polygon (moveTo, lineTo…, close), an ellipse as 4 cubics (k = 0.5523) rotated
/// about its center; null when the shape has no fill area.
InkVectorPath? _shapeFillPath(core.ShapeObject o) {
  if (shapeGeometryOf(o).fill == null) return null;
  switch (o.geometry) {
    case core.PolylineGeometry(:final points):
      final pts = [
        for (final p in points)
          if (p.x.isFinite && p.y.isFinite) p,
      ];
      final verbs = Uint8List(pts.length + 1)
        ..fillRange(1, pts.length, InkPathVerb.lineTo.index);
      verbs[0] = InkPathVerb.moveTo.index;
      verbs[pts.length] = InkPathVerb.close.index;
      final coords = Float32List(2 * pts.length);
      for (var i = 0; i < pts.length; i++) {
        coords[2 * i] = pts[i].x;
        coords[2 * i + 1] = pts[i].y;
      }
      return InkVectorPath(verbs, coords);
    case core.EllipseGeometry(:final ellipseFrame):
      return _ellipsePath(ellipseFrame);
  }
}

/// The ellipse inscribed in [frame] (rotated about its center): moveTo + 4 cubics with
/// k = 0.5523 + close, from the local (a, 0) through (0, b) — positive orientation.
InkVectorPath _ellipsePath(core.ElementFrame frame) {
  final r = frame.rect;
  final a = r.width / 2, b = r.height / 2;
  final c = frame.center;
  final rot = frame.rotation.isFinite ? frame.rotation : 0.0;
  final cr = math.cos(rot), sr = math.sin(rot);
  const k = 0.5523;
  final local = <double>[
    a, 0, //
    a, k * b, k * a, b, 0, b,
    -k * a, b, -a, k * b, -a, 0,
    -a, -k * b, -k * a, -b, 0, -b,
    k * a, -b, a, -k * b, a, 0,
  ];
  final coords = Float32List(local.length);
  for (var i = 0; i < local.length; i += 2) {
    final x = local[i], y = local[i + 1];
    coords[i] = c.x + x * cr - y * sr;
    coords[i + 1] = c.y + x * sr + y * cr;
  }
  return InkVectorPath(
    Uint8List.fromList([
      InkPathVerb.moveTo.index,
      InkPathVerb.cubicTo.index,
      InkPathVerb.cubicTo.index,
      InkPathVerb.cubicTo.index,
      InkPathVerb.cubicTo.index,
      InkPathVerb.close.index,
    ]),
    coords,
  );
}

/// The outline piece of a shape (6.9.5): the line / dash-piece polygons, the dots as
/// circles (moveTo + 4 cubics, k = 0.5523 · r, from (x + r, y) through (x, y + r)), the
/// head triangles — every sub-path positively oriented, one nonzero path (S-10). The
/// polygons are moveTo, lineTo…, close (no smoothing: the heads keep their points).
InkVectorPath _outlinePath(ShapeOutlineParts parts) {
  final verbs = <int>[];
  final coords = <double>[];
  void polygon(Float32List poly) {
    final m = poly.length ~/ 2;
    if (m < 3) return;
    verbs
      ..add(InkPathVerb.moveTo.index)
      ..addAll(List.filled(m - 1, InkPathVerb.lineTo.index))
      ..add(InkPathVerb.close.index);
    coords.addAll(poly);
  }

  parts.pieces.forEach(polygon);
  final r = parts.dotRadius;
  final k = 0.5523 * r;
  for (final c in parts.dots) {
    final x = c.dx, y = c.dy;
    verbs.addAll([
      InkPathVerb.moveTo.index,
      InkPathVerb.cubicTo.index,
      InkPathVerb.cubicTo.index,
      InkPathVerb.cubicTo.index,
      InkPathVerb.cubicTo.index,
      InkPathVerb.close.index,
    ]);
    coords.addAll([
      x + r, y, //
      x + r, y + k, x + k, y + r, x, y + r,
      x - k, y + r, x - r, y + k, x - r, y,
      x - r, y - k, x - k, y - r, x, y - r,
      x + k, y - r, x + r, y - k, x + r, y,
    ]);
  }
  parts.heads.forEach(polygon);
  return InkVectorPath(Uint8List.fromList(verbs), Float32List.fromList(coords));
}

/// 6.21: the lines of the paragraph the annotation layer draws (textBoxParagraphOf —
/// the same layout): text of the line without its line break, x = the line's left,
/// baselineY, width — frame-local pt. Lines that start at or below the frame height are
/// left out (the frame clips them on screen). Empty while NoteSans is not loaded
/// (CP-INK-9 — PDF falls back to the raster) and for an empty text.
List<InkTextLine> _textLines(core.TextBoxObject o) {
  if (!InkFontsDebug.isLoaded) return const [];
  final paragraph = textBoxParagraphOf(o);
  if (paragraph == null) return const [];
  final metrics = paragraph.computeLineMetrics();
  if (metrics.isEmpty) return const [];
  final text = o.text;
  // the code-unit range of every line (a line without code units — the empty line after
  // a final line break — stays empty)
  final start = List<int>.filled(metrics.length, -1);
  final end = List<int>.filled(metrics.length, -1);
  for (var i = 0; i < text.length; i++) {
    final line = paragraph.getLineNumberAt(i);
    if (line == null || line < 0 || line >= metrics.length) continue;
    if (start[line] < 0) start[line] = i;
    end[line] = i + 1;
  }
  final height = o.frame.rect.height;
  final out = <InkTextLine>[];
  var top = 0.0;
  for (final m in metrics) {
    if (top >= height) break;
    final n = m.lineNumber;
    var lineText = n >= 0 && n < start.length && start[n] >= 0
        ? text.substring(start[n], end[n])
        : '';
    lineText = _withoutLineBreak(lineText);
    out.add(
      InkTextLine._(
        text: lineText,
        x: m.left,
        baselineY: m.baseline,
        width: m.width,
      ),
    );
    top += m.height;
  }
  return out;
}

/// [line] without one trailing line break (\n, \r\n, \r, U+2028, U+2029).
String _withoutLineBreak(String line) {
  if (line.endsWith('\r\n')) return line.substring(0, line.length - 2);
  if (line.endsWith('\n') ||
      line.endsWith('\r') ||
      line.endsWith(' ') ||
      line.endsWith(' ')) {
    return line.substring(0, line.length - 1);
  }
  return line;
}

final class _GroupBuilder {
  _GroupBuilder(this.key);
  final HighlighterGroupKey key;
  final List<InkHighlighterLine> lines = [];
}

/// Non-deleted strokes in core.Stroke.compareOrder (input already sorted is
/// kept as is — checked in O(n)).
List<InkStroke> _zOrdered(List<InkStroke> strokes) {
  var sorted = true;
  var deleted = false;
  for (var i = 0; i < strokes.length; i++) {
    if (strokes[i].source.deletedAt != null) deleted = true;
    if (i > 0 &&
        core.Stroke.compareOrder(strokes[i - 1].source, strokes[i].source) >
            0) {
      sorted = false;
    }
  }
  if (sorted && !deleted) return strokes;
  final out = [
    for (final s in strokes)
      if (s.source.deletedAt == null) s,
  ];
  if (!sorted) out.sort((a, b) => core.Stroke.compareOrder(a.source, b.source));
  return out;
}

/// Alpha 0xFF (K-5): transparency is the opacity field.
int _opaque(int argb) => 0xFF000000 + argb % 0x1000000;

/// The screen opacity (style.opacity × pencil tilt factor) × [pencilFactor]
/// for the textured pencil; clamped to [0, 1].
double _fillOpacity(InkStroke s, double pencilFactor) {
  var o = strokeOpacity(s);
  if (s.profile.textured) {
    o *= pencilFactor.isNaN
        ? InkTuning.exportPencilOpacityFactor
        : pencilFactor;
  }
  if (o.isNaN) return 1;
  return o.clamp(0.0, 1.0).toDouble();
}

/// The width of the segment a zero-length highlighter line becomes (pt).
const double _zeroLengthLinePt = 1e-3;

/// moveTo + lineTo through x,y pairs (kept, not copied); all points equal → a 0.001 pt
/// horizontal segment (see the file comment).
InkVectorPath _centerline(Float32List xy) {
  final n = xy.length ~/ 2;
  if (n == 0) return InkVectorPath(Uint8List(0), Float32List(0));
  final x0 = xy[0], y0 = xy[1];
  var zero = true;
  for (var i = 1; i < n && zero; i++) {
    if (xy[2 * i] != x0 || xy[2 * i + 1] != y0) zero = false;
  }
  if (zero) {
    return InkVectorPath(
      Uint8List.fromList([InkPathVerb.moveTo.index, InkPathVerb.lineTo.index]),
      Float32List.fromList([x0, y0, x0 + _zeroLengthLinePt, y0]),
    );
  }
  final verbs = Uint8List(n)..fillRange(1, n, InkPathVerb.lineTo.index);
  verbs[0] = InkPathVerb.moveTo.index;
  return InkVectorPath(verbs, xy);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Same verbs and coordinates (paths compare by content).
bool _pathEquals(InkVectorPath a, InkVectorPath b) {
  if (identical(a, b)) return true;
  if (a.verbs.length != b.verbs.length || a.coords.length != b.coords.length) {
    return false;
  }
  for (var i = 0; i < a.verbs.length; i++) {
    if (a.verbs[i] != b.verbs[i]) return false;
  }
  for (var i = 0; i < a.coords.length; i++) {
    if (a.coords[i] != b.coords[i]) return false;
  }
  return true;
}

int _pathHash(InkVectorPath p) =>
    Object.hash(p.verbs.length, p.coords.length, Object.hashAll(p.verbs));

// --- INTERNAL constructors (testing.dart InkVectorFixtures — 03-ink 4.12) ---------------

@internal
InkPageVectors newInkPageVectors({
  required List<InkHighlighterGroup> highlighterGroups,
  required List<InkFillShape> inkShapes,
  required List<InkImageVector> underlay,
  required List<InkAnnotationVector> annotations,
  required List<InkFillShape> cover,
  required Rect bounds,
}) => InkPageVectors._(
  highlighterGroups: List.unmodifiable(highlighterGroups),
  inkShapes: List.unmodifiable(inkShapes),
  bounds: bounds,
  underlay: List.unmodifiable(underlay),
  annotations: List.unmodifiable(annotations),
  cover: List.unmodifiable(cover),
);

@internal
InkFillShape newInkFillShape({
  required String strokeId,
  required core.PenTool tool,
  required InkVectorPath path,
  required int colorArgb,
  required double opacity,
  String? objectId,
}) => InkFillShape._(
  strokeId: strokeId,
  tool: tool,
  path: path,
  colorArgb: colorArgb,
  opacity: opacity,
  objectId: objectId,
);

@internal
InkHighlighterGroup newInkHighlighterGroup({
  required int colorArgb,
  required double opacity,
  required InkBlendMode blend,
  required List<InkHighlighterLine> lines,
}) => InkHighlighterGroup._(
  colorArgb: colorArgb,
  opacity: opacity,
  blend: blend,
  lines: List.unmodifiable(lines),
);

@internal
InkHighlighterLine newInkHighlighterLine({
  required String strokeId,
  required InkVectorPath centerline,
  required double width,
  required InkCap cap,
}) => InkHighlighterLine._(
  strokeId: strokeId,
  centerline: centerline,
  width: width,
  cap: cap,
);

@internal
InkImageVector newInkImageVector({
  required String assetId,
  required core.ElementFrame frame,
  required int pixelWidth,
  required int pixelHeight,
}) => InkImageVector._(
  assetId: assetId,
  frame: frame,
  pixelWidth: pixelWidth,
  pixelHeight: pixelHeight,
);

@internal
InkTextVector newInkTextVector({
  required core.TextBoxObject object,
  required List<InkTextLine> lines,
}) => InkTextVector._(object: object, lines: List.unmodifiable(lines));

@internal
InkTextLine newInkTextLine({
  required String text,
  required double x,
  required double baselineY,
  required double width,
}) => InkTextLine._(text: text, x: x, baselineY: baselineY, width: width);

@internal
InkMathVector newInkMathVector({required core.MathObject object}) =>
    InkMathVector._(object: object);
