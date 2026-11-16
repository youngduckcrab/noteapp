// T19 (03-ink 6.13-2, -3, -7, 6.15): when raster tiles are made — never while
// a pen is down; idleBeforeRasterMs (300) after the last input, then one per
// frame, visible chunks nearest the centre first; none while isScaling, and
// zoomSettleMs (150) after the zoom ends; tiles of chunks outside the visible
// rect + 1 chunk freed releaseInvisibleAfterMs (2 s) after the viewport
// changed; every tile's toImageSync time goes to InkDiagnostics.tileRaster.
// All waits are fake time (testWidgets), the budget clock a fake clock.
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/dev_tools.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show inkBaseStatsOf, inkChunkCacheOf, inkRasterTilesOf;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/page_view.dart';
import '../support/raster.dart';

const _frame = Duration(milliseconds: 16);

/// Advances [stepUs] on every reading (a frame's work is never free).
final class _TickClock implements InkClock {
  _TickClock(this.stepUs);
  final int stepUs;
  int us = 0;
  @override
  int nowUs() => us += stepUs;
  @override
  bool get alignedWithEventTimestamps => true;
}

List<core.Stroke> _strokes() {
  var n = 0;
  return InkDevTools.syntheticStrokes(
    pageId: 'p1',
    pageSize: core.PageSize.a4Portrait,
    count: 60,
    newId: () => 'w${n++}',
    createdAt: 1000,
    seed: 3,
  );
}

InkPageController _controller({
  InkRenderConfig config = InkRenderConfig.nativeDefaults,
  InkClock? clock,
  List<core.Stroke>? strokes,
}) => createTestPageController(
  config: config,
  clock: clock,
  services: testInkCoreServices(startMillis: 100000),
)..updateContent(SyntheticInk.pageContent(strokes: strokes ?? _strokes()));

/// Chunks with ink (each gets one tile when the whole page is visible).
List<int> _inkedChunks(InkPageController c) {
  final chunks = inkChunkCacheOf(c);
  return [
    for (var i = 0; i < chunks.chunkCount; i++)
      if (chunks.strokeCountOf(i) > 0) i,
  ];
}

void main() {
  testWidgets('no tile while the pen is down; 300 ms after the last input, '
      'one per frame until done', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    await pumpPageView(tester, c);
    expect(c.renderStats.currentBucket, 1.5);
    final inked = _inkedChunks(c);
    expect(inked.length, greaterThan(6));

    // one second of writing, a sample per frame
    final samples = SyntheticInk.line(
      const ui.Offset(100, 100),
      const ui.Offset(400, 300),
      samples: 60,
    );
    final session = c.beginStroke(
      samples.first,
      style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
      viewScale: 1,
    );
    for (final s in samples.skip(1)) {
      session.addSample(s);
      await tester.pump(_frame);
    }
    expect(tilesMade(c), 0, reason: 'a pen is down');
    await tester.pump(const Duration(milliseconds: 500));
    expect(tilesMade(c), 0, reason: 'still down after 500 ms of stillness');
    final edit = session.end()!;
    // EDITOR's commit: CORE content with the new stroke
    c.updateContent(
      SyntheticInk.pageContent(strokes: [..._strokes(), ...edit.added]),
    );
    await tester.pump(const Duration(milliseconds: 299));
    expect(tilesMade(c), 0, reason: 'idle wait (300 ms) not over');
    await tester.pump(const Duration(milliseconds: 2));
    expect(tilesMade(c), 1);
    final inkedNow = _inkedChunks(c);
    for (var k = 2; k <= inkedNow.length; k++) {
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump();
      expect(tilesMade(c), k, reason: 'one per frame');
      expect(inkBaseStatsOf(c).lastPaintTiles, 1);
    }
    expect(tester.binding.hasScheduledFrame, isFalse, reason: 'done');
    await tester.pump(const Duration(seconds: 5));
    expect(tilesMade(c), inkedNow.length);
    expect(c.renderStats.rasterTiles, inkedNow.length);
    for (final i in inkedNow) {
      expect(inkRasterTilesOf(c).has(i, 1.5), isTrue, reason: 'chunk $i');
    }
  });

  testWidgets('order: the visible chunks nearest the centre of the visible '
      'rect first', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    // the lower right quarter of A4 (3 × 4 chunks of 256 pt) is visible
    const visible = ui.Rect.fromLTWH(300, 420, 295, 420);
    await pumpPageView(tester, c, visiblePageRect: visible);
    await tester.pump(const Duration(milliseconds: 301));
    final chunks = inkChunkCacheOf(c);
    final tiles = inkRasterTilesOf(c);
    final order = <int>[];
    for (var frame = 0; frame < 20; frame++) {
      for (var i = 0; i < chunks.chunkCount; i++) {
        if (tiles.has(i, 1.5) && !order.contains(i)) order.add(i);
      }
      if (!tester.binding.hasScheduledFrame) break;
      await tester.pump();
    }
    final centre = visible.center;
    double distance(int i) =>
        (chunks.cellRectOf(i).center - centre).distanceSquared;
    final visibleOnes = [
      for (final i in order)
        if (chunks.cellRectOf(i).overlaps(visible)) i,
    ];
    expect(
      order.take(visibleOnes.length),
      visibleOnes,
      reason: 'visible first',
    );
    for (var k = 1; k < visibleOnes.length; k++) {
      expect(
        distance(visibleOnes[k]),
        greaterThanOrEqualTo(distance(visibleOnes[k - 1])),
      );
    }
    // only chunks within the visible rect + 1 chunk get tiles
    final keep = visible.inflate(256);
    for (final i in order) {
      expect(chunks.cellRectOf(i).overlaps(keep), isTrue);
    }
    expect(order.length, lessThan(_inkedChunks(c).length + 1));
  });

  testWidgets('none while isScaling; 150 ms after the zoom ends, tiles at '
      'the new bucket', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    await pumpPageView(tester, c);
    await rasterAllTiles(tester, c);
    final tiles = c.renderStats.rasterTiles;
    final made = tilesMade(c);
    expect(tiles, _inkedChunks(c).length);

    // pinch: the ancestor scale grows frame by frame while isScaling
    for (var k = 1; k <= 30; k++) {
      await tester.pumpWidget(
        pageViewApp(c, ancestorScale: 1 + k / 30, isScaling: true),
      );
      await tester.pump(_frame);
    }
    await tester.pump(const Duration(seconds: 1));
    expect(c.renderStats.currentBucket, 3.0);
    expect(tilesMade(c), made, reason: 'frozen while scaling');
    expect(c.renderStats.rasterTiles, tiles, reason: 'old tiles drawn');

    await tester.pumpWidget(pageViewApp(c, ancestorScale: 2));
    await tester.pump(const Duration(milliseconds: 149));
    expect(tilesMade(c), made, reason: 'zoom not settled (150 ms)');
    await tester.pump(const Duration(milliseconds: 2));
    expect(tilesMade(c), made + 1);
    await rasterAllTiles(tester, c);
    expect(tilesMade(c), made + tiles);
    expect(c.renderStats.rasterTiles, tiles, reason: 'bucket 1.5 ones gone');
    for (final i in _inkedChunks(c)) {
      expect(inkRasterTilesOf(c).has(i, 3), isTrue);
      expect(inkRasterTilesOf(c).has(i, 1.5), isFalse);
    }
  });

  testWidgets('(v2.13-perf) tiles of chunks outside the visible rect + 1 '
      'chunk stay after 2 s: a mounted page keeps its whole page (the budget '
      'LRU frees them, raster_scroll_test)', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    await pumpPageView(tester, c);
    await rasterAllTiles(tester, c);
    final all = c.renderStats.rasterTiles;
    const visible = ui.Rect.fromLTWH(0, 0, 200, 200);
    await tester.pumpWidget(pageViewApp(c, visiblePageRect: visible));
    await tester.pump(const Duration(milliseconds: 2001));
    expect(
      c.renderStats.rasterTiles,
      all,
      reason: 'scrolled back: no re-raster',
    );
    expect(c.cachePool.stats.rasterTiles, all);
    // scrolling on: nothing to make again, nothing released
    await tester.pumpWidget(
      pageViewApp(c, visiblePageRect: const ui.Rect.fromLTWH(0, 600, 200, 200)),
    );
    final made = tilesMade(c);
    await rasterAllTiles(tester, c);
    await tester.pump(const Duration(milliseconds: 2001));
    expect(tilesMade(c), made);
    expect(c.renderStats.rasterTiles, all);
  });

  testWidgets('every tile records its toImageSync time (tileRaster)', (
    tester,
  ) async {
    final clock = _TickClock(250);
    final c = _controller(clock: clock);
    addTearDown(c.dispose);
    c.diagnostics.enabled = true;
    await pumpPageView(tester, c);
    await rasterAllTiles(tester, c);
    final made = tilesMade(c);
    expect(made, _inkedChunks(c).length);
    final snap = c.diagnostics.snapshot;
    expect(snap.tileRaster.count, made);
    // two clock readings around each tile = one 250 µs tick
    expect(snap.lastTileRasterMs, 0.25);
    expect(snap.tileRaster.maxMs, 0.25);
    expect(snap.cache.rasterTiles, made);
    expect(snap.cache.rasterBytes, c.renderStats.rasterBytes);
    c.diagnostics.enabled = false;
  });

  testWidgets('maxTileRastersPerFrame and the frame budget', (tester) async {
    final c = _controller(
      config: const InkRenderConfig(maxTileRastersPerFrame: 3),
    );
    addTearDown(c.dispose);
    await pumpPageView(tester, c);
    await tester.pump(const Duration(milliseconds: 301));
    expect(tilesMade(c), 3);
    await tester.pump();
    expect(tilesMade(c), 6);

    // a clock where every reading costs 3 ms: the budget (4 ms) is gone
    // after the first tile
    final slow = _controller(
      clock: _TickClock(3000),
      config: const InkRenderConfig(maxTileRastersPerFrame: 3),
    );
    addTearDown(slow.dispose);
    await pumpPageView(tester, slow);
    await tester.pump(const Duration(milliseconds: 400));
    // loading (time-sliced) comes first; then at most one tile per frame
    var frames = 0;
    while (tester.binding.hasScheduledFrame && frames < 400) {
      await tester.pump();
      frames++;
      expect(inkBaseStatsOf(slow).lastPaintTiles, lessThanOrEqualTo(1));
    }
    expect(tilesMade(slow), _inkedChunks(slow).length);
  });

  testWidgets('rasterTiles: false → no tiles, no timers', (tester) async {
    final c = _controller(config: const InkRenderConfig(rasterTiles: false));
    addTearDown(c.dispose);
    await pumpPageView(tester, c);
    await tester.pump(const Duration(seconds: 3));
    expect(tilesMade(c), 0);
    expect(c.renderStats.currentBucket, 1.5);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('no view → tiles freed at once; dispose → none in the pool', (
    tester,
  ) async {
    final c = _controller();
    await pumpPageView(tester, c);
    await rasterAllTiles(tester, c);
    expect(c.cachePool.stats.rasterTiles, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    expect(c.renderStats.rasterTiles, 0);
    expect(c.cachePool.stats.rasterTiles, 0);
    await tester.pump(const Duration(seconds: 5));
    expect(tilesMade(c), _inkedChunks(c).length, reason: 'none without view');

    await pumpPageView(tester, c);
    await rasterAllTiles(tester, c);
    expect(c.cachePool.stats.rasterTiles, _inkedChunks(c).length);
    final pool = c.cachePool;
    c.dispose();
    expect(pool.stats.rasterTiles, 0);
    expect(pool.stats.chunkPictures, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('budget too small for the visible tiles: evicted chunks stay '
      'vector until the viewport changes (no evict / remake loop)', (
    tester,
  ) async {
    // bucket 1.5: a full 256 pt chunk = 384 × 384 px ≈ 590 KB (the edge
    // chunks of A4 are smaller); room for 3 full ones
    final c = _controller(
      config: const InkRenderConfig(rasterBudgetBytes: 3 * 384 * 384 * 4),
    );
    addTearDown(c.dispose);
    await pumpPageView(tester, c);
    final frames = await rasterAllTiles(tester, c);
    expect(frames, lessThan(30), reason: 'it stops');
    final inked = _inkedChunks(c).length;
    expect(tilesMade(c), inked, reason: 'each chunk tried once');
    expect(c.renderStats.rasterTiles, lessThan(inked));
    expect(c.renderStats.rasterBytes, lessThanOrEqualTo(3 * 384 * 384 * 4));
    await tester.pump(const Duration(seconds: 3));
    expect(tilesMade(c), inked);
  });

  test('the scheduler alone: quiet after both waits, only while attached', () {
    // covered with fake time by the widget tests above; here: no timer is
    // created without a view
    final c = _controller();
    addTearDown(c.dispose);
    c.setViewport(deviceScale: 1, isScaling: false);
    expect(c.renderStats.rasterTiles, 0);
    expect(inkBaseStatsOf(c).tilesMade, 0);
  });
}
