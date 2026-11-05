// T10 (03-ink 8, 6.12 R6, contract 7.2.15 '커밋 인계' / '커밋 실패' v1.1):
// the pending display of an edit hands over to the base layers without a
// flicker or a double paint — at once when updateContent comes in the same
// call (CORE N-1), or frames later; discardEdit drops every id of the edit,
// discardPending one id; the timeout drops a forgotten edit with a warning.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show inkChunkCacheOf;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/page_view.dart';
import '../support/pixels.dart';

const _white = [255, 255, 255, 255];
const _bluePx = [0, 0, 255, 255];

final _blue = core.StrokeStyle.defaultsFor(core.PenTool.ballpoint)
    .copyWith(colorArgb: 0xFF0000FF, width: 4);

/// Pixels that differ by more than [tol] in any channel.
int _diffCount(Pixels a, Pixels b, {int tol = 1}) {
  expect((a.width, a.height), (b.width, b.height));
  var n = 0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      if (!samePixel(a.at(x, y), b.at(x, y), tol: tol)) n++;
    }
  }
  return n;
}

void main() {
  late FakeInkClock clock;
  late InkPageController controller;
  late List<core.Stroke> committed;
  var revision = 1;
  final a = strokeThrough(
    segment(const Offset(20, 100), const Offset(120, 100)),
    _blue,
    id: 'a',
  );
  final b = strokeThrough(
    segment(const Offset(20, 200), const Offset(120, 200)),
    _blue,
    id: 'b',
  );

  /// What EDITOR does after a successful execute: CORE's stored copies
  /// (another object, same points) arrive through updateContent.
  void commit(InkEdit edit) {
    committed = [
      for (final s in committed)
        if (!edit.removedIds.contains(s.id)) s,
      for (final s in edit.added) s.copyWith(updatedAt: s.updatedAt + 1),
    ];
    controller.updateContent(
      SyntheticInk.pageContent(strokes: committed, revision: ++revision),
    );
  }

  setUp(() {
    clock = FakeInkClock();
    // pen-down times after the committed strokes' createdAt → new strokes
    // land on top of the z order (appended, R3)
    controller = createTestPageController(
      clock: clock,
      services: testInkCoreServices(startMillis: 100000),
    );
    committed = [a, b];
    revision = 1;
    controller.updateContent(
      SyntheticInk.pageContent(strokes: committed, revision: revision),
    );
  });
  tearDown(() => controller.dispose());

  InkEdit draw(
    WidgetTester tester,
    List<Offset> points, {
    required core.StrokeStyle style,
  }) {
    final samples = [
      for (var i = 0; i < points.length; i++)
        InkSample(
          position: points[i],
          timeUs: i * 8333,
          kind: InkPointerKind.touch,
        ),
    ];
    final s = controller.beginStroke(samples.first, style: style, viewScale: 1)
      ..addSamples(samples.skip(1));
    return s.end(samples.last)!;
  }

  InkEdit erase(double y) {
    final s = controller.beginErase(
      InkSample(
        position: Offset(60, y),
        timeUs: 0,
        kind: InkPointerKind.stylus,
      ),
      spec: const EraserSpec(mode: EraserMode.stroke, radius: 3),
      viewScale: 1,
    );
    return s.end()!;
  }

  testWidgets('opacity 0.5 pen: the committed frame equals the pending one', (
    tester,
  ) async {
    await pumpPageView(tester, controller, width: 596);
    // crosses itself and the chunk border x = 256
    final style = core.StrokeStyle.defaultsFor(core.PenTool.marker)
        .copyWith(colorArgb: 0xFF202020, opacity: 0.5, smoothing: 0);
    final edit = draw(tester, [
      ...segment(const Offset(150, 300), const Offset(400, 300), step: 1),
      ...segment(const Offset(400, 300), const Offset(300, 220), step: 1),
      ...segment(const Offset(300, 220), const Offset(300, 380), step: 1),
    ], style: style);
    await tester.pump();
    final pending = await capturePixels(tester);
    final single = pending.at(200, 300);
    expect(single, isNot(_white));
    expect(single[0], greaterThan(60), reason: 'semi-transparent');
    expect(samePixel(pending.at(300, 300), single, tol: 2), isTrue);
    final records = inkChunkCacheOf(controller).recordCount;

    commit(edit);
    expect(controller.pendingIds, isEmpty);
    await tester.pump();
    final after = await capturePixels(tester);
    expect(_diffCount(pending, after), 0, reason: 'no double paint, no gap');
    expect(
      inkChunkCacheOf(controller).recordCount,
      records,
      reason: 'appended (R3), no chunk re-recorded',
    );
  });

  testWidgets('updateContent frames later: no flicker meanwhile', (
    tester,
  ) async {
    await pumpPageView(tester, controller, width: 596);
    final edit = draw(
      tester,
      segment(const Offset(150, 400), const Offset(450, 420), step: 3),
      style: _blue,
    );
    await tester.pump();
    final first = await capturePixels(tester);
    expect(first.at(300, 410), isNot(_white));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_diffCount(first, await capturePixels(tester)), 0);
    expect(controller.pendingIds, {edit.added.single.id});
    commit(edit);
    await tester.pump();
    expect(_diffCount(first, await capturePixels(tester)), 0);
    expect(controller.pendingIds, isEmpty);
  });

  testWidgets('several pending edits; each hands over on its own', (
    tester,
  ) async {
    await pumpPageView(tester, controller, width: 596);
    final one = draw(
      tester,
      segment(const Offset(150, 500), const Offset(400, 500), step: 3),
      style: _blue,
    );
    final two = draw(
      tester,
      segment(const Offset(150, 560), const Offset(400, 560), step: 3),
      style: _blue,
    );
    await tester.pump();
    final both = await capturePixels(tester);
    expect(both.at(300, 500), _bluePx);
    expect(both.at(300, 560), _bluePx);
    commit(one);
    expect(controller.pendingIds, {two.added.single.id});
    await tester.pump();
    expect(_diffCount(both, await capturePixels(tester)), 0);
    commit(two);
    await tester.pump();
    expect(_diffCount(both, await capturePixels(tester)), 0);
    expect(controller.pendingIds, isEmpty);
  });

  testWidgets('erase: hidden while pending, removed on commit', (tester) async {
    await pumpPageView(tester, controller, width: 596);
    expect((await capturePixels(tester)).at(60, 100), _bluePx);
    final edit = erase(100);
    await tester.pump();
    final pending = await capturePixels(tester);
    expect(pending.at(60, 100), _white);
    commit(edit);
    await tester.pump();
    expect(_diffCount(pending, await capturePixels(tester)), 0);
  });

  testWidgets('discardEdit: every pending id of the edit at once', (
    tester,
  ) async {
    await pumpPageView(tester, controller, width: 596);
    final before = await capturePixels(tester);
    final eraser = controller.beginErase(
      const InkSample(
        position: Offset(60, 90),
        timeUs: 0,
        kind: InkPointerKind.stylus,
      ),
      spec: const EraserSpec(mode: EraserMode.stroke, radius: 3),
      viewScale: 1,
    );
    eraser.addSample(
      const InkSample(
        position: Offset(60, 210),
        timeUs: 8333,
        kind: InkPointerKind.stylus,
      ),
    );
    final edit = eraser.end()!;
    expect(edit.removedIds, {'a', 'b'});
    await tester.pump();
    final hidden = await capturePixels(tester);
    expect(hidden.at(60, 100), _white);
    expect(hidden.at(60, 200), _white);
    controller.discardEdit(edit); // execute threw (contract 7.2.15 v1.1)
    expect(controller.pendingIds, isEmpty);
    await tester.pump();
    expect(_diffCount(before, await capturePixels(tester)), 0);
  });

  testWidgets('discardEdit of a pen stroke: the stroke disappears', (
    tester,
  ) async {
    await pumpPageView(tester, controller, width: 596);
    final before = await capturePixels(tester);
    final edit = draw(
      tester,
      segment(const Offset(150, 600), const Offset(400, 600), step: 3),
      style: _blue,
    );
    await tester.pump();
    expect((await capturePixels(tester)).at(300, 600), _bluePx);
    controller.discardEdit(edit);
    await tester.pump();
    expect(_diffCount(before, await capturePixels(tester)), 0);
  });

  testWidgets('discardPending(id): only that id', (tester) async {
    await pumpPageView(tester, controller, width: 596);
    final ea = erase(100);
    final eb = erase(200);
    await tester.pump();
    controller.discardPending('a');
    expect(controller.pendingIds, {'b'});
    await tester.pump();
    final px = await capturePixels(tester);
    expect(px.at(60, 100), _bluePx, reason: 'a shown again');
    expect(px.at(60, 200), _white, reason: 'b still pending');
    expect(ea.removedIds, {'a'});
    commit(eb);
    expect(controller.pendingIds, isEmpty);
  });

  testWidgets('timeout: the forgotten edit is dropped with a warning', (
    tester,
  ) async {
    controller.diagnostics.enabled = true;
    await pumpPageView(tester, controller, width: 596);
    final before = await capturePixels(tester);
    draw(
      tester,
      segment(const Offset(150, 700), const Offset(400, 700), step: 3),
      style: _blue,
    );
    erase(100);
    await tester.pump();
    final pending = await capturePixels(tester);
    expect(pending.at(300, 700), _bluePx);
    expect(pending.at(60, 100), _white);
    clock.advanceMs(2999);
    controller.updateContent(
      SyntheticInk.pageContent(strokes: committed, revision: ++revision),
    );
    expect(controller.pendingIds, hasLength(2), reason: 'not yet');
    clock.advanceMs(2);
    // the next page change after the 3 s limit drops both
    controller.updateContent(
      SyntheticInk.pageContent(strokes: committed, revision: ++revision),
    );
    expect(controller.pendingIds, isEmpty);
    expect(controller.diagnostics.snapshot.warnings, 2);
    await tester.pump();
    expect(_diffCount(before, await capturePixels(tester)), 0);
  });
}
