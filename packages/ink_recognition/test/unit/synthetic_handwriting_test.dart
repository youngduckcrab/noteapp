// SyntheticHandwriting (testing.dart — its body file is imported for the
// drawing record) — the 6.6 v2.1 generator (m5-7/05-library 4.3, 6.6,
// 8.2 L2-05; contract 7.6 CP-L4). Checked on the strokes it returns and on
// what it drew (src/testing/synthetic_handwriting.dart SyntheticPage):
//  - Random(seed) only: the same seed gives the same strokes; the E-L5
//    prototype's values for seed 1 (3 lines) and seed 7 (10 lines);
//  - ids 'syn_<seed>_l<line>_<n>' (valid entity ids), createdAt increasing,
//    t = 8 ms per point, ballpoint;
//  - 6.6 ranges (H, pitch, slants, points per stroke) and the v2.1 rules:
//    neighbouring lines keep a gap ≥ 0.25·H, relative slant ≤ 2°, a glyph's
//    ink box is its glyph box, every further stroke of a glyph starts on a
//    point of the previous one, marks come after their line's glyphs;
//  - redraws / moves over the V9 pages (E-L5: 10 redraws, 0 moves).
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/src/lines/glyph_boxes.dart';
import 'package:ink_recognition/src/testing/synthetic_handwriting.dart';
import 'package:note_core/note_core.dart' as core;

const double _eps = 0.02; // 0.01 pt CORE quantization + float32

InkBox _inkBox(core.Stroke s) {
  final p = s.points;
  var box = InkBox(p.x(0), p.y(0), p.x(0), p.y(0));
  for (var i = 1; i < p.length; i++) {
    box = box.union(InkBox(p.x(i), p.y(i), p.x(i), p.y(i)));
  }
  return box;
}

/// [glyph]'s ink, mapped back to line coordinates, as one box.
InkBox _lineInkBox(SyntheticPage page, SyntheticLine line, SyntheticGlyph g) {
  InkBox? box;
  for (final k in g.strokes) {
    final p = page.strokes[k].points;
    for (var i = 0; i < p.length; i++) {
      final (x, y) = line.fromPage(p.x(i), p.y(i));
      final b = InkBox(x, y, x, y);
      box = box == null ? b : box.union(b);
    }
  }
  return box!;
}

Iterable<SyntheticPage> _v9Pages() sync* {
  for (var seed = 1; seed <= 20; seed++) {
    for (var lineCount = 3; lineCount <= 12; lineCount++) {
      yield synthesizeHandwriting(
        pageId: 'p1',
        lineCount: lineCount,
        seed: seed,
      );
    }
  }
}

void main() {
  group('determinism and the E-L5 prototype', () {
    test('the same seed → the same strokes; another seed → others', () {
      final a = SyntheticHandwriting.lines(pageId: 'p1', seed: 7);
      final b = SyntheticHandwriting.lines(pageId: 'p1', seed: 7);
      expect(b.map((s) => s.id), a.map((s) => s.id));
      expect(b.map((s) => s.createdAt), a.map((s) => s.createdAt));
      expect(
        b.map((s) => s.points.rawData.toList()),
        a.map((s) => s.points.rawData.toList()),
      );
      final other = SyntheticHandwriting.lines(pageId: 'p1', seed: 8);
      expect(other.first.id, startsWith('syn_8_l00_'));
      expect(
        other.first.points.rawData.toList(),
        isNot(a.first.points.rawData.toList()),
      );
    });

    test('seed 1, 3 lines = the prototype (synth.dart Mode.v21, '
        'connected): 114 strokes, 5 marks, the first stroke box', () {
      final page = synthesizeHandwriting(pageId: 'p1', lineCount: 3, seed: 1);
      expect(page.strokes, hasLength(114));
      expect([
        for (final l in page.lines)
          for (final g in l.glyphs)
            if (g.isMark) g,
      ], hasLength(5));
      expect(page.glyphHeight, closeTo(22.099018010176913, 1e-9));
      final first = page.strokes.first;
      expect(first.id, 'syn_1_l00_0000');
      expect(first.createdAt, 1730790000000);
      expect(first.points.length, 11);
      final box = _inkBox(first);
      expect(box.left, closeTo(66.44608217535037, _eps));
      expect(box.top, closeTo(34.77491266849876, _eps));
      expect(box.right, closeTo(78.5876136275735, _eps));
      expect(box.bottom, closeTo(47.444273538870675, _eps));
      expect(page.strokes.last.id, 'syn_1_l02_0113');
      expect(page.strokes.last.createdAt, 1730790029486);
      expect(page.redraws, 0);
    });

    test('seed 7, 10 lines = the prototype: 343 strokes, 14 marks', () {
      final page = synthesizeHandwriting(pageId: 'p1', lineCount: 10, seed: 7);
      expect(page.strokes, hasLength(343));
      expect(
        page.lines.expand((l) => l.glyphs).where((g) => g.isMark),
        hasLength(14),
      );
      expect(page.glyphHeight, closeTo(15.545675451086467, 1e-9));
      expect(page.strokes.first.points.length, 13);
      final box = _inkBox(page.strokes.first);
      expect(box.left, closeTo(42.425589195603166, _eps));
      expect(box.bottom, closeTo(55.652341648765855, _eps));
      expect(page.strokes.last.id, 'syn_7_l09_0342');
      expect(page.strokes.last.createdAt, 1730790090729);
    });

    test('the V9 pages: 10 lines drawn again, none moved (E-L5)', () {
      var redraws = 0, shifted = 0, strokes = 0;
      for (final page in _v9Pages()) {
        redraws += page.redraws;
        shifted += page.shifted;
        strokes += page.strokes.length;
      }
      expect((redraws, shifted, strokes), (10, 0, 46171));
    });
  });

  group('strokes', () {
    test('ids syn_<seed>_l<line>_<n>, valid entity ids; n = stroke number, '
        'lines never go back; createdAt increases', () {
      final strokes = SyntheticHandwriting.lines(pageId: 'p1', seed: 7);
      final pattern = RegExp(r'^syn_7_l(\d\d)_(\d{4})$');
      final lines = <int>{};
      var lastLine = 0;
      for (final (i, s) in strokes.indexed) {
        final m = pattern.firstMatch(s.id);
        expect(m, isNotNull, reason: s.id);
        expect(core.isValidEntityId(s.id), isTrue, reason: s.id);
        expect(int.parse(m!.group(2)!), i);
        final line = int.parse(m.group(1)!);
        expect(line, greaterThanOrEqualTo(lastLine));
        lastLine = line;
        lines.add(line);
        expect(s.pageId, 'p1');
        if (i > 0) expect(s.createdAt, greaterThan(strokes[i - 1].createdAt));
      }
      expect(lines, {0, 1, 2, 3, 4}); // lineCount default 5
    });

    test('ballpoint, t = 8 ms per point, gaps between strokes and lines', () {
      final strokes = SyntheticHandwriting.lines(pageId: 'p2', lineCount: 12);
      expect(strokes.map((s) => s.id.substring(7, 9)).toSet(), hasLength(12));
      for (final (i, s) in strokes.indexed) {
        expect(s.style, core.StrokeStyle.defaultsFor(core.PenTool.ballpoint));
        for (var p = 0; p < s.points.length; p++) {
          expect(s.points.t(p), p * 8);
        }
        if (i == 0) continue;
        final prev = strokes[i - 1];
        final pause = s.createdAt - prev.createdAt - prev.points.length * 8;
        final newLine = s.id.substring(7, 9) != prev.id.substring(7, 9);
        expect(
          pause,
          newLine ? inInclusiveRange(680, 1700) : inInclusiveRange(80, 200),
          reason: s.id,
        );
      }
    });

    test('lineCount 0 → no strokes; outside 0..99 → ArgumentError', () {
      expect(SyntheticHandwriting.lines(pageId: 'p', lineCount: 0), isEmpty);
      expect(
        () => SyntheticHandwriting.lines(pageId: 'p', lineCount: 100),
        throwsArgumentError,
      );
      expect(
        () => SyntheticHandwriting.lines(pageId: 'p', lineCount: -1),
        throwsArgumentError,
      );
    });
  });

  group('6.6 v2.1 rules on the V9 pages (seeds 1–20 × 3–12 lines)', () {
    final pages = _v9Pages().toList();

    test('ranges: H 14–28 pt, θp ±4°, δ ±1° (relative slant ≤ 2°), glyph '
        'strokes 6–20 points, mark strokes 3–6, 1–4 strokes a glyph', () {
      const deg = math.pi / 180;
      for (final page in pages) {
        expect(page.glyphHeight, inInclusiveRange(14, 28));
        expect(page.pageSlant.abs(), lessThanOrEqualTo(4 * deg));
        for (final (i, line) in page.lines.indexed) {
          expect(line.slant.abs(), lessThanOrEqualTo(1 * deg));
          if (i > 0) {
            final relative = (line.slant - page.lines[i - 1].slant).abs();
            expect(relative, lessThanOrEqualTo(2 * deg));
          }
          for (final g in line.glyphs) {
            if (g.isMark) {
              expect(g.strokes, hasLength(1));
            } else {
              expect(g.strokes.length, inInclusiveRange(1, 4));
            }
            for (final k in g.strokes) {
              expect(
                page.strokes[k].points.length,
                g.isMark ? inInclusiveRange(3, 6) : inInclusiveRange(6, 20),
              );
            }
          }
        }
      }
    });

    test('neighbouring lines: overlapping ink boxes keep a gap ≥ 0.25·H', () {
      var pairs = 0;
      for (final page in pages) {
        final minGap = 0.25 * page.glyphHeight - _eps;
        List<InkBox> inkOf(SyntheticLine line) => [
          for (final g in line.glyphs)
            g.strokes
                .map((k) => _inkBox(page.strokes[k]))
                .reduce((a, b) => a.union(b)),
        ];
        for (var i = 1; i < page.lines.length; i++) {
          final up = inkOf(page.lines[i - 1]), down = inkOf(page.lines[i]);
          for (final a in up) {
            for (final b in down) {
              if (a.left < b.right && b.left < a.right) {
                pairs++;
                expect(b.top - a.bottom, greaterThanOrEqualTo(minGap));
              }
            }
          }
        }
      }
      expect(pairs, greaterThan(10000)); // the rule is really exercised
    });

    test("a glyph's ink box is its glyph box (in line coordinates)", () {
      for (final page in pages) {
        for (final line in page.lines) {
          for (final g in line.glyphs) {
            final ink = _lineInkBox(page, line, g);
            expect(ink.left, closeTo(g.box.left, _eps));
            expect(ink.top, closeTo(g.box.top, _eps));
            expect(ink.right, closeTo(g.box.right, _eps));
            expect(ink.bottom, closeTo(g.box.bottom, _eps));
          }
        }
      }
    });

    test('every further stroke of a glyph starts on a point of the previous '
        'stroke (up to the 3-point average: half a walk step)', () {
      var chained = 0;
      for (final page in pages) {
        for (final line in page.lines) {
          for (final g in line.glyphs) {
            for (var k = 0; k < g.strokes.length; k++) {
              final anchor = g.anchors[k];
              if (g.isMark || k == 0) {
                expect(anchor, isNull);
                continue;
              }
              expect(anchor, isNotNull);
              chained++;
              final prev = page.strokes[g.strokes[k - 1]].points;
              final self = page.strokes[g.strokes[k]].points;
              final (ax, ay) = line.fromPage(prev.x(anchor!), prev.y(anchor));
              final (fx, fy) = line.fromPage(self.x(0), self.y(0));
              expect(
                (fx - ax).abs(),
                lessThanOrEqualTo(g.step * g.scaleX / 2 + _eps),
              );
              expect(
                (fy - ay).abs(),
                lessThanOrEqualTo(g.step * g.scaleY / 2 + _eps),
              );
            }
          }
        }
      }
      expect(chained, greaterThan(10000));
    });

    test("marks are drawn after all of their line's glyphs", () {
      var marks = 0;
      for (final page in pages) {
        for (final line in page.lines) {
          final glyphTimes = [
            for (final g in line.glyphs)
              if (!g.isMark)
                for (final k in g.strokes) page.strokes[k].createdAt,
          ];
          final lastGlyph = glyphTimes.reduce(math.max);
          for (final g in line.glyphs.where((g) => g.isMark)) {
            marks++;
            for (final k in g.strokes) {
              expect(page.strokes[k].createdAt, greaterThan(lastGlyph));
            }
          }
        }
      }
      expect(marks, greaterThan(100));
    });

    test('every line starts at the 40 pt margin (before the slant)', () {
      for (final page in pages) {
        for (final line in page.lines) {
          final glyphs = line.glyphs.where((g) => !g.isMark).toList();
          expect(glyphs.first.box.left, 40);
          for (final g in glyphs) {
            expect(g.box.width, greaterThan(0));
          }
        }
      }
    });
  });
}
