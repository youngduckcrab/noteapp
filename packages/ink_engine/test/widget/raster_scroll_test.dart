// (v2.13-perf) Raster tiles while the pages are dragged (03-ink 6.13-2, -3,
// -7). A page that is mounted but off screen (EDITOR's visible ±1: visible
// rect Rect.zero) is the next one to come into view — it gets the tiles of its
// whole page when quiet, and keeps them; a drag at the same scale (only the
// visible rect moves, the bucket stays) does not put tiles off, so the chunks
// that come into view are drawn from tiles instead of replaying their vector
// pictures (texture strokes: a saveLayer and tile shaders each) every frame.
// EDITOR sends isScaling only while the scale changes (page_viewport_test:
// a pan / fling is not scaling). Review fixes: a partly visible page gets
// tiles for its whole page; a chunk outside the visible rect + 1 chunk only
// takes free budget (never evicts the visible tiles); the pages of one pool
// make at most maxTileRastersPerFrame tiles per frame together.
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/dev_tools.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show inkChunkCacheOf, inkRasterTilesOf;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/page_view.dart';
import '../support/raster.dart';

const _frame = Duration(milliseconds: 16);

InkPageController _controller({
  InkCachePool? pool,
  InkRenderConfig config = InkRenderConfig.nativeDefaults,
  String pageId = 'p1',
}) {
  var n = 0;
  final InkPageController c;
  if (pool == null) {
    c = createTestPageController(
      config: InkRenderConfig.nativeDefaults,
      services: testInkCoreServices(startMillis: 100000),
    );
  } else {
    final clock = FakeInkClock();
    c = InkPageController(
      pageId: pageId,
      services: testInkCoreServices(startMillis: 100000),
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
  return c..updateContent(
    SyntheticInk.pageContent(
      pageId: pageId,
      strokes: InkDevTools.syntheticStrokes(
        pageId: pageId,
        pageSize: core.PageSize.a4Portrait,
        count: 60,
        newId: () => 'w${n++}',
        createdAt: 1000,
        seed: 3,
      ),
    ),
  );
}

List<int> _inked(InkPageController c) {
  final chunks = inkChunkCacheOf(c);
  return [
    for (var i = 0; i < chunks.chunkCount; i++)
      if (chunks.strokeCountOf(i) > 0) i,
  ];
}

void _expectAllTiles(InkPageController c, {String? reason}) {
  for (final i in _inked(c)) {
    expect(
      inkRasterTilesOf(c).has(i, 1.5),
      isTrue,
      reason: '${reason ?? ''} chunk $i',
    );
  }
}

void main() {
  testWidgets('a mounted page off screen (visible rect empty) gets the tiles '
      'of its whole page when quiet', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    await pumpPageView(tester, c, visiblePageRect: ui.Rect.zero);
    await rasterAllTiles(tester, c);
    expect(_inked(c).length, greaterThan(6));
    _expectAllTiles(c, reason: 'off screen, about to be shown');
    expect(c.renderStats.rasterTiles, _inked(c).length);
  });

  testWidgets('a page dragged out of view keeps its tiles; dragged back, '
      'no tile is made again', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    await pumpPageView(tester, c);
    await rasterAllTiles(tester, c);
    final made = tilesMade(c);
    expect(made, _inked(c).length);
    await tester.pumpWidget(pageViewApp(c, visiblePageRect: ui.Rect.zero));
    await tester.pump(const Duration(seconds: 3));
    _expectAllTiles(c, reason: 'released after 2 s?');
    await tester.pumpWidget(pageViewApp(c));
    await rasterAllTiles(tester, c);
    expect(tilesMade(c), made, reason: 'drawn from the kept tiles');
  });

  testWidgets('a drag at the same scale keeps making tiles (one per frame) '
      'for the chunks coming into view', (tester) async {
    // A budget for the visible rect + 1 chunk only (6 tiles of 256 pt at
    // bucket 1.5): the rest of the page has no tile before the drag, the
    // drag makes them as they come near (evicting the ones left behind).
    const tile = 384 * 384 * 4;
    final config = InkRenderConfig.nativeDefaults.copyWith(
      rasterBudgetBytes: 6 * tile,
    );
    final pool = InkCachePool(config);
    addTearDown(pool.dispose);
    final c = _controller(pool: pool, config: config);
    addTearDown(c.dispose);
    // the top of the page is visible, quiet: its tiles are made
    const view = ui.Rect.fromLTWH(0, 0, 595, 200);
    await pumpPageView(tester, c, visiblePageRect: view);
    await rasterAllTiles(tester, c);
    final before = tilesMade(c);
    expect(
      c.renderStats.rasterTiles,
      lessThan(_inked(c).length),
      reason: 'the far chunks do not fit',
    );
    // drag down the page: 5 pt per frame for 2 s, never still for 150 ms
    // (EDITOR: isScaling false — a pan is not a zoom)
    for (var k = 1; k <= 120; k++) {
      await tester.pumpWidget(
        pageViewApp(c, visiblePageRect: view.shift(ui.Offset(0, 5.0 * k))),
      );
      await tester.pump(_frame);
    }
    expect(
      tilesMade(c),
      greaterThan(before),
      reason: 'the chunks that came into view during the drag',
    );
    final last = view.shift(const ui.Offset(0, 600));
    final chunks = inkChunkCacheOf(c);
    for (final i in _inked(c)) {
      if (chunks.cellRectOf(i).overlaps(last)) {
        expect(inkRasterTilesOf(c).has(i, 1.5), isTrue, reason: 'chunk $i');
      }
    }
  });

  testWidgets('a zoom still puts tiles off (isScaling, then 150 ms)', (
    tester,
  ) async {
    final c = _controller();
    addTearDown(c.dispose);
    await pumpPageView(tester, c);
    await rasterAllTiles(tester, c);
    final made = tilesMade(c);
    for (var k = 1; k <= 10; k++) {
      await tester.pumpWidget(
        pageViewApp(c, ancestorScale: 1 + k / 10, isScaling: true),
      );
      await tester.pump(_frame);
    }
    await tester.pumpWidget(pageViewApp(c, ancestorScale: 2));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tilesMade(c), made);
  });

  testWidgets('a partly visible page (a sliver at the screen edge) gets the '
      'tiles of its whole page when quiet', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    await pumpPageView(
      tester,
      c,
      visiblePageRect: const ui.Rect.fromLTWH(0, 0, 595, 60),
    );
    await rasterAllTiles(tester, c);
    _expectAllTiles(c, reason: 'scrolled into view next');
  });

  testWidgets('an off-screen neighbour only takes free budget: the visible '
      "page's tiles are never evicted for it", (tester) async {
    // 14 tiles of 256 pt at bucket 1.5 (384 × 384 × 4 bytes each)
    const tile = 384 * 384 * 4;
    final config = InkRenderConfig.nativeDefaults.copyWith(
      rasterBudgetBytes: 14 * tile,
    );
    final pool = InkCachePool(config);
    addTearDown(pool.dispose);
    final a = _controller(pool: pool, config: config, pageId: 'a');
    final b = _controller(pool: pool, config: config, pageId: 'b');
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await _pumpTwo(tester, a, null, b, ui.Rect.zero);
    await rasterAllTiles(tester, a);
    expect(_inked(a).length, inInclusiveRange(8, 13));
    _expectAllTiles(a, reason: 'visible page');
    expect(
      b.renderStats.rasterTiles,
      lessThan(_inked(b).length),
      reason: 'only into the free budget',
    );
    expect(tester.binding.hasScheduledFrame, isFalse, reason: 'no busy loop');
  });

  testWidgets('pages of one pool make at most maxTileRastersPerFrame tiles '
      'per frame together', (tester) async {
    final pool = InkCachePool(InkRenderConfig.nativeDefaults);
    addTearDown(pool.dispose);
    final a = _controller(pool: pool, pageId: 'a');
    final b = _controller(pool: pool, pageId: 'b');
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await _pumpTwo(tester, a, null, b, ui.Rect.zero);
    await tester.pump(const Duration(milliseconds: 400));
    var last = tilesMade(a) + tilesMade(b);
    var frames = 0;
    while (frames < 200 && tester.binding.hasScheduledFrame) {
      await tester.pump();
      frames++;
      final now = tilesMade(a) + tilesMade(b);
      expect(now - last, lessThanOrEqualTo(1), reason: 'frame $frames');
      last = now;
    }
    expect(last, _inked(a).length + _inked(b).length);
  });
}

/// Two page views side by side sharing a pool ([a] and [b] with their
/// visible rects).
Future<void> _pumpTwo(
  WidgetTester tester,
  InkPageController a,
  ui.Rect? visibleA,
  InkPageController b,
  ui.Rect? visibleB,
) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const ui.Size(1300, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 600,
              child: InkPageView(controller: a, visiblePageRect: visibleA),
            ),
            SizedBox(
              width: 600,
              child: InkPageView(controller: b, visiblePageRect: visibleB),
            ),
          ],
        ),
      ),
    ),
  );
}
