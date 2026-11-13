// lib/src/tools/math_pen/math_pen_group.dart — (math pen, phase 1) the pure
// rules of the 수식 펜 (docs/plans/m5-7/research/math-pen-phase1.md 3.2, 7):
// which stroke joins the open group, which formula a stroke reopens, and the
// strokes a reopened formula gives back.
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:note_core/note_core.dart' as core;

/// The tuning of the math pen (design note 3.2, 7.1). H is the group's
/// typical stroke height: the median point-bounds height of its strokes,
/// dots left out, clamped to [[minLineHeightPt], [maxLineHeightPt]].
abstract final class MathPenTuning {
  /// A stroke joins when its horizontal gap to the group is ≤ this × H —
  /// room for the space between symbols (usually 0.3–1.0 H) and exponents;
  /// the next formula is usually ≥ 2 H away.
  static const double gapXFactor = 1.5;

  /// … and its vertical gap ≤ this × H — fraction bars, sub/superscripts and
  /// the inside of a root; the next line (≥ 1.2 H line spacing plus its own
  /// height) stays out.
  static const double gapYFactor = 1.0;

  /// Strokes lower than this (pt) are dots: left out of H.
  static const double dotHeightPt = 2;

  /// H is clamped to this range (pt): dots and dashes do not pull it to 0,
  /// a tall ∫ or bracket does not blow it up (the median does the rest).
  static const double minLineHeightPt = 8;
  static const double maxLineHeightPt = 72;

  /// A group holds at most this many strokes (= the ink a formula may keep).
  static const int maxGroupStrokes = core.PageObjectLimits.maxMathInkStrokes;

  /// A math pen stroke starting within frame + clamp(this × frame height,
  /// [minReopenMarginPt], [maxReopenMarginPt]) of a formula with ink reopens
  /// it.
  static const double reopenMarginFactor = 0.5;
  static const double minReopenMarginPt = 8;
  static const double maxReopenMarginPt = 40;

  /// Pen-up → recognition (design note 11.2, the brief's 0.4–0.6 s).
  static const Duration recognizeDelay = Duration(milliseconds: 500);
}

/// The point bounds of [s] (no width inflation) as a Rect.
Rect strokePointBounds(core.Stroke s) {
  final b = s.points.pointBounds;
  return Rect.fromLTRB(b.left, b.top, b.right, b.bottom);
}

/// The union of [strokes]' point bounds; Rect.zero when empty.
Rect unionPointBounds(Iterable<core.Stroke> strokes) {
  Rect? r;
  for (final s in strokes) {
    final b = strokePointBounds(s);
    r = r == null ? b : r.expandToInclude(b);
  }
  return r ?? Rect.zero;
}

/// H of a group whose strokes have point-bounds [heights] (see
/// [MathPenTuning]); [fallback] (the new stroke's height) when every stroke
/// is a dot or there is none.
double mathPenLineHeight(Iterable<double> heights, {double fallback = 0}) {
  final tall = [
    for (final h in heights)
      if (h >= MathPenTuning.dotHeightPt) h,
  ]..sort();
  final double base;
  if (tall.isEmpty) {
    base = fallback;
  } else {
    final mid = tall.length ~/ 2;
    base = tall.length.isOdd ? tall[mid] : (tall[mid - 1] + tall[mid]) / 2;
  }
  return base
      .clamp(MathPenTuning.minLineHeightPt, MathPenTuning.maxLineHeightPt)
      .toDouble();
}

/// Whether a stroke with point bounds [stroke] joins a group with bounds
/// [group] whose strokes have point-bounds [heights] (design note 3.2):
/// gapX ≤ 1.5 H and gapY ≤ 1.0 H, and the group is below its stroke limit.
bool mathPenJoins({
  required Rect group,
  required List<double> heights,
  required Rect stroke,
}) {
  if (heights.length >= MathPenTuning.maxGroupStrokes) return false;
  final h = mathPenLineHeight(heights, fallback: stroke.height);
  final gapX = math.max(
    0.0,
    math.max(stroke.left - group.right, group.left - stroke.right),
  );
  final gapY = math.max(
    0.0,
    math.max(stroke.top - group.bottom, group.top - stroke.bottom),
  );
  return gapX <= MathPenTuning.gapXFactor * h &&
      gapY <= MathPenTuning.gapYFactor * h;
}

/// The reopen margin of [math] (pt).
double mathReopenMargin(core.MathObject math) =>
    (MathPenTuning.reopenMarginFactor * math.frame.rect.height)
        .clamp(MathPenTuning.minReopenMarginPt, MathPenTuning.maxReopenMarginPt)
        .toDouble();

/// The formula a math pen stroke starting at [p] (page pt) reopens: a
/// MathObject of [objects] with ink whose frame + [mathReopenMargin] holds
/// [p]; several → the nearest frame centre, then the top one (z).
core.MathObject? reopenCandidateAt(
  Iterable<core.PageObject> objects,
  Offset p,
) {
  final point = core.PagePoint(p.dx, p.dy);
  core.MathObject? best;
  var bestDistance = double.infinity;
  for (final o in objects) {
    if (o is! core.MathObject || o.ink.isEmpty || o.isDeleted) continue;
    if (!o.frame.contains(point, tolerance: mathReopenMargin(o))) continue;
    final c = o.frame.center;
    final d = (Offset(c.x, c.y) - p).distance;
    // Later objects are on top: they win a tie.
    if (d <= bestDistance) {
      best = o;
      bestDistance = d;
    }
  }
  return best;
}

/// The formula under [p] exactly (no margin — a tap or a pen dot), top one.
core.MathObject? mathAt(Iterable<core.PageObject> objects, Offset p) {
  final point = core.PagePoint(p.dx, p.dy);
  core.MathObject? hit;
  for (final o in objects) {
    if (o is core.MathObject && !o.isDeleted && o.frame.contains(point)) {
      hit = o;
    }
  }
  return hit;
}

/// The handwriting [math] gives back when it is reopened (design note 7.2):
/// its ink with new ids ([newId]), its page, createdAt kept (z order),
/// updatedAt [now], no version or deletedAt; when the formula was recoloured
/// (its colour differs from the ink's most common colour) every stroke takes
/// the formula's colour.
List<core.Stroke> reopenedStrokes(
  core.MathObject math, {
  required String Function() newId,
  required core.EpochMillis now,
}) {
  final dominant = _dominantColor(math.ink);
  final recolor = dominant != null && dominant != math.style.colorArgb;
  return [
    for (final s in math.ink)
      core.Stroke(
        id: newId(),
        pageId: math.pageId,
        style: recolor
            ? s.style.copyWith(colorArgb: math.style.colorArgb)
            : s.style,
        points: s.points,
        recordingId: s.recordingId,
        recordingOffsetMs: s.recordingOffsetMs,
        createdAt: s.createdAt,
        updatedAt: now,
      ),
  ];
}

int? _dominantColor(List<core.Stroke> strokes) {
  final counts = <int, int>{};
  for (final s in strokes) {
    counts[s.style.colorArgb] = (counts[s.style.colorArgb] ?? 0) + 1;
  }
  int? best;
  var n = 0;
  for (final e in counts.entries) {
    if (e.value > n) (best, n) = (e.key, e.value);
  }
  return best;
}

/// The reopen command: [math] removed and [strokes] (its handwriting with new
/// ids, plus [written] — the stroke of this contact) added, in ONE step.
core.CompositeCommand reopenCommand(
  core.MathObject math,
  List<core.Stroke> strokes, {
  core.EditCommand? written,
}) => core.CompositeCommand([
  core.RemoveElements(pageId: math.pageId, elementIds: [math.id]),
  core.AddStrokes(pageId: math.pageId, strokes: strokes),
  ?written,
], label: written == null ? 'editor-math-reopen' : 'editor-math-reopen-write');
