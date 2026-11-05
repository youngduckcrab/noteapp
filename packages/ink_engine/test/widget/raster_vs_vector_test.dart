// T19 (03-ink 6.13 L3, -4, -5, -6): the same content drawn from raster tiles
// and from the vector chunk pictures differs in < 1 % of the pixels, for
// 128 pt (web) and 256 pt (native) chunks, at a device scale equal to its
// bucket and between two buckets (downsampled tile). A stroke appended over a
// tile is drawn on top of it (the tile stays); an erased stroke drops its
// chunks' tiles (vectors until the next quiet moment); above the largest
// bucket the vector pictures are drawn; another bucket's tiles are drawn
// stretched until the new ones are made.
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/dev_tools.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/base_cache.dart';
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show inkChunkCacheOf;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/page_view.dart';
import '../support/pixels.dart';
import '../support/raster.dart';

const _page = core.PageSize(512, 640);

/// Handwriting-like strokes of four fill pens, plus long strokes crossing
/// chunk lines.
List<core.Stroke> _strokes(core.PageSize size) {
  var n = 0;
  String id() => 'r${n++}';
  return [
    for (final (i, tool, count) in [
      (0, core.PenTool.ballpoint, 120),
      (1, core.PenTool.fountain, 60),
      (2, core.PenTool.marker, 30),
      (3, core.PenTool.brush, 20),
    ])
      ...InkDevTools.syntheticStrokes(
        pageId: 'p1',
        pageSize: size,
        count: count,
        newId: id,
        createdAt: 1000 + i * 1000,
        seed: 7 + i,
        tool: tool,
      ),
    strokeThrough(
      segment(const ui.Offset(20, 20), ui.Offset(size.width - 20, 600)),
      core.StrokeStyle.defaultsFor(core.PenTool.fountain),
      id: 'diag',
      createdAt: 9000,
    ),
    strokeThrough(
      segment(const ui.Offset(30, 250), const ui.Offset(480, 270)),
      core.StrokeStyle.defaultsFor(core.PenTool.marker),
      id: 'across',
      createdAt: 9001,
    ),
  ];
}

InkPageController _controller(
  double chunk, {
  required bool raster,
  required List<core.Stroke> strokes,
  core.PageSize size = _page,
}) => createTestPageController(
  config: InkRenderConfig(rasterTiles: raster, chunkSizePt: chunk),
)..updateContent(SyntheticInk.pageContent(strokes: strokes, size: size));

/// Non-empty chunks of [c] (each gets one tile).
int _inkedChunks(InkPageController c) {
  final chunks = inkChunkCacheOf(c);
  var n = 0;
  for (var i = 0; i < chunks.chunkCount; i++) {
    if (chunks.strokeCountOf(i) > 0) n++;
  }
  return n;
}

Future<Pixels> _vectorShot(
  WidgetTester tester,
  double chunk,
  List<core.Stroke> strokes, {
  required double width,
  required double dpr,
  core.PageSize size = _page,
}) async {
  final c = _controller(chunk, raster: false, strokes: strokes, size: size);
  addTearDown(c.dispose);
  await pumpPageView(tester, c, width: width, devicePixelRatio: dpr);
  return capturePixels(tester);
}

void main() {
  for (final chunk in [128.0, 256.0]) {
    // Channel tolerance: 8 when a tile pixel is a device pixel (measured:
    // 0 differing pixels); 32 when the tile is resampled (bucket 1.5 drawn at
    // 1.008 — the anti-aliased fringe moves by a fraction of a pixel;
    // measured 2.8 % of the pixels differ by more than 8, 0.2 % by more than
    // 32, mean channel difference 0.18 %).
    for (final (label, width, dpr, bucket, size, tolerance) in [
      ('device scale = bucket 2', 512.0, 2.0, 2.0, _page, 8),
      (
        'A4, device scale 1.008 → bucket 1.5 (downsampled)',
        600.0,
        1.0,
        1.5,
        core.PageSize.a4Portrait,
        32,
      ),
    ]) {
      testWidgets('chunk ${chunk.round()} pt, $label: raster vs vector '
          '< 1 %', (tester) async {
        final strokes = _strokes(size);
        final vector = await _vectorShot(
          tester,
          chunk,
          strokes,
          width: width,
          dpr: dpr,
          size: size,
        );
        final c = _controller(
          chunk,
          raster: true,
          strokes: strokes,
          size: size,
        );
        addTearDown(c.dispose);
        await pumpPageView(tester, c, width: width, devicePixelRatio: dpr);
        expect(tilesMade(c), 0, reason: 'first frames draw vectors');
        await rasterAllTiles(tester, c);
        expect(c.renderStats.currentBucket, bucket);
        final inked = _inkedChunks(c);
        expect(inked, greaterThan(4));
        expect(tilesMade(c), inked, reason: 'one tile per inked chunk');
        expect(c.renderStats.rasterTiles, inked);
        final side = (chunk * bucket).round();
        expect(
          c.renderStats.rasterBytes,
          lessThanOrEqualTo(inked * side * side * 4),
        );
        expect(c.cachePool.stats.rasterTiles, inked);
        final raster = await capturePixels(tester);
        expect(
          differingShare(vector, raster, tolerance: tolerance),
          lessThan(0.01),
        );
        expect(meanDifference(vector, raster), lessThan(0.01));
        expect(inkedPixels(raster), greaterThan(inkedPixels(vector) * 0.98));
      });
    }
  }

  testWidgets('a stroke appended over a tile is drawn on top; the tile '
      'stays', (tester) async {
    final strokes = _strokes(_page);
    final top = strokeThrough(
      segment(const ui.Offset(40, 100), const ui.Offset(300, 140)),
      core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
      id: 'top',
      createdAt: 20000,
    );
    final now = [...strokes, top];
    final vector = await _vectorShot(tester, 128, now, width: 512, dpr: 2);
    final c = _controller(128, raster: true, strokes: strokes);
    addTearDown(c.dispose);
    await pumpPageView(tester, c, width: 512, devicePixelRatio: 2);
    await rasterAllTiles(tester, c);
    final made = tilesMade(c);
    final tiles = c.renderStats.rasterTiles;
    c.updateContent(
      SyntheticInk.pageContent(strokes: now, size: _page, revision: 2),
    );
    await tester.pump();
    expect(c.renderStats.rasterTiles, tiles, reason: 'appends keep tiles');
    expect(inkChunkCacheOf(c).appendedCountAt(0, 0), 1);
    expect(differingShare(vector, await capturePixels(tester)), lessThan(0.01));
    await rasterAllTiles(tester, c);
    expect(tilesMade(c), made, reason: 'nothing to make again');
  });

  testWidgets('an erased stroke drops its chunks\' tiles: vectors at once, '
      'new tiles when quiet', (tester) async {
    final strokes = _strokes(_page);
    final now = [
      for (final s in strokes)
        if (s.id != 'diag') s,
    ];
    final vector = await _vectorShot(tester, 128, now, width: 512, dpr: 2);
    final c = _controller(128, raster: true, strokes: strokes);
    addTearDown(c.dispose);
    await pumpPageView(tester, c, width: 512, devicePixelRatio: 2);
    await rasterAllTiles(tester, c);
    final made = tilesMade(c);
    final tiles = c.renderStats.rasterTiles;
    c.updateContent(
      SyntheticInk.pageContent(strokes: now, size: _page, revision: 2),
    );
    await tester.pump();
    // 'diag' crosses 4 columns × 5 rows of 128 pt cells: those tiles go
    final dropped = tiles - c.renderStats.rasterTiles;
    expect(dropped, greaterThanOrEqualTo(5));
    expect(differingShare(vector, await capturePixels(tester)), lessThan(0.01));
    await tester.pump(const Duration(milliseconds: 299));
    expect(tilesMade(c), made, reason: 'not before the idle wait');
    await rasterAllTiles(tester, c);
    expect(tilesMade(c), made + dropped);
    expect(c.renderStats.rasterTiles, tiles);
    expect(differingShare(vector, await capturePixels(tester)), lessThan(0.01));
  });

  testWidgets('above the largest bucket the vector pictures are drawn; '
      'another bucket\'s tiles are stretched until new ones are made', (
    tester,
  ) async {
    final strokes = _strokes(_page);
    final vectorShot = await _vectorShot(
      tester,
      128,
      strokes,
      width: 512,
      dpr: 1,
    );
    final c = _controller(128, raster: true, strokes: strokes);
    addTearDown(c.dispose);
    await pumpPageView(tester, c, width: 512, devicePixelRatio: 1);
    await rasterAllTiles(tester, c);
    expect(c.renderStats.currentBucket, 1.0);
    final tiles = c.renderStats.rasterTiles;
    final made = tilesMade(c);
    expect(differingShare(vectorShot, await capturePixels(tester)), 0);
    // ancestor zoom 5 → device scale 5 → vector only (the ancestor
    // transform is not in the captured layer, so the pixels compare 1:1)
    await tester.pumpWidget(pageViewApp(c, width: 512, ancestorScale: 5));
    await tester.pump();
    expect(c.renderStats.currentBucket, isNull);
    expect(differingShare(vectorShot, await capturePixels(tester)), 0);
    await rasterAllTiles(tester, c);
    expect(tilesMade(c), made, reason: 'no tiles above the largest bucket');
    // zoom 2 (bucket 2): the bucket-1 tiles are drawn at once (stretched)
    await tester.pumpWidget(pageViewApp(c, width: 512, ancestorScale: 2));
    await tester.pump();
    expect(c.renderStats.currentBucket, 2.0);
    expect(c.renderStats.rasterTiles, tiles);
    expect(differingShare(vectorShot, await capturePixels(tester)), 0);
    await rasterAllTiles(tester, c);
    expect(tilesMade(c), made + tiles, reason: 'the bucket-2 tiles');
    expect(c.renderStats.rasterTiles, tiles, reason: 'bucket 1 ones dropped');
    expect(
      c.renderStats.rasterBytes,
      greaterThan(tiles * 128 * 128 * 4 * 2),
      reason: 'four times the pixels of the bucket-1 tiles (edge tiles less)',
    );
  });

  test('InkChunkCache cell / page rects', () {
    final cache = InkChunkCache(chunkSizePt: 256, maxAppended: 16)
      ..reset(const ui.Size(595.2756, 841.8898));
    addTearDown(cache.dispose);
    expect((cache.columns, cache.rows), (3, 4));
    expect(cache.cellRectOf(2), const ui.Rect.fromLTWH(512, 0, 256, 256));
    expect(
      cache.pageRectOf(11),
      const ui.Rect.fromLTRB(512, 768, 595.2756, 841.8898),
    );
    expect(cache.pageRectOf(0), const ui.Rect.fromLTWH(0, 0, 256, 256));
  });
}
