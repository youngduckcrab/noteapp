// lib/src/lines/glyph_boxes.dart — (internal) steps 1–3 of the line grouping
// (m5-7/05-library 6.5): stroke boxes, glyph boxes (union of overlapping
// widened stroke boxes) and the glyph height H. Pure Dart; web safe.
import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../model/handwriting_trace.dart';
import 'line_tuning.dart';

/// An axis-aligned box in page pt.
@immutable
final class InkBox {
  const InkBox(this.left, this.top, this.right, this.bottom);

  final double left, top, right, bottom;

  double get width => right - left;
  double get height => bottom - top;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;

  InkBox union(InkBox other) => InkBox(
    math.min(left, other.left),
    math.min(top, other.top),
    math.max(right, other.right),
    math.max(bottom, other.bottom),
  );

  @override
  bool operator ==(Object other) =>
      other is InkBox &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'InkBox($left, $top, $right, $bottom)';
}

/// The box of [trace]'s points; null when it has none (6.5 step 1).
InkBox? traceBox(HandwritingTrace trace) {
  final xs = trace.xs, ys = trace.ys;
  if (xs.isEmpty) return null;
  var left = xs[0], right = xs[0], top = ys[0], bottom = ys[0];
  for (var i = 1; i < xs.length; i++) {
    final x = xs[i], y = ys[i];
    if (x < left) left = x;
    if (x > right) right = x;
    if (y < top) top = y;
    if (y > bottom) bottom = y;
  }
  return InkBox(left, top, right, bottom);
}

/// Median of [values] (mean of the middle two for an even count); 0 when
/// empty.
double medianOf(Iterable<double> values) {
  final sorted = values.toList()..sort();
  final n = sorted.length;
  if (n == 0) return 0;
  return n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}

/// A glyph box: the union of the stroke boxes of [strokes] (indices into the
/// box list given to [buildGlyphBoxes], ascending).
final class GlyphBox {
  GlyphBox(this.box, this.strokes);

  final InkBox box;
  final List<int> strokes;

  /// Tie-break key — the smallest stroke index.
  int get key => strokes.first;
}

/// h_s of 6.5 step 2: the median height of [boxes], at least
/// minStrokeHeight.
double strokeHeightOf(
  Iterable<InkBox> boxes, {
  LineTuning tuning = kLineTuning,
}) => math.max(
  tuning.minStrokeHeight,
  medianOf([for (final b in boxes) b.height]),
);

/// 6.5 step 2: boxes widened by glyphInflateX / glyphInflateY × h_s (the
/// median box height, at least minStrokeHeight — or [strokeHeight] when
/// given: the indexer widens a line's added strokes by that line's h_s,
/// 6.9.4 ②) that overlap are joined (union-find, a sweep by left edge that
/// compares live boxes only). Glyphs come in the order of their smallest
/// stroke index.
List<GlyphBox> buildGlyphBoxes(
  List<InkBox> boxes, {
  LineTuning tuning = kLineTuning,
  double? strokeHeight,
}) {
  final n = boxes.length;
  if (n == 0) return const [];
  final hs = strokeHeight ?? strokeHeightOf(boxes, tuning: tuning);
  final ex = tuning.glyphInflateX * hs;
  final ey = tuning.glyphInflateY * hs;
  final parent = List<int>.generate(n, (i) => i);
  int find(int a) {
    var x = a;
    while (parent[x] != x) {
      parent[x] = parent[parent[x]];
      x = parent[x];
    }
    return x;
  }

  final byLeft = List<int>.generate(n, (i) => i)
    ..sort((a, b) {
      final c = boxes[a].left.compareTo(boxes[b].left);
      return c != 0 ? c : a.compareTo(b);
    });
  final live = <int>[];
  for (final i in byLeft) {
    final bi = boxes[i];
    live.removeWhere((j) => boxes[j].right + ex < bi.left - ex);
    for (final j in live) {
      final bj = boxes[j];
      if (bj.left - ex <= bi.right + ex &&
          bi.left - ex <= bj.right + ex &&
          bj.top - ey <= bi.bottom + ey &&
          bi.top - ey <= bj.bottom + ey) {
        final ra = find(i), rb = find(j);
        if (ra != rb) parent[math.max(ra, rb)] = math.min(ra, rb);
      }
    }
    live.add(i);
  }
  final members = <int, List<int>>{};
  for (var i = 0; i < n; i++) {
    (members[find(i)] ??= <int>[]).add(i);
  }
  return [
    for (final strokes in members.values)
      GlyphBox(
        strokes.map((i) => boxes[i]).reduce((a, b) => a.union(b)),
        strokes,
      ),
  ];
}

/// 6.5 step 3: the median glyph-box height, again without boxes lower than
/// smallBoxRatio × the first median (dots, commas); at least minGlyphHeight.
double glyphHeightOf(List<GlyphBox> glyphs, {LineTuning tuning = kLineTuning}) {
  final first = medianOf([for (final g in glyphs) g.box.height]);
  final height = medianOf([
    for (final g in glyphs)
      if (g.box.height >= tuning.smallBoxRatio * first) g.box.height,
  ]);
  return math.max(height, tuning.minGlyphHeight);
}

/// The glyph height H (pt) of [traces] — 6.5 steps 1–3 (what the text box
/// builder and the writing area use for a line, 6.4 / 6.13.4). Traces
/// without points are ignored; no points at all → minGlyphHeight.
double estimateGlyphHeight(
  List<HandwritingTrace> traces, {
  LineTuning tuning = kLineTuning,
}) {
  final boxes = [for (final t in traces) ?traceBox(t)];
  return glyphHeightOf(buildGlyphBoxes(boxes, tuning: tuning), tuning: tuning);
}
