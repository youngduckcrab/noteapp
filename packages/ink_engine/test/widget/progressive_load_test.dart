// T19 (03-ink 6.13 time slicing): a newly shown page of 2000 strokes is
// recorded within frameWorkBudgetMs (4 ms) per frame — visible chunks first,
// unrecorded chunks blank (paper) — and is complete within a few frames,
// pixel for pixel the same as the page recorded at once. An edit to a chunk
// already shown is recorded in full in its frame (never blank). The budget
// is measured on a fake clock that advances on every reading (no real time).
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/dev_tools.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show inkBaseStatsOf, inkChunkCacheOf;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/page_view.dart';
import '../support/pixels.dart';
import '../support/raster.dart';

/// Each reading costs [stepUs]: the record loop reads the clock once per
/// stroke drawn, so a frame draws about budget / step strokes.
final class _TickClock implements InkClock {
  _TickClock(this.stepUs);
  final int stepUs;
  int us = 0;
  @override
  int nowUs() => us += stepUs;
  @override
  bool get alignedWithEventTimestamps => true;
}

const _step = 5; // µs per stroke drawn → 800 per 4 ms frame
const _budgetUs = 4000;

final List<core.Stroke> _page = () {
  var n = 0;
  return InkDevTools.syntheticStrokes(
    pageId: 'p1',
    pageSize: core.PageSize.a4Portrait,
    count: 2000,
    newId: () => 'g${n++}',
    createdAt: 1000,
    seed: 11,
  );
}();

InkPageController _controller(InkClock clock) => createTestPageController(
  config: const InkRenderConfig(rasterTiles: false),
  clock: clock,
)..updateContent(SyntheticInk.pageContent(strokes: _page));

/// Chunk-stroke pairs: the draws a full recording makes.
int _draws(InkPageController c) {
  final chunks = inkChunkCacheOf(c);
  var n = 0;
  for (var i = 0; i < chunks.chunkCount; i++) {
    n += chunks.strokeCountOf(i);
  }
  return n;
}

void main() {
  testWidgets('2000 strokes: ≤ 4 ms of work per frame, visible chunks '
      'first, complete within a few frames, same pixels', (tester) async {
    // reference: the same page recorded at once (frozen clock)
    final reference = _controller(FakeInkClock());
    addTearDown(reference.dispose);
    await pumpPageView(tester, reference);
    expect(inkChunkCacheOf(reference).loadingCount, 0);
    final want = await capturePixels(tester);
    final draws = _draws(reference);
    expect(draws, greaterThan(2000));

    final c = _controller(_TickClock(_step));
    addTearDown(c.dispose);
    const visible = ui.Rect.fromLTWH(0, 560, 595.2756, 280); // bottom third
    await pumpPageView(tester, c, visiblePageRect: visible);
    final chunks = inkChunkCacheOf(c);
    final stats = inkBaseStatsOf(c);
    // first frame: stopped at the budget (+ one stroke, + the final reading)
    expect(stats.lastPaintUs, lessThanOrEqualTo(_budgetUs + 2 * _step));
    expect(chunks.loadingCount, greaterThan(0), reason: 'time-sliced');
    expect(chunks.loadingCount, lessThan(chunks.chunkCount));
    // the chunks done first are visible ones
    final firstDone = [
      for (var i = 0; i < chunks.chunkCount; i++)
        if (chunks.pictureOf(i) != null) i,
    ];
    for (final i in firstDone) {
      expect(chunks.cellRectOf(i).overlaps(visible), isTrue, reason: '$i');
    }
    // a chunk not recorded yet is blank paper on screen
    final partial = await capturePixels(tester);
    final blank = [
      for (var i = 0; i < chunks.chunkCount; i++)
        if (chunks.pictureOf(i) == null) i,
    ].first;
    final cell = chunks
        .cellRectOf(blank)
        .intersect(const ui.Rect.fromLTWH(0, 0, 595.2756, 841.8898));
    final scale = 600 / 595.2756;
    var inkInBlank = 0;
    for (
      var y = (cell.top * scale).ceil();
      y < (cell.bottom * scale).floor();
      y += 3
    ) {
      for (
        var x = (cell.left * scale).ceil();
        x < (cell.right * scale).floor();
        x += 3
      ) {
        final px = partial.at(x, y);
        if (px[0] < 250) inkInBlank++;
      }
    }
    expect(inkInBlank, 0, reason: 'chunk $blank is still blank');

    var frames = 1;
    final visibleCells = [
      for (var i = 0; i < chunks.chunkCount; i++)
        if (chunks.cellRectOf(i).overlaps(visible)) i,
    ];
    var visibleDoneAt = -1;
    while (chunks.loadingCount > 0 && frames < 100) {
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump();
      frames++;
      expect(stats.lastPaintUs, lessThanOrEqualTo(_budgetUs + 2 * _step));
      if (visibleDoneAt < 0 &&
          visibleCells.every((i) => chunks.pictureOf(i) != null)) {
        visibleDoneAt = frames;
      }
    }
    expect(chunks.loadingCount, 0);
    // ~200 draws per frame
    final expected = (draws * _step / _budgetUs).ceil();
    expect(frames, lessThanOrEqualTo(expected + 2));
    expect(visibleDoneAt, lessThan(frames), reason: 'visible chunks first');
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(differingShare(want, await capturePixels(tester), tolerance: 0), 0);
  });

  testWidgets('strokes appended while loading land on top', (tester) async {
    final c = _controller(_TickClock(_step));
    addTearDown(c.dispose);
    await pumpPageView(tester, c);
    final chunks = inkChunkCacheOf(c);
    expect(chunks.loadingCount, greaterThan(0));
    final top = strokeThrough(
      segment(const ui.Offset(20, 20), const ui.Offset(560, 800)),
      core.StrokeStyle.defaultsFor(core.PenTool.marker),
      id: 'top',
      createdAt: 99999,
    );
    final now = [..._page, top];
    c.updateContent(SyntheticInk.pageContent(strokes: now, revision: 2));
    for (var f = 0; f < 100 && chunks.loadingCount > 0; f++) {
      await tester.pump();
    }
    expect(chunks.loadingCount, 0);
    await tester.pump();
    final got = await capturePixels(tester);

    final reference = createTestPageController(
      config: const InkRenderConfig(rasterTiles: false),
    )..updateContent(SyntheticInk.pageContent(strokes: now, revision: 2));
    addTearDown(reference.dispose);
    await pumpPageView(tester, reference);
    expect(differingShare(await capturePixels(tester), got, tolerance: 0), 0);
  });

  testWidgets('an edit to a loaded chunk is recorded in full at once (no '
      'blank frame)', (tester) async {
    final clock = _TickClock(_step);
    final c = _controller(clock);
    addTearDown(c.dispose);
    await pumpPageView(tester, c);
    final chunks = inkChunkCacheOf(c);
    for (var f = 0; f < 100 && chunks.loadingCount > 0; f++) {
      await tester.pump();
    }
    expect(chunks.loadingCount, 0);
    final records = chunks.recordCount;
    // erase every stroke starting in the top left chunk: it is dirty
    final now = [
      for (final s in _page)
        if (!(s.points.x(0) < 200 && s.points.y(0) < 200)) s,
    ];
    expect(now.length, lessThan(_page.length));
    c.updateContent(SyntheticInk.pageContent(strokes: now, revision: 2));
    await tester.pump();
    expect(chunks.dirtyCount, 0, reason: 'recorded in this frame');
    expect(chunks.loadingCount, 0);
    expect(chunks.recordCount, greaterThan(records));
    expect(
      inkBaseStatsOf(c).lastPaintUs,
      lessThan(_budgetUs),
      reason: 'the full record reads the clock only twice',
    );
  });
}
