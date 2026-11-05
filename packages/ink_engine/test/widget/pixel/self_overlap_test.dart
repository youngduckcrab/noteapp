// T08 (03-ink 8, 6.8 nonzero, 6.12 R5): a semi-transparent stroke that
// crosses itself is painted once — the overlapping part has the same pixel as
// a single part, both for a committed stroke (one nonzero path) and for the
// stroke being written (frozen chunks + tail inside one saveLayer).
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/src/render/sessions.dart' show liveFrozenChunks;
import 'package:ink_engine/src/render/stroke_painter.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../../support/outline_helpers.dart';
import '../../support/pixels.dart';

/// (20,50) → (150,50) → (100,10) → (100,90): crosses itself at (100, 50).
List<Offset> _loop() => [
  ...segment(const Offset(20, 50), const Offset(150, 50)),
  ...segment(const Offset(150, 50), const Offset(100, 10)).skip(1),
  ...segment(const Offset(100, 10), const Offset(100, 90)).skip(1),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final tool in [
    core.PenTool.ballpoint,
    core.PenTool.fountain,
    core.PenTool.marker,
  ]) {
    test('$tool opacity 0.5: overlap = single part', () async {
      final style = core.StrokeStyle.defaultsFor(tool)
          .copyWith(width: 4, opacity: 0.5);
      final s = InkStroke.of(strokeThrough(_loop(), style));
      final px = await renderPixels(200, 100, (canvas) {
        paintPaper(canvas, core.PaperColors.white);
        paintFillStroke(canvas, s, OutlineGenerator.outline(s));
      });
      final single = px.at(40, 50);
      expect(single, isNot([255, 255, 255, 255]));
      expect(single[0], greaterThan(60), reason: 'semi-transparent');
      expect(samePixel(px.at(100, 50), single), isTrue);
      expect(samePixel(px.at(100, 75), single), isTrue);
    });
  }

  test('live chunks: overlapping paths inside one layer', () async {
    final a = outlineFor(
      segment(const Offset(20, 50), const Offset(120, 50)),
      width: 4,
    ).toPath();
    final b = outlineFor(
      segment(const Offset(100, 10), const Offset(100, 90)),
      width: 4,
    ).toPath();
    final px = await renderPixels(200, 100, (canvas) {
      paintPaper(canvas, core.PaperColors.white);
      paintFillPaths(
        canvas,
        [a, b],
        profile: PenProfile.ballpoint,
        colorArgb: 0xFF1A1A1A,
        opacity: 0.5,
        bounds: const Rect.fromLTRB(0, 0, 200, 100),
      );
    });
    expect(samePixel(px.at(100, 50), px.at(40, 50)), isTrue);
    // control: two separate semi-transparent fills darken the overlap
    final control = await renderPixels(200, 100, (canvas) {
      paintPaper(canvas, core.PaperColors.white);
      final paint = inkFillPaint(
        PenProfile.ballpoint,
        inkColor(0xFF1A1A1A, 0.5),
      );
      canvas
        ..drawPath(a, paint)
        ..drawPath(b, paint);
    });
    expect(samePixel(control.at(100, 50), control.at(40, 50)), isFalse);
  });

  testWidgets('the stroke being written (InkPageView, frozen chunks)', (
    tester,
  ) async {
    final key = GlobalKey();
    final controller = createTestPageController();
    addTearDown(controller.dispose);
    controller.updateContent(SyntheticInk.pageContent());
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(600, 860);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: core.PageSize.a4Portrait.width,
              child: InkPageView(controller: controller),
            ),
          ),
        ),
      ),
    );
    // touch → simulated pressure at once → chunks freeze every 64 points
    final points = [
      ...segment(const Offset(20, 150), const Offset(300, 150), step: 1),
      ...segment(const Offset(300, 150), const Offset(200, 60), step: 1),
      ...segment(const Offset(200, 60), const Offset(200, 260), step: 1),
    ];
    final samples = [
      for (var i = 0; i < points.length; i++)
        InkSample(
          position: points[i],
          timeUs: i * 8333,
          kind: InkPointerKind.touch,
        ),
    ];
    final style = core.StrokeStyle.defaultsFor(core.PenTool.marker)
        .copyWith(opacity: 0.5, smoothing: 0);
    final session = controller.beginStroke(
      samples.first,
      style: style,
      viewScale: 1,
    );
    session.addSamples(samples.skip(1));
    await tester.pump();
    expect(liveFrozenChunks(session.live).length, greaterThan(2));
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    final px = await tester.runAsync(() async {
      final image = await boundary.toImage();
      try {
        return Pixels(image.width, image.height, (await image.toByteData())!);
      } finally {
        image.dispose();
      }
    });
    final single = px!.at(60, 150);
    expect(single, isNot([255, 255, 255, 255]));
    expect(single[0], greaterThan(60), reason: 'semi-transparent');
    expect(samePixel(px.at(200, 150), single, tol: 2), isTrue);
    session.cancel();
  });
}
