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
  /// the inside of a root (usually 0–0.5 H). Both gaps are measured to the
  /// NEAREST member stroke (not to the group's union bounds), so a group
  /// that already spans a fraction does not reach further down. The next
  /// line of ruled paper (8 mm ≈ 23 pt pitch, H ≈ 12–15 pt) is 0.5–0.9 H
  /// below the letters of this one: 0.6 keeps most of it out (a tight hand
  /// on narrow rules still joins — nothing is lost, it is one formula).
  static const double gapYFactor = 0.6;

  /// The bubble keeps this × H clear above and below the group (more than
  /// [gapYFactor]: a stroke of the next symbol — the bar of a "+" — often
  /// starts above the group's bounds, and a stroke that starts on the bubble
  /// is not drawn).
  static const double bubbleClearanceFactor = 1.0;

  /// Strokes lower than this (pt) are dots: left out of H.
  static const double dotHeightPt = 2;

  /// H is clamped to this range (pt): dots and dashes do not pull it to 0,
  /// a tall ∫ or bracket does not blow it up (the median does the rest).
  static const double minLineHeightPt = 8;
  static const double maxLineHeightPt = 72;

  /// A group holds at most this many strokes and points (= the ink a
  /// formula may keep): a stroke that would go over starts a new group, and
  /// a formula is not reopened by a stroke that would take it over.
  static const int maxGroupStrokes = core.PageObjectLimits.maxMathInkStrokes;
  static const int maxGroupPoints = core.PageObjectLimits.maxMathInkPoints;

  /// A math pen stroke starting within the frame grown by clamp(this ×
  /// frame height, [minReopenMarginPt], [maxReopenMarginPt]) left and right
  /// (the next symbol, "+1" after x²) …
  static const double reopenMarginFactor = 0.5;
  static const double minReopenMarginPt = 8;
  static const double maxReopenMarginPt = 40;

  /// … and clamp(this × frame height, [minReopenMarginYPt],
  /// [maxReopenMarginYPt]) up and down (an exponent, a denominator) of a
  /// formula with ink reopens it — less than sideways, so the next line
  /// started under a formula does not reopen it.
  static const double reopenMarginYFactor = 0.3;
  static const double minReopenMarginYPt = 4;
  static const double maxReopenMarginYPt = 16;

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

/// Whether a stroke with point bounds [stroke] ([strokePoints] points) joins
/// a group whose member strokes have point bounds [members] and
/// [groupPoints] points in all (design note 3.2): gapX ≤ 1.5 H and gapY ≤
/// 0.6 H to the nearest member (H from the members' heights), and the group
/// stays within its stroke and point limits.
bool mathPenJoins({
  required List<Rect> members,
  required Rect stroke,
  int groupPoints = 0,
  int strokePoints = 0,
}) {
  if (members.isEmpty) return false;
  if (members.length + 1 > MathPenTuning.maxGroupStrokes) return false;
  if (groupPoints + strokePoints > MathPenTuning.maxGroupPoints) return false;
  final h = mathPenLineHeight([
    for (final m in members) m.height,
  ], fallback: stroke.height);
  final maxX = MathPenTuning.gapXFactor * h;
  final maxY = MathPenTuning.gapYFactor * h;
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
  return false;
}

/// Whether [strokes] plus [extra] stay within the ink a formula may keep
/// (PageObjectLimits.maxMathInkStrokes / maxMathInkPoints).
bool mathInkWithin(Iterable<core.Stroke> strokes, {core.Stroke? extra}) {
  var n = 0;
  var points = 0;
  for (final s in [...strokes, ?extra]) {
    n++;
    points += s.points.length;
  }
  return n <= MathPenTuning.maxGroupStrokes &&
      points <= MathPenTuning.maxGroupPoints;
}

/// The reopen margin of [math] left and right (pt).
double mathReopenMargin(core.MathObject math) =>
    (MathPenTuning.reopenMarginFactor * math.frame.rect.height)
        .clamp(MathPenTuning.minReopenMarginPt, MathPenTuning.maxReopenMarginPt)
        .toDouble();

/// The reopen margin of [math] up and down (pt).
double mathReopenMarginY(core.MathObject math) =>
    (MathPenTuning.reopenMarginYFactor * math.frame.rect.height)
        .clamp(
          MathPenTuning.minReopenMarginYPt,
          MathPenTuning.maxReopenMarginYPt,
        )
        .toDouble();

/// Whether [p] (page pt), turned back by −rotation about the frame centre
/// (as ElementFrame.contains), lies in [frame] grown by [mx] / [my].
bool _inFrame(core.ElementFrame frame, Offset p, double mx, double my) {
  final r = frame.rect;
  final c = frame.center;
  final cos = math.cos(frame.rotation), sin = math.sin(frame.rotation);
  final dx = p.dx - c.x, dy = p.dy - c.y;
  final x = frame.rotation == 0 ? p.dx : c.x + cos * dx + sin * dy;
  final y = frame.rotation == 0 ? p.dy : c.y - sin * dx + cos * dy;
  return x >= r.left - mx &&
      x <= r.right + mx &&
      y >= r.top - my &&
      y <= r.bottom + my;
}

/// The formula a math pen stroke starting at [p] (page pt) reopens: a
/// MathObject of [objects] with ink whose frame grown by [mathReopenMargin]
/// sideways and [mathReopenMarginY] up and down holds [p]; several → the
/// nearest frame centre, then the top one (z).
core.MathObject? reopenCandidateAt(
  Iterable<core.PageObject> objects,
  Offset p,
) {
  core.MathObject? best;
  var bestDistance = double.infinity;
  for (final o in objects) {
    if (o is! core.MathObject || o.ink.isEmpty || o.isDeleted) continue;
    if (!_inFrame(o.frame, p, mathReopenMargin(o), mathReopenMarginY(o))) {
      continue;
    }
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
/// (its colour differs from the ink's most common colour, both compared
/// opaque — recog's dominantColorOf rule) every stroke takes the formula's
/// colour.
List<core.Stroke> reopenedStrokes(
  core.MathObject math, {
  required String Function() newId,
  required core.EpochMillis now,
}) {
  final dominant = _dominantColor(math.ink);
  final recolor = dominant != null && dominant != _opaque(math.style.colorArgb);
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

int _opaque(int argb) => 0xFF000000 + argb % 0x1000000;

/// The colour most of [strokes] use, compared opaque; a tie → the first in
/// z order (the same rule as recog's dominantColorOf).
int? _dominantColor(List<core.Stroke> strokes) {
  final counts = <int, int>{}; // insertion order = first use in z order
  for (final s in [...strokes]..sort(core.Stroke.compareOrder)) {
    final c = _opaque(s.style.colorArgb);
    counts[c] = (counts[c] ?? 0) + 1;
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
