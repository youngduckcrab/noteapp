@TestOn('browser')
library;

// T26b (m5-7/03-ink 8.1): the off-screen layout host on the web (Chrome =
// CanvasKit) — layout works without loading the KaTeX fonts (rootBundle does not
// answer under `flutter test --platform chrome`), validate is the same, and the
// MathPreview widget lays out.
// (T36, 6.12.2) The raster host on CanvasKit, without the KaTeX fonts: the SVG
// glyph samples have their ink, and the delayed loader seam gives the same
// results as on the VM (waits for a late picture, null past the settle cap,
// FIFO queue, joined requests, timer turns, also from inside paint) — the
// bodies of test/support/math_raster_cases.dart.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';

import '../support/math_raster_cases.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('layout is non-null without the KaTeX fonts', () {
    final l = InkMathRenderer.layout(
      r'\left\{\begin{array}{l} x+y=1 \\ x-y=3 \end{array}\right.',
      fontSizePt: 18,
    );
    expect(l, isNotNull);
    expect(l!.sizePt.width, greaterThan(0));
    expect(l.baselinePt, greaterThan(0));
    expect(InkMathRenderer.layout(r'\frac{a', fontSizePt: 18), isNull);
  });

  test('validate gives the same messages', () {
    expect(InkMathRenderer.validate(r'\frac{a}{b}'), isNull);
    expect(InkMathRenderer.validate(r'\frac{a'), "Expected '}', got 'EOF'");
    expect(InkMathRenderer.validate(''), 'Empty formula');
  });

  testWidgets('MathPreview lays out', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: MathPreview(
            latex: r'\int_0^1 \frac{\sin x}{x}\,dx',
            fontSize: 24,
            color: Color(0xFF000000),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(MathPreview)).width, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  group('(T36) SVG glyph samples', svgGlyphCases);
  group('(T36) raster queue', () {
    offscreenQueueCases();
    paintPhaseRequestCase();
  });
}
