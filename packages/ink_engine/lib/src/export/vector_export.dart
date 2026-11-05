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
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

import '../geometry/outline_generator.dart';
import '../geometry/vector_path.dart';
import '../model/ink_layer.dart';
import '../model/ink_stroke.dart';
import '../pen/pen_profile.dart';
import '../render/highlighter_compositor.dart';
import '../render/ink_page_content.dart';
import '../render/stroke_painter.dart' show strokeOpacity;
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
final class InkFillShape {
  InkFillShape._({
    required this.strokeId,
    required this.tool,
    required this.path,
    required this.colorArgb,
    required this.opacity,
  });
  final String strokeId;
  final core.PenTool tool;

  /// nonzero fill
  final InkVectorPath path;
  final int colorArgb;
  final double opacity;
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
}

final class InkPageVectors {
  InkPageVectors._({
    required this.highlighterGroups,
    required this.inkShapes,
    required this.bounds,
  });

  static final InkPageVectors _empty = InkPageVectors._(
    highlighterGroups: const [],
    inkShapes: const [],
    bounds: Rect.zero,
  );

  /// draw first (below ink)
  final List<InkHighlighterGroup> highlighterGroups;

  /// then these, in order
  final List<InkFillShape> inkShapes;
  final Rect bounds;
  bool get isEmpty => highlighterGroups.isEmpty && inkShapes.isEmpty;
}

abstract final class InkVectorExport {
  static InkPageVectors exportStrokes(
    List<InkStroke> strokes, {
    InkExportOptions options = const InkExportOptions(),
  }) {
    final zOrdered = _zOrdered(strokes);
    if (zOrdered.isEmpty) return InkPageVectors._empty;
    final blend = core.PaperColors.isDark(options.paperColorArgb)
        ? InkBlendMode.normal
        : InkBlendMode.multiply;
    final groups = <HighlighterGroupKey, _GroupBuilder>{};
    final groupOrder = <_GroupBuilder>[];
    final shapes = <InkFillShape>[];
    Rect? bounds;
    void include(Rect r) =>
        bounds = bounds == null ? r : bounds!.expandToInclude(r);

    for (final s in zOrdered) {
      if (s.layer == InkLayer.highlighter) {
        final key = HighlighterGroupKey.of(s.style);
        if (key.opacityPercent <= 0) continue;
        final line = HighlighterLine.of(s);
        final g = groups.putIfAbsent(key, () {
          final created = _GroupBuilder(key);
          groupOrder.add(created);
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
        include(line.bounds);
        continue;
      }
      final opacity = _fillOpacity(s, options.pencilOpacityFactor);
      if (opacity <= 0) continue;
      final outline = OutlineGenerator.outline(s);
      final path = outline.toVectorPath(smooth: options.smooth);
      if (path.verbs.isEmpty) continue;
      shapes.add(
        InkFillShape._(
          strokeId: s.id,
          tool: s.style.tool,
          path: path,
          colorArgb: _opaque(s.style.colorArgb),
          opacity: opacity,
        ),
      );
      include(outline.bounds);
    }
    return InkPageVectors._(
      highlighterGroups: List.unmodifiable([
        for (final g in groupOrder)
          InkHighlighterGroup._(
            colorArgb: g.key.colorArgb,
            opacity: g.key.opacity,
            blend: blend,
            lines: List.unmodifiable(g.lines),
          ),
      ]),
      inkShapes: List.unmodifiable(shapes),
      bounds: bounds ?? Rect.zero,
    );
  }

  /// options == null → InkExportOptions(paperColorArgb: content.background.paperColorArgb).
  static InkPageVectors exportPage(
    InkPageContent content, {
    InkExportOptions? options,
  }) => exportStrokes(
    content.strokes,
    options:
        options ??
        InkExportOptions(paperColorArgb: content.background.paperColorArgb),
  );
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
