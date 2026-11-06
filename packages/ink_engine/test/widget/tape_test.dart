// m5-7/03-ink T31 (6.7): the memorization tape on the cover layer.
// - Covered: the writing under a tape is not visible (the tape color), also at
//   style opacity 0.3 (covering is always opaque); revealed: only the border
//   (1 logical px, opacity 0.6) — the writing shows; striped: 45° stripes in
//   the 15 % darker color, page-fixed spacing, only inside the tape.
// - L-1: a tape is above the text boxes (cover > annotation) — committed,
//   pending and while it is written.
// - hitTestTape: the band (distance to the centerline ≤ w / 2), not the CORE
//   bounds; the topmost tape.
// - A toggle re-records the cover picture only (the ink chunks stay).
// - The InkLayer.cover branch check of 6.7-5 (review S-3): one test per place
//   that used to treat 'not highlighter' as ink — sessions.dart (the live
//   layer), the controller's inkBase / inkActive, the cover live part (pending,
//   pending transform, selection preview), base_cache (the ink chunks),
//   vector_export (cover), thumbnail_renderer, layer_painters. The pen
//   preview's branch is in pen_preview_test.dart.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/geometry/outline_generator.dart';
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show inkChunkCacheOf, inkCoverCacheOf, inkPageRenderOf;
import 'package:ink_engine/src/render/layer_painters.dart';
import 'package:ink_engine/src/render/tape_painter.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/pixels.dart';

const _pageId = 'p1';
const _blue = 0xFF0000FF;
const _green = 0xFF00AA00;
const _tape = 0xFF7E57C2; // the default tape color (6.2)
const _white = 0xFFFFFFFF;

core.Stroke _stroke(
  String id,
  Offset a,
  Offset b,
  int createdAt, {
  core.PenTool tool = core.PenTool.ballpoint,
  int color = _blue,
  double width = 4,
  double opacity = 1,
  InkTapeStyle? tapeStyle,
}) {
  var style = core.StrokeStyle.defaultsFor(tool)
      .copyWith(colorArgb: color, width: width, opacity: opacity);
  if (tapeStyle != null) style = style.withInkExtras(tapeStyle: tapeStyle);
  return strokeThrough(
    segment(a, b),
    style,
    id: id,
  ).copyWith(createdAt: createdAt);
}

core.Stroke _tapeStroke(
  String id,
  Offset a,
  Offset b,
  int createdAt, {
  double width = 14,
  double opacity = 1,
  InkTapeStyle? tapeStyle,
}) => _stroke(
  id,
  a,
  b,
  createdAt,
  tool: core.PenTool.tape,
  color: _tape,
  width: width,
  opacity: opacity,
  tapeStyle: tapeStyle,
);

core.TextBoxObject _box(String id, core.PageRect r, int createdAt) =>
    core.TextBoxObject(
      id: id,
      pageId: _pageId,
      frame: core.ElementFrame(r),
      text: '',
      style: const core.TextBoxStyle(backgroundArgb: _green),
      createdAt: createdAt,
    );

InkPageContent _content(
  List<core.Stroke> strokes, {
  List<core.PageObject> objects = const [],
  int revision = 1,
}) => InkPageContent.fromCore(
  page: SyntheticInk.page(pageId: _pageId),
  strokes: strokes,
  objects: objects,
  revision: revision,
);

/// Paints [layers] (all by default) of [c] over white paper at 1 px per pt.
Future<Pixels> _pixelsOf(
  InkPageController c, {
  Iterable<InkRenderLayer> layers = InkRenderLayer.values,
  int w = 300,
  int h = 300,
}) => renderPixels(w, h, (canvas) {
  paintPaper(canvas, _white);
  final render = inkPageRenderOf(c);
  for (final layer in layers) {
    render.paint(canvas, layer, 1);
  }
});

bool _near(List<int> px, int argb, {int tol = 3}) => samePixel(px, [
  (argb >> 16) & 0xFF,
  (argb >> 8) & 0xFF,
  argb & 0xFF,
  255,
], tol: tol);

InkSample _sample(Offset p, int i) => InkSample(
  position: p,
  timeUs: i * 8333,
  kind: InkPointerKind.stylus,
  pressure: 0.5,
);

void main() {
  group('covered, revealed, striped (6.7-3, 6.7-4)', () {
    test('covered: the writing under a tape is the tape color — also at style '
        'opacity 0.3, and when the tape is older than the writing', () async {
      final c = createTestPageController()
        ..updateContent(
          _content([
            _tapeStroke('t', const Offset(150, 60), const Offset(150, 140), 1),
            _tapeStroke(
              'faint',
              const Offset(220, 60),
              const Offset(220, 140),
              2,
              opacity: 0.3,
            ),
            _stroke('ink', const Offset(20, 100), const Offset(280, 100), 3),
          ]),
        );
      addTearDown(c.dispose);
      final px = await _pixelsOf(c);
      expect(_near(px.at(100, 100), _blue), isTrue, reason: 'writing');
      for (final x in [146, 150, 154]) {
        expect(_near(px.at(x, 100), _tape), isTrue, reason: 'tape over ink $x');
        expect(_near(px.at(x + 70, 100), _tape), isTrue, reason: 'opacity 0.3');
        expect(_near(px.at(x, 80), _tape), isTrue, reason: 'tape on paper');
      }
    });

    test('revealed: only the 1 px border at opacity 0.6 — the writing and the '
        'paper show inside', () async {
      final c = createTestPageController()
        ..updateContent(
          _content([
            _stroke('ink', const Offset(20, 100), const Offset(280, 100), 1),
            _tapeStroke('t', const Offset(150, 60), const Offset(150, 140), 2),
          ]),
        );
      addTearDown(c.dispose);
      c.toggleTape('t');
      final px = await _pixelsOf(c);
      expect(_near(px.at(150, 100), _blue), isTrue, reason: 'writing shows');
      expect(_near(px.at(150, 80), _white), isTrue, reason: 'paper shows');
      // the border column near x = 143 (the left side of the 14 pt band)
      var border = 0;
      for (var x = 140; x <= 146; x++) {
        final p = px.at(x, 80);
        if (!_near(p, _white, tol: 8)) {
          border++;
          // a 0.6 tint of the tape color over white, never the full color
          expect(_near(p, _tape, tol: 20), isFalse, reason: 'x $x');
        }
      }
      expect(border, inInclusiveRange(1, 3), reason: 'a thin border');
      c.toggleTape('t');
      expect(_near((await _pixelsOf(c)).at(150, 100), _tape), isTrue);
    });

    test('striped: 45° stripes of the 15 % darker color every 6 pt '
        '(page-fixed), only inside the tape', () async {
      final c = createTestPageController()
        ..updateContent(
          _content([
            _tapeStroke(
              's',
              const Offset(20, 200),
              const Offset(280, 200),
              1,
              width: 20,
              tapeStyle: InkTapeStyle.striped,
            ),
          ]),
        );
      addTearDown(c.dispose);
      final px = await _pixelsOf(c);
      final stripe = tapeStripeColor(_tape).toARGB32();
      expect(stripe, isNot(_tape));
      expect((stripe >> 16) & 0xFF, (((_tape >> 16) & 0xFF) * 0.85).round());
      expect((stripe >> 8) & 0xFF, (((_tape >> 8) & 0xFF) * 0.85).round());
      expect(stripe & 0xFF, ((_tape & 0xFF) * 0.85).round());
      // centers of the stripe runs along the row y = 200
      final centers = <double>[];
      int? runStart;
      for (var x = 40; x < 260; x++) {
        final dark =
            _near(px.at(x, 200), stripe, tol: 30) &&
            !_near(px.at(x, 200), _tape, tol: 10);
        if (dark && runStart == null) runStart = x;
        if (!dark && runStart != null) {
          centers.add((runStart + x - 1) / 2);
          runStart = null;
        }
      }
      expect(centers.length, greaterThan(20));
      // 6 pt between 45° lines → 6 · √2 along a row
      for (var k = 1; k < centers.length; k++) {
        expect(
          centers[k] - centers[k - 1],
          closeTo(6 * math.sqrt2, 1.5),
          reason: 'stripe $k',
        );
      }
      // the stripes are on the page grid x + y = k · 6√2
      final phase = (centers.first + 200) / (6 * math.sqrt2);
      expect((phase - phase.round()).abs(), lessThan(0.15));
      // nothing outside the tape band (20 pt wide → 190 .. 210)
      for (var x = 40; x < 260; x += 3) {
        expect(_near(px.at(x, 186), _white), isTrue, reason: 'above $x');
        expect(_near(px.at(x, 214), _white), isTrue, reason: 'below $x');
      }
    });
  });

  group('L-1: the tape is above the text boxes (cover > annotation)', () {
    test('committed, while written, and pending', () async {
      final box = _box('box', core.PageRect.fromLTWH(60, 30, 120, 40), 1);
      final c = createTestPageController()
        ..updateContent(_content(const [], objects: [box]));
      addTearDown(c.dispose);
      var px = await _pixelsOf(c);
      expect(_near(px.at(120, 50), _green), isTrue, reason: 'the box');
      // while written
      final style = core.StrokeStyle.defaultsFor(core.PenTool.tape);
      final session = c.beginStroke(
        _sample(const Offset(40, 50), 0),
        style: style,
        viewScale: 1,
      );
      for (var i = 1; i <= 60; i++) {
        session.addSample(_sample(Offset(40 + 3.0 * i, 50), i));
      }
      px = await _pixelsOf(c);
      expect(_near(px.at(120, 50), _tape), isTrue, reason: 'live tape on top');
      // pending (not in the content yet)
      final edit = session.end()!;
      expect(edit.added.single.style.tool, core.PenTool.tape);
      px = await _pixelsOf(c);
      expect(_near(px.at(120, 50), _tape), isTrue, reason: 'pending on top');
      // committed
      c.updateContent(_content(edit.added, objects: [box], revision: 2));
      px = await _pixelsOf(c);
      expect(_near(px.at(120, 50), _tape), isTrue, reason: 'committed on top');
      expect(_near(px.at(120, 66), _green), isTrue, reason: 'box below it');
    });
  });

  group('hitTestTape (6.7-7)', () {
    test('inside the band → the tape; outside the band but inside the CORE '
        'bounds → null; ink strokes never', () {
      final t = _tapeStroke(
        't',
        const Offset(20, 40),
        const Offset(180, 40),
        1,
      );
      final c = createTestPageController()
        ..updateContent(
          _content([
            t,
            _stroke('ink', const Offset(20, 80), const Offset(180, 80), 2),
          ]),
        );
      addTearDown(c.dispose);
      expect(c.hitTestTape(const Offset(100, 40))?.id, 't');
      expect(c.hitTestTape(const Offset(100, 46.5))?.id, 't');
      // 9 pt from the centerline: outside the 7 pt band, inside the bounds
      // (inflated by 0.75 · w = 10.5)
      expect(InkStroke.of(t).bounds.contains(const Offset(100, 49)), isTrue);
      expect(c.hitTestTape(const Offset(100, 49)), isNull);
      expect(c.hitTestTape(const Offset(100, 80)), isNull, reason: 'ink');
      expect(c.hitTestTape(const Offset(250, 40)), isNull);
    });

    test('two crossing tapes → the topmost', () {
      final c = createTestPageController()
        ..updateContent(
          _content([
            _tapeStroke('low', const Offset(20, 40), const Offset(180, 40), 1),
            _tapeStroke('top', const Offset(100, 0), const Offset(100, 80), 2),
          ]),
        );
      addTearDown(c.dispose);
      expect(c.hitTestTape(const Offset(100, 40))?.id, 'top');
      expect(c.hitTestTape(const Offset(60, 40))?.id, 'low');
    });
  });

  test(
    'a toggle re-records the cover picture only: the ink chunks stay',
    () async {
      final c = createTestPageController()
        ..updateContent(
          _content([
            _stroke('ink', const Offset(20, 100), const Offset(280, 100), 1),
            _tapeStroke('t', const Offset(150, 60), const Offset(150, 140), 2),
          ]),
        );
      addTearDown(c.dispose);
      await _pixelsOf(c);
      final chunks = inkChunkCacheOf(c);
      final cover = inkCoverCacheOf(c);
      final chunkRecords = chunks.recordCount;
      final coverRecords = cover.recordCount;
      var inkBase = 0, coverRepaints = 0;
      c.layerRepaint(InkRenderLayer.inkBase).addListener(() => inkBase++);
      c.layerRepaint(InkRenderLayer.cover).addListener(() => coverRepaints++);
      c.toggleTape('t');
      await _pixelsOf(c);
      c.setAllTapesRevealed(false);
      await _pixelsOf(c);
      expect(chunks.recordCount, chunkRecords);
      expect(cover.recordCount, coverRecords + 2);
      expect(inkBase, 0);
      expect(coverRepaints, 2);
    },
  );

  group('InkLayer.cover branches (6.7-5, review S-3)', () {
    test('sessions.dart: the tape being written repaints cover, never '
        'inkActive', () {
      final c = createTestPageController()..updateContent(_content(const []));
      addTearDown(c.dispose);
      final counts = {for (final l in InkRenderLayer.values) l: 0};
      for (final l in InkRenderLayer.values) {
        c.layerRepaint(l).addListener(() => counts[l] = counts[l]! + 1);
      }
      final session = c.beginStroke(
        _sample(const Offset(40, 50), 0),
        style: core.StrokeStyle.defaultsFor(core.PenTool.tape),
        viewScale: 1,
      );
      counts.updateAll((_, _) => 0);
      for (var i = 1; i <= 20; i++) {
        session.addSample(_sample(Offset(40 + 3.0 * i, 50), i));
      }
      expect(counts[InkRenderLayer.cover], 20);
      expect(counts[InkRenderLayer.inkActive], 0);
      expect(counts[InkRenderLayer.highlighterActive], 0);
      session.cancel();
    });

    test('ink_page_controller: inkBase and inkActive never draw a tape '
        '(committed, pending or written); cover draws all three', () async {
      final c = createTestPageController()
        ..updateContent(
          _content([
            _tapeStroke('t', const Offset(40, 40), const Offset(260, 40), 1),
          ]),
        );
      addTearDown(c.dispose);
      final s1 = c.beginStroke(
        _sample(const Offset(40, 120), 0),
        style: core.StrokeStyle.defaultsFor(core.PenTool.tape),
        viewScale: 1,
      );
      for (var i = 1; i <= 40; i++) {
        s1.addSample(_sample(Offset(40 + 5.0 * i, 120), i));
      }
      s1.end(); // pending at y = 120
      final s2 = c.beginStroke(
        _sample(const Offset(40, 200), 0),
        style: core.StrokeStyle.defaultsFor(core.PenTool.tape),
        viewScale: 1,
      );
      for (var i = 1; i <= 40; i++) {
        s2.addSample(_sample(Offset(40 + 5.0 * i, 200), i));
      }
      final ink = await _pixelsOf(
        c,
        layers: const [
          InkRenderLayer.highlighterBase,
          InkRenderLayer.highlighterActive,
          InkRenderLayer.inkBase,
          InkRenderLayer.inkActive,
        ],
      );
      final cover = await _pixelsOf(c, layers: const [InkRenderLayer.cover]);
      for (final y in [40, 120, 200]) {
        expect(_near(ink.at(150, y), _white), isTrue, reason: 'ink $y');
        expect(_near(cover.at(150, y), _tape), isTrue, reason: 'cover $y');
      }
      s2.cancel();
    });

    test('base_cache: the ink chunks never hold a tape', () async {
      final c = createTestPageController()
        ..updateContent(
          _content([
            _stroke('ink', const Offset(20, 100), const Offset(280, 100), 1),
            _tapeStroke('t1', const Offset(150, 60), const Offset(150, 140), 2),
            _tapeStroke('t2', const Offset(50, 20), const Offset(50, 140), 3),
          ]),
        );
      addTearDown(c.dispose);
      await _pixelsOf(c);
      expect(inkChunkCacheOf(c).strokeCountOf(0), 1);
      expect(inkCoverCacheOf(c).strokeCount, 2);
    });

    test('cover live part: a pending transform and the selection preview move '
        'the tape (covered); the old place is paper', () async {
      final t = _tapeStroke(
        't',
        const Offset(60, 60),
        const Offset(160, 60),
        1,
      );
      final c = createTestPageController()..updateContent(_content([t]));
      addTearDown(c.dispose);
      final selection = c.select({'t'});
      selection.setPreviewTransform(core.Affine2.translation(0, 80));
      var px = await _pixelsOf(c, layers: const [InkRenderLayer.cover]);
      expect(_near(px.at(110, 140), _tape), isTrue, reason: 'preview');
      expect(_near(px.at(110, 60), _white), isTrue, reason: 'old place');
      final edit = selection.commitTransform()!;
      expect(edit.kind, InkEditKind.transformStrokes);
      px = await _pixelsOf(c, layers: const [InkRenderLayer.cover]);
      expect(_near(px.at(110, 140), _tape), isTrue, reason: 'pending');
      expect(_near(px.at(110, 60), _white), isTrue, reason: 'pending old');
      // a recolor preview of a pending recolor keeps the tape opaque
      c.discardEdit(edit);
      final recolor = c.select({'t'}).recolor(0xFF00AA00);
      px = await _pixelsOf(c, layers: const [InkRenderLayer.cover]);
      expect(_near(px.at(110, 60), _green), isTrue, reason: 'recolored');
      c.discardEdit(recolor);
    });

    test('vector_export: tapes go to cover — opaque, whatever the reveal '
        'state; never inkShapes', () {
      final content = _content([
        _stroke('ink', const Offset(20, 100), const Offset(280, 100), 1),
        _tapeStroke(
          't',
          const Offset(150, 60),
          const Offset(150, 140),
          2,
          opacity: 0.3,
          tapeStyle: InkTapeStyle.striped,
        ),
      ]);
      final c = createTestPageController()..updateContent(content);
      addTearDown(c.dispose);
      c.toggleTape('t');
      final v = InkVectorExport.exportPage(content);
      expect(v.inkShapes.map((s) => s.strokeId), ['ink']);
      expect(v.cover, hasLength(1));
      final tape = v.cover.single;
      expect(tape.strokeId, 't');
      expect(tape.tool, core.PenTool.tape);
      expect(tape.opacity, 1);
      expect(tape.colorArgb, _tape);
      expect(
        tape.path.bounds,
        OutlineGenerator.outline(content.strokeById('t')!)
            .toVectorPath()
            .bounds,
      );
    });

    testWidgets('thumbnail_renderer: the thumbnail has the tape, covered', (
      tester,
    ) async {
      final page = SyntheticInk.page(pageId: _pageId);
      final thumb = await tester.runAsync(
        () =>
            InkPageThumbnailRenderer(
              backgroundBuilders: const [TemplateBackgroundLayerBuilder()],
            ).render(
              core.PageContent(
                page: page,
                strokes: [
                  _stroke(
                    'ink',
                    const Offset(20, 100),
                    const Offset(280, 100),
                    2,
                  ),
                  _tapeStroke(
                    't',
                    const Offset(150, 60),
                    const Offset(150, 140),
                    1,
                    width: 30,
                  ),
                ],
                revision: 1,
              ),
              maxSidePx: 842,
            ),
      );
      expect(thumb, isNotNull);
      final px = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(thumb!.bytes);
        final frame = await codec.getNextFrame();
        final data = await frame.image.toByteData();
        final out = Pixels(frame.image.width, frame.image.height, data!);
        frame.image.dispose();
        codec.dispose();
        return out;
      });
      final k = thumb!.width / page.size.width;
      int at(double v) => (v * k).round();
      expect(_near(px!.at(at(150), at(100)), _tape, tol: 6), isTrue);
      expect(_near(px.at(at(60), at(100)), _blue, tol: 40), isTrue);
    });

    test('layer_painters: paintStrokeLayers draws the tapes last, covered '
        '(a newer ink stroke stays under the tape)', () async {
      final strokes = [
        InkStroke.of(
          _tapeStroke('t', const Offset(150, 60), const Offset(150, 140), 1),
        ),
        InkStroke.of(
          _stroke('ink', const Offset(20, 100), const Offset(280, 100), 2),
        ),
      ];
      final px = await renderPixels(300, 200, (canvas) {
        paintPaper(canvas, _white);
        paintStrokeLayers(
          canvas,
          strokes,
          paperColorArgb: _white,
          outlineOf: OutlineGenerator.outline,
        );
      });
      expect(_near(px.at(150, 100), _tape), isTrue);
      expect(_near(px.at(100, 100), _blue), isTrue);
    });
  });
}
