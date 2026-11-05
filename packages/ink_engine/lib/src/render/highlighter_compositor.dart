// lib/src/render/highlighter_compositor.dart — INTERNAL (03-ink 6.10).
//
// Highlighters never get darker where they overlap: strokes with the same
// (opaque color, opacity rounded to 1/100) form a group, the group's lines are
// drawn OPAQUE (same color on same color = no change) inside one
// saveLayer(groupBounds, alpha = opacity, blend B), B = multiply on light
// paper and srcOver on dark paper. Groups are ordered by their lowest z.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

import '../geometry/outline_generator.dart';
import '../model/ink_stroke.dart';
import 'stroke_painter.dart';

/// (opaque color, opacity in 1/100) — the 6.10-1 group key.
@immutable
final class HighlighterGroupKey {
  const HighlighterGroupKey(this.colorArgb, this.opacityPercent);

  factory HighlighterGroupKey.of(core.StrokeStyle style, {int? colorArgb}) =>
      HighlighterGroupKey(
        0xFF000000 + (colorArgb ?? style.colorArgb) % 0x1000000,
        (style.opacity.clamp(0.0, 1.0) * 100).round(),
      );

  /// alpha 0xFF
  final int colorArgb;
  final int opacityPercent;

  double get opacity => opacityPercent / 100;

  @override
  bool operator ==(Object other) =>
      other is HighlighterGroupKey &&
      other.colorArgb == colorArgb &&
      other.opacityPercent == opacityPercent;

  @override
  int get hashCode => Object.hash(colorArgb, opacityPercent);

  @override
  String toString() =>
      'HighlighterGroupKey(0x${colorArgb.toRadixString(16)}, '
      '$opacityPercent%)';
}

/// One stroked centerline of a group.
final class HighlighterLine {
  HighlighterLine(this.xy, this.width);

  /// Centerline of a highlighter stroke.
  factory HighlighterLine.of(InkStroke stroke) => HighlighterLine(
    OutlineGenerator.polyline(stroke.points),
    stroke.style.width,
  );

  /// x,y pairs (page pt)
  final Float32List xy;
  final double width;

  /// Everything the stroke can touch: the square cap corners reach
  /// width / 2 · √2 from a centerline point (6.7 K-1 3).
  Rect get bounds {
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (var i = 0; i + 1 < xy.length; i += 2) {
      minX = math.min(minX, xy[i]);
      maxX = math.max(maxX, xy[i]);
      minY = math.min(minY, xy[i + 1]);
      maxY = math.max(maxY, xy[i + 1]);
    }
    if (minX > maxX) return Rect.zero;
    final e = width / 2 * math.sqrt2;
    return Rect.fromLTRB(minX - e, minY - e, maxX + e, maxY + e);
  }
}

/// The lines of one group, in z order.
final class HighlighterGroup {
  HighlighterGroup(this.key);

  final HighlighterGroupKey key;
  final List<HighlighterLine> lines = [];

  Rect get bounds {
    Rect? r;
    for (final l in lines) {
      final b = l.bounds;
      r = r == null ? b : r.expandToInclude(b);
    }
    return r ?? Rect.zero;
  }
}

/// Builds groups from (key, line) pairs given in z order; the result is
/// ordered by each group's lowest z (6.10-1).
List<HighlighterGroup> groupHighlighterLines(
  Iterable<(HighlighterGroupKey, HighlighterLine)> zOrdered,
) {
  final byKey = <HighlighterGroupKey, HighlighterGroup>{};
  final order = <HighlighterGroup>[];
  for (final (key, line) in zOrdered) {
    final g = byKey.putIfAbsent(key, () {
      final created = HighlighterGroup(key);
      order.add(created);
      return created;
    });
    g.lines.add(line);
  }
  return order;
}

/// Groups of committed highlighter strokes given in z order.
List<HighlighterGroup> groupHighlighters(Iterable<InkStroke> zOrdered) =>
    groupHighlighterLines([
      for (final s in zOrdered)
        (HighlighterGroupKey.of(s.style), HighlighterLine.of(s)),
    ]);

/// Paints one group (6.10-3): saveLayer(bounds + [marginPt], alpha =
/// opacity, [blend]) → every line opaque → restore. [extra] paints more
/// opaque content into the same layer (the stroke being written, 6.10-6) with
/// the group's opaque line paint; its area must be inside [extraBounds].
void paintHighlighterGroup(
  Canvas canvas,
  HighlighterGroup group, {
  required BlendMode blend,
  double marginPt = 0,
  void Function(Canvas canvas, Color opaqueColor)? extra,
  Rect? extraBounds,
}) {
  var bounds = group.bounds;
  if (extraBounds != null) {
    bounds = group.lines.isEmpty
        ? extraBounds
        : bounds.expandToInclude(extraBounds);
  }
  if (bounds.isEmpty && extra == null) return;
  final opaque = Color(group.key.colorArgb);
  canvas.saveLayer(
    bounds.inflate(marginPt),
    Paint()
      ..color = inkColor(0, group.key.opacity)
      ..blendMode = blend,
  );
  for (final line in group.lines) {
    drawHighlighterLine(
      canvas,
      line.xy,
      highlighterLinePaint(line.width, opaque),
    );
  }
  extra?.call(canvas, opaque);
  canvas.restore();
}

/// Paints [groups] in order on paper [paperColorArgb] (6.10-4 blend).
void paintHighlighterGroups(
  Canvas canvas,
  Iterable<HighlighterGroup> groups, {
  required int paperColorArgb,
  double marginPt = 0,
}) {
  final blend = highlighterBlendFor(paperColorArgb);
  for (final g in groups) {
    paintHighlighterGroup(canvas, g, blend: blend, marginPt: marginPt);
  }
}
