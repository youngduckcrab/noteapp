// m5-7/03-ink 8.2 T36 (6.12.2–6.12.4, 6.24): the formula raster and how the
// annotation layer draws it (VM, KaTeX fonts loaded).
// - rasterize: the 300 dpi size = ⌈layout · 300/72⌉ with ink; the SVG glyph
//   samples (root sign, vector arrow, stretchy arrow, brace) have their ink;
//   invalid LaTeX → null; a big formula at 300 dpi stays ≤ 4 Mpx and ≤ 8192 px.
// - On a page: before the raster the light placeholder; when it arrives only the
//   annotation chunks that drew that formula are recorded again (other chunks
//   and layers keep their pictures) and the chunk pins the raster until its
//   picture goes; contain fit (centred, nothing outside the frame — also
//   rotated); a color change is a new raster; another bucket after setViewport
//   (not while scaling); a working set over a small budget: lowered buckets,
//   re-records ≤ formulas × 2, every formula drawn at last, another page's
//   chunks untouched; an invalid stored formula → the 6.13 placeholder and
//   mathInvalid once; a failed raster → mathRasterFailed, the placeholder
//   stays and the same raster is not asked again within mathRasterRetryMs.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/math/math_raster_cache.dart';
import 'package:ink_engine/src/math/offscreen_host.dart';
import 'package:ink_engine/src/render/base_cache.dart';
import 'package:ink_engine/src/render/cache_pool.dart' show mathRasterCacheOf;
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show inkAnnotationCacheOf, inkChunkCacheOf, inkPageRenderOf;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/delayed_svg_loader.dart';
import '../support/math_raster_cases.dart';
import '../support/pixels.dart';

const _pageId = 'p1';
const _black = 0xFF000000;

core.MathObject _math(
  String id,
  core.PagePoint at, {
  String latex = r'\frac{a}{b}+\sqrt{x}',
  int color = _black,
  double fontSizePt = 24,
  double widthScale = 1,
  double heightScale = 1,
  double rotation = 0,
  String pageId = _pageId,
}) {
  final l = InkMathRenderer.layout(latex, fontSizePt: fontSizePt);
  final w = (l?.sizePt.width ?? 40) * widthScale;
  final h = (l?.sizePt.height ?? 20) * heightScale;
  return core.MathObject(
    id: id,
    pageId: pageId,
    frame: core.ElementFrame(
      core.PageRect(at.x, at.y, at.x + w, at.y + h),
      rotation: rotation,
    ),
    latex: latex,
    style: core.MathStyle(colorArgb: color, fontSizePt: fontSizePt),
    createdAt: 1,
  );
}

InkPageContent _content(
  List<core.PageObject> objects, {
  List<core.Stroke> strokes = const [],
  int revision = 1,
  String pageId = _pageId,
}) => InkPageContent.fromCore(
  page: SyntheticInk.page(pageId: pageId),
  strokes: strokes,
  objects: objects,
  revision: revision,
);

void _paintAll(InkPageController c) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final render = inkPageRenderOf(c);
  for (final layer in InkRenderLayer.values) {
    render.paint(canvas, layer, 1);
  }
  recorder.endRecording().dispose();
}

/// Lets the queued rasters arrive (no paint in between).
Future<void> _arrive(InkPageController c) async {
  final cache = mathRasterCacheOf(c.cachePool);
  for (var i = 0; i < 2000 && cache.stats.queued > 0; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(cache.stats.queued, 0, reason: 'the rasters arrived');
  await pumpEventQueue();
}

/// Paints and lets the queued rasters arrive until nothing is queued and no annotation
/// chunk waits to be recorded.
Future<void> _settle(InkPageController c) async {
  final cache = mathRasterCacheOf(c.cachePool);
  final annotation = inkAnnotationCacheOf(c);
  for (var i = 0; i < 100; i++) {
    _paintAll(c);
    await _arrive(c);
    if (annotation.dirtyCount == 0 && cache.stats.queued == 0) return;
  }
  fail('the formula rasters did not settle');
}

/// The page at 1 px per pt over white paper (the top left [w] × [h] pt).
Future<Pixels> _pixels(InkPageController c, {int w = 600, int h = 850}) =>
    renderPixels(w, h, (canvas) {
      paintPaper(canvas, 0xFFFFFFFF);
      final render = inkPageRenderOf(c);
      for (final layer in InkRenderLayer.values) {
        render.paint(canvas, layer, 1);
      }
    });

/// Pixels in [r] darker than [below] on every channel (formula ink, not the placeholder).
int _dark(Pixels p, core.PageRect r, {int below = 128}) {
  var n = 0;
  for (var y = r.top.floor(); y < r.bottom.ceil(); y++) {
    for (var x = r.left.floor(); x < r.right.ceil(); x++) {
      final c = p.at(x, y);
      if (c[0] < below && c[1] < below && c[2] < below) n++;
    }
  }
  return n;
}

bool _isPaper(List<int> c) => c[0] > 245 && c[1] > 245 && c[2] > 245;

/// The bounding box of the pixels of [p] that are not paper (null = none).
ui.Rect? _inkBox(Pixels p) {
  int? x0, y0, x1, y1;
  for (var y = 0; y < p.height; y++) {
    for (var x = 0; x < p.width; x++) {
      if (_isPaper(p.at(x, y))) continue;
      x0 = x0 == null ? x : math.min(x0, x);
      x1 = x1 == null ? x : math.max(x1, x);
      y0 = y0 == null ? y : math.min(y0, y);
      y1 = y1 == null ? y : math.max(y1, y);
    }
  }
  if (x0 == null) return null;
  return ui.Rect.fromLTRB(x0.toDouble(), y0!.toDouble(), x1! + 1.0, y1! + 1.0);
}

/// The ink pixels of [p] outside the frame of [o] (rotated), 1.5 px for the edge.
int _outside(Pixels p, core.PageObject o) {
  final r = o.frame.rect;
  final cx = o.frame.center.x, cy = o.frame.center.y;
  final rot = o.frame.rotation;
  final cosA = math.cos(-rot), sinA = math.sin(-rot);
  var n = 0;
  for (var y = 0; y < p.height; y++) {
    for (var x = 0; x < p.width; x++) {
      if (_isPaper(p.at(x, y))) continue;
      final dx = x + 0.5 - cx, dy = y + 0.5 - cy;
      final lx = dx * cosA - dy * sinA, ly = dx * sinA + dy * cosA;
      if (lx.abs() > r.width / 2 + 1.5 || ly.abs() > r.height / 2 + 1.5) n++;
    }
  }
  return n;
}

List<int> _generations(InkChunkCache cache) => [
  for (var i = 0; i < cache.chunkCount; i++) cache.generationOf(i),
];

List<int> _changed(List<int> before, List<int> after) => [
  for (var i = 0; i < after.length; i++)
    if (after[i] != before[i]) i,
];

/// The chunk index of page point ([x], [y]) at 256 pt chunks (3 columns on A4).
int _chunkAt(double x, double y) => (y ~/ 256) * 3 + (x ~/ 256);

InkPageController _controllerOn(
  InkCachePool pool,
  InkRenderConfig config, {
  String pageId = _pageId,
}) {
  final clock = FakeInkClock();
  return InkPageController(
    pageId: pageId,
    services: testInkCoreServices(),
    config: config,
    cachePool: pool,
    pressureStore: MemoryPressureStore(),
    pressureMode: () => PressureMode.auto,
    diagnostics: InkDiagnostics(clock: clock),
    clock: clock,
    pencilGrain: PencilGrain(),
    backgroundBuilders: const [TemplateBackgroundLayerBuilder()],
  );
}

final Stopwatch _wall = Stopwatch()..start();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadKatexFontsForTest();
    await InkFonts.ensureLoaded();
  });

  group('rasterize', () {
    test('300 dpi: ⌈layout · 300/72⌉ px with ink', () async {
      const latex = r'\sum_{k=1}^{n} k^2';
      final l = InkMathRenderer.layout(latex, fontSizePt: 18)!;
      const k = 300 / 72;
      final image = await InkMathRenderer.rasterize(
        latex,
        colorArgb: _black,
        fontSizePt: 18,
        pixelsPerPt: k,
      );
      expect(image, isNotNull);
      expect(image!.width, (l.sizePt.width * k).ceil());
      expect(image.height, (l.sizePt.height * k).ceil());
      final p = await imagePixels(image);
      image.dispose();
      expect(inkIn(p), greaterThan(1000));
    });

    test('invalid LaTeX → null', () async {
      for (final latex in [r'\frac{a', r'\foo', r'\tag{1}']) {
        expect(
          await InkMathRenderer.rasterize(
            latex,
            colorArgb: _black,
            fontSizePt: 18,
            pixelsPerPt: 4,
          ),
          isNull,
          reason: latex,
        );
      }
    });

    test(
      'a big formula at 300 dpi: ≤ 4 Mpx and the long side ≤ 8192 px',
      () async {
        final latex = '${List.filled(40, 'x^{2}+').join()}y';
        final l = InkMathRenderer.layout(latex, fontSizePt: 96)!;
        expect(l.sizePt.width * 300 / 72, greaterThan(8192), reason: 'capped');
        final image = await InkMathRenderer.rasterize(
          latex,
          colorArgb: _black,
          fontSizePt: 96,
          pixelsPerPt: 300 / 72,
        );
        expect(image, isNotNull);
        expect(
          image!.width * image.height,
          lessThanOrEqualTo(InkTuning.maxRasterPixels),
        );
        expect(
          math.max(image.width, image.height),
          lessThanOrEqualTo(InkTuning.maxRasterSidePx),
        );
        image.dispose();
      },
    );

    group('SVG glyph samples', svgGlyphCases);
  });

  group('on a page', () {
    tearDown(() {
      OffscreenMathHost.debugExtraSvgLoader = null;
      OffscreenMathHost.debugNowUs = () => _wall.elapsedMicroseconds;
    });

    test('the placeholder first; the arrival records again only the annotation '
        'chunks that drew the formula; the chunk pins its raster', () async {
      final m1 = _math('m1', const core.PagePoint(30, 30));
      final m2 = _math('m2', const core.PagePoint(530, 300), latex: r'\vec{v}');
      final text = core.TextBoxObject(
        id: 't1',
        pageId: _pageId,
        frame: const core.ElementFrame(core.PageRect(300, 780, 400, 820)),
        text: 'Note',
        style: const core.TextBoxStyle(fontSizePt: 18),
        createdAt: 2,
      );
      final stroke = strokeThrough(
        segment(const ui.Offset(300, 300), const ui.Offset(400, 320)),
        core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
        id: 's1',
      );
      final c = createTestPageController()
        ..updateContent(_content([m1, m2, text], strokes: [stroke]));
      final cache = mathRasterCacheOf(c.cachePool);
      final annotation = inkAnnotationCacheOf(c);
      final ink = inkChunkCacheOf(c);
      var repaints = 0;
      c.layerRepaint(InkRenderLayer.annotation).addListener(() => repaints++);

      _paintAll(c);
      expect(cache.stats.queued, 2);
      final annotationGen = _generations(annotation);
      final inkGen = _generations(ink);
      // (painted before the rasters can arrive — they need timer turns)
      final before = await _pixels(c);
      expect(_dark(before, m1.frame.rect), 0, reason: 'placeholder only');
      expect(_dark(before, m2.frame.rect), 0);
      final center = before.at(
        m1.frame.center.x.round(),
        m1.frame.center.y.round(),
      );
      expect(center[0], lessThan(255), reason: 'the light box');

      await _arrive(c);
      expect(repaints, greaterThan(0));
      expect(_changed(annotationGen, _generations(annotation)), [
        _chunkAt(30, 30),
        _chunkAt(530, 300),
      ]);
      expect(_generations(ink), inkGen);

      final drawn = await _pixels(c);
      expect(_dark(drawn, m1.frame.rect), greaterThan(50));
      expect(_dark(drawn, m2.frame.rect), greaterThan(5));
      expect(annotation.heldPinCount, 2, reason: 'one pin per formula chunk');
      expect(cache.stats.pinnedBytes, cache.stats.bytes);
      // the same objects in a new revision record nothing
      final records = annotation.recordCount;
      c.updateContent(_content([m1, m2, text], strokes: [stroke], revision: 2));
      await _settle(c);
      expect(annotation.recordCount, records);
      c.dispose();
      expect(cache.stats.pinnedBytes, 0, reason: 'the pictures went');
    });

    test(
      'contain fit (K-6): centred in a wider / taller / smaller frame, nothing '
      'outside it — also rotated 30°',
      () async {
        final base = _math('m', const core.PagePoint(0, 0));
        final lw = base.frame.rect.width, lh = base.frame.rect.height;
        for (final (ws, hs, rot) in [
          (3.0, 1.0, 0.0),
          (1.0, 2.0, 0.0),
          (0.5, 0.5, 0.0),
          (1.0, 1.0, math.pi / 6),
        ]) {
          final m = _math(
            'm',
            const core.PagePoint(100, 100),
            widthScale: ws,
            heightScale: hs,
            rotation: rot,
          );
          final c = createTestPageController()..updateContent(_content([m]));
          await _settle(c);
          final p = await _pixels(c, w: 400, h: 400);
          final box = _inkBox(p);
          expect(box, isNotNull, reason: '$ws × $hs');
          if (rot == 0) {
            final s = math.min(ws, hs);
            final c0 = m.frame.center;
            expect(box!.center.dx, closeTo(c0.x, 2), reason: '$ws × $hs');
            expect(box.center.dy, closeTo(c0.y, 2), reason: '$ws × $hs');
            expect(box.width, lessThanOrEqualTo(lw * s + 2));
            expect(box.height, lessThanOrEqualTo(lh * s + 2));
          }
          expect(_outside(p, m), 0, reason: '$ws × $hs, rotation $rot');
          c.dispose();
        }
      },
    );

    test('a color change is a new raster', () async {
      final m = _math('m', const core.PagePoint(40, 40));
      final c = createTestPageController()..updateContent(_content([m]));
      final cache = mathRasterCacheOf(c.cachePool);
      await _settle(c);
      final rasterized = cache.stats.rasterized;
      final red = m.copyWith(
        style: m.style.copyWith(colorArgb: 0xFFDD0000),
        updatedAt: 2,
      );
      c.updateContent(_content([red], revision: 2));
      await _settle(c);
      expect(cache.stats.rasterized, rasterized + 1);
      final p = await _pixels(c, w: 200, h: 200);
      var reds = 0;
      final r = m.frame.rect;
      for (var y = r.top.floor(); y < r.bottom; y++) {
        for (var x = r.left.floor(); x < r.right; x++) {
          final px = p.at(x, y);
          if (px[0] > 150 && px[1] < 90 && px[2] < 90) reds++;
        }
      }
      expect(reds, greaterThan(30));
      expect(_dark(p, r), 0, reason: 'no black left');
      c.dispose();
    });

    test(
      'another bucket after setViewport (not while scaling): only the formula '
      'chunks are recorded again, at the new bucket',
      () async {
        final m = _math('m', const core.PagePoint(40, 40));
        final other = _math('o', const core.PagePoint(530, 780), latex: 'y');
        final c = createTestPageController()
          ..updateContent(_content([m, other]));
        final cache = mathRasterCacheOf(c.cachePool);
        final annotation = inkAnnotationCacheOf(c);
        await _settle(c);
        final f = mathFormulaOf(m);
        expect(cache.isPinned((formula: f, bucket: 2)), isTrue);
        c.setViewport(deviceScale: 3.5, isScaling: true);
        expect(cache.stats.queued, 0, reason: 'not while scaling');
        final gen = _generations(annotation);
        c.setViewport(deviceScale: 3.5, isScaling: false);
        expect(cache.stats.queued, 2);
        await _arrive(c);
        expect(_changed(gen, _generations(annotation)), [
          _chunkAt(40, 40),
          _chunkAt(530, 780),
        ]);
        _paintAll(c);
        expect(cache.isPinned((formula: f, bucket: 4)), isTrue);
        expect(cache.isPinned((formula: f, bucket: 2)), isFalse);
        c.dispose();
      },
    );

    test(
      'a working set over the budget: lowered buckets, re-records ≤ formulas '
      '× 2, every formula drawn at last, another page untouched',
      () async {
        const config = InkRenderConfig(
          rasterTiles: false,
          mathRasterCacheBytes: 96 * 1024,
        );
        final pool = InkCachePool(config);
        final formulas = [
          for (var i = 0; i < 20; i++)
            _math(
              'm$i',
              core.PagePoint(20 + (i % 4) * 140.0, 20 + (i ~/ 4) * 150.0),
              latex: '\\frac{a_{$i}}{b+c}',
              fontSizePt: 36,
            ),
        ];
        final c = _controllerOn(pool, config)
          ..updateContent(_content(formulas));
        final other = _controllerOn(pool, config, pageId: 'p2')
          ..updateContent(
            _content([
              _math('x', const core.PagePoint(40, 40), pageId: 'p2'),
            ], pageId: 'p2'),
          );
        await _settle(other);
        final cache = mathRasterCacheOf(pool);
        final annotation = inkAnnotationCacheOf(c);
        final otherRecords = inkAnnotationCacheOf(other).recordCount;
        _paintAll(c);
        final firstRecords = annotation.recordCount;
        final rasterizedBefore = cache.stats.rasterized;
        await _settle(c);
        expect(
          annotation.recordCount - firstRecords,
          lessThanOrEqualTo(20 * 2),
        );
        expect(
          cache.stats.rasterized - rasterizedBefore,
          lessThanOrEqualTo(20 * 2),
        );
        expect(cache.stats.downgraded, greaterThan(0));
        expect(inkAnnotationCacheOf(other).recordCount, otherRecords);
        final p = await _pixels(c);
        for (final m in formulas) {
          expect(
            _dark(p, m.frame.rect, below: 170),
            greaterThan(0),
            reason: m.id,
          );
        }
        expect(annotation.heldPinCount, greaterThanOrEqualTo(20));
        c.dispose();
        other.dispose();
        pool.dispose();
      },
    );

    test(
      'an invalid stored formula: the 6.13 placeholder, mathInvalid once, no '
      'raster asked',
      () async {
        final bad = core.MathObject(
          id: 'bad',
          pageId: _pageId,
          frame: const core.ElementFrame(core.PageRect(50, 50, 150, 100)),
          latex: r'\frac{a',
          style: const core.MathStyle(),
          createdAt: 1,
        );
        final c = createTestPageController()..updateContent(_content([bad]));
        c.diagnostics.enabled = true;
        final cache = mathRasterCacheOf(c.cachePool);
        _paintAll(c);
        _paintAll(c);
        expect(c.diagnostics.snapshot.warnings, 1, reason: 'mathInvalid');
        expect(cache.stats.queued, 0);
        final p = await _pixels(c, w: 200, h: 200);
        expect(_inkBox(p), isNotNull, reason: 'the hatched box');
        expect(_outside(p, bad), 0);
        expect(inkAnnotationCacheOf(c).hasKey(InkDrawKeys.hairline), isTrue);
        c.diagnostics.enabled = false;
        c.dispose();
      },
    );

    test('a failed raster (glyph pictures not settled): mathRasterFailed, the '
        'placeholder stays, not asked again within mathRasterRetryMs', () async {
      var looks = 0;
      // every look at the settle clock is 2 s later: the cap is passed at once
      OffscreenMathHost.debugNowUs = () => (looks++) * 2000000;
      OffscreenMathHost.debugExtraSvgLoader = DelayedSvgLoader(
        const Duration(milliseconds: 50),
      );
      final clock = FakeInkClock();
      final m = _math('m', const core.PagePoint(40, 40));
      final c = createTestPageController(clock: clock)
        ..updateContent(_content([m]));
      c.diagnostics.enabled = true;
      final cache = mathRasterCacheOf(c.cachePool);
      final annotation = inkAnnotationCacheOf(c);
      final f = mathFormulaOf(m);
      _paintAll(c);
      await _arrive(c);
      expect(cache.stats.failures, 1);
      expect(c.diagnostics.snapshot.warnings, 1, reason: 'mathRasterFailed');
      expect(annotation.dirtyCount, 0, reason: 'the placeholder stays');
      // its chunk recorded again inside the pause: not asked again
      OffscreenMathHost.debugExtraSvgLoader = null;
      final near = _math('n', const core.PagePoint(60, 120), latex: 'z');
      c.updateContent(_content([m, near], revision: 2));
      await _settle(c);
      expect(cache.stats.failures, 1);
      expect(cache.isCached((formula: f, bucket: 2)), isFalse);
      // after the pause the next record asks again
      clock.advanceMs(InkTuning.mathRasterRetryMs + 1.0);
      c.updateContent(_content([m], revision: 3));
      await _settle(c);
      expect(cache.isCached((formula: f, bucket: 2)), isTrue);
      expect(
        _dark(await _pixels(c, w: 200, h: 200), m.frame.rect),
        greaterThan(20),
      );
      c.diagnostics.enabled = false;
      c.dispose();
    });
  });
}
