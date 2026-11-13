// (math pen, phase 1 — docs/plans/m5-7/research/math-pen-phase1.md 3.2, 7)
// The pure rules: which stroke joins the open group (gapX ≤ 1.5 H, gapY ≤
// 0.6 H to the nearest member, H = median height without dots clamped 8–72
// pt, 400 strokes / 40 000 points at most), which formula a stroke reopens
// (frame + clamp(0.5 × height, 8, 40) sideways, clamp(0.3 × height, 4, 16)
// up and down, rotated frames, ink only, nearest), the reopened strokes (new ids, page,
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
    // "x" of height 20 as two members.
    const members = [
      Rect.fromLTWH(100, 100, 40, 20),
      Rect.fromLTWH(100, 100, 40, 20),
    ];
    bool joins(Rect stroke, {List<Rect> m = members}) =>
        mathPenJoins(members: m, stroke: stroke);

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

    test('a denominator below joins (gapY ≤ 0.6 H); the next line of ruled '
        'paper does not', () {
      expect(joins(const Rect.fromLTWH(100, 125, 30, 15)), isTrue);
      expect(joins(const Rect.fromLTWH(100, 132, 30, 15)), isTrue);
      expect(joins(const Rect.fromLTWH(100, 133, 30, 15)), isFalse);
      expect(joins(const Rect.fromLTWH(100, 67, 30, 20)), isFalse); // above
      // Review: an 8 mm (≈ 23 pt) pitch with H ≈ 15 pt — the next line
      // starts 0.6–0.9 H below the letters of this one.
      const line = [
        Rect.fromLTWH(100, 100, 12, 15),
        Rect.fromLTWH(116, 100, 12, 15),
        Rect.fromLTWH(132, 100, 12, 15),
      ];
      expect(
        mathPenJoins(
          members: line,
          stroke: const Rect.fromLTWH(100, 124.5, 12, 15),
        ),
        isFalse,
      );
    });

    test('the gaps are measured to the nearest member, not to the union: a '
        'fraction does not stretch the group further down', () {
      // A fraction bar 100..160 at y 120 and a short numerator on its left.
      const fraction = [
        Rect.fromLTWH(100, 100, 12, 18), // numerator
        Rect.fromLTWH(100, 120, 60, 1), // bar
        Rect.fromLTWH(100, 123, 12, 18), // denominator
      ];
      // Under the bar's right end, 0.5 H below the bar: joins (the bar).
      expect(
        mathPenJoins(
          members: fraction,
          stroke: const Rect.fromLTWH(150, 130, 8, 8),
        ),
        isTrue,
      );
      // Right of the numerator, level with it, but 2 H from every member
      // horizontally: it would join the union (100..160) — not the members.
      expect(
        mathPenJoins(
          members: const [
            Rect.fromLTWH(100, 100, 12, 18),
            Rect.fromLTWH(100, 160, 120, 1),
          ],
          stroke: const Rect.fromLTWH(150, 100, 10, 18),
        ),
        isFalse,
      );
    });

    test('dots do not shrink H; a tiny H is clamped to 8 pt', () {
      // Only dots: H = clamp(new stroke height) → 8.
      expect(
        mathPenJoins(
          members: const [Rect.fromLTWH(100, 100, 1, 1)],
          stroke: const Rect.fromLTWH(109, 100, 1, 1),
        ),
        isTrue,
      );
      expect(
        mathPenJoins(
          members: const [Rect.fromLTWH(100, 100, 1, 1)],
          stroke: const Rect.fromLTWH(114, 100, 1, 1),
        ),
        isFalse,
      );
    });

    test('a full group (400 strokes) takes no more', () {
      expect(
        joins(
          const Rect.fromLTWH(142, 100, 8, 10),
          m: List.filled(MathPenTuning.maxGroupStrokes, members.first),
        ),
        isFalse,
      );
      expect(
        joins(
          const Rect.fromLTWH(142, 100, 8, 10),
          m: List.filled(MathPenTuning.maxGroupStrokes - 1, members.first),
        ),
        isTrue,
      );
    });

    test('a group over the point limit with the new stroke takes no more '
        '(review: 200 long strokes reach 40 000 points)', () {
      bool joinsWith(int groupPoints, int strokePoints) => mathPenJoins(
        members: members,
        stroke: const Rect.fromLTWH(142, 100, 8, 10),
        groupPoints: groupPoints,
        strokePoints: strokePoints,
      );
      expect(joinsWith(MathPenTuning.maxGroupPoints - 100, 100), isTrue);
      expect(joinsWith(MathPenTuning.maxGroupPoints - 100, 101), isFalse);
    });

    test('mathInkWithin: strokes and points with the extra stroke', () {
      final s = _stroke('a', const Rect.fromLTWH(0, 0, 10, 10)); // 2 points
      expect(mathInkWithin([s]), isTrue);
      expect(
        mathInkWithin(List.filled(MathPenTuning.maxGroupStrokes, s)),
        isTrue,
      );
      expect(
        mathInkWithin(List.filled(MathPenTuning.maxGroupStrokes, s), extra: s),
        isFalse,
      );
      final long = core.Stroke(
        id: 'long',
        pageId: 'p',
        style: s.style,
        points: core.StrokePoints.fromList([
          for (var i = 0; i < MathPenTuning.maxGroupPoints - 1; i++)
            core.StrokePoint(i / 100, 0, t: 0),
        ]),
        createdAt: 1,
      );
      expect(mathInkWithin([long]), isTrue);
      expect(mathInkWithin([long], extra: s), isFalse);
    });
  });

  group('reopenCandidateAt', () {
    test('inside the frame + margin (sideways 0.5 × height clamped 8–40, '
        'up and down 0.3 × height clamped 4–16)', () {
      final m = _math(); // height 20 → margin 10 sideways, 6 up and down
      expect(mathReopenMargin(m), 10);
      expect(mathReopenMarginY(m), 6);
      expect(reopenCandidateAt([m], const Offset(165, 110)), m);
      expect(reopenCandidateAt([m], const Offset(170, 110)), m);
      expect(reopenCandidateAt([m], const Offset(171, 110)), isNull);
      expect(reopenCandidateAt([m], const Offset(130, 94)), m);
      expect(reopenCandidateAt([m], const Offset(130, 93)), isNull);
      expect(reopenCandidateAt([m], const Offset(130, 126)), m);
      // Review: the next line started under a formula does not reopen it.
      expect(reopenCandidateAt([m], const Offset(130, 128)), isNull);
      expect(
        mathReopenMarginY(_math(rect: const Rect.fromLTWH(0, 0, 9, 4))),
        4,
      );
      expect(
        mathReopenMarginY(_math(rect: const Rect.fromLTWH(0, 0, 9, 200))),
        16,
      );
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

    test('colours are compared opaque (recog dominantColorOf): ink with a '
        'translucent alpha of the formula colour is not recoloured', () {
      final ink = [
        _stroke('i1', const Rect.fromLTWH(100, 100, 10, 10), color: 0x801A1A1A),
        _stroke('i2', const Rect.fromLTWH(112, 100, 10, 10), color: 0x801A1A1A),
      ];
      final m = _math(ink: ink);
      final out = reopenedStrokes(m, newId: () => 'x', now: 1);
      expect(out.map((s) => s.style.colorArgb).toSet(), {0x801A1A1A});
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
