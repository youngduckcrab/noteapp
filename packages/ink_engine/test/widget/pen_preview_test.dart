// T20 (03-ink 4.9, EDITOR 5.3 #17): PenPreviewPainter — the real pipeline's
// S curve (fountain width follows the pressure swell; inside the size), the
// highlighter as a group on the paper, the pencil without grain until the
// PencilGrain is ready and then textured with no rebuild by the caller
// (repaint: pencilGrain), and the shouldRepaint rules.
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/pen_preview.dart'
    show penPreviewScript, penPreviewStrokeOf;
import 'package:note_core/note_core.dart' as core;

import '../support/pixels.dart';

final _key = GlobalKey(debugLabel: 'pen preview');
const _size = Size(240, 80);

Widget _app(CustomPainter painter, {int paper = 0xFFFFFFFF}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: RepaintBoundary(
      key: _key,
      child: ColoredBox(
        color: Color(paper),
        child: CustomPaint(size: _size, painter: painter),
      ),
    ),
  ),
);

Future<Pixels> _shot(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      return Pixels(image.width, image.height, (await image.toByteData())!);
    } finally {
      image.dispose();
    }
  }))!;
}

core.StrokeStyle _style(core.PenTool tool, {double? width}) {
  final s = core.StrokeStyle.defaultsFor(tool);
  return width == null ? s : s.copyWith(width: width);
}

/// Distinct red values of the stroke's pixels along its middle row band.
Set<int> _inkValues(Pixels px) => {
  for (var y = 30; y < 50; y++)
    for (var x = 60; x < 180; x++)
      if (px.at(x, y)[0] < 200) px.at(x, y)[0],
};

void main() {
  test('the S curve script stays inside the size, real pressure swell', () {
    final style = _style(core.PenTool.fountain, width: 6);
    final script = penPreviewScript(style, PenPreviewShape.sCurve, _size);
    expect(script.length, 96);
    expect(script.first.kind, InkPointerKind.stylus);
    for (final s in script) {
      expect(s.position.dx, inInclusiveRange(0, _size.width));
      expect(s.position.dy, inInclusiveRange(0, _size.height));
    }
    expect(script[48].pressure!, greaterThan(script.first.pressure! + 0.5));
    final line = penPreviewScript(style, PenPreviewShape.line, _size);
    expect({for (final s in line) s.position.dy}, {_size.height / 2});
    final built = penPreviewStrokeOf(style, PenPreviewShape.sCurve, _size)!;
    final b = built.stroke.bounds;
    expect(b.left, greaterThanOrEqualTo(-0.5));
    expect(b.right, lessThanOrEqualTo(_size.width + 0.5));
    expect(b.top, greaterThanOrEqualTo(-0.5));
    expect(b.bottom, lessThanOrEqualTo(_size.height + 0.5));
    // fountain: thicker in the middle (pressure) than at the ends
    final p = built.stroke.points;
    final mid = p.length ~/ 2;
    expect(
      built.stroke.radiusAt(mid),
      greaterThan(built.stroke.radiusAt(2) * 1.3),
    );
    expect(
      penPreviewStrokeOf(style, PenPreviewShape.sCurve, _size),
      same(built),
      reason: 'cached',
    );
  });

  testWidgets('each pen draws inside the size; the highlighter on the paper '
      'blend', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(400, 200);
    addTearDown(tester.view.reset);
    for (final tool in [
      core.PenTool.ballpoint,
      core.PenTool.fountain,
      core.PenTool.highlighter,
      core.PenTool.pencil,
      core.PenTool.marker,
    ]) {
      final style = _style(tool);
      await tester.pumpWidget(_app(PenPreviewPainter(style: style)));
      final px = await _shot(tester);
      var inked = 0;
      for (var y = 0; y < px.height; y++) {
        for (var x = 0; x < px.width; x++) {
          if (px.at(x, y)[0] < 250 || px.at(x, y)[2] < 250) inked++;
        }
      }
      expect(inked, greaterThan(100), reason: '$tool');
      // nothing at the very corner (margins)
      expect(px.at(0, 0), [255, 255, 255, 255], reason: '$tool');
    }
    // highlighter on black paper: screen blend lightens
    await tester.pumpWidget(
      _app(
        PenPreviewPainter(
          style: _style(core.PenTool.highlighter, width: 20),
          shape: PenPreviewShape.line,
          paperColorArgb: core.PaperColors.black,
        ),
        paper: core.PaperColors.black,
      ),
    );
    final dark = await _shot(tester);
    final c = dark.at(120, 40);
    expect(c[0] + c[1] + c[2], greaterThan(60), reason: 'lighter than paper');
  });

  testWidgets('pencil: no grain before ready, textured after — the painter '
      'repaints itself', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(400, 200);
    addTearDown(tester.view.reset);
    final grain = PencilGrain();
    addTearDown(grain.dispose);
    final painter = PenPreviewPainter(
      style: _style(
        core.PenTool.pencil,
        width: 24,
      ).copyWith(colorArgb: 0xFF000000),
      shape: PenPreviewShape.line,
      pencilGrain: grain,
    );
    await tester.pumpWidget(_app(painter));
    expect(grain.value, isNull);
    final before = _inkValues(await _shot(tester));
    expect(before.length, lessThanOrEqualTo(3), reason: 'flat fill');
    for (var i = 0; i < 500 && grain.value == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
    }
    expect(grain.value, isNotNull);
    // the notifier marked the painter for paint: one frame, no rebuild
    await tester.pump();
    // no new widget: the same painter object repainted on the notifier
    expect(
      tester.widget<CustomPaint>(find.byType(CustomPaint).last).painter,
      same(painter),
    );
    final after = _inkValues(await _shot(tester));
    expect(after.length, greaterThan(before.length + 5), reason: 'grain');
  });

  test('shouldRepaint: style, shape, paper by value; grain by identity', () {
    final g1 = PencilGrain();
    final g2 = PencilGrain();
    addTearDown(g1.dispose);
    addTearDown(g2.dispose);
    final style = _style(core.PenTool.ballpoint);
    final base = PenPreviewPainter(style: style, pencilGrain: g1);
    bool repaint(PenPreviewPainter p) => p.shouldRepaint(base);
    expect(
      repaint(
        PenPreviewPainter(
          style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
          pencilGrain: g1,
        ),
      ),
      isFalse,
    );
    expect(
      repaint(
        PenPreviewPainter(style: style.copyWith(width: 9), pencilGrain: g1),
      ),
      isTrue,
    );
    expect(
      repaint(
        PenPreviewPainter(
          style: style,
          shape: PenPreviewShape.line,
          pencilGrain: g1,
        ),
      ),
      isTrue,
    );
    expect(
      repaint(
        PenPreviewPainter(
          style: style,
          paperColorArgb: core.PaperColors.black,
          pencilGrain: g1,
        ),
      ),
      isTrue,
    );
    expect(repaint(PenPreviewPainter(style: style, pencilGrain: g2)), isTrue);
    expect(repaint(PenPreviewPainter(style: style)), isTrue);
  });

  test('a tiny or empty size draws nothing and does not throw', () {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final p = PenPreviewPainter(style: _style(core.PenTool.fountain));
    p
      ..paint(canvas, Size.zero)
      ..paint(canvas, const Size(4, 4))
      ..paint(canvas, const Size(400, 2));
    recorder.endRecording().dispose();
  });
}
