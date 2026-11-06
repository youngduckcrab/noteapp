// T20 (03-ink 4.9, EDITOR 5.3 #17): PenPreviewPainter — the real pipeline's
// S curve (fountain width follows the pressure swell; inside the size), the
// highlighter as a group on the paper, the pencil without grain until the
// PencilGrain is ready and then textured with no rebuild by the caller
// (repaint: pencilGrain), and the shouldRepaint rules.
// v2 (m5-7/03-ink 6.2 'pen preview v2', T27): the painter branches on the
// render method — the round-1 pens keep their pixels (also the unchanged
// goldens/pen_preview.png), the brush draws with its own profile, and all five
// P1 pens draw without exceptions (those still on the ballpoint fallback too).
// T28~T31 add their rows: T29 the dashed preview (dashedPolyline — dashes and
// gaps of style.dashPattern × width along the line).
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/geometry/stroke_outline.dart';
import 'package:ink_engine/src/render/highlighter_compositor.dart';
import 'package:ink_engine/src/render/pen_preview.dart'
    show penPreviewScript, penPreviewStrokeOf;
import 'package:ink_engine/src/render/stroke_painter.dart';
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

  testWidgets('v2: the round-1 pens draw the same pixels as their filled '
      'outline / highlighter group', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(400, 200);
    addTearDown(tester.view.reset);
    for (final tool in core.PenTool.values.where((t) => t.isP0)) {
      final style = _style(tool);
      await tester.pumpWidget(_app(PenPreviewPainter(style: style)));
      final viaPainter = await _shot(tester);
      final built = penPreviewStrokeOf(style, PenPreviewShape.sCurve, _size)!;
      await tester.pumpWidget(
        _app(_RoundOnePainter(built.stroke, built.outline)),
      );
      final roundOne = await _shot(tester);
      expect(
        _differingPixels(viaPainter, roundOne),
        0,
        reason: '${tool.name}: the render-method branch is the round-1 path',
      );
    }
  });

  testWidgets('v2: the brush preview — ink, thick middle, thin tapered ends', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(400, 200);
    addTearDown(tester.view.reset);
    final style = _style(core.PenTool.brush, width: 4);
    final built = penPreviewStrokeOf(style, PenPreviewShape.line, _size)!;
    expect(built.stroke.profile, same(PenProfile.brush));
    expect(built.outline, isNotNull);
    final n = built.stroke.points.length;
    final mid = built.stroke.radiusAt(n ~/ 2);
    // pressure 0.9 in the middle: f = 1 + 0.9 · 0.8 = 1.72; the tips taper to
    // taperMinFactor 0.08
    expect(mid, closeTo(2 * 4 * 1.72 / core.kMaxWidthFactor, 0.15));
    expect(built.stroke.radiusAt(0), lessThan(mid * 0.3));
    expect(built.stroke.radiusAt(n - 1), lessThan(mid * 0.3));
    await tester.pumpWidget(
      _app(
        PenPreviewPainter(
          style: style.copyWith(colorArgb: 0xFF000000),
          shape: PenPreviewShape.line,
        ),
      ),
    );
    final px = await _shot(tester);
    int column(int x) {
      var c = 0;
      for (var y = 0; y < px.height; y++) {
        if (px.at(x, y)[0] < 128) c++;
      }
      return c;
    }

    final midX = (_size.width / 2).round();
    expect(column(midX), greaterThanOrEqualTo(5), reason: 'thick middle');
    final left = built.stroke.bounds.left.ceil() + 1;
    expect(column(left), lessThan(column(midX)), reason: 'tapered start');
  });

  testWidgets('v2: the dashed preview — dashes and gaps of the pattern × '
      'width (T29)', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(400, 200);
    addTearDown(tester.view.reset);
    for (final (pattern, on, off) in [
      (const [4.0, 3.0], 8.0, 6.0),
      (const [2.0, 2.0], 4.0, 4.0),
    ]) {
      final style = _style(
        core.PenTool.dashed,
        width: 2,
      ).withInkExtras(dashPattern: pattern).copyWith(colorArgb: 0xFF000000);
      final built = penPreviewStrokeOf(style, PenPreviewShape.line, _size)!;
      expect(built.stroke.profile, same(PenProfile.dashed));
      expect(built.outline!.polygons.length, greaterThan(5));
      await tester.pumpWidget(
        _app(PenPreviewPainter(style: style, shape: PenPreviewShape.line)),
      );
      final px = await _shot(tester);
      // runs of ink / paper along the middle row
      final y = (_size.height / 2).round();
      final runs = <(bool, int)>[];
      for (var x = 0; x < px.width; x++) {
        final ink = px.at(x, y)[0] < 128;
        if (runs.isNotEmpty && runs.last.$1 == ink) {
          runs[runs.length - 1] = (ink, runs.last.$2 + 1);
        } else {
          runs.add((ink, 1));
        }
      }
      // drop the paper margins and the last (cut) dash
      final inner = runs.sublist(1, runs.length - 2);
      final dashes = [
        for (final r in inner)
          if (r.$1) r.$2,
      ];
      final gaps = [
        for (final r in inner)
          if (!r.$1) r.$2,
      ];
      expect(dashes.length, greaterThan(5), reason: '$pattern');
      for (final d in dashes) {
        expect(d.toDouble(), closeTo(on, 1.5), reason: '$pattern dash');
      }
      for (final g in gaps) {
        expect(g.toDouble(), closeTo(off, 1.5), reason: '$pattern gap');
      }
    }
  });

  testWidgets('v2: every P1 pen draws ink without exceptions (ballpoint '
      'fallback until T28, T30, T31)', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(400, 200);
    addTearDown(tester.view.reset);
    for (final tool in core.PenTool.values.where((t) => !t.isP0)) {
      for (final shape in PenPreviewShape.values) {
        await tester.pumpWidget(
          _app(PenPreviewPainter(style: _style(tool), shape: shape)),
        );
        expect(tester.takeException(), isNull, reason: '$tool $shape');
        final px = await _shot(tester);
        var inked = 0;
        for (var y = 0; y < px.height; y++) {
          for (var x = 0; x < px.width; x++) {
            final c = px.at(x, y);
            if (c[0] < 250 || c[1] < 250 || c[2] < 250) inked++;
          }
        }
        expect(inked, greaterThan(50), reason: '$tool $shape');
      }
    }
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

  test(
    'an empty or non-finite size draws nothing (no pixel, any tool)',
    () async {
      const sizes = [
        Size.zero,
        Size(0, 80),
        Size(240, 0),
        Size(double.infinity, 80),
        Size(240, double.nan),
      ];
      for (final tool in core.PenTool.values) {
        final p = PenPreviewPainter(style: _style(tool));
        for (final size in sizes) {
          expect(await _paintedPixels(p, size), 0, reason: '$tool $size');
        }
      }
    },
  );

  test('a tiny size does not throw (the margin shrinks to the short side)', () {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final p = PenPreviewPainter(style: _style(core.PenTool.fountain));
    p
      ..paint(canvas, const Size(1, 1))
      ..paint(canvas, const Size(4, 4))
      ..paint(canvas, const Size(400, 2));
    recorder.endRecording().dispose();
  });
}

int _differingPixels(Pixels a, Pixels b) {
  expect([a.width, a.height], [b.width, b.height]);
  var n = 0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      final p = a.at(x, y), q = b.at(x, y);
      if (p[0] != q[0] || p[1] != q[1] || p[2] != q[2] || p[3] != q[3]) n++;
    }
  }
  return n;
}

/// The round-1 PenPreviewPainter body: the highlighter group, else the fill.
class _RoundOnePainter extends CustomPainter {
  _RoundOnePainter(this.stroke, this.outline);
  final InkStroke stroke;
  final StrokeOutline? outline;

  @override
  void paint(Canvas canvas, Size size) {
    if (stroke.layer == InkLayer.highlighter) {
      paintHighlighterGroups(
        canvas,
        groupHighlighters([stroke]),
        paperColorArgb: core.PaperColors.white,
        marginPt: 1,
      );
      return;
    }
    paintFillStroke(canvas, stroke, outline!);
  }

  @override
  bool shouldRepaint(_RoundOnePainter oldDelegate) => true;
}

/// Pixels with alpha > 0 after [painter] paints [size] on a transparent canvas
/// with a 64 px border on every side (so ink outside the size counts too).
Future<int> _paintedPixels(CustomPainter painter, Size size) async {
  const pad = 64;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..translate(pad.toDouble(), pad.toDouble());
  painter.paint(canvas, size);
  final picture = recorder.endRecording();
  int side(double v) => (v.isFinite ? v.ceil() : 0) + 2 * pad;
  final image = await picture.toImage(side(size.width), side(size.height));
  picture.dispose();
  try {
    final data = (await image.toByteData())!;
    var n = 0;
    for (var i = 3; i < data.lengthInBytes; i += 4) {
      if (data.getUint8(i) != 0) n++;
    }
    return n;
  } finally {
    image.dispose();
  }
}
