// B21 (v2.13-perf): a texture page coming into view while the pages are
// dragged. Run: flutter test benchmark/page_scroll_bench_test.dart.
//
// The page: 300 texture strokes (pencil, brush, crayon, chalk, watercolor,
// spray — 50 each) + 200 ballpoint strokes on A4, the pencil grain and the
// texture tiles ready, one InkCachePool shared by the page controllers as in
// the app (inkCachePoolProvider).
//   B21a mount (cold): a new controller and new strokes — UI-thread time of
//        every inkBase frame until the page is recorded (the 4 ms slices);
//   B21b re-mount (warm): a new controller with the same InkStroke objects
//        (the page scrolled out of the mounted range and back) — same;
//   B21c raster per frame: what the raster thread replays every frame while
//        the page moves — the inkBase layer picture drawn at 2 device px per
//        pt (Picture.toImage, the flutter_tester software rasterizer): the
//        vector chunk pictures vs the raster tiles of the same chunks.
@Tags(['bench'])
library;

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show inkChunkCacheOf, inkPageRenderOf;
import 'package:ink_engine/src/render/raster_tiles.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import 'support/bench.dart';
import 'support/workloads.dart';

const _texture = [
  core.PenTool.pencil,
  core.PenTool.brush,
  core.PenTool.crayon,
  core.PenTool.chalk,
  core.PenTool.watercolor,
  core.PenTool.spray,
];

List<core.Stroke> _page() => [
  for (var k = 0; k < _texture.length; k++)
    ...handwriting(
      count: 50,
      points: 40 + 20 * k,
      tool: _texture[k],
      seed: 10 + k,
      idPrefix: _texture[k].name,
      createdAt: 1000 + 50 * k,
    ),
  ...handwriting(count: 200, points: 120, seed: 3, createdAt: 2000),
];

void main() {
  const config = InkRenderConfig(rasterTiles: false);
  late PencilGrain grain;
  late InkCachePool pool;

  setUpAll(() async {
    grain = PencilGrain();
    await grain.ready;
  });

  InkPageController controller() => InkPageController(
    pageId: 'p1',
    services: testInkCoreServices(),
    config: config,
    cachePool: pool,
    pressureStore: MemoryPressureStore(),
    pressureMode: () => PressureMode.auto,
    diagnostics: InkDiagnostics(clock: InkClock.platform()),
    clock: InkClock.platform(),
    pencilGrain: grain,
    backgroundBuilders: const [TemplateBackgroundLayerBuilder()],
  );

  /// inkBase frames until every chunk is recorded: (total ms, max frame ms, frames).
  (double, double, int) load(InkPageController c, InkPageContent content) {
    c.updateContent(content);
    var total = 0.0, worst = 0.0;
    var frames = 0;
    final w = Stopwatch();
    do {
      w
        ..reset()
        ..start();
      final recorder = ui.PictureRecorder();
      inkPageRenderOf(c).paint(ui.Canvas(recorder), InkRenderLayer.inkBase, 1);
      recorder.endRecording().dispose();
      w.stop();
      final ms = w.elapsedMicroseconds / 1000;
      total += ms;
      if (ms > worst) worst = ms;
      frames++;
    } while (inkChunkCacheOf(c).loadingCount > 0 && frames < 10000);
    return (total, worst, frames);
  }

  test('B21a/b mount of a texture page (cold, warm)', () {
    final source = _page();
    for (final warm in [false, true]) {
      final totals = <double>[], worst = <double>[];
      var frames = 0;
      pool = InkCachePool(config);
      final shared = pageOf(freshCopies(source));
      for (var r = 0; r < 6; r++) {
        if (!warm) pool = InkCachePool(config);
        final c = controller();
        final (t, m, f) = load(c, warm ? shared : pageOf(freshCopies(source)));
        c.dispose();
        if (r == 0) continue; // warm-up
        totals.add(t);
        worst.add(m);
        frames = f;
      }
      report(
        'B21',
        warm ? 'remount texture page (warm caches)' : 'mount texture page',
        BenchStats(totals),
        criteria: const {},
        extra: {
          'frames': frames,
          'max_frame_ms': (BenchStats(worst).median * 100).round() / 100,
        },
      );
    }
  });

  test('B21c raster of the inkBase layer per frame: vector vs tiles', () async {
    pool = InkCachePool(config);
    final c = controller();
    load(c, pageOf(_page()));
    final chunks = inkChunkCacheOf(c);
    const bucket = 2.0;
    final size = core.PageSize.a4Portrait;
    final w = (size.width * bucket).ceil(), h = (size.height * bucket).ceil();
    ui.Picture vector() {
      final r = ui.PictureRecorder();
      final canvas = ui.Canvas(r)..scale(bucket);
      inkPageRenderOf(c).paint(canvas, InkRenderLayer.inkBase, bucket);
      return r.endRecording();
    }

    final tiles = <RasterTile>[];
    for (var i = 0; i < chunks.chunkCount; i++) {
      final p = chunks.pictureOf(i);
      if (p == null || chunks.strokeCountOf(i) == 0) continue;
      tiles.add(
        rasterizeChunk(
          picture: p,
          appended: chunks.appendedOf(i),
          chunkRect: chunks.pageRectOf(i),
          bucket: bucket,
          generation: chunks.generationOf(i),
        ),
      );
    }
    ui.Picture tiled() {
      final r = ui.PictureRecorder();
      final canvas = ui.Canvas(r)..scale(bucket);
      for (final t in tiles) {
        t.draw(canvas);
      }
      return r.endRecording();
    }

    for (final (name, make) in [('vector', vector), ('tiles', tiled)]) {
      final samples = <double>[];
      for (var r = 0; r < 8; r++) {
        final picture = make();
        final sw = Stopwatch()..start();
        final image = await picture.toImage(w, h);
        sw.stop();
        image.dispose();
        picture.dispose();
        if (r >= 2) samples.add(sw.elapsedMicroseconds / 1000);
      }
      report(
        'B21',
        'raster inkBase frame at 2x ($name)',
        BenchStats(samples),
        criteria: const {},
      );
    }
    for (final t in tiles) {
      t.dispose();
    }
    c.dispose();
  });
}
