// (math pen, phase 1 — docs/plans/m5-7/research/math-pen-phase1.md 11.3)
// buildMathFromPen: the formula left-aligned to the ink, vertically centred
// on it, about the ink's height (mathFontSizeFor), the dominant colour, the
// strokes kept as ink in z order (version null); over the ink limits → no
// ink; unusable LaTeX / no strokes → null. The label is 'recog-math-pen'.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart' as ink_testing;
import 'package:ink_recognition/src/actions/object_builders.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/recognition_test_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ink_testing.useInkTestFonts);

  final strokes = [
    glyphStroke('b', 130, 210, 30, createdAt: 2, colorArgb: 0xFFE53935),
    glyphStroke('a', 100, 200, 40, createdAt: 1, colorArgb: 0xFFE53935),
    glyphStroke('c', 150, 190, 10, createdAt: 3),
  ];

  core.MathObject? build(List<core.Stroke> s, {String latex = 'x^{2}'}) =>
      buildMathFromPen(
        id: 'm',
        pageId: kPageId,
        nowMs: 5,
        latex: latex,
        engineId: 'e/1',
        strokes: s,
      );

  test('left-aligned, vertically centred, about the ink height', () {
    final m = build(strokes)!;
    // Ink point bounds: x 100.., y 190..240.
    expect(m.frame.rect.left, 100);
    expect((m.frame.rect.top + m.frame.rect.bottom) / 2, closeTo(215, 0.01));
    final base = ink.InkMathRenderer.layout('x^{2}', fontSizePt: 18)!;
    expect(
      m.style.fontSizePt,
      mathFontSizeFor(boundsHeightPt: 50, baseHeightPt: base.sizePt.height),
    );
    expect(m.frame.rect.height, closeTo(50, 50 * 0.1));
    expect(m.frame.rotation, 0);
    expect(m.style.colorArgb, 0xFFE53935);
    expect(m.latex, 'x^{2}');
    expect(m.engineId, 'e/1');
    expect(m.createdAt, 5);
  });

  test('the strokes are its ink: z order, page set, version null', () {
    final m = build([
      for (final s in strokes)
        s.copyWith(version: const core.Hlc(1, 0, '0000000000000001')),
    ])!;
    expect(m.ink.map((s) => s.id), ['a', 'b', 'c']);
    expect(m.ink.map((s) => s.version), [null, null, null]);
    expect(m.ink.map((s) => s.pageId).toSet(), {kPageId});
    expect(m.ink.first.points.contentEquals(strokes[1].points), isTrue);
  });

  test('over the ink limits → the formula without ink', () {
    final many = [
      for (var i = 0; i <= core.PageObjectLimits.maxMathInkStrokes; i++)
        glyphStroke('s$i', 100 + i * 0.1, 200, 20),
    ];
    expect(mathInkFits(many), isFalse);
    expect(mathInkFits(many.take(400).toList()), isTrue);
    final m = build(many)!;
    expect(m.ink, isEmpty);
  });

  test('unusable LaTeX or no strokes → null; the label', () {
    expect(build(strokes, latex: r'\frac{'), isNull);
    expect(build(strokes, latex: '  '), isNull);
    expect(build(const []), isNull);
    expect(kMathPenLabel, 'recog-math-pen');
  });
}
