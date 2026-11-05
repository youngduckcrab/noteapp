@TestOn('browser')
library;

// Foundation step B3 on the web (Chrome = CanvasKit): the browser InkClock behind the
// conditional import, the web render defaults and a page view + thumbnail PNG round trip.
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

void main() {
  test('InkClock.platform is performance.now() on the web', () {
    final clock = InkClock.platform();
    expect(clock.alignedWithEventTimestamps, isTrue);
    final a = clock.nowUs();
    final b = clock.nowUs();
    expect(a, greaterThan(0));
    expect(b, greaterThanOrEqualTo(a));
  });

  test('platformDefault is webDefaults', () {
    expect(InkRenderConfig.platformDefault, InkRenderConfig.webDefaults);
  });

  testWidgets('pen stroke → view → thumbnail PNG', (tester) async {
    final c = createTestPageController()
      ..updateContent(SyntheticInk.pageContent());
    addTearDown(c.dispose);
    final samples = SyntheticInk.line(
      const Offset(50, 50),
      const Offset(200, 120),
    );
    final s = c.beginStroke(
      samples.first,
      style: core.StrokeStyle.defaultsFor(core.PenTool.fountain),
      viewScale: 1,
    )..addSamples(samples.skip(1));
    final edit = s.end()!;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: InkPageView(controller: c),
      ),
    );
    final stroke = edit.added.single;
    c.updateContent(SyntheticInk.pageContent(strokes: [stroke], revision: 2));
    expect(c.pendingIds, isEmpty);
    await tester.pump();
    final thumb = await tester.runAsync(
      () =>
          InkPageThumbnailRenderer(
            backgroundBuilders: const [TemplateBackgroundLayerBuilder()],
          ).render(
            core.PageContent(
              page: SyntheticInk.page(),
              strokes: [stroke],
              revision: 2,
            ),
            maxSidePx: 128,
          ),
    );
    expect(thumb!.height, 128);
    final size = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(thumb.bytes);
      final frame = await codec.getNextFrame();
      return (frame.image.width, frame.image.height);
    });
    expect(size, (thumb.width, thumb.height));
  });
}
