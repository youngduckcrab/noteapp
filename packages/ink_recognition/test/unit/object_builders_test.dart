// L2-12 (m5-7/05-library 8.2, 6.13.4, 6.14.6, 6.15.1, 6.15.3): the objects and
// commands the recognition actions make — the 6.13.4 table (text, font size
// from the glyph height, the dominant colour, width and position inside the
// page, the 10,000-character limit, the height from INK's measure), the
// 6.15.3 size scale and centre, the 6.15.1 re-layout (centre and rotation
// kept, 'manual'), the 6.14.6 insert (centred, moved inside the page) and the
// command shapes CompositeCommand([RemoveElements(pageId:, elementIds: List),
// AddObjects(pageId:, objects:)]) with their labels.
import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart' as ink_testing;
import 'package:ink_recognition/src/actions/object_builders.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

import '../support/recognition_test_scope.dart';

const _a4 = core.PageSize.a4Portrait; // 595.28 × 841.89

/// [n] separate glyph strokes [h] pt tall on one line (left to right).
List<core.Stroke> _glyphs(
  int n,
  double h, {
  double x0 = 100,
  double y = 200,
  int colorArgb = 0xFF1A1A1A,
}) => [
  for (var i = 0; i < n; i++)
    glyphStroke('g$i', x0 + i * h * 2, y, h, colorArgb: colorArgb),
];

void main() {
  // InkMathRenderer.layout needs the widgets binding (C23-07).
  TestWidgetsFlutterBinding.ensureInitialized();

  group('6.13.4 text box', () {
    setUpAll(ink_testing.useInkTestFonts);

    test('text: lines trimmed, empty lines dropped, joined with \\n', () {
      expect(joinLineTexts(['  오늘 회의 ', '', '   ', 'notes\t']), '오늘 회의\nnotes');
      expect(joinLineTexts(const []), '');
    });

    test(
      'more than 10,000 characters → too long (the primary is disabled)',
      () {
        expect(core.PageObjectLimits.maxTextLength, 10000);
        expect(isTextTooLong('가' * 10000), isFalse);
        expect(isTextTooLong('가' * 10001), isTrue);
      },
    );

    test('fontSizePt = clamp(H × 0.8, 10, 48) rounded to 0.5', () {
      expect(textBoxFontSizeFor(20), 16);
      expect(textBoxFontSizeFor(13.1), 10.5); // 10.48
      expect(textBoxFontSizeFor(17.3), 14); // 13.84
      expect(textBoxFontSizeFor(17.6), 14); // 14.08
      expect(textBoxFontSizeFor(17.9), 14.5); // 14.32
      expect(textBoxFontSizeFor(4), 10); // floor
      expect(textBoxFontSizeFor(100), 48); // ceiling
      expect(textBoxFontSizeFor(double.nan), 10);
      expect(textBoxFontSizeFor(double.infinity), 10);
    });

    test('H is the 6.5 glyph height of the input strokes', () {
      final h = glyphHeightOfStrokes(_glyphs(6, 20));
      expect(h, closeTo(20, 1));
      expect(textBoxFontSizeFor(h), 16);
      expect(glyphHeightOfStrokes(const []), greaterThan(0)); // floor value
    });

    test('colour: the most used one (opaque), a tie → first in z order', () {
      core.Stroke s(String id, int argb, int createdAt) =>
          glyphStroke(id, 0, 0, 10, colorArgb: argb, createdAt: createdAt);
      expect(
        dominantColorOf([
          s('a', 0xFF0000FF, 1),
          s('b', 0xFFFF0000, 2),
          s('c', 0xFFFF0000, 3),
        ]),
        0xFFFF0000,
      );
      // tie: z order (createdAt → id), not list order
      expect(
        dominantColorOf([s('b', 0xFFFF0000, 2), s('a', 0xFF0000FF, 1)]),
        0xFF0000FF,
      );
      expect(
        dominantColorOf([s('y', 0xFFFF0000, 5), s('x', 0xFF0000FF, 5)]),
        0xFF0000FF, // same createdAt → id 'x' first
      );
      // compared opaque; the result's alpha is 0xFF
      expect(
        dominantColorOf([
          s('a', 0x8000FF00, 1),
          s('b', 0x4000FF00, 2),
          s('c', 0xFF0000FF, 3),
        ]),
        0xFF00FF00,
      );
      expect(dominantColorOf(const []), isNull);
    });

    test('width = clamp(max(bounds width, 120), 40, page − 32); left inside '
        '[16, page − 16 − width]; top ≥ 0', () {
      var p = textBoxPlacementOf(const Rect.fromLTWH(100, 200, 60, 30), _a4);
      expect((p.left, p.top, p.width), (100, 200, 120));
      p = textBoxPlacementOf(const Rect.fromLTWH(100, 200, 300, 30), _a4);
      expect(p.width, 300);
      p = textBoxPlacementOf(const Rect.fromLTWH(-50, -20, 900, 30), _a4);
      expect(p.width, closeTo(_a4.width - 32, 1e-9));
      expect(p.left, 16);
      expect(p.top, 0);
      p = textBoxPlacementOf(const Rect.fromLTWH(5, 10, 50, 30), _a4);
      expect(p.left, 16);
      p = textBoxPlacementOf(const Rect.fromLTWH(560, 10, 50, 30), _a4);
      expect(p.left, closeTo(_a4.width - 16 - 120, 1e-9)); // inside the page
      // the smallest page (72 pt): width 40 at the 16 pt margin
      p = textBoxPlacementOf(
        const Rect.fromLTWH(30, 10, 10, 10),
        const core.PageSize(72, 72),
      );
      expect((p.left, p.width), (16, 40));
    });

    test('buildTextBox: style, frame from INK measure, id and times', () async {
      final inputs = _glyphs(6, 20, colorArgb: 0xFF3366CC);
      const bounds = Rect.fromLTWH(100, 200, 220, 20);
      final box = await buildTextBox(
        id: 'box-1',
        pageId: kPageId,
        nowMs: 1730800000123,
        text: '오늘 회의\nnotes',
        inputStrokes: inputs,
        boundsPt: bounds,
        pageSize: _a4,
      );
      expect(box.id, 'box-1');
      expect(box.pageId, kPageId);
      expect(box.text, '오늘 회의\nnotes');
      expect(box.createdAt, 1730800000123);
      expect(box.updatedAt, 1730800000123);
      expect(box.style.fontSizePt, 16);
      expect(box.style.colorArgb, 0xFF3366CC);
      expect(box.style.bold, isFalse);
      expect(box.style.align, core.TextAlignKind.start);
      expect(box.style.lineHeight, 1.4);
      expect(box.style.backgroundArgb, isNull);
      expect(box.frame.rotation, 0);
      expect(box.frame.rect.left, 100);
      expect(box.frame.rect.top, 200);
      expect(box.frame.rect.width, 220);
      final measured = await ink.InkTextLayout.measure(
        box.text,
        box.style,
        widthPt: 220,
      );
      expect(box.frame.rect.height, measured.height);
      expect(measured.height, greaterThan(2 * 16)); // two lines
    });

    test(
      'an explicit glyph height wins; no strokes → default colour',
      () async {
        final box = await buildTextBox(
          id: 'box-2',
          pageId: kPageId,
          nowMs: 1,
          text: 'x',
          inputStrokes: const [],
          boundsPt: const Rect.fromLTWH(0, 0, 10, 10),
          pageSize: _a4,
          glyphHeightPt: 40,
        );
        expect(box.style.fontSizePt, 32);
        expect(box.style.colorArgb, const core.TextBoxStyle().colorArgb);
        expect(box.frame.rect.left, 16);
      },
    );

    test('recognition inputs: no highlighter / tape / laser, z order kept', () {
      final strokes = [
        glyphStroke('b', 0, 0, 10),
        glyphStroke('h', 0, 0, 10, tool: core.PenTool.highlighter),
        glyphStroke('t', 0, 0, 10, tool: core.PenTool.tape),
        glyphStroke('l', 0, 0, 10, tool: core.PenTool.laser),
        glyphStroke('p', 0, 0, 10, tool: core.PenTool.pencil),
        glyphStroke('f', 0, 0, 10, tool: core.PenTool.fountain),
      ];
      expect(
        [for (final s in recognitionInputsOf(strokes)) s.id],
        ['b', 'p', 'f'],
      );
    });
  });

  group('commands (contract 7.2.3 — named arguments, one execute)', () {
    test('replace: CompositeCommand([RemoveElements(List of the input stroke '
        'ids), AddObjects([object])]) with the recog label', () {
      final inputs = [glyphStroke('s2', 0, 0, 10), glyphStroke('s1', 0, 0, 10)];
      final box = core_testing.PageObjectFixtures.textBox(pageId: kPageId);
      final cmd = replaceStrokesCommand(
        pageId: kPageId,
        strokes: inputs,
        object: box,
        label: kToTextLabel,
      );
      expect(cmd, isA<core.CompositeCommand>());
      expect(cmd.label, 'recog-to-text');
      expect(cmd.commands, hasLength(2));
      final remove = cmd.commands[0] as core.RemoveElements;
      expect(remove.pageId, kPageId);
      expect(remove.elementIds, isA<List<String>>());
      expect(remove.elementIds, ['s2', 's1']);
      final add = cmd.commands[1] as core.AddObjects;
      expect(add.pageId, kPageId);
      expect(add.objects, [box]);
      expect(kToMathLabel, 'recog-to-math');
    });

    test('add / update: one object each', () {
      final m = core_testing.PageObjectFixtures.math(pageId: kPageId);
      final add = addObjectCommand(kPageId, m);
      expect(add.pageId, kPageId);
      expect(add.objects, [m]);
      expect(add.label, 'add-objects');
      final update = updateObjectCommand(kPageId, m);
      expect(update.pageId, kPageId);
      expect(update.objects, [m]);
      expect(update.label, 'update-objects');
    });
  });

  group('math', () {
    test(
      'usableLatex: trimmed; empty, invalid or > 4,000 characters → null',
      () {
        expect(usableLatex('  \\frac{a}{b} '), r'\frac{a}{b}');
        expect(usableLatex('   '), isNull);
        expect(usableLatex(r'\frac{a}{'), isNull);
        expect(core.PageObjectLimits.maxLatexLength, 4000);
        expect(usableLatex('x' * 4001), isNull);
      },
    );

    test('6.15.3: f = clamp(18 × bounds height ÷ layout(18).height, 6, 144) '
        'to 0.5, centred on the selection, dominant colour', () {
      const latex = r'x^2+\frac{1}{2}';
      final base = ink.InkMathRenderer.layout(latex, fontSizePt: 18)!;
      final bounds = Rect.fromCenter(
        center: const Offset(300, 400),
        width: 200,
        height: base.sizePt.height * 2,
      );
      final inputs = _glyphs(3, 20, colorArgb: 0xFFCC0000);
      final m = buildMathFromStrokes(
        id: 'm1',
        pageId: kPageId,
        nowMs: 77,
        latex: latex,
        engineId: 'fake/1',
        inputStrokes: inputs,
        boundsPt: bounds,
      )!;
      expect(m.style.fontSizePt, 36);
      final laid = ink.InkMathRenderer.layout(latex, fontSizePt: 36)!;
      expect(m.frame.rect.width, closeTo(laid.sizePt.width, 1e-9));
      expect(m.frame.rect.height, closeTo(laid.sizePt.height, 1e-9));
      expect(m.frame.center.x, closeTo(300, 1e-9));
      expect(m.frame.center.y, closeTo(400, 1e-9));
      expect(m.frame.rotation, 0);
      expect(m.style.colorArgb, 0xFFCC0000);
      expect(m.engineId, 'fake/1');
      expect(
        (m.id, m.pageId, m.createdAt, m.updatedAt),
        ('m1', kPageId, 77, 77),
      );
      expect(m.latex, latex);
    });

    test('6.15.3 size: 0.5 steps and the [6, 144] clamp', () {
      expect(mathFontSizeFor(boundsHeightPt: 20, baseHeightPt: 20), 18);
      expect(mathFontSizeFor(boundsHeightPt: 21, baseHeightPt: 20), 19); // 18.9
      expect(mathFontSizeFor(boundsHeightPt: 20.4, baseHeightPt: 20), 18.5);
      expect(mathFontSizeFor(boundsHeightPt: 1, baseHeightPt: 20), 6);
      expect(mathFontSizeFor(boundsHeightPt: 900, baseHeightPt: 20), 144);
      expect(mathFontSizeFor(boundsHeightPt: 20, baseHeightPt: 0), 18);
      final m = buildMathFromStrokes(
        id: 'm',
        pageId: kPageId,
        nowMs: 1,
        latex: 'x',
        engineId: 'manual',
        inputStrokes: const [],
        boundsPt: const Rect.fromLTWH(0, 0, 4000, 4000),
      )!;
      expect(m.style.fontSizePt, 144);
      expect(m.style.colorArgb, const core.MathStyle().colorArgb);
    });

    test('6.15.3: a formula that cannot be laid out → null', () {
      expect(
        buildMathFromStrokes(
          id: 'm',
          pageId: kPageId,
          nowMs: 1,
          latex: r'\notacommand{x}',
          engineId: 'manual',
          inputStrokes: const [],
          boundsPt: const Rect.fromLTWH(0, 0, 40, 40),
        ),
        isNull,
      );
    });

    test('6.15.1 relayout: new size at the same font size, centre and '
        'rotation kept, engineId manual, updatedAt now', () {
      final original = core.MathObject(
        id: 'm9',
        pageId: kPageId,
        frame: core.ElementFrame(
          core.PageRect.fromLTWH(200, 300, 40, 20),
          rotation: 0.5,
        ),
        latex: 'x',
        style: const core.MathStyle(fontSizePt: 24, colorArgb: 0xFF00AA00),
        engineId: 'fake/1',
        createdAt: 10,
      );
      const latex = r'\sum_{i=1}^{n} i';
      final edited = relayoutMath(original, latex: latex, nowMs: 99)!;
      final laid = ink.InkMathRenderer.layout(latex, fontSizePt: 24)!;
      expect(edited.id, 'm9');
      expect(edited.latex, latex);
      expect(edited.engineId, 'manual');
      expect(edited.createdAt, 10);
      expect(edited.updatedAt, 99);
      expect(edited.style, original.style);
      expect(edited.frame.rotation, 0.5);
      expect(edited.frame.center.x, closeTo(220, 1e-9));
      expect(edited.frame.center.y, closeTo(310, 1e-9));
      expect(edited.frame.rect.width, closeTo(laid.sizePt.width, 1e-9));
      expect(edited.frame.rect.height, closeTo(laid.sizePt.height, 1e-9));
      expect(relayoutMath(original, latex: r'\frac{', nowMs: 1), isNull);
    });

    test('6.14.6 insert: default style, centred in the area, moved inside '
        'the page, rotation 0', () {
      const latex = r'E=mc^2';
      final laid = ink.InkMathRenderer.layout(latex, fontSizePt: 18)!;
      final m = buildInsertedMath(
        id: 'm2',
        pageId: kPageId,
        nowMs: 5,
        latex: ' $latex ',
        engineId: 'manual',
        areaPt: const Rect.fromLTWH(0, 100, 400, 300),
        pageSize: _a4,
      )!;
      expect(m.style, const core.MathStyle());
      expect(m.latex, latex);
      expect(m.engineId, 'manual');
      expect(m.frame.rotation, 0);
      expect(m.frame.center.x, closeTo(200, 1e-9));
      expect(m.frame.center.y, closeTo(250, 1e-9));
      expect(m.frame.rect.width, closeTo(laid.sizePt.width, 1e-9));
      // an area whose centre is at the page corner → inside the page
      final corner = buildInsertedMath(
        id: 'm3',
        pageId: kPageId,
        nowMs: 5,
        latex: latex,
        engineId: 'fake/1',
        areaPt: Rect.fromCenter(
          center: Offset(_a4.width, _a4.height),
          width: 100,
          height: 100,
        ),
        pageSize: _a4,
      )!;
      expect(corner.engineId, 'fake/1');
      expect(corner.frame.rect.right, closeTo(_a4.width, 1e-9));
      expect(corner.frame.rect.bottom, closeTo(_a4.height, 1e-9));
      final origin = buildInsertedMath(
        id: 'm4',
        pageId: kPageId,
        nowMs: 5,
        latex: latex,
        engineId: 'manual',
        areaPt: const Rect.fromLTWH(-200, -200, 10, 10),
        pageSize: _a4,
      )!;
      expect((origin.frame.rect.left, origin.frame.rect.top), (0, 0));
      expect(
        buildInsertedMath(
          id: 'm5',
          pageId: kPageId,
          nowMs: 5,
          latex: 'x' * 4001,
          engineId: 'manual',
          areaPt: const Rect.fromLTWH(0, 0, 100, 100),
          pageSize: _a4,
        ),
        isNull,
      );
    });

    test('the built objects are valid CORE objects (bounds finite)', () {
      final m = buildInsertedMath(
        id: 'm6',
        pageId: kPageId,
        nowMs: 5,
        latex: 'y',
        engineId: 'manual',
        areaPt: const Rect.fromLTWH(0, 0, 100, 100),
        pageSize: const core.PageSize(200, 200),
      )!;
      final b = m.bounds;
      expect(
        [b.left, b.top, b.right, b.bottom].every((v) => v.isFinite),
        isTrue,
      );
      expect(core.PageObject.fromJson(m.toJson()), m);
    });
  });
}
