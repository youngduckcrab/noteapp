// T08 (03-ink 8, 6.10): highlighters do not darken where they overlap, stay
// "under the text" on light paper (multiply) and stay visible on dark paper
// (srcOver).
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/src/render/highlighter_compositor.dart';
import 'package:ink_engine/src/render/layer_painters.dart';
import 'package:ink_engine/src/render/stroke_painter.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../../support/pixels.dart';

final core.StrokeStyle _yellow = core.StrokeStyle.defaultsFor(
  core.PenTool.highlighter,
).copyWith(width: 16);

core.Stroke _horizontal({core.StrokeStyle? style}) => strokeThrough(
  segment(const Offset(20, 50), const Offset(180, 50)),
  style ?? _yellow,
);

core.Stroke _vertical({core.StrokeStyle? style}) => strokeThrough(
  segment(const Offset(100, 10), const Offset(100, 90)),
  style ?? _yellow,
);

Future<Pixels> _paintStrokes(
  List<core.Stroke> strokes, {
  int paper = core.PaperColors.white,
  void Function(ui.Canvas canvas)? under,
}) => renderPixels(200, 100, (canvas) {
  paintPaper(canvas, paper);
  under?.call(canvas);
  paintStrokeLayers(
    canvas,
    strokes.map(InkStroke.of),
    paperColorArgb: paper,
    outlineOf: OutlineGenerator.outline,
  );
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('same color, same opacity = one group', () {
    test('the overlap pixel equals a single-stroke pixel', () async {
      final px = await _paintStrokes([_horizontal(), _vertical()]);
      final single = px.at(40, 50);
      final overlap = px.at(100, 50);
      expect(single, isNot([255, 255, 255, 255]), reason: 'visible');
      expect(samePixel(overlap, single), isTrue, reason: '$overlap $single');
      expect(samePixel(px.at(100, 20), single), isTrue);
    });

    test('control: two separate composites darken the overlap', () async {
      final a = InkStroke.of(_horizontal()), b = InkStroke.of(_vertical());
      final px = await renderPixels(200, 100, (canvas) {
        paintPaper(canvas, core.PaperColors.white);
        for (final s in [a, b]) {
          paintHighlighterGroups(
            canvas,
            groupHighlighters([s]),
            paperColorArgb: core.PaperColors.white,
          );
        }
      });
      expect(samePixel(px.at(100, 50), px.at(40, 50)), isFalse);
    });

    test('another color or opacity is another group', () async {
      final pink = _yellow.copyWith(colorArgb: 0xFFFF4FA3);
      final px = await _paintStrokes([_horizontal(), _vertical(style: pink)]);
      expect(samePixel(px.at(100, 50), px.at(40, 50)), isFalse);
      final lighter = _yellow.copyWith(opacity: 0.6);
      final px2 = await _paintStrokes([
        _horizontal(),
        _vertical(style: lighter),
      ]);
      expect(samePixel(px2.at(100, 50), px2.at(40, 50)), isFalse);
      // opacity rounded to 1/100: 0.351 joins the 0.35 group
      final key = HighlighterGroupKey.of(_yellow.copyWith(opacity: 0.351));
      expect(key, HighlighterGroupKey.of(_yellow));
    });

    test('a stroke crossing itself is not darker either', () async {
      final loop = strokeThrough([
        ...segment(const Offset(20, 50), const Offset(150, 50)),
        ...segment(const Offset(150, 50), const Offset(100, 10)).skip(1),
        ...segment(const Offset(100, 10), const Offset(100, 90)).skip(1),
      ], _yellow);
      final px = await _paintStrokes([loop]);
      expect(samePixel(px.at(100, 50), px.at(40, 50)), isTrue);
    });
  });

  group('paper decides the blend (6.10-4)', () {
    void blackText(ui.Canvas canvas) => canvas.drawRect(
      const Rect.fromLTRB(90, 40, 110, 60),
      Paint()..color = const Color(0xFF000000),
    );

    test('white paper: multiply keeps black text black', () async {
      expect(highlighterBlendFor(core.PaperColors.white), BlendMode.multiply);
      expect(highlighterBlendFor(core.PaperColors.ivory), BlendMode.multiply);
      final px = await _paintStrokes([_horizontal()], under: blackText);
      expect(px.at(100, 50), [0, 0, 0, 255]);
      // the highlighter itself tints the paper
      final tint = px.at(40, 50);
      expect(tint[2], lessThan(200)); // blue goes down under yellow
      expect(tint[0], greaterThan(240));
    });

    test('control: srcOver would lift the black text', () async {
      final px = await renderPixels(200, 100, (canvas) {
        paintPaper(canvas, core.PaperColors.white);
        blackText(canvas);
        paintHighlighterGroup(
          canvas,
          groupHighlighters([InkStroke.of(_horizontal())]).single,
          blend: BlendMode.srcOver,
        );
      });
      expect(px.at(100, 50), isNot([0, 0, 0, 255]));
    });

    test('dark paper: srcOver keeps the highlighter visible', () async {
      expect(highlighterBlendFor(core.PaperColors.black), BlendMode.srcOver);
      final px = await _paintStrokes([
        _horizontal(),
        _vertical(),
      ], paper: core.PaperColors.black);
      final paper = px.at(40, 20);
      final hl = px.at(40, 50);
      expect(hl[0] - paper[0], greaterThan(50));
      expect(hl[1] - paper[1], greaterThan(50));
      expect(samePixel(px.at(100, 50), hl), isTrue);
      // control: multiply on (almost) black stays dark
      final dark = await renderPixels(200, 100, (canvas) {
        paintPaper(canvas, core.PaperColors.black);
        paintHighlighterGroup(
          canvas,
          groupHighlighters([InkStroke.of(_horizontal())]).single,
          blend: BlendMode.multiply,
        );
      });
      expect(dark.at(40, 50)[0] - paper[0], lessThan(20));
    });
  });

  testWidgets(
    'InkPageView: same-color overlap = single, ink above highlighter',
    (tester) async {
      final key = GlobalKey();
      final controller = createTestPageController();
      addTearDown(controller.dispose);
      final pen = strokeThrough(
        segment(const Offset(20, 70), const Offset(180, 70)),
        core.StrokeStyle.defaultsFor(core.PenTool.marker)
            .copyWith(colorArgb: 0xFF000000),
        createdAt: 10, // below the highlighters in z, still drawn above them
      );
      controller.updateContent(
        SyntheticInk.pageContent(
          strokes: [
            _horizontal(),
            _vertical(),
            strokeThrough(
              segment(const Offset(20, 70), const Offset(180, 70)),
              _yellow,
            ),
            pen,
          ],
        ),
      );
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
      final single = px!.at(40, 50);
      expect(single, isNot([255, 255, 255, 255]));
      expect(samePixel(px.at(100, 50), single), isTrue);
      expect(px.at(60, 70), [0, 0, 0, 255]); // marker over highlighter
    },
  );
}
