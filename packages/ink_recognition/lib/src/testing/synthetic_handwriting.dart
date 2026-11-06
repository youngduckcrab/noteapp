// lib/src/testing/synthetic_handwriting.dart — body of
// package:ink_recognition/testing.dart SyntheticHandwriting (contract
// m5-7/00-overview 7.6, m5-7/05-library 4.3, 6.6 v2.1).
//
// L2-05: the 6.6 v2.1 generator, ported from the E-L5 prototype (7.3 —
// lines/lib/synth.dart, Mode.v21, fill: true, connected: true) with the same
// Random(seed) call order, so a seed gives the prototype's page (pinned by
// unit/synthetic_handwriting_test.dart). Random(seed) only, no clock:
//  - page 595 pt, margin 40 pt; per page H ∈ [14, 28] pt, line pitch
//    ∈ [1.6, 2.4]·H, slant θp ∈ [−4°, 4°] about the column centre
//    (297.5, 421); per line δ ∈ [−1°, 1°] about the line centre;
//  - 2–5 words a line (gap 0.4–0.9·H), 2–5 glyphs a word (width 0.8–1.1·H,
//    gap 0.05–0.2·H, size ±15 %, baseline jitter ±0.08·H); a word past
//    555 pt ends the line;
//  - a glyph is 1–4 strokes of 6–20 points (random walk, step
//    0.25·min(w, h), 3-point average); every further stroke starts on a
//    point of the previous one; the glyph's ink is then stretched so its
//    box IS the glyph box;
//  - 10 % of the glyphs get a small mark (0.1–0.2·H high, above or at the
//    lower right), drawn after the whole line;
//  - neighbouring lines: every horizontally overlapping pair of glyph / mark
//    boxes keeps a gap ≥ 0.25·H — the line is drawn again (≤ 50 times),
//    then moved down by what is missing (the prototype drew it once more at
//    the lower baseline; E-L5 never got there — 0 of 200 pages);
//  - times: 8 ms between points, 80–200 ms between strokes, 600–1,500 ms
//    between lines; createdAt from 1,730,790,000,000.
import 'dart:math' as math;

import 'package:note_core/note_core.dart' as core;

import '../lines/glyph_boxes.dart' show InkBox;

const double _pageWidth = 595;
const double _margin = 40;
const double _rightLimit = _pageWidth - _margin;
const double _pageCenterX = _pageWidth / 2;
const double _pageCenterY = 421;
const double _minLineGap = 0.25; // × H
const int _maxRedraws = 50;
const int _baseCreatedAt = 1730790000000;
const int _pointIntervalMs = 8;

// Stroke id 'syn_<seed>_l<line, 2 digits>_<n, 4 digits>': line from 0, n =
// stroke number on the page from 0 (both in writing order).
String _strokeId(int seed, int line, int n) =>
    'syn_${seed}_l${line.toString().padLeft(2, '0')}_'
    '${n.toString().padLeft(4, '0')}';

abstract final class SyntheticHandwriting {
  // fixed-seed lines as core.Stroke lists
  /// (v2.1) stroke ids `'syn_<seed>_l<line>_<n>'` (CP-L4)
  // Line from 0 (2 digits), n = stroke number on the page from 0 (4 digits);
  // createdAt increases in writing order. lineCount outside 0..99 →
  // ArgumentError (the id has two line digits).
  static List<core.Stroke> lines({
    required String pageId,
    int lineCount = 5,
    int seed = 1,
  }) => synthesizeHandwriting(
    pageId: pageId,
    lineCount: lineCount,
    seed: seed,
  ).strokes;
}

/// (internal) What the generator drew — tests check the 6.6 rules on it.
final class SyntheticPage {
  SyntheticPage._(
    this.strokes,
    this.glyphHeight,
    this.pageSlant,
    this.lines,
    this.redraws,
    this.shifted,
  );

  final List<core.Stroke> strokes;

  /// H (pt).
  final double glyphHeight;

  /// θp (radians), about (297.5, 421).
  final double pageSlant;
  final List<SyntheticLine> lines;

  /// Lines drawn again for the gap rule / lines moved down.
  final int redraws, shifted;
}

/// (internal) One line: its glyphs (then its marks) in drawing order.
final class SyntheticLine {
  SyntheticLine._(
    this.index,
    this.slant,
    this.centerX,
    this.centerY,
    this.pageSlant,
    this.shiftY,
    this.glyphs,
  );

  final int index;

  /// δ (radians), about ([centerX], [centerY]) in line coordinates.
  final double slant;
  final double centerX, centerY;
  final double pageSlant;

  /// How far the line was moved down after the redraws (pt; 0 normally).
  final double shiftY;
  final List<SyntheticGlyph> glyphs;

  /// Line coordinates (glyph boxes are axis-aligned there) → page pt.
  (double, double) toPage(double x, double y) {
    final cl = math.cos(slant), sl = math.sin(slant);
    final cp = math.cos(pageSlant), sp = math.sin(pageSlant);
    var dx = x - centerX, dy = y - centerY;
    final nx = centerX + dx * cl - dy * sl, ny = centerY + dx * sl + dy * cl;
    dx = nx - _pageCenterX;
    dy = ny - _pageCenterY;
    return (
      _pageCenterX + dx * cp - dy * sp,
      _pageCenterY + dx * sp + dy * cp + shiftY,
    );
  }

  /// Page pt → line coordinates (the inverse of [toPage]).
  (double, double) fromPage(double x, double y) {
    final cl = math.cos(slant), sl = math.sin(slant);
    final cp = math.cos(pageSlant), sp = math.sin(pageSlant);
    var dx = x - _pageCenterX, dy = y - shiftY - _pageCenterY;
    final nx = _pageCenterX + dx * cp + dy * sp;
    final ny = _pageCenterY - dx * sp + dy * cp;
    dx = nx - centerX;
    dy = ny - centerY;
    return (centerX + dx * cl + dy * sl, centerY - dx * sl + dy * cl);
  }
}

/// (internal) A glyph or a mark.
final class SyntheticGlyph {
  SyntheticGlyph._(
    this.box,
    this.pageBox,
    this.strokes,
    this.isMark,
    this.scaleX,
    this.scaleY,
    this.step,
    this.anchors,
  );

  /// The glyph box in line coordinates (= the box of its ink there).
  final InkBox box;

  /// The axis-aligned box of the rotated glyph box (page pt).
  final InkBox pageBox;

  /// Its strokes (indices into SyntheticPage.strokes), in drawing order.
  final List<int> strokes;
  final bool isMark;

  /// The stretch that made the ink box the glyph box, and the walk step
  /// (before the stretch).
  final double scaleX, scaleY, step;

  /// Per stroke: the point of the previous stroke it started on (index into
  /// that stroke's points); null for the first stroke and for marks.
  final List<int?> anchors;
}

/// The 6.6 v2.1 page (see the file comment). [SyntheticHandwriting.lines] =
/// its strokes.
SyntheticPage synthesizeHandwriting({
  required String pageId,
  required int lineCount,
  required int seed,
}) {
  if (lineCount < 0 || lineCount > 99) {
    throw ArgumentError.value(lineCount, 'lineCount', 'must be 0..99');
  }
  final rnd = math.Random(seed);
  double u(double a, double b) => a + (b - a) * rnd.nextDouble();
  int ui(int a, int b) => a + rnd.nextInt(b - a + 1);

  final h = u(14, 28);
  final pitch = u(1.6, 2.4) * h;
  final pageSlant = u(-4, 4) * math.pi / 180;
  final style = core.StrokeStyle.defaultsFor(core.PenTool.ballpoint);
  final out = <core.Stroke>[];
  final lines = <SyntheticLine>[];
  var clock = _baseCreatedAt;
  var n = 0;
  var redraws = 0, shifted = 0;
  var baseline = _margin + h;
  _DrawnLine? previous;

  _DrawnLine drawLine(double base, int index) {
    final slant = u(-1, 1) * math.pi / 180;
    final glyphs = <InkBox>[];
    var x = _margin;
    final words = ui(2, 5);
    for (var w = 0; w < words; w++) {
      final letters = ui(2, 5);
      final drafts = <InkBox>[];
      var wx = x;
      for (var k = 0; k < letters; k++) {
        final s = u(0.85, 1.15);
        final gw = u(0.8, 1.1) * h * s, gh = h * s;
        final jitter = u(-0.08, 0.08) * h;
        drafts.add(InkBox(wx, base - gh + jitter, wx + gw, base + jitter));
        wx += gw + u(0.05, 0.2) * h;
      }
      if (drafts.last.right > _rightLimit && glyphs.isNotEmpty) break;
      glyphs.addAll(drafts);
      x = wx + u(0.4, 0.9) * h;
    }

    final strokes = <_DraftStroke>[];
    (double, double, int)? lastPoint; // x, y, point index
    double walk(InkBox g, int points, {required bool chain}) {
      final xs = <double>[], ys = <double>[];
      var px = u(g.left, g.right), py = u(g.top, g.bottom);
      int? anchor;
      if (chain && lastPoint != null) {
        final (lx, ly, li) = lastPoint!;
        (px, py, anchor) = (lx, ly, li);
      }
      final step = 0.25 * math.min(g.width, g.height);
      for (var p = 0; p < points; p++) {
        xs.add(px);
        ys.add(py);
        final a = u(0, 2 * math.pi);
        px = (px + step * math.cos(a)).clamp(g.left, g.right);
        py = (py + step * math.sin(a)).clamp(g.top, g.bottom);
      }
      final sx = <double>[], sy = <double>[]; // 3-point average
      for (var p = 0; p < xs.length; p++) {
        final a = math.max(0, p - 1), b = math.min(xs.length - 1, p + 1);
        var tx = 0.0, ty = 0.0;
        for (var q = a; q <= b; q++) {
          tx += xs[q];
          ty += ys[q];
        }
        sx.add(tx / (b - a + 1));
        sy.add(ty / (b - a + 1));
      }
      strokes.add(_DraftStroke(sx, sy, anchor));
      final k = rnd.nextInt(sx.length);
      lastPoint = (sx[k], sy[k], k);
      return step;
    }

    // Stretches strokes[from..] so their ink box is [g]; the scales.
    (double, double) fitTo(InkBox g, int from) {
      var l = double.infinity, t = double.infinity;
      var r = double.negativeInfinity, b = double.negativeInfinity;
      for (var k = from; k < strokes.length; k++) {
        for (final x in strokes[k].xs) {
          l = math.min(l, x);
          r = math.max(r, x);
        }
        for (final y in strokes[k].ys) {
          t = math.min(t, y);
          b = math.max(b, y);
        }
      }
      final sx = r > l ? g.width / (r - l) : 1.0;
      final sy = b > t ? g.height / (b - t) : 1.0;
      for (var k = from; k < strokes.length; k++) {
        final s = strokes[k];
        strokes[k] = _DraftStroke(
          [
            for (final x in s.xs)
              r > l ? g.left + (x - l) * sx : (g.left + g.right) / 2,
          ],
          [
            for (final y in s.ys)
              b > t ? g.top + (y - t) * sy : (g.top + g.bottom) / 2,
          ],
          s.anchor,
        );
      }
      return (sx, sy);
    }

    final drawn = <_DrawnGlyph>[];
    final marks = <InkBox>[];
    for (final g in glyphs) {
      final from = strokes.length;
      lastPoint = null;
      var step = 0.0;
      for (var s = ui(1, 4); s > 0; s--) {
        step = walk(g, ui(6, 20), chain: true);
      }
      final (sx, sy) = fitTo(g, from);
      drawn.add(_DrawnGlyph(g, from, strokes.length, false, sx, sy, step));
      if (rnd.nextDouble() < 0.1) {
        final mh = u(0.1, 0.2) * h, mw = u(0.1, 0.3) * h;
        if (rnd.nextBool()) {
          final cx = u(g.left, g.right), bottom = g.top - u(0.05, 0.15) * h;
          marks.add(InkBox(cx - mw / 2, bottom - mh, cx + mw / 2, bottom));
        } else {
          final l = g.right + u(0, 0.1) * h;
          marks.add(InkBox(l, g.bottom - mh, l + mw, g.bottom));
        }
      }
    }
    for (final m in marks) {
      final from = strokes.length;
      final step = walk(m, ui(3, 6), chain: false);
      final (sx, sy) = fitTo(m, from);
      drawn.add(_DrawnGlyph(m, from, strokes.length, true, sx, sy, step));
    }

    final minX = glyphs.first.left;
    final maxX = glyphs.map((g) => g.right).reduce(math.max);
    final line = SyntheticLine._(
      index,
      slant,
      (minX + maxX) / 2,
      base - h / 2,
      pageSlant,
      0,
      const [],
    );
    return _DrawnLine(line, strokes, drawn);
  }

  for (var index = 0; index < lineCount; index++) {
    var line = drawLine(baseline, index);
    if (previous != null) {
      final minGap = _minLineGap * h;
      var tries = 0;
      while (_gap(previous, line) < minGap && tries < _maxRedraws) {
        line = drawLine(baseline, index);
        tries++;
        redraws++;
      }
      final gap = _gap(previous, line);
      if (gap < minGap) {
        final down = minGap - gap + 0.01;
        baseline += down;
        line = line.movedDown(down);
        shifted++;
      }
    }
    final first = n;
    for (final s in line.strokes) {
      final points = <core.StrokePoint>[];
      for (var p = 0; p < s.xs.length; p++) {
        final (x, y) = line.line.toPage(s.xs[p], s.ys[p]);
        points.add(
          core.StrokePoint(x, y, t: (p * _pointIntervalMs).toDouble()),
        );
      }
      out.add(
        core.Stroke(
          id: _strokeId(seed, index, n),
          pageId: pageId,
          style: style,
          points: core.StrokePoints.fromList(points),
          createdAt: clock,
        ),
      );
      n++;
      clock += s.xs.length * _pointIntervalMs + ui(80, 200);
    }
    clock += ui(600, 1500);
    lines.add(line.finish(first));
    previous = line;
    baseline += pitch;
  }
  return SyntheticPage._(out, h, pageSlant, lines, redraws, shifted);
}

/// The smallest vertical gap between horizontally overlapping boxes of two
/// neighbouring lines (infinity when none overlap).
double _gap(_DrawnLine up, _DrawnLine down) {
  var gap = double.infinity;
  for (final a in up.pageBoxes) {
    for (final b in down.pageBoxes) {
      if (a.left < b.right && b.left < a.right) {
        gap = math.min(gap, b.top - a.bottom);
      }
    }
  }
  return gap;
}

final class _DraftStroke {
  _DraftStroke(this.xs, this.ys, this.anchor);

  final List<double> xs, ys; // line coordinates
  final int? anchor;
}

final class _DrawnGlyph {
  _DrawnGlyph(
    this.box,
    this.from,
    this.to,
    this.isMark,
    this.scaleX,
    this.scaleY,
    this.step,
  );

  final InkBox box;
  final int from, to; // strokes of the line
  final bool isMark;
  final double scaleX, scaleY, step;
}

final class _DrawnLine {
  _DrawnLine(this.line, this.strokes, this.glyphs)
    : pageBoxes = [for (final g in glyphs) _pageBox(line, g.box)];

  final SyntheticLine line;
  final List<_DraftStroke> strokes;
  final List<_DrawnGlyph> glyphs;
  final List<InkBox> pageBoxes;

  _DrawnLine movedDown(double dy) => _DrawnLine(
    SyntheticLine._(
      line.index,
      line.slant,
      line.centerX,
      line.centerY,
      line.pageSlant,
      line.shiftY + dy,
      const [],
    ),
    strokes,
    glyphs,
  );

  /// The line with its glyphs; its first stroke is page stroke [first].
  SyntheticLine finish(int first) => SyntheticLine._(
    line.index,
    line.slant,
    line.centerX,
    line.centerY,
    line.pageSlant,
    line.shiftY,
    [
      for (final (i, g) in glyphs.indexed)
        SyntheticGlyph._(
          g.box,
          pageBoxes[i],
          [for (var k = g.from; k < g.to; k++) first + k],
          g.isMark,
          g.scaleX,
          g.scaleY,
          g.step,
          [for (var k = g.from; k < g.to; k++) strokes[k].anchor],
        ),
    ],
  );
}

/// The axis-aligned page box of the rotated corners of [box].
InkBox _pageBox(SyntheticLine line, InkBox box) {
  final corners = [
    line.toPage(box.left, box.top),
    line.toPage(box.right, box.top),
    line.toPage(box.left, box.bottom),
    line.toPage(box.right, box.bottom),
  ];
  return InkBox(
    corners.map((c) => c.$1).reduce(math.min),
    corners.map((c) => c.$2).reduce(math.min),
    corners.map((c) => c.$1).reduce(math.max),
    corners.map((c) => c.$2).reduce(math.max),
  );
}
