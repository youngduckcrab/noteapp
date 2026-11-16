// E2-21b (P-B, m5-7/04-editor 8.3 — INK T39 and E2-15 are both merged):
// the auto shape on the real CORE (openTestNoteStore) and the real INK's
// hold detection (03-ink 6.18: InkTuning.shapeHoldMs within
// shapeHoldRadiusPx of the anchor; with no new samples a timer armed at the
// anchor fires the hold) wired through the editor (E2-15):
//
//   inkShapeFitterProvider = INK FakeInkShapeFitter(fit: a rectangle) → the
//   pen draws SyntheticInk.loopThenHold's loop through the pointer, then
//   holds still past shapeHoldMs (600 ms of fake time, review S-4) → lift →
//   content.objects has ONE ShapeObject (rectangle) and no stroke, undoDepth
//   +1 (one step) → undo → no shape and no stroke (the original stroke is
//   never stored — 7.2.3) → redo → the shape → leave, open again → the
//   shape is kept.
// (v2.12, C212-01) After the snap the pen stays down and drags: the loop
// ends at the top middle, so only the top edge follows the pen (from where it
// left the dead zone) and the bottom edge stays → lift → ONE ShapeObject with
// the adjusted rectangle, one undo step → undo → nothing.
//
// Skipped by default (dart_test.yaml `integration` skip); runs with
// `ws test --run-skipped -t integration --package feature_editor`.
@Tags(['integration'])
@TestOn('vm')
library;

import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:feature_editor/src/ui/toolbar/undo_redo_buttons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart' as ink_testing;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing_vm.dart';

import '../helpers/pump_editor.dart';

/// The page rect (pt) the loop is drawn in and the fake fit returns.
const Rect _box = Rect.fromLTRB(150, 200, 350, 320);

Future<void> _flush(WidgetTester tester, [int rounds = 3]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

core.PageContent _page(EditorTestHandles h) =>
    h.session.pageIfLoaded(h.pageId(0))!;

Future<void> _leave(WidgetTester tester, bool Function() closed) async {
  await tester.tap(find.byKey(EditorToolbar.backKey));
  for (var i = 0; i < 30 && !closed(); i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
  expect(closed(), isTrue);
}

void main() {
  testWidgets('real CORE + real INK hold: loop + 600 ms still → ONE '
      'rectangle, no stroke, one undo step → undo → redo → reopen', (
    tester,
  ) async {
    final store = (await tester.runAsync(openTestNoteStore))!;
    final geometry = core.ShapeGeometry.rectangle(
      core.PageRect(_box.left, _box.top, _box.right, _box.bottom),
    );
    final fitter = ink_testing.FakeInkShapeFitter(
      fit: ink.InkShapeFit(
        kind: core.ShapeKind.rectangle,
        geometry: geometry,
        score: 0.95,
      ),
    );
    final h = await pumpEditor(
      tester,
      store: store,
      title: '자동 도형 스모크',
      pages: 2,
      overrides: [ink.inkShapeFitterProvider.overrideWithValue(fitter)],
      recordSession: false,
    );
    await _flush(tester, 2);
    final firstSession = h.session;
    expect(_page(h).strokes, isEmpty);
    expect(_page(h).objects, isEmpty);
    expect(h.session.history.undoDepth, 0);

    // --- the loop through the pointer, then a still hold ---------------------
    final samples = ink_testing.SyntheticInk.loopThenHold(
      bounds: _box,
      holdMs: 0,
    );
    final points = [for (final s in samples) h.toGlobal(0, s.position)];
    await h.driver.down(1, points.first, kind: PointerDeviceKind.stylus);
    for (final p in points.skip(1)) {
      await h.driver.wait(const Duration(milliseconds: 8));
      await h.driver.move(1, p);
    }
    // Still: no new samples; INK's timer armed at the anchor fires the hold.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(fitter.calls, greaterThanOrEqualTo(1));
    await h.driver.up(1);
    await _flush(tester, 2);

    expect(_page(h).strokes, isEmpty, reason: 'the stroke became the shape');
    final shapes = _page(h).objects.whereType<core.ShapeObject>().toList();
    expect(_page(h).objects, hasLength(1));
    expect(shapes.single.shapeKind, core.ShapeKind.rectangle);
    expect(shapes.single.geometry, geometry);
    expect(h.session.history.undoDepth, 1);
    expect(h.session.history.undoLabel, 'add-objects');
    final shapeId = shapes.single.id;
    expect(h.controllerOf(0).content!.objects.map((o) => o.id), [shapeId]);
    expect(h.controllerOf(0).content!.strokes, isEmpty);

    // --- undo: nothing (the original stroke was never stored) ---------------
    await tester.tap(find.byKey(UndoRedoButtons.undoKey));
    await _flush(tester, 2);
    expect(h.session.history.undoDepth, 0);
    expect(h.session.history.canUndo, isFalse);
    expect(_page(h).objects, isEmpty);
    expect(_page(h).strokes, isEmpty);

    // --- redo: the shape --------------------------------------------------
    await tester.tap(find.byKey(UndoRedoButtons.redoKey));
    await _flush(tester, 2);
    expect(h.session.history.undoDepth, 1);
    expect([for (final o in _page(h).objects) o.id], [shapeId]);
    expect(_page(h).strokes, isEmpty);

    // --- leave, open again ------------------------------------------------
    await _leave(tester, () => h.closeCount > 0);
    expect(store.persistenceStatus.pendingOps, 0);
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 5 && !firstSession.isClosed; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    expect(firstSession.isClosed, isTrue);
    var closedAgain = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [core.noteStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: EditorScreen(
            key: ValueKey('again-${h.noteId}'),
            noteId: h.noteId,
            onClose: () => closedAgain++,
          ),
        ),
      ),
    );
    await tester.pump();
    await h.settlePages();
    await _flush(tester, 2);
    expect(identical(h.session, firstSession), isFalse);
    expect(h.session.history.undoDepth, 0);
    final reopened = _page(h);
    expect(reopened.strokes, isEmpty);
    expect([for (final o in reopened.objects) o.id], [shapeId]);
    expect(
      (reopened.objects.single as core.ShapeObject).shapeKind,
      core.ShapeKind.rectangle,
    );

    await _leave(tester, () => closedAgain > 0);
    await tester.pumpWidget(const SizedBox());
    var closed = false;
    unawaited(store.close().then((_) => closed = true));
    for (var i = 0; i < 50 && !closed; i++) {
      await _flush(tester, 1);
    }
    expect(closed, isTrue);
  });

  testWidgets('(C212-01) real CORE + real INK: loop + hold, then drag '
      'before the lift → ONE adjusted rectangle, one undo step', (
    tester,
  ) async {
    final store = (await tester.runAsync(openTestNoteStore))!;
    final fitter = ink_testing.FakeInkShapeFitter(
      fit: ink.InkShapeFit(
        kind: core.ShapeKind.rectangle,
        geometry: core.ShapeGeometry.rectangle(
          core.PageRect(_box.left, _box.top, _box.right, _box.bottom),
        ),
        score: 0.95,
      ),
    );
    final h = await pumpEditor(
      tester,
      store: store,
      title: '도형 조절 스모크',
      overrides: [ink.inkShapeFitterProvider.overrideWithValue(fitter)],
      recordSession: false,
    );
    await _flush(tester, 2);
    final samples = ink_testing.SyntheticInk.loopThenHold(
      bounds: _box,
      holdMs: 0,
    );
    final points = [for (final s in samples) h.toGlobal(0, s.position)];
    await h.driver.down(1, points.first, kind: PointerDeviceKind.stylus);
    for (final p in points.skip(1)) {
      await h.driver.wait(const Duration(milliseconds: 8));
      await h.driver.move(1, p);
    }
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(fitter.calls, 1);
    // out of the dead zone 40 pt up (the shape starts following there), then
    // 40 pt down in steps, then lift
    final end = samples.last.position;
    await h.driver.wait(const Duration(milliseconds: 8));
    await h.driver.move(1, h.toGlobal(0, end + const Offset(0, -40)));
    for (var k = 1; k <= 8; k++) {
      await h.driver.wait(const Duration(milliseconds: 8));
      await h.driver.move(1, h.toGlobal(0, end + Offset(0, -40 + 5.0 * k)));
    }
    await h.driver.up(1);
    await _flush(tester, 2);

    expect(fitter.calls, 1, reason: 'no refit while adjusting');
    expect(_page(h).strokes, isEmpty);
    final shape = _page(h).objects.single as core.ShapeObject;
    expect(shape.shapeKind, core.ShapeKind.rectangle);
    final expected = core.ShapeGeometry.rectangle(
      core.PageRect(_box.left, _box.top + 40, _box.right, _box.bottom),
    ).points;
    final got = (shape.geometry as core.PolylineGeometry).points;
    expect(got, hasLength(4));
    for (var i = 0; i < 4; i++) {
      expect(got[i].x, closeTo(expected[i].x, 0.01), reason: 'x$i');
      expect(got[i].y, closeTo(expected[i].y, 0.01), reason: 'y$i');
    }
    expect(h.session.history.undoDepth, 1);
    await tester.tap(find.byKey(UndoRedoButtons.undoKey));
    await _flush(tester, 2);
    expect(_page(h).objects, isEmpty);
    expect(_page(h).strokes, isEmpty);

    await _leave(tester, () => h.closeCount > 0);
    await tester.pumpWidget(const SizedBox());
    var closed = false;
    unawaited(store.close().then((_) => closed = true));
    for (var i = 0; i < 50 && !closed; i++) {
      await _flush(tester, 1);
    }
    expect(closed, isTrue);
  });
}
