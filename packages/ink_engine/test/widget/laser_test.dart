// m5-7/03-ink T30 (6.6, K-9, CP-INK-7): the laser on the page. While written and
// while it fades, only the overlay layer has its pixels — the inkBase chunks are
// never recorded; end() == null, nothing pending, the content is the same object
// (no updateContent); cancel() takes the trail away at once; its color is
// InkTuning.laserArgb whatever style.colorArgb says (glow + opaque core); a stored
// laser stroke (abnormal data) draws in the inkBase layer like the same stroke
// with the ballpoint; and in a page view the overlay asks for the next frame only
// while a trail is visible and the InkClock moves (a still FakeInkClock settles).
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show inkChunkCacheOf, inkPageRenderOf, laserTrailsOf, repaintInkLayer;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/page_view.dart';
import '../support/pixels.dart';

const _red = [0xFF, 0x3B, 0x30, 0xFF]; // InkTuning.laserArgb

Future<Pixels> _layer(InkPageController c, InkRenderLayer layer) =>
    renderPixels(400, 300, (canvas) {
      paintPaper(canvas, 0xFFFFFFFF);
      inkPageRenderOf(c).paint(canvas, layer, 1);
    });

Future<Map<InkRenderLayer, Pixels>> _layers(InkPageController c) async => {
  for (final layer in InkRenderLayer.values) layer: await _layer(c, layer),
};

int _inked(Pixels p) {
  var n = 0;
  for (var y = 0; y < p.height; y++) {
    for (var x = 0; x < p.width; x++) {
      if (!samePixel(p.at(x, y), const [255, 255, 255, 255], tol: 2)) n++;
    }
  }
  return n;
}

int _differing(Pixels a, Pixels b) {
  var n = 0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      if (!samePixel(a.at(x, y), b.at(x, y), tol: 2)) n++;
    }
  }
  return n;
}

List<InkSample> _line() =>
    SyntheticInk.line(const ui.Offset(40, 150), const ui.Offset(360, 150));

void main() {
  late FakeInkClock clock;
  late InkPageController c;
  late InkPageContent content;

  setUp(() {
    clock = FakeInkClock(startUs: 5000000);
    content = SyntheticInk.pageContent(
      strokes: [
        strokeThrough(
          segment(const ui.Offset(40, 60), const ui.Offset(360, 60)),
          core.StrokeStyle.defaultsFor(core.PenTool.ballpoint)
              .copyWith(width: 3, colorArgb: 0xFF2040A0),
          id: 'ink',
        ),
      ],
    );
    c = createTestPageController(clock: clock)..updateContent(content);
  });
  tearDown(() => c.dispose());

  StrokeSession laser({core.StrokeStyle? style}) {
    final samples = _line();
    final s = c.beginStroke(
      samples.first,
      style: style ?? core.StrokeStyle.defaultsFor(core.PenTool.laser),
      viewScale: 1,
    );
    for (final sample in samples.skip(1)) {
      clock.advanceMs(8);
      s.addSample(sample);
    }
    return s;
  }

  test('only the overlay has the trail; no inkBase chunk is recorded; end() '
      'is null, nothing pending, the content unchanged (K-9)', () async {
    final before = await _layers(c);
    final records = inkChunkCacheOf(c).recordCount;
    final s = laser();
    final writing = await _layers(c);
    expect(s.end(_line().last), isNull);
    expect(c.pendingIds, isEmpty);
    expect(identical(c.content, content), isTrue);
    final lifted = await _layers(c);
    clock.advanceMs(700);
    final fading = await _layers(c);
    for (final layer in InkRenderLayer.values) {
      if (layer == InkRenderLayer.overlay) continue;
      for (final now in [writing, lifted, fading]) {
        expect(_differing(before[layer]!, now[layer]!), 0, reason: '$layer');
      }
    }
    expect(_inked(before[InkRenderLayer.overlay]!), 0);
    expect(_inked(writing[InkRenderLayer.overlay]!), greaterThan(1000));
    expect(_inked(lifted[InkRenderLayer.overlay]!), greaterThan(1000));
    expect(inkChunkCacheOf(c).recordCount, records, reason: 'no re-record');
    // fading: lighter than at the lift, then gone
    final mid = fading[InkRenderLayer.overlay]!.at(200, 150);
    final full = lifted[InkRenderLayer.overlay]!.at(200, 150);
    expect(mid[1], greaterThan(full[1] + 40), reason: 'half faded: lighter');
    clock.advanceMs(800);
    expect(_inked(await _layer(c, InkRenderLayer.overlay)), 0);
    expect(laserTrailsOf(c).trails, isEmpty);
  });

  test('cancel(): the trail is gone at once', () async {
    final s = laser();
    expect(_inked(await _layer(c, InkRenderLayer.overlay)), greaterThan(1000));
    s.cancel();
    expect(_inked(await _layer(c, InkRenderLayer.overlay)), 0);
    expect(c.pendingIds, isEmpty);
  });

  test('the color is InkTuning.laserArgb whatever the style color '
      '(CP-INK-7): an opaque core, a translucent glow', () async {
    for (final color in [0xFF00AA00, 0x400000FF]) {
      final s = laser(
        style: core.StrokeStyle.defaultsFor(core.PenTool.laser)
            .copyWith(colorArgb: color, width: 4),
      );
      final px = await _layer(c, InkRenderLayer.overlay);
      expect(samePixel(px.at(200, 150), _red, tol: 2), isTrue, reason: 'core');
      // the glow: 2.5 × width wide at opacity 0.3 — red over white, lighter
      final glow = px.at(200, 154);
      expect(glow[0], greaterThan(250));
      expect(glow[1], inInclusiveRange(150, 235));
      expect(glow[1], closeTo(glow[2] + 10, 30), reason: 'a pale red');
      s.cancel();
    }
    expect(InkTuning.laserArgb, 0xFFFF3B30);
  });

  test('a stored laser stroke draws in inkBase like the ballpoint '
      '(the fallback, 6.6-5)', () async {
    final pts = segment(const ui.Offset(40, 220), const ui.Offset(360, 240));
    final style = core.StrokeStyle.defaultsFor(core.PenTool.laser)
        .copyWith(width: 3, colorArgb: 0xFF7A1FA0);
    final stored = strokeThrough(pts, style, id: 'stored-laser');
    final asBallpoint = strokeThrough(
      pts,
      core.StrokeStyle.defaultsFor(core.PenTool.ballpoint)
          .copyWith(width: 3, colorArgb: 0xFF7A1FA0),
      id: 'stored-laser',
    );
    c.updateContent(SyntheticInk.pageContent(strokes: [stored], revision: 2));
    final laserPx = await _layer(c, InkRenderLayer.inkBase);
    expect(_inked(laserPx), greaterThan(500));
    expect(_inked(await _layer(c, InkRenderLayer.overlay)), 0);
    c.updateContent(
      SyntheticInk.pageContent(strokes: [asBallpoint], revision: 3),
    );
    final ballPx = await _layer(c, InkRenderLayer.inkBase);
    expect(_differing(laserPx, ballPx), 0);
  });

  testWidgets('frames: the overlay repaints while a trail is visible and the '
      'InkClock moves; a still clock settles; nothing after the fade', (
    tester,
  ) async {
    await pumpPageView(tester, c, width: content.pageSize.width);
    expect(tester.binding.hasScheduledFrame, isFalse);
    final s = laser();
    // the first paint of the trail (the clock moved since the last one) asks for
    // the next frame
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue);
    // that frame sees the same clock: no further frame
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(s.end(), isNull);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpAndSettle(); // a still FakeInkClock settles
    expect(laserTrailsOf(c).trails, hasLength(1));
    // a moving clock: every frame asks for the next one (the overlay only)
    final records = inkChunkCacheOf(c).recordCount;
    repaintInkLayer(c, InkRenderLayer.overlay);
    for (var i = 0; i < 10; i++) {
      clock.advanceMs(16);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isTrue, reason: 'frame $i');
    }
    expect(inkChunkCacheOf(c).recordCount, records);
    // past laserFadeMs: the trail is removed and no frame is asked for
    clock.advanceMs(1500);
    await tester.pump();
    expect(laserTrailsOf(c).trails, isEmpty);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpAndSettle();
  });
}
