// B14 object page, B16 hitTestObject, B17 vector export v2, B18 thumbnail v2,
// B19 formula layout (m5-7/03-ink 6.25, 9.5, T43). Run: flutter test benchmark/
// (bench tag). Fonts: the committed NoteSans (rootBundle) and the KaTeX fonts.
@Tags(['bench'])
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/cache_pool.dart' show mathRasterCacheOf;
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show
        inkAnnotationCacheOf,
        inkChunkCacheOf,
        inkPageRenderOf,
        inkUnderlayCacheOf;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' show PageObjectFixtures;

import '../test/support/memory_asset_store.dart';
import 'support/bench.dart';
import 'support/workloads.dart';

const _pageId = 'p1';
const _latex = [
  r'\frac{a}{b}+\sqrt{x}',
  r'x_{1}^{2}+x_{2}^{2}',
  r'\sqrt[3]{\frac{1}{1+y}}',
  r'\frac{\partial f}{\partial x_i}',
];

/// Random rects inside A4 (24 pt margin).
core.PageRect _rect(math.Random rng, double w, double h) {
  final x = 24 + rng.nextDouble() * (a4.width - 48 - w);
  final y = 24 + rng.nextDouble() * (a4.height - 48 - h);
  return core.PageRect(x, y, x + w, y + h);
}

/// Shapes of every kind (a third filled, a third dashed / dotted), text boxes,
/// formulas and images, createdAt in that order from [createdAt]. New instances
/// every call (InkPageContent / view caches are per instance).
List<core.PageObject> _objects({
  int shapes = 0,
  int texts = 0,
  int formulas = 0,
  int images = 0,
  int seed = 14,
  int createdAt = 10000,
}) {
  final rng = math.Random(seed);
  var t = createdAt;
  final out = <core.PageObject>[];
  for (var i = 0; i < shapes; i++) {
    final kind = core.ShapeKind.values[i % core.ShapeKind.values.length];
    final s = PageObjectFixtures.shape(
      pageId: _pageId,
      kind: kind,
      rect: _rect(rng, 30 + rng.nextDouble() * 90, 20 + rng.nextDouble() * 80),
      createdAt: t++,
      id: 'sh$i',
    );
    out.add(
      core.ShapeObject(
        id: s.id,
        pageId: s.pageId,
        shapeKind: s.shapeKind,
        geometry: s.geometry,
        style: core.ShapeStyle(
          strokeColorArgb: 0xFF1A1A1A,
          strokeWidth: 1 + (i % 4),
          dash: core.LineDash.values[i % core.LineDash.values.length],
          fillColorArgb: i % 3 == 0 ? 0xFF90CAF9 : null,
          arrowHeads: s.style.arrowHeads,
        ),
        createdAt: s.createdAt,
      ),
    );
  }
  for (var i = 0; i < texts; i++) {
    out.add(
      PageObjectFixtures.textBox(
        pageId: _pageId,
        text: '안녕 hello 줄 $i\n한글 텍스트 상자 검색',
        rect: _rect(rng, 170, 48),
        createdAt: t++,
        id: 'tx$i',
      ),
    );
  }
  for (var i = 0; i < formulas; i++) {
    final latex = _latex[i % _latex.length];
    final l = InkMathRenderer.layout(latex, fontSizePt: 18)!;
    out.add(
      core.MathObject(
        id: 'mx$i',
        pageId: _pageId,
        frame: core.ElementFrame(_rect(rng, l.sizePt.width, l.sizePt.height)),
        latex: latex,
        style: const core.MathStyle(fontSizePt: 18),
        createdAt: t++,
      ),
    );
  }
  for (var i = 0; i < images; i++) {
    out.add(
      PageObjectFixtures.image(
        pageId: _pageId,
        assetId: 'img${i % 10}',
        rect: _rect(rng, 120, 90),
        pixelWidth: 256,
        pixelHeight: 192,
        createdAt: t++,
        id: 'im$i',
      ),
    );
  }
  return out;
}

/// [count] tape strokes (straight, 14 pt) — the cover layer.
List<core.Stroke> _tapes(int count, {int seed = 15}) {
  final rng = math.Random(seed);
  return [
    for (var i = 0; i < count; i++)
      () {
        final r = _rect(rng, 60 + rng.nextDouble() * 80, 0);
        return strokeAlong(
          [
            for (var k = 0; k <= 20; k++)
              ui.Offset(r.left + (r.right - r.left) * k / 20, r.top),
          ],
          id: 'tape$i',
          tool: core.PenTool.tape,
          createdAt: 500 + i,
        );
      }(),
  ];
}

void _paint(InkPageController c, Iterable<InkRenderLayer> layers) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final render = inkPageRenderOf(c);
  for (final layer in layers) {
    render.paint(canvas, layer, 1);
  }
  recorder.endRecording().dispose();
}

const _baseLayers = [
  InkRenderLayer.underlay,
  InkRenderLayer.highlighterBase,
  InkRenderLayer.inkBase,
  InkRenderLayer.annotation,
  InkRenderLayer.cover,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryAssetStore store;
  late InkImageCache images;
  late List<PageBackgroundLayerBuilder> builders;
  late InkCachePool pool;
  const config = InkRenderConfig(rasterTiles: false);

  InkPageController controller() {
    final clock = FakeInkClock();
    return InkPageController(
      pageId: _pageId,
      services: testInkCoreServices(),
      config: config,
      cachePool: pool,
      pressureStore: MemoryPressureStore(),
      pressureMode: () => PressureMode.auto,
      diagnostics: InkDiagnostics(clock: clock),
      clock: clock,
      pencilGrain: PencilGrain(),
      backgroundBuilders: builders,
      shapeFitter: () => const NoShapeFitter(),
    );
  }

  /// Paints until every image and formula raster arrived (the caches are warm).
  Future<void> settle(InkPageController c) async {
    final math = mathRasterCacheOf(pool);
    for (var i = 0; i < 400; i++) {
      _paint(c, _baseLayers);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      if (inkAnnotationCacheOf(c).dirtyCount == 0 &&
          inkUnderlayCacheOf(c).dirtyCount == 0 &&
          math.stats.queued == 0) {
        _paint(c, _baseLayers);
        return;
      }
    }
    fail('the image / formula rasters did not settle');
  }

  setUpAll(() async {
    await InkFonts.ensureLoaded();
    await loadKatexFontsForTest();
    store = MemoryAssetStore();
    for (var i = 0; i < 10; i++) {
      store.bytes['img$i'] = await testPngBytes(
        width: 256,
        height: 192,
        argb: 0xFF000000 + 0x101010 * (i + 3),
      );
    }
    images = InkImageCache(assets: store, budgetBytes: 64 << 20);
    builders = [
      ImageBackgroundLayerBuilder(assets: store, images: images),
      const TemplateBackgroundLayerBuilder(),
    ];
    pool = InkCachePool(config);
  });

  tearDownAll(() async {
    images.dispose();
    await store.close();
  });

  /// fromCore + updateContent + one paint of the base layers on a fresh controller
  /// with fresh CORE objects (the caches of the pool / image cache stay warm).
  (BenchStats, InkPageController) pageLoad(
    List<core.PageObject> Function() objects,
    List<core.Stroke> Function() strokes, {
    int runs = 12,
    bool settled = true,
  }) {
    final page = SyntheticInk.page(pageId: _pageId);
    late InkPageController c;
    late List<core.PageObject> fresh;
    late List<core.Stroke> freshStrokes;
    final controllers = <InkPageController>[];
    final stats = measure(
      () {
        c.updateContent(
          InkPageContent.fromCore(
            page: page,
            strokes: freshStrokes,
            objects: fresh,
            revision: 1,
          ),
        );
        _paint(c, _baseLayers);
      },
      setUp: () {
        fresh = objects();
        freshStrokes = strokes();
        c = controller();
        controllers.add(c);
      },
      warmup: 3,
      runs: runs,
    );
    if (settled) {
      // every chunk recorded by the one paint; every formula a raster cache hit
      expect(inkAnnotationCacheOf(c).dirtyCount, 0);
      expect(inkUnderlayCacheOf(c).dirtyCount, 0);
    }
    expect(mathRasterCacheOf(pool).stats.queued, 0, reason: 'raster hits');
    for (final x in controllers) {
      if (!identical(x, c)) x.dispose();
    }
    return (stats, c);
  }

  List<core.PageObject> b14Objects() =>
      _objects(shapes: 200, texts: 100, formulas: 20, images: 20);

  group('B14 object page', () {
    setUpAll(() async {
      // warm the formula raster and image caches (the case is 'cache hit')
      final warm = controller()
        ..updateContent(
          InkPageContent.fromCore(
            page: SyntheticInk.page(pageId: _pageId),
            strokes: _tapes(50),
            objects: b14Objects(),
            revision: 1,
          ),
        );
      await settle(warm);
      warm.dispose();
    });

    test('200 shapes + 100 text + 20 formulas + 20 images (caches hit) + 50 '
        'tapes — fromCore + diff + first chunk recording', () {
      final (stats, c) = pageLoad(b14Objects, () => _tapes(50));
      final extra = {
        'ink_chunks': inkChunkCacheOf(c).pictureCount,
        'annotation_chunks': inkAnnotationCacheOf(c).pictureCount,
      };
      c.dispose();
      report(
        'B14',
        'object page 200 shapes + 100 text + 20 math + 20 images + 50 tapes',
        stats,
        criteria: {'median_ms': 12},
        extra: extra,
      );
    });

    test('(reference) the parts of B14 on their own', () {
      for (final (name, objects, strokes) in [
        ('200 shapes', () => _objects(shapes: 200), () => <core.Stroke>[]),
        ('100 text boxes', () => _objects(texts: 100), () => <core.Stroke>[]),
        (
          '20 formulas + 20 images',
          () => _objects(formulas: 20, images: 20),
          () => <core.Stroke>[],
        ),
        ('50 tapes', () => <core.PageObject>[], () => _tapes(50)),
      ]) {
        final (stats, c) = pageLoad(objects, strokes, runs: 8, settled: false);
        c.dispose();
        report('B14', 'part: $name', stats, criteria: const {});
      }
    });

    test(
      'one preview object update (setPreviewObjects + live layer paint)',
      () {
        final (_, c) = pageLoad(b14Objects, () => _tapes(50), runs: 1);
        var k = 0;
        final stats = measure(
          () {
            k++;
            c.setPreviewObjects([
              PageObjectFixtures.shape(
                pageId: _pageId,
                kind: core.ShapeKind.ellipse,
                rect: core.PageRect(100, 100, 160 + k % 50, 140 + k % 30),
                createdAt: 99999,
                id: 'preview',
              ),
            ]);
            _paint(c, const [InkRenderLayer.inkActive]);
          },
          warmup: 10,
          runs: 60,
        );
        c.dispose();
        report(
          'B14',
          'one preview object update (setPreviewObjects + live layer paint)',
          stats,
          criteria: {'median_ms': 0.5},
        );
      },
    );
  });

  test('B16 hitTestObject: 2000 objects', () {
    final objs = _objects(
      shapes: 1200,
      texts: 400,
      formulas: 200,
      images: 200,
      seed: 16,
    );
    final c = createTestPageController()
      ..updateContent(
        InkPageContent.fromCore(
          page: SyntheticInk.page(pageId: _pageId),
          strokes: const [],
          objects: objs,
          revision: 1,
        ),
      );
    final rng = math.Random(160);
    final points = [
      for (var i = 0; i < 500; i++)
        ui.Offset(rng.nextDouble() * a4.width, rng.nextDouble() * a4.height),
    ];
    c.hitTestObject(points.first); // builds the object index (not measured)
    var i = 0, hits = 0;
    final stats = measure(
      () {
        if (c.hitTestObject(points[i++ % points.length]) != null) hits++;
      },
      warmup: 3,
      runs: 30,
      inner: 100,
    );
    expect(hits, greaterThan(0));
    c.dispose();
    report(
      'B16',
      'hitTestObject, 2000 objects (500 random points)',
      stats,
      criteria: {'median_ms': 0.2},
      extra: {'hit_share': hits / (33 * 100)},
    );
  });

  test('B17 vector export v2: 200 shapes + 100 text + 1000 strokes', () {
    final content = InkPageContent.fromCore(
      page: SyntheticInk.page(pageId: _pageId),
      strokes: mixedPage(1000),
      objects: _objects(shapes: 200, texts: 100),
      revision: 1,
    );
    late InkPageVectors v;
    final stats = measure(
      () => v = InkVectorExport.exportPage(content),
      warmup: 3,
      runs: 12,
    );
    expect(v.annotations, isNotEmpty);
    for (final (name, part) in [
      (
        'part: 1000 strokes',
        InkPageContent.fromCore(
          page: SyntheticInk.page(pageId: _pageId),
          strokes: mixedPage(1000),
          revision: 1,
        ),
      ),
      (
        'part: 200 shapes + 100 text',
        InkPageContent.fromCore(
          page: SyntheticInk.page(pageId: _pageId),
          strokes: const [],
          objects: _objects(shapes: 200, texts: 100),
          revision: 1,
        ),
      ),
    ]) {
      report(
        'B17',
        name,
        measure(() => InkVectorExport.exportPage(part), warmup: 3, runs: 12),
        criteria: const {},
      );
    }
    report(
      'B17',
      'vector export 200 shapes + 100 text + 1000 strokes',
      stats,
      criteria: {'median_ms': 60},
      extra: {
        'ink_shapes': v.inkShapes.length,
        'annotations': v.annotations.length,
      },
    );
  });

  test('B18 thumbnail v2: 50 objects (10 images, cache hit) + 1000 strokes, '
      '512 px', () async {
    final renderer = InkPageThumbnailRenderer(backgroundBuilders: builders);
    final content = core.PageContent(
      page: SyntheticInk.page(pageId: _pageId),
      strokes: mixedPage(1000),
      objects: _objects(shapes: 25, texts: 15, images: 10, seed: 18),
      revision: 1,
    );
    core.PageThumbnail? thumb;
    final stats = await measureAsync(
      () async => thumb = await renderer.render(content),
      warmup: 2,
      runs: 8,
    );
    expect(thumb, isNotNull);
    expect(thumb!.bytes.sublist(1, 4), 'PNG'.codeUnits);
    report(
      'B18',
      'thumbnail 50 objects + 1000 strokes, 512 px PNG',
      stats,
      criteria: {'median_ms': 800},
      extra: {'png_bytes': thumb!.bytes.length},
    );
  });

  test('B19 InkMathRenderer.layout: a usual formula (reference)', () {
    var i = 0;
    final stats = measure(
      () {
        // a new formula every call (no cache can answer it)
        final n = i++;
        InkMathRenderer.layout(
          '\\frac{a_{$n}}{\\sqrt{b^{2}+$n}}+x_{1}^{2}',
          fontSizePt: 18,
        );
      },
      warmup: 10,
      runs: 40,
    );
    report(
      'B19',
      'layout: fraction + root + sub/superscripts (debug VM, reference)',
      stats,
      criteria: const {},
    );
  });
}
