// lib/src/lines/group_into_lines.dart — contract m5-7/00-overview 7.2.11
// (m5-7/05-library 4.4.6, 6.5).
//
// L2-05: the 6.5 algorithm, ported from the E-L5 prototype (7.3 —
// lines/lib/group_lines.dart, confirmed constants 0.5 / 0.1):
//  1. drop strokes without points; a box per stroke;
//  2. glyph boxes — overlapping widened stroke boxes joined (glyph_boxes.dart);
//  3. the glyph height H — median glyph-box height without small boxes;
//  4. line chains — big boxes (≥ 0.35·H) left to right; a box joins the line
//     whose right end is within gapFactor·H and whose last two big boxes
//     overlap it vertically by ≥ 0.5 (the best ratio, then the nearest
//     centre), else it starts a line — so slanted lines still chain;
//  5. small boxes join the line whose band (± 0.6·H) holds their centre y and
//     whose span (± gapFactor·H) holds their centre x, nearest to the centre
//     y of the horizontally nearest big box; otherwise a line of their own;
//  6. lines by band top, then left; strokes in a line by first-sample time,
//     then input order.
// Every sort key ends with the input index, so the result is deterministic
// (and, without exact ties, independent of the input order). Constants:
// line_tuning.dart.
import 'dart:math' as math;

import '../model/handwriting_trace.dart';
import 'glyph_boxes.dart';
import 'line_tuning.dart';

/// Pure Dart line grouping (search indexing AND lasso conversion use the same function).
/// (v2.1, CP-L7) Lines in reading order, strokes in a line by first-sample time; gapFactor = the
/// horizontal gap that still joins a line ÷ the median glyph-box height; deterministic.
List<List<HandwritingTrace>> groupIntoLines(
  List<HandwritingTrace> traces, {
  double gapFactor = 1.2,
}) => [
  for (final line in groupTraceIndices(traces, gapFactor: gapFactor))
    [for (final i in line) traces[i]],
];

/// [groupIntoLines] as indices into [traces] (tests, the indexer's line
/// bookkeeping).
List<List<int>> groupTraceIndices(
  List<HandwritingTrace> traces, {
  double gapFactor = 1.2,
  LineTuning tuning = kLineTuning,
}) {
  // 1. Strokes with points and their boxes.
  final input = <int>[];
  final boxes = <InkBox>[];
  for (var i = 0; i < traces.length; i++) {
    if (traceBox(traces[i]) case final box?) {
      input.add(i);
      boxes.add(box);
    }
  }
  if (input.isEmpty) return const [];
  double t0(int i) => traces[i].ts.isEmpty ? 0 : traces[i].ts[0];

  // 2–3. Glyph boxes (stroke numbers = positions in [input]) and H.
  final glyphs = buildGlyphBoxes(boxes, tuning: tuning);
  final height = glyphHeightOf(glyphs, tuning: tuning);
  final smallLimit = tuning.smallBoxRatio * height;
  int byLeftTop(GlyphBox a, GlyphBox b) {
    var c = a.box.left.compareTo(b.box.left);
    if (c != 0) return c;
    c = a.box.top.compareTo(b.box.top);
    return c != 0 ? c : a.key.compareTo(b.key);
  }

  final big = [
    for (final g in glyphs)
      if (g.box.height >= smallLimit) g,
  ]..sort(byLeftTop);
  final small = [
    for (final g in glyphs)
      if (g.box.height < smallLimit) g,
  ]..sort(byLeftTop);

  // 4. Line chains.
  final maxGap = gapFactor * height;
  final lines = <_Line>[];
  for (final g in big) {
    _Line? best;
    var bestRatio = -1.0;
    var bestDy = double.infinity;
    for (final line in lines) {
      if (g.box.left - line.right > maxGap) continue;
      final band = line.tailBand(tuning.tailBoxes);
      final overlap =
          math.min(g.box.bottom, band.bottom) - math.max(g.box.top, band.top);
      if (overlap <= 0) continue;
      final ratio = overlap / math.min(g.box.height, band.height);
      if (ratio < tuning.minVerticalOverlap) continue;
      final dy = (g.box.centerY - band.centerY).abs();
      if (ratio > bestRatio || (ratio == bestRatio && dy < bestDy)) {
        best = line;
        bestRatio = ratio;
        bestDy = dy;
      }
    }
    (best ?? (lines..add(_Line())).last).addBig(g);
  }

  // 5. Small boxes.
  final slack = tuning.smallAttachBand * height;
  final alone = <_Line>[];
  for (final s in small) {
    _Line? best;
    var bestDistance = double.infinity;
    final cx = s.box.centerX, cy = s.box.centerY;
    for (final line in lines) {
      final band = line.bigBand;
      if (cy < band.top - slack || cy > band.bottom + slack) continue;
      if (cx < line.big.first.box.left - maxGap || cx > line.right + maxGap) {
        continue;
      }
      var near = line.big.first;
      for (final g in line.big) {
        if ((g.box.centerX - cx).abs() < (near.box.centerX - cx).abs()) {
          near = g;
        }
      }
      final distance = (cy - near.box.centerY).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = line;
      }
    }
    if (best == null) {
      alone.add(_Line()..small.add(s));
    } else {
      best.small.add(s);
    }
  }

  // 6. Reading order; strokes in a line by first-sample time.
  final ordered = [...lines, ...alone]
    ..sort((a, b) {
      final ba = a.band, bb = b.band;
      var c = ba.top.compareTo(bb.top);
      if (c != 0) return c;
      c = ba.left.compareTo(bb.left);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return [
    for (final line in ordered)
      [
        for (final g in [...line.big, ...line.small])
          for (final k in g.strokes) input[k],
      ]..sort((a, b) {
        final c = t0(a).compareTo(t0(b));
        return c != 0 ? c : a.compareTo(b);
      }),
  ];
}

final class _Line {
  final List<GlyphBox> big = [];
  final List<GlyphBox> small = [];
  double right = double.negativeInfinity;
  InkBox? _bigBand;
  InkBox? _band;
  int? _key;

  void addBig(GlyphBox g) {
    big.add(g);
    right = math.max(right, g.box.right);
    final band = _bigBand;
    _bigBand = band == null ? g.box : band.union(g.box);
  }

  /// Union of the big boxes (a line from step 4 has at least one).
  InkBox get bigBand => _bigBand!;

  /// Union of the last [count] big boxes.
  InkBox tailBand(int count) {
    var band = big.last.box;
    for (var i = math.max(0, big.length - count); i < big.length - 1; i++) {
      band = band.union(big[i].box);
    }
    return band;
  }

  /// Union of all its boxes (asked for after step 5 only).
  InkBox get band => _band ??= [
    ...big,
    ...small,
  ].map((g) => g.box).reduce((a, b) => a.union(b));

  /// Tie-break key — the smallest stroke number in the line.
  int get key => _key ??= [
    for (final g in big) g.key,
    for (final g in small) g.key,
  ].reduce(math.min);
}
