// T10 (03-ink 8, 6.10-6): while a highlighter is being written, its color
// group leaves the base highlighter picture (re-recorded once) and the active
// layer composites the committed lines, the pending strokes and the stroke
// being written in ONE layer — the overlap with an existing same-color
// highlighter stays a single-stroke pixel before, during and after the
// commit; ink strokes stay on top.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show inkHighlighterCacheOf;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/page_view.dart';
import '../support/pixels.dart';

const _bluePx = [0, 0, 255, 255];

void main() {
  late InkPageController controller;
  late List<core.Stroke> committed;
  final hlStyle = core.StrokeStyle.defaultsFor(core.PenTool.highlighter);
  final existing = strokeThrough(
    segment(const Offset(50, 150), const Offset(400, 150)),
    hlStyle,
    id: 'hl-old',
  );
  final ink = strokeThrough(
    segment(const Offset(300, 60), const Offset(300, 260)),
    core.StrokeStyle.defaultsFor(core.PenTool.marker)
        .copyWith(colorArgb: 0xFF0000FF, width: 6),
    id: 'ink',
  );

  setUp(() {
    committed = [existing, ink];
    controller = createTestPageController(
      services: testInkCoreServices(startMillis: 100000),
    )..updateContent(SyntheticInk.pageContent(strokes: committed));
  });
  tearDown(() => controller.dispose());

  StrokeSession write(core.StrokeStyle style, List<Offset> points) {
    final samples = [
      for (var i = 0; i < points.length; i++)
        InkSample(
          position: points[i],
          timeUs: i * 8333,
          kind: InkPointerKind.touch,
        ),
    ];
    return controller.beginStroke(samples.first, style: style, viewScale: 1)
      ..addSamples(samples.skip(1));
  }

  /// A vertical stroke through the existing highlighter at x = 150 and a
  /// horizontal one along it covering the ink at x = 300.
  List<Offset> cross() => [
    ...segment(const Offset(150, 60), const Offset(150, 150), step: 2),
    ...segment(const Offset(150, 150), const Offset(350, 150), step: 2),
  ];

  testWidgets('same color: overlap = single pixel while writing, pending, '
      'committed', (tester) async {
    await pumpPageView(tester, controller, width: 596);
    final hlCache = inkHighlighterCacheOf(controller);
    final before = await capturePixels(tester);
    final single = before.at(100, 150);
    expect(single, isNot([255, 255, 255, 255]));
    expect(before.at(300, 120), _bluePx, reason: 'ink above highlighter');
    final records = hlCache.recordCount;

    final session = write(hlStyle, cross());
    await tester.pump();
    expect(
      hlCache.recordCount,
      records + 1,
      reason: 'the group left the base picture (once)',
    );
    final writing = await capturePixels(tester);
    final fresh = writing.at(150, 90);
    expect(samePixel(fresh, single, tol: 2), isTrue, reason: 'same group');
    expect(
      samePixel(writing.at(200, 150), single, tol: 2),
      isTrue,
      reason: 'overlap with the committed one is not darker',
    );
    expect(samePixel(writing.at(100, 150), single, tol: 2), isTrue);
    expect(writing.at(300, 150), _bluePx, reason: 'ink above, writing');

    session.addSample(
      const InkSample(
        position: Offset(360, 150),
        timeUs: 400000,
        kind: InkPointerKind.touch,
      ),
    );
    await tester.pump();
    expect(hlCache.recordCount, records + 1, reason: 'not per frame');

    final edit = session.end()!;
    await tester.pump();
    final pending = await capturePixels(tester);
    expect(samePixel(pending.at(200, 150), single, tol: 2), isTrue);
    expect(samePixel(pending.at(150, 90), single, tol: 2), isTrue);
    expect(pending.at(300, 150), _bluePx);

    committed = [...committed, edit.added.single];
    controller.updateContent(
      SyntheticInk.pageContent(strokes: committed, revision: 2),
    );
    await tester.pump();
    final after = await capturePixels(tester);
    expect(samePixel(after.at(200, 150), single, tol: 2), isTrue);
    expect(samePixel(after.at(150, 90), single, tol: 2), isTrue);
    expect(after.at(300, 150), _bluePx);
    expect(hlCache.recordCount, records + 2, reason: 'group back in base');
  });

  testWidgets('another color is another group (control: darker overlap)', (
    tester,
  ) async {
    await pumpPageView(tester, controller, width: 596);
    final single = (await capturePixels(tester)).at(100, 150);
    final other = hlStyle.copyWith(colorArgb: 0xFF7FD3FF);
    final session = write(other, cross());
    await tester.pump();
    final px = await capturePixels(tester);
    final alone = px.at(150, 90);
    final overlap = px.at(200, 150);
    expect(samePixel(overlap, single, tol: 2), isFalse);
    expect(samePixel(overlap, alone, tol: 2), isFalse);
    expect(px.at(300, 150), _bluePx);
    session.cancel();
  });

  testWidgets('cancel: the group goes back to the base picture', (
    tester,
  ) async {
    await pumpPageView(tester, controller, width: 596);
    final before = await capturePixels(tester);
    final hlCache = inkHighlighterCacheOf(controller);
    final records = hlCache.recordCount;
    final session = write(hlStyle, cross());
    await tester.pump();
    expect(hlCache.recordCount, records + 1);
    session.cancel();
    await tester.pump();
    final px = await capturePixels(tester);
    expect(samePixel(px.at(100, 150), before.at(100, 150)), isTrue);
    expect(samePixel(px.at(150, 90), before.at(150, 90)), isTrue);
    expect(hlCache.recordCount, records + 2, reason: 'back in base');
  });
}
