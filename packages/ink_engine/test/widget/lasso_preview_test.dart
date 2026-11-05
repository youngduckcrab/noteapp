// T17 (03-ink 6.12 R8, 6.21 L1): while a lasso is drawn the overlay layer
// shows its path closed end → start: inside filled with
// InkTuning.lassoFillArgb (nonzero — both loops of a figure 8), the path a
// 1.5 screen px dashed line (6 px on / 4 px off) in InkTuning.lassoPathArgb,
// at any viewScale. It grows with addPoint and is gone after end / cancel.
import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/page_view.dart';
import '../support/pixels.dart';

List<int> _rgba(int argb) => [
  (argb ~/ 0x10000) % 0x100,
  (argb ~/ 0x100) % 0x100,
  argb % 0x100,
  argb ~/ 0x1000000,
];

/// [argb] (translucent) over the opaque [paper] pixel.
List<int> _over(int argb, List<int> paper) {
  final c = _rgba(argb);
  final a = c[3] / 255;
  return [
    for (var i = 0; i < 3; i++) (c[i] * a + paper[i] * (1 - a)).round(),
    255,
  ];
}

void main() {
  late InkPageController controller;
  final pathPx = _rgba(InkTuning.lassoPathArgb);

  setUp(() {
    controller = createTestPageController()
      ..updateContent(
        SyntheticInk.pageContent(size: const core.PageSize(400, 400)),
      );
  });
  tearDown(() => controller.dispose());

  /// A square lasso whose screen corners are (100.5, 100.5) and
  /// (300.5, 300.5) at [viewScale]: the 1.5 px line covers whole pixel rows.
  LassoSession square(double viewScale) {
    Offset at(double x, double y) => Offset(x / viewScale, y / viewScale);
    return controller.beginLasso(at(100.5, 100.5), viewScale: viewScale)
      ..addPoint(at(300.5, 100.5))
      ..addPoint(at(300.5, 300.5))
      ..addPoint(at(100.5, 300.5));
  }

  for (final viewScale in [1.0, 2.0]) {
    testWidgets('path and fill colors, dashes in screen px (viewScale '
        '${viewScale.toInt()})', (tester) async {
      await pumpPageView(
        tester,
        controller,
        width: 400 * viewScale,
        surface: Size(400 * viewScale + 20, 400 * viewScale + 20),
      );
      final paper = (await capturePixels(tester)).at(50, 50);
      expect(paper[3], 255);

      square(viewScale);
      await tester.pump();
      final px = await capturePixels(tester);
      // inside: the fill over the paper; outside: the paper
      expect(
        samePixel(px.at(200, 200), _over(InkTuning.lassoFillArgb, paper)),
        isTrue,
        reason: '${px.at(200, 200)}',
      );
      expect(px.at(50, 50), paper);
      expect(px.at(350, 200), paper);
      // the top edge (pixel row 100 is fully under the 1.5 px line):
      // dashes [100.5, 106.5], [110.5, 116.5], … with gaps between
      for (final x in [102, 105, 112, 115, 122, 125]) {
        expect(px.at(x, 100), pathPx, reason: 'dash at x = $x');
      }
      for (final x in [108, 109, 118, 119]) {
        expect(
          samePixel(px.at(x, 100), pathPx, tol: 30),
          isFalse,
          reason: 'gap at x = $x',
        );
      }
      // the left edge (closing edge 100.5, 300.5 → 100.5, 100.5) too
      expect(
        [for (var y = 110; y < 290; y++) px.at(100, y)]
            .where((p) => samePixel(p, pathPx)),
        isNotEmpty,
      );
      // the line is 1.5 px: rows 98 and 102 are not covered
      expect(samePixel(px.at(103, 98), pathPx, tol: 30), isFalse);
      expect(samePixel(px.at(103, 102), pathPx, tol: 30), isFalse);
    });
  }

  testWidgets('grows with addPoint; gone after end and cancel', (tester) async {
    await pumpPageView(
      tester,
      controller,
      width: 400,
      surface: const Size(420, 420),
    );
    final paper = (await capturePixels(tester)).at(50, 50);
    final fill = _over(InkTuning.lassoFillArgb, paper);

    final s = controller.beginLasso(const Offset(100, 100), viewScale: 1);
    await tester.pump();
    expect((await capturePixels(tester)).at(101, 100), paper, reason: '1 pt');

    s
      ..addPoint(const Offset(300, 100))
      ..addPoint(const Offset(300, 200));
    await tester.pump();
    var px = await capturePixels(tester);
    expect(samePixel(px.at(250, 140), fill), isTrue, reason: 'triangle');
    expect(px.at(150, 180), paper, reason: 'not yet inside');

    s.addPoint(const Offset(100, 200));
    await tester.pump();
    px = await capturePixels(tester);
    expect(samePixel(px.at(150, 180), fill), isTrue, reason: 'square now');

    s.end();
    await tester.pump();
    px = await capturePixels(tester);
    expect(px.at(150, 180), paper);
    expect(px.at(200, 100), paper);

    final c = controller.beginLasso(const Offset(100, 100), viewScale: 1)
      ..addPoint(const Offset(300, 100))
      ..addPoint(const Offset(300, 300));
    await tester.pump();
    expect(samePixel((await capturePixels(tester)).at(280, 150), fill), isTrue);
    c.cancel();
    await tester.pump();
    expect((await capturePixels(tester)).at(280, 150), paper);
  });

  testWidgets('figure 8: both loops filled once (nonzero)', (tester) async {
    await pumpPageView(
      tester,
      controller,
      width: 400,
      surface: const Size(420, 420),
    );
    final paper = (await capturePixels(tester)).at(10, 10);
    final fill = _over(InkTuning.lassoFillArgb, paper);
    const n = 160;
    Offset p(int k) => Offset(
      200 + 150 * math.sin(2 * math.pi * k / n),
      200 + 80 * math.sin(4 * math.pi * k / n),
    );
    final s = controller.beginLasso(p(0), viewScale: 1);
    for (var k = 1; k < n; k++) {
      s.addPoint(p(k));
    }
    await tester.pump();
    final px = await capturePixels(tester);
    expect(samePixel(px.at(300, 200), fill), isTrue, reason: 'right loop');
    expect(samePixel(px.at(100, 200), fill), isTrue, reason: 'left loop');
    expect(px.at(200, 330), paper);
    s.cancel();

    // a square wound twice: still one layer of fill
    final twice = controller.beginLasso(const Offset(100, 100), viewScale: 1);
    for (final q in [
      ...const [Offset(300, 100), Offset(300, 300), Offset(100, 300)],
      ...const [Offset(100, 100), Offset(300, 100), Offset(300, 300)],
      const Offset(100, 300),
    ]) {
      twice.addPoint(q);
    }
    await tester.pump();
    expect(samePixel((await capturePixels(tester)).at(200, 200), fill), isTrue);
    twice.cancel();
  });
}
