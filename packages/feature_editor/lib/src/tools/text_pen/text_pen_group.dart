// lib/src/tools/text_pen/text_pen_group.dart — (text pen, phase 1 —
// m5-7/04-editor 6.21) the pure rule of the 텍스트 펜: which stroke joins the
// open group. H is the math pen's (the median point-bounds height of the
// members, dots left out, clamped to 8–72 pt — mathPenLineHeight).
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:note_core/note_core.dart' as core;

import '../math_pen/math_pen_group.dart' show mathPenLineHeight;

abstract final class TextPenTuning {
  /// On the same row a stroke joins when its horizontal gap to the nearest
  /// member is ≤ this × H — room for the space between words (usually
  /// 0.5–1.5 H); text further away is another note.
  static const double gapXFactor = 2.5;

  /// … and its vertical gap to that member ≤ this × H (the same row:
  /// descenders, accents, a dot above the line).
  static const double gapYFactor = 0.6;

  /// The next row joins when it starts ≤ this × H below the group (ruled
  /// paper: 0.5–0.9 H between the rows) and overlaps the group sideways.
  static const double nextRowGapFactor = 1.2;

  /// A next row may start this × H left of the group (a ragged margin).
  static const double nextRowLeftSlackFactor = 1.0;

  /// The bubble keeps this × H clear above the group, [bubbleBelowFactor] ×
  /// H below it (where the next row starts — the bubble takes the pointer).
  static const double bubbleAboveFactor = 1.0;
  static const double bubbleBelowFactor = 1.4;

  /// A group holds at most this many rows (the conversion sheet's 20 lines),
  /// strokes and points (the cost of one recognition).
  static const int maxRows = 20;
  static const int maxGroupStrokes = core.PageObjectLimits.maxMathInkStrokes;
  static const int maxGroupPoints = core.PageObjectLimits.maxMathInkPoints;
}

/// How many rows [members] (point bounds) form: sorted by their vertical
/// centre, a member whose centre lies below the current row's bottom starts
/// a new row.
int textPenRowCount(List<Rect> members) {
  if (members.isEmpty) return 0;
  final sorted = [...members]
    ..sort((a, b) => a.center.dy.compareTo(b.center.dy));
  var rows = 1;
  var bottom = sorted.first.bottom;
  for (final m in sorted.skip(1)) {
    if (m.center.dy > bottom) {
      rows++;
      bottom = m.bottom;
    } else {
      bottom = math.max(bottom, m.bottom);
    }
  }
  return rows;
}

/// Whether a stroke with point bounds [stroke] ([strokePoints] points) joins
/// a text pen group whose members have point bounds [members] and
/// [groupPoints] points in all: on the same row (gapX ≤ 2.5 H, gapY ≤ 0.6 H
/// to the nearest member) or as the next row (≤ 1.2 H below the group,
/// overlapping it sideways), and within the stroke, point and row limits.
bool textPenJoins({
  required List<Rect> members,
  required Rect stroke,
  int groupPoints = 0,
  int strokePoints = 0,
}) {
  if (members.isEmpty) return false;
  if (members.length + 1 > TextPenTuning.maxGroupStrokes) return false;
  if (groupPoints + strokePoints > TextPenTuning.maxGroupPoints) return false;
  final h = mathPenLineHeight([
    for (final m in members) m.height,
  ], fallback: stroke.height);
  final maxX = TextPenTuning.gapXFactor * h;
  final maxY = TextPenTuning.gapYFactor * h;
  for (final m in members) {
    final gapX = math.max(
      0.0,
      math.max(stroke.left - m.right, m.left - stroke.right),
    );
    final gapY = math.max(
      0.0,
      math.max(stroke.top - m.bottom, m.top - stroke.bottom),
    );
    if (gapX <= maxX && gapY <= maxY) return true;
  }
  // The next row.
  var union = members.first;
  for (final m in members.skip(1)) {
    union = union.expandToInclude(m);
  }
  final below = stroke.top - union.bottom;
  if (below > TextPenTuning.nextRowGapFactor * h) return false;
  if (stroke.bottom <= union.bottom) return false; // not below: another note
  final overlaps =
      stroke.left <= union.right &&
      stroke.right >= union.left - TextPenTuning.nextRowLeftSlackFactor * h;
  if (!overlaps) return false;
  return textPenRowCount([...members, stroke]) <= TextPenTuning.maxRows;
}
