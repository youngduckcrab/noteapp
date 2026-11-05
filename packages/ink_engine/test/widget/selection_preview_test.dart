// T18 (03-ink 6.22 미리보기, 6.12 R7): while a selection is moved / resized
// / rotated its strokes leave their old place and are drawn under the
// preview transform. A similarity (move, corner keeping the aspect,
// rotation) draws ONE picture recorded at the identity through the matrix; an
// edge handle (or a width limit) records the CORE-transformed strokes again,
// within the frame budget (the last picture, corrected by a matrix, fills the
// frames in between). After the commit's updateContent the page differs from
// the preview by < 1 % of its pixels.
import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show selectionPreviewStatsOf;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/page_view.dart';
import '../support/pixels.dart';

const _white = [255, 255, 255, 255];
const _bluePx = [0, 0, 255, 255];

final _blue = core.StrokeStyle.defaultsFor(core.PenTool.ballpoint)
    .copyWith(colorArgb: 0xFF0000FF, width: 4);

/// One frame per call of nowUs() (1 ms each).
final class _TickingClock implements InkClock {
  int us = 0;
  @override
  int nowUs() => us += 1000;
  @override
  bool get alignedWithEventTimestamps => true;
}

int _diffCount(Pixels a, Pixels b, {int tol = 8}) {
  expect((a.width, a.height), (b.width, b.height));
  var n = 0;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      if (!samePixel(a.at(x, y), b.at(x, y), tol: tol)) n++;
    }
  }
  return n;
}

int _inkCount(Pixels p) {
  var n = 0;
  for (var y = 0; y < p.height; y++) {
    for (var x = 0; x < p.width; x++) {
      if (!samePixel(p.at(x, y), _white, tol: 8)) n++;
    }
  }
  return n;
}

/// The commit frame differs from the last preview frame on < 1 % of the
/// page's pixels (channel tolerance 8), and only at anti-aliased edges (no
/// pixel by 96 or more: the shape does not jump).
void _expectSameShape(Pixels preview, Pixels committed) {
  final diff = _diffCount(preview, committed);
  expect(
    diff / (preview.width * preview.height),
    lessThan(0.01),
    reason: '$diff px differ',
  );
  expect(_diffCount(preview, committed, tol: 96), 0);
}

void main() {
  late InkPageController controller;
  late List<core.Stroke> committed;
  var revision = 1;

  /// Rows a, b (selected) and c (not): blue, 4 pt.
  List<core.Stroke> rows({int count = 2, core.StrokeStyle? style}) => [
    for (var k = 0; k < count; k++)
      strokeThrough(
        segment(
          Offset(60, 100.0 + 30 * k),
          Offset(160, 100.0 + 30 * k + (k.isOdd ? 12 : 0)),
        ),
        style ?? _blue,
        id: 'r$k',
        createdAt: 2000 + k,
      ),
    strokeThrough(
      segment(const Offset(60, 330), const Offset(160, 330)),
      _blue,
      id: 'c',
      createdAt: 1000,
    ),
  ];

  void push(List<core.Stroke> strokes) {
    committed = strokes;
    controller.updateContent(
      SyntheticInk.pageContent(
        strokes: strokes,
        size: const core.PageSize(400, 400),
        revision: ++revision,
      ),
    );
  }

  /// EDITOR after a successful execute of a transform commit.
  void commitTransform(InkSelection sel) {
    final edit = sel.commitTransform()!;
    final m = edit.transform!;
    push([
      for (final s in committed)
        edit.targetIds.contains(s.id) ? s.transformed(m) : s,
    ]);
    expect(controller.pendingIds, isEmpty);
  }

  Future<void> pump(WidgetTester tester) => pumpPageView(
    tester,
    controller,
    width: 400,
    surface: const Size(420, 420),
  );

  void setUpController({InkClock? clock, double budgetMs = 4}) {
    controller = createTestPageController(
      clock: clock,
      config: InkRenderConfig(rasterTiles: false, frameWorkBudgetMs: budgetMs),
    );
    revision = 1;
    push(rows());
  }

  tearDown(() => controller.dispose());

  testWidgets('move: nothing at the old place, the strokes at the new one; '
      'one identity picture through the matrix', (tester) async {
    setUpController();
    await pump(tester);
    final before = await capturePixels(tester);
    expect(before.at(110, 100), _bluePx);
    final sel = controller.select({'r0', 'r1'});
    for (var k = 1; k <= 6; k++) {
      sel.setPreviewTransform(SelectionGeometry.move(Offset(25.0 * k, 0)));
      await tester.pump();
    }
    final px = await capturePixels(tester);
    expect(px.at(110, 100), _white, reason: 'old place');
    expect(px.at(90, 106), _white);
    expect(px.at(260, 100), _bluePx, reason: '150 pt to the right');
    expect(px.at(110, 330), _bluePx, reason: 'c stays');
    final stats = selectionPreviewStatsOf(controller);
    expect(stats.identityRecords, 1);
    expect(stats.exactRecords, 0);
    expect(stats.matrixFrames, greaterThanOrEqualTo(6));

    commitTransform(sel);
    await tester.pump();
    final after = await capturePixels(tester);
    expect(after.at(110, 100), _white);
    expect(after.at(260, 100), _bluePx);
    _expectSameShape(px, after);
  });

  for (final (name, transformOf) in <(String, core.Affine2 Function(Rect))>[
    (
      'corner keeping the aspect',
      (b) => SelectionGeometry.resize(
        bounds: b,
        handle: SelectionHandle.bottomRight,
        delta: const Offset(60, 20),
      ),
    ),
    (
      'rotation',
      (b) => SelectionGeometry.rotate(bounds: b, radians: math.pi / 5),
    ),
    (
      'shrinking corner',
      (b) => SelectionGeometry.resize(
        bounds: b,
        handle: SelectionHandle.topLeft,
        delta: const Offset(40, 10),
      ),
    ),
  ]) {
    testWidgets('$name = matrix preview; commit differs < 1 %', (tester) async {
      setUpController();
      await pump(tester);
      final sel = controller.select({'r0', 'r1'});
      final m = transformOf(sel.bounds);
      // a few frames of the drag, ending at m
      for (final f in [0.3, 0.6, 1.0]) {
        sel.setPreviewTransform(
          f == 1.0
              ? m
              : core.Affine2(
                  1 + (m.a - 1) * f,
                  m.b * f,
                  m.c * f,
                  1 + (m.d - 1) * f,
                  m.tx * f,
                  m.ty * f,
                ),
        );
        await tester.pump();
      }
      final preview = await capturePixels(tester);
      final stats = selectionPreviewStatsOf(controller);
      expect(stats.identityRecords, 1);
      expect(stats.exactRecords, 0);
      expect(stats.matrixFrames, greaterThanOrEqualTo(3));

      commitTransform(sel);
      await tester.pump();
      final after = await capturePixels(tester);
      _expectSameShape(preview, after);
      expect(_inkCount(after), greaterThan(200));
    });
  }

  testWidgets('edge handle: recorded again (exact), only when m changes; '
      'commit differs < 1 %', (tester) async {
    setUpController();
    await pump(tester);
    final sel = controller.select({'r0', 'r1'});
    final bounds = sel.bounds;
    core.Affine2 edge(double dx) => SelectionGeometry.resize(
      bounds: bounds,
      handle: SelectionHandle.right,
      delta: Offset(dx, 0),
    );
    for (final dx in [20.0, 60.0, 120.0]) {
      sel.setPreviewTransform(edge(dx));
      await tester.pump();
    }
    var stats = selectionPreviewStatsOf(controller);
    expect(stats.exactRecords, 3);
    expect(stats.matrixFrames, 0);
    // an unrelated repaint with the same m draws the recorded picture
    push([...committed]);
    await tester.pump();
    stats = selectionPreviewStatsOf(controller);
    expect(stats.exactRecords, 3);
    expect(stats.exactFrames, greaterThanOrEqualTo(4));
    final preview = await capturePixels(tester);
    // stretched to the right: x 60 → 160 becomes 60 → ~280
    expect(preview.at(250, 100), _bluePx);
    expect(preview.at(110, 330), _bluePx);

    commitTransform(sel);
    await tester.pump();
    final after = await capturePixels(tester);
    _expectSameShape(preview, after);
  });

  testWidgets('a width limit makes even a similarity exact', (tester) async {
    controller = createTestPageController();
    revision = 1;
    push(rows(style: _blue.copyWith(width: 20)));
    await pump(tester);
    final sel = controller.select({'r0', 'r1'});
    // × 2: width 40 > 30 → CORE clamps it, so no matrix picture
    sel.setPreviewTransform(
      core.Affine2.scaling(2, 2, originX: 60, originY: 100),
    );
    await tester.pump();
    final stats = selectionPreviewStatsOf(controller);
    expect(stats.matrixFrames, 0);
    expect(stats.exactRecords, 1);
  });

  testWidgets('over the frame budget: corrected frames, finished later', (
    tester,
  ) async {
    // every nowUs() call takes 1 ms; budget 2 ms → about 2 strokes per frame
    setUpController(clock: _TickingClock(), budgetMs: 2);
    push(rows(count: 10));
    await pump(tester);
    final sel = controller.select({for (var k = 0; k < 10; k++) 'r$k'});
    final m = SelectionGeometry.resize(
      bounds: sel.bounds,
      handle: SelectionHandle.bottom,
      delta: const Offset(0, -60),
    );
    sel.setPreviewTransform(m);
    await tester.pump();
    var stats = selectionPreviewStatsOf(controller);
    expect(stats.exactRecords, 0);
    expect(stats.correctedFrames, 1);
    // the frames ask for themselves until the recording is finished
    for (var i = 0; i < 20 && stats.exactRecords == 0; i++) {
      await tester.pump();
      stats = selectionPreviewStatsOf(controller);
    }
    expect(stats.exactRecords, 1);
    expect(stats.correctedFrames, greaterThan(1));
    final framesBefore = stats.correctedFrames + stats.exactFrames;
    await tester.pump();
    stats = selectionPreviewStatsOf(controller);
    expect(
      stats.correctedFrames + stats.exactFrames,
      framesBefore,
      reason: 'no more frames once finished',
    );
    final preview = await capturePixels(tester);

    commitTransform(sel);
    await tester.pump();
    final after = await capturePixels(tester);
    _expectSameShape(preview, after);
  });

  testWidgets('clearing the selection ends the preview (old place again)', (
    tester,
  ) async {
    setUpController();
    await pump(tester);
    final before = await capturePixels(tester);
    final sel = controller.select({'r0'});
    sel.setPreviewTransform(SelectionGeometry.move(const Offset(100, 50)));
    await tester.pump();
    expect((await capturePixels(tester)).at(110, 100), _white);
    controller.clearSelection();
    await tester.pump();
    expect(_diffCount(before, await capturePixels(tester), tol: 1), 0);
  });
}
