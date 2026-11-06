// T26b (m5-7/03-ink 8.1, 4.10, 6.12.2): InkMathRenderer.layout with the KaTeX
// fonts — size > 0, baseline in (0, height), twice the font size ≈ twice the size
// (±2%), an invalid formula → null, a call inside a build → StateError (S-9);
// (T36) rasterize gives the laid-out size × pixelsPerPt (the raster itself:
// widget/math_render_test.dart, the queue: offscreen_queue_test.dart).
@TestOn('vm')
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadKatexFontsForTest);

  test(r'\frac{a}{b}: size > 0, baseline inside', () {
    final l = InkMathRenderer.layout(r'\frac{a}{b}', fontSizePt: 18)!;
    expect(l.sizePt.width, greaterThan(0));
    expect(l.sizePt.height, greaterThan(0));
    expect(l.baselinePt, greaterThan(0));
    expect(l.baselinePt, lessThan(l.sizePt.height));
  });

  test('twice the font size ≈ twice the size (±2%)', () {
    for (final latex in [
      r'\frac{a}{b}',
      r'x^2 + y^2 = z^2',
      r'\sum_{k=1}^{n} k^2',
      r'\left\{\begin{array}{l} x+y=1 \\ x-y=3 \end{array}\right.',
    ]) {
      final a = InkMathRenderer.layout(latex, fontSizePt: 18)!;
      final b = InkMathRenderer.layout(latex, fontSizePt: 36)!;
      expect(b.sizePt.width / a.sizePt.width, closeTo(2, 0.04), reason: latex);
      expect(
        b.sizePt.height / a.sizePt.height,
        closeTo(2, 0.04),
        reason: latex,
      );
    }
  });

  test('the same formula gives the same layout (host reuse)', () {
    final a = InkMathRenderer.layout(r'\sqrt{x}', fontSizePt: 20);
    InkMathRenderer.layout(r'\int_0^1 f(x)\,dx', fontSizePt: 12);
    final b = InkMathRenderer.layout(r'\sqrt{x}', fontSizePt: 20);
    expect(a, b);
  });

  test('an invalid formula → null; a bad font size → ArgumentError', () {
    expect(InkMathRenderer.layout(r'\frac{a', fontSizePt: 18), isNull);
    expect(InkMathRenderer.layout('', fontSizePt: 18), isNull);
    expect(
      () => InkMathRenderer.layout('x', fontSizePt: 0),
      throwsArgumentError,
    );
  });

  testWidgets('called inside an outer build → StateError (S-9)', (
    tester,
  ) async {
    Object? error;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          try {
            InkMathRenderer.layout('x', fontSizePt: 18);
          } on StateError catch (e) {
            error = e;
          }
          return const SizedBox();
        },
      ),
    );
    expect(error, isA<StateError>());
    // outside the frame phases it works in a widget test too
    expect(InkMathRenderer.layout('x', fontSizePt: 18), isNotNull);
  });

  test(
    '(T36) rasterize: the laid-out size × pixelsPerPt, rounded up',
    () async {
      final l = InkMathRenderer.layout(r'\frac{a}{b}', fontSizePt: 18)!;
      final image = await InkMathRenderer.rasterize(
        r'\frac{a}{b}',
        colorArgb: 0xFF000000,
        fontSizePt: 18,
        pixelsPerPt: 2,
      );
      expect(image, isNotNull);
      expect(
        (image!.width, image.height),
        ((l.sizePt.width * 2).ceil(), (l.sizePt.height * 2).ceil()),
      );
      image.dispose();
    },
  );
}
