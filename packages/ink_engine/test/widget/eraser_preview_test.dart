// T15 (03-ink 6.19 2, 6.12 R6/R7): strokes the eraser touches disappear on
// the next frame while the gesture goes on, stay hidden as pending after
// end() — also across an unrelated updateContent — and the frame after the
// commit's updateContent is identical (no flicker). cancel() shows them again.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/page_view.dart';
import '../support/pixels.dart';

const _white = [255, 255, 255, 255];
const _bluePx = [0, 0, 255, 255];

final _blue = core.StrokeStyle.defaultsFor(core.PenTool.ballpoint)
    .copyWith(colorArgb: 0xFF0000FF, width: 4);
final _yellow = core.StrokeStyle.defaultsFor(core.PenTool.highlighter)
    .copyWith(colorArgb: 0xFFFFE600);

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

InkSample _at(double x, double y, int i) => InkSample(
  position: Offset(x, y),
  timeUs: i * 8333,
  kind: InkPointerKind.stylus,
);

void main() {
  late InkPageController controller;
  late List<core.Stroke> committed;
  var revision = 1;

  // five vertical blue strokes at x = 100, 180, …, 420 (crossing the chunk
  // border x = 256) and one highlighter row under them at y = 400
  final columns = [
    for (var k = 0; k < 5; k++)
      strokeThrough(
        segment(Offset(100.0 + 80 * k, 250), Offset(100.0 + 80 * k, 450)),
        _blue,
        id: 'col$k',
        createdAt: 2000 + k,
      ),
  ];
  final row = strokeThrough(
    segment(const Offset(60, 400), const Offset(500, 400)),
    _yellow,
    id: 'row',
    createdAt: 1000,
  );
  final other = strokeThrough(
    segment(const Offset(60, 600), const Offset(500, 600)),
    _blue,
    id: 'other',
    createdAt: 3000,
  );

  void push(List<core.Stroke> strokes) {
    committed = strokes;
    controller.updateContent(
      SyntheticInk.pageContent(strokes: committed, revision: ++revision),
    );
  }

  /// EDITOR after a successful execute: the strokes are gone from CORE.
  void commit(InkEdit edit) => push([
    for (final s in committed)
      if (!edit.removedIds.contains(s.id)) s,
  ]);

  setUp(() {
    controller = createTestPageController();
    revision = 1;
    committed = [row, ...columns];
    controller.updateContent(
      SyntheticInk.pageContent(strokes: committed, revision: revision),
    );
  });
  tearDown(() => controller.dispose());

  testWidgets('touched strokes vanish frame by frame; commit = same frame', (
    tester,
  ) async {
    await pumpPageView(tester, controller, width: 596);
    final before = await capturePixels(tester);
    for (var k = 0; k < 5; k++) {
      expect(before.at(100 + 80 * k, 300), _bluePx);
    }
    expect(before.at(80, 400), isNot(_white), reason: 'highlighter');

    // a pass along y = 300 from x = 60 to the right, samples 40 pt apart,
    // stroke filter all — the highlighter row (y = 400) is never reached
    final session = controller.beginErase(
      _at(60, 300, 0),
      spec: const EraserSpec(mode: EraserMode.stroke, radius: 4),
      viewScale: 1,
    );
    await tester.pump();
    expect(_diffCount(before, await capturePixels(tester)), 0);
    var x = 60.0, i = 0;
    for (var k = 0; k < 5; k++) {
      // the next sample is past column k
      while (x <= 100 + 80 * k) {
        x += 40;
        session.addSample(_at(x, 300, ++i));
      }
      await tester.pump();
      final frame = await capturePixels(tester);
      for (var j = 0; j < 5; j++) {
        expect(
          frame.at(100 + 80 * j, 300),
          j <= k ? _white : _bluePx,
          reason: 'after column $k: column $j',
        );
        // the whole stroke disappears, not only near the eraser
        expect(frame.at(100 + 80 * j, 440), j <= k ? _white : _bluePx);
      }
      expect(frame.at(80, 400), isNot(_white), reason: 'row stays');
      expect(session.touchedStrokeIds.length, k + 1);
    }
    final edit = session.end()!;
    expect(edit.removedIds, {for (var k = 0; k < 5; k++) 'col$k'});
    expect(controller.pendingIds, edit.removedIds);
    await tester.pump();
    final pending = await capturePixels(tester);

    // an unrelated update (another device adds a stroke) before the commit:
    // the erased strokes stay hidden
    push([...committed, other]);
    await tester.pump();
    final unrelated = await capturePixels(tester);
    for (var k = 0; k < 5; k++) {
      expect(unrelated.at(100 + 80 * k, 300), _white);
    }
    expect(unrelated.at(300, 600), _bluePx);
    expect(controller.pendingIds, edit.removedIds);

    commit(edit);
    expect(controller.pendingIds, isEmpty);
    await tester.pump();
    final after = await capturePixels(tester);
    expect(_diffCount(unrelated, after), 0, reason: 'no flicker on commit');
    // and apart from the new stroke, what pending showed
    for (final p in [const Offset(100, 300), const Offset(260, 440)]) {
      expect(
        after.at(p.dx.toInt(), p.dy.toInt()),
        pending.at(p.dx.toInt(), p.dy.toInt()),
      );
    }
  });

  testWidgets('highlighterOnly hides the highlighter only; cancel restores', (
    tester,
  ) async {
    await pumpPageView(tester, controller, width: 596);
    final before = await capturePixels(tester);
    final session = controller.beginErase(
      _at(60, 400, 0),
      spec: const EraserSpec(
        mode: EraserMode.stroke,
        radius: 4,
        filter: core.StrokeFilter.highlighterOnly,
      ),
      viewScale: 1,
    );
    session.addSample(_at(300, 400, 1));
    await tester.pump();
    final hidden = await capturePixels(tester);
    expect(session.touchedStrokeIds, {'row'});
    expect(hidden.at(80, 400), _white, reason: 'highlighter hidden');
    expect(hidden.at(100, 400), _bluePx, reason: 'pen columns stay');
    session.cancel();
    expect(controller.pendingIds, isEmpty);
    await tester.pump();
    expect(_diffCount(before, await capturePixels(tester)), 0);
  });

  testWidgets('a failed commit (discardEdit) shows the strokes again', (
    tester,
  ) async {
    await pumpPageView(tester, controller, width: 596);
    final before = await capturePixels(tester);
    final session = controller.beginErase(
      _at(90, 300, 0),
      spec: const EraserSpec(mode: EraserMode.stroke, radius: 4),
      viewScale: 1,
    );
    session.addSample(_at(200, 300, 1));
    final edit = session.end()!;
    expect(edit.removedIds, {'col0', 'col1'});
    await tester.pump();
    expect((await capturePixels(tester)).at(100, 300), _white);
    controller.discardEdit(edit);
    await tester.pump();
    expect(_diffCount(before, await capturePixels(tester)), 0);
  });

  testWidgets('partial mode (T16): only the ink inside the eraser goes; '
      'pending pieces hand over without a flicker', (tester) async {
    await pumpPageView(tester, controller, width: 596);
    // a horizontal pass along y = 300 from x 60 to 200: cuts columns 0 and 1
    final session = controller.beginErase(
      _at(60, 300, 0),
      spec: const EraserSpec(mode: EraserMode.partial, radius: 6),
      viewScale: 1,
    );
    session.addSample(_at(200, 300, 1));
    await tester.pump();
    final during = await capturePixels(tester);
    expect(during.at(100, 300), _white, reason: 'inside the eraser');
    expect(during.at(180, 300), _white);
    expect(during.at(100, 280), _bluePx, reason: 'the rest of column 0');
    expect(during.at(100, 320), _bluePx);
    expect(during.at(180, 440), _bluePx);
    expect(during.at(260, 300), _bluePx, reason: 'column 2 untouched');
    final edit = session.end()!;
    expect(edit.removedIds, {'col0', 'col1'});
    expect(edit.added, hasLength(4));
    await tester.pump();
    final pending = await capturePixels(tester);
    expect(_diffCount(during, pending), 0, reason: 'preview = pending');
    // CORE's stored copies of the pieces arrive
    push(
      [
        for (final s in committed)
          if (!edit.removedIds.contains(s.id)) s,
        for (final s in edit.added) s.copyWith(updatedAt: s.updatedAt + 1),
      ]..sort(core.Stroke.compareOrder),
    );
    expect(controller.pendingIds, isEmpty);
    await tester.pump();
    expect(_diffCount(pending, await capturePixels(tester)), 0);
  });
}
