// (math pen, phase 1 — docs/plans/m5-7/research/math-pen-phase1.md 3.2, 7)
// The pure rules: which stroke joins the open group (gapX ≤ 1.5 H, gapY ≤
// 1.0 H, H = median height without dots clamped 8–72 pt, 400 strokes at
// most), which formula a stroke reopens (frame + clamp(0.5 × height, 8, 40),
// rotated frames, ink only, nearest), the reopened strokes (new ids, page,
// createdAt kept, recoloured formula) and the reopen command.
import 'dart:math' as math;
import 'dart:ui';

import 'package:feature_editor/src/tools/math_pen/math_pen_group.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;

core.Stroke _stroke(
  String id,
  Rect r, {
  int color = 0xFF1A1A1A,
  int createdAt = 10,
}) => core.Stroke(
  id: id,
  pageId: 'p',
  style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint)
      .copyWith(colorArgb: color),
  points: core.StrokePoints.fromList([
    core.StrokePoint(r.left, r.top, t: 0),
    core.StrokePoint(r.right, r.bottom, t: 8),
  ]),
  createdAt: createdAt,
);

core.MathObject _math({
  Rect rect = const Rect.fromLTWH(100, 100, 60, 20),
  double rotation = 0,
  List<core.Stroke>? ink,
  int color = 0xFF1A1A1A,
  String id = 'm',
}) => core.MathObject(
  id: id,
  pageId: 'p',
  frame: core.ElementFrame(
    core.PageRect(rect.left, rect.top, rect.right, rect.bottom),
    rotation: rotation,
  ),
  latex: 'x^{2}',
  style: core.MathStyle(colorArgb: color),
  ink: ink ?? [_stroke('i1', rect), _stroke('i2', rect.deflate(2))],
  createdAt: 1,
);

void main() {
  group('mathPenLineHeight', () {
    test('median of the heights without dots, clamped 8–72', () {
      expect(mathPenLineHeight([10, 20, 30]), 20);
      expect(mathPenLineHeight([10, 20, 30, 40]), 25);
      expect(mathPenLineHeight([1, 1.5, 20]), 20); // dots left out
      expect(mathPenLineHeight([1, 1], fallback: 30), 30);
      expect(mathPenLineHeight([3, 4]), 8);
      expect(mathPenLineHeight([200, 300]), 72);
      expect(mathPenLineHeight(const [], fallback: 0), 8);
    });
  });

  group('mathPenJoins (H = 20 pt)', () {
    const group = Rect.fromLTWH(100, 100, 40, 20); // "x" of height 20
    const heights = [20.0, 20.0];
    bool joins(Rect stroke, {List<double> h = heights}) =>
        mathPenJoins(group: group, heights: h, stroke: stroke);

    test('an exponent up and right of the group joins', () {
      expect(joins(const Rect.fromLTWH(142, 88, 8, 10)), isTrue);
    });

    test('the next symbol of the same formula joins (gap ≤ 1.5 H)', () {
      expect(joins(const Rect.fromLTWH(140 + 29, 102, 15, 15)), isTrue);
      expect(joins(const Rect.fromLTWH(140 + 30, 102, 15, 15)), isTrue);
    });

    test('a formula further away starts a new group (gap > 1.5 H)', () {
      expect(joins(const Rect.fromLTWH(140 + 31, 102, 15, 15)), isFalse);
      expect(joins(const Rect.fromLTWH(20, 102, 15, 15)), isFalse); // left
    });

    test(
      'a denominator below joins (gapY ≤ 1.0 H); the next line does not',
      () {
        expect(joins(const Rect.fromLTWH(100, 125, 30, 15)), isTrue);
        expect(joins(const Rect.fromLTWH(100, 140, 30, 15)), isTrue);
        expect(joins(const Rect.fromLTWH(100, 141, 30, 15)), isFalse);
        expect(joins(const Rect.fromLTWH(100, 60, 30, 15)), isFalse); // above
      },
    );

    test('dots do not shrink H; a tiny H is clamped to 8 pt', () {
      // Only dots: H = clamp(new stroke height) → 8.
      expect(
        mathPenJoins(
          group: const Rect.fromLTWH(100, 100, 1, 1),
          heights: const [1],
          stroke: const Rect.fromLTWH(109, 100, 1, 1),
        ),
        isTrue,
      );
      expect(
        mathPenJoins(
          group: const Rect.fromLTWH(100, 100, 1, 1),
          heights: const [1],
          stroke: const Rect.fromLTWH(114, 100, 1, 1),
        ),
        isFalse,
      );
    });

    test('a full group (400 strokes) takes no more', () {
      expect(
        joins(
          const Rect.fromLTWH(142, 100, 8, 10),
          h: List.filled(MathPenTuning.maxGroupStrokes, 20),
        ),
        isFalse,
      );
      expect(
        joins(
          const Rect.fromLTWH(142, 100, 8, 10),
          h: List.filled(MathPenTuning.maxGroupStrokes - 1, 20),
        ),
        isTrue,
      );
    });
  });

  group('reopenCandidateAt', () {
    test('inside the frame + margin (0.5 × height clamped 8–40)', () {
      final m = _math(); // height 20 → margin 10
      expect(mathReopenMargin(m), 10);
      expect(reopenCandidateAt([m], const Offset(165, 110)), m);
      expect(reopenCandidateAt([m], const Offset(170, 110)), m);
      expect(reopenCandidateAt([m], const Offset(171, 110)), isNull);
      expect(reopenCandidateAt([m], const Offset(130, 89)), isNull);
      expect(mathReopenMargin(_math(rect: const Rect.fromLTWH(0, 0, 9, 4))), 8);
      expect(
        mathReopenMargin(_math(rect: const Rect.fromLTWH(0, 0, 9, 200))),
        40,
      );
    });

    test('a formula without ink is never reopened', () {
      expect(
        reopenCandidateAt([_math(ink: const [])], const Offset(130, 110)),
        isNull,
      );
    });

    test('a rotated frame is tested turned back', () {
      final m = _math(
        rect: const Rect.fromLTWH(100, 100, 100, 10),
        rotation: math.pi / 2,
      );
      // Turned a quarter: the frame now spans y 100..200 around x 150.
      expect(reopenCandidateAt([m], const Offset(150, 60)), m);
      expect(reopenCandidateAt([m], const Offset(195, 105)), isNull);
    });

    test('several: the nearest centre, a tie → the top one', () {
      final a = _math(id: 'a', rect: const Rect.fromLTWH(100, 100, 60, 20));
      final b = _math(id: 'b', rect: const Rect.fromLTWH(165, 100, 60, 20));
      expect(reopenCandidateAt([a, b], const Offset(161, 110))!.id, 'a');
      expect(reopenCandidateAt([a, b], const Offset(164, 110))!.id, 'b');
      final c = _math(id: 'c', rect: const Rect.fromLTWH(100, 100, 60, 20));
      expect(reopenCandidateAt([a, c], const Offset(130, 110))!.id, 'c');
    });

    test('mathAt: the frame exactly, top one; math without ink too', () {
      final m = _math(ink: const []);
      expect(mathAt([m], const Offset(130, 110)), m);
      expect(mathAt([m], const Offset(161, 110)), isNull);
    });
  });

  group('reopenedStrokes / reopenCommand', () {
    test('new ids, page, createdAt and points kept, updatedAt now, no '
        'version', () {
      final ink = [
        _stroke(
          'i1',
          const Rect.fromLTWH(100, 100, 10, 10),
          createdAt: 3,
        ).copyWith(version: const core.Hlc(1, 0, '0000000000000001')),
        _stroke('i2', const Rect.fromLTWH(112, 100, 10, 10), createdAt: 4),
      ];
      final m = _math(ink: ink);
      var n = 0;
      final out = reopenedStrokes(m, newId: () => 'n${++n}', now: 777);
      expect(out.map((s) => s.id), ['n1', 'n2']);
      expect(out.map((s) => s.createdAt), [3, 4]);
      expect(out.map((s) => s.updatedAt), [777, 777]);
      expect(out.map((s) => s.version), [null, null]);
      expect(out.map((s) => s.pageId), ['p', 'p']);
      for (var i = 0; i < 2; i++) {
        expect(out[i].points.contentEquals(ink[i].points), isTrue);
        expect(out[i].style, ink[i].style);
      }
    });

    test('a recoloured formula gives its colour to the strokes', () {
      final m = _math(color: 0xFFE53935);
      final out = reopenedStrokes(m, newId: () => 'x', now: 1);
      expect(out.map((s) => s.style.colorArgb).toSet(), {0xFFE53935});
    });

    test('reopenCommand: remove the formula, add the strokes (+ the written '
        'one) in one composite', () {
      final m = _math();
      final strokes = reopenedStrokes(m, newId: () => 'r', now: 1);
      final c = reopenCommand(m, strokes);
      expect(c.label, 'editor-math-reopen');
      expect(c.commands, hasLength(2));
      expect((c.commands[0] as core.RemoveElements).elementIds, ['m']);
      expect((c.commands[1] as core.AddStrokes).strokes, strokes);
      final w = reopenCommand(
        m,
        strokes,
        written: core.AddStrokes(pageId: 'p', strokes: const []),
      );
      expect(w.label, 'editor-math-reopen-write');
      expect(w.commands, hasLength(3));
    });
  });
}
