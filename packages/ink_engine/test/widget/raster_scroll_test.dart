// (v2.13-perf) Raster tiles while the pages are dragged (03-ink 6.13-2, -3,
// -7). A page that is mounted but off screen (EDITOR's visible ±1: visible
// rect Rect.zero) is the next one to come into view — it gets the tiles of its
// whole page when quiet, and keeps them; a drag at the same scale (only the
// visible rect moves, the bucket stays) does not put tiles off, so the chunks
// that come into view are drawn from tiles instead of replaying their vector
// pictures (texture strokes: a saveLayer and tile shaders each) every frame.
import 'dart:ui' as ui;

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

InkPageController _controller() {
  var n = 0;
  return createTestPageController(
    config: InkRenderConfig.nativeDefaults,
    services: testInkCoreServices(startMillis: 100000),
  )..updateContent(
    SyntheticInk.pageContent(
      strokes: InkDevTools.syntheticStrokes(
        pageId: 'p1',
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
    final c = _controller();
    addTearDown(c.dispose);
    // the top of the page is visible, quiet: its tiles are made
    const view = ui.Rect.fromLTWH(0, 0, 595, 200);
    await pumpPageView(tester, c, visiblePageRect: view);
    await rasterAllTiles(tester, c);
    final before = tilesMade(c);
    // drag down the page: 4 pt per frame for 2 s, never still for 150 ms
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
}
