// E-21 (integration stage, contract 7.7 step 5; 04-editor 8.2 E-21): the
// editor on the real CORE (openTestNoteStore — drift on an in-memory SQLite
// database) and the real INK, driven by synthetic pointers through the whole
// screen:
//
//   open the note → the notDurable banner (in-memory CORE = nativeMemory,
//   contract 7.2.12 / 7.6 v1.1 C11-12) → three pen strokes → the partial
//   eraser cuts two of them (one SplitStrokes) → one undo restores them →
//   lasso + drag moves the third → leave (flushAll, then onClose) → open the
//   note again from the store → the strokes, the moved position and the last
//   viewed page are kept.
//
// Screen positions come from the viewport (h.toGlobal → viewport.pageToScreen
// from the page area's origin), so nothing depends on the banner's height.
// The sentences are not compared here: the fixed-sentence check is E-00
// editor_strings_test, the two-screen check INFRA V5 (C11-24).
//
// Skipped by default: dart_test.yaml gives the `integration` tag a skip
// reason, so a plain `flutter test` / `ws test` reports this suite as skipped;
// it runs with `flutter test --run-skipped -t integration` (`ws test
// --run-skipped -t integration`). The store is opened and closed inside
// tester.runAsync, so none of its real timers (trash auto purge) is left in
// the fake-async zone; store.close() at the end.
@Tags(['integration'])
@TestOn('vm')
library;

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:feature_editor/src/ui/toolbar/undo_redo_buttons.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing_vm.dart';

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

/// The y (pt) of the three horizontal pen strokes on page 0.
const List<double> _rows = [150, 250, 350];

/// Eraser path (pt): straight down at x = 200 through the first two rows only.
const List<Offset> _eraserPath = [
  Offset(200, 110),
  Offset(200, 150),
  Offset(200, 190),
  Offset(200, 230),
  Offset(200, 270),
  Offset(200, 300),
];

/// Screen px the lassoed stroke is dragged by.
const Offset _drag = Offset(60, 40);

Rect _rectOf(core.Stroke s) =>
    Rect.fromLTRB(s.bounds.left, s.bounds.top, s.bounds.right, s.bounds.bottom);

List<core.Stroke> _strokesOn(EditorTestHandles h, int pageIndex) =>
    h.session.pageIfLoaded(h.pageId(pageIndex))!.strokes;

Set<String> _shownIds(ink.InkPageController c) => {
  for (final s in c.content!.strokes) s.id,
};

List<Offset> _pointsOf(core.Stroke s) => [
  for (var i = 0; i < s.points.length; i++)
    Offset(s.points.x(i), s.points.y(i)),
];

void _expectSamePoints(List<Offset> actual, List<Offset> expected) {
  expect(actual, hasLength(expected.length));
  for (var i = 0; i < expected.length; i++) {
    expect(actual[i].dx, closeTo(expected[i].dx, 1e-6), reason: 'x of $i');
    expect(actual[i].dy, closeTo(expected[i].dy, 1e-6), reason: 'y of $i');
  }
}

/// Pumps a fresh app (new root container) with EditorScreen for [noteId] on
/// [store] — opening the note again — and lets the pages load.
Future<void> _reopen(
  WidgetTester tester,
  EditorTestHandles h, {
  required VoidCallback onClose,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [core.noteStoreProvider.overrideWithValue(h.store)],
      child: MaterialApp(
        home: EditorScreen(
          key: ValueKey('again-${h.noteId}'),
          noteId: h.noteId,
          onClose: onClose,
        ),
      ),
    ),
  );
  await tester.pump();
  await h.settlePages();
}

void main() {
  testWidgets('real CORE + real INK: banner, pen, partial erase, undo, lasso '
      'move, leave, open again', (tester) async {
    // The store's own timers (trash auto purge) stay out of the fake-async
    // zone: open and close it inside runAsync.
    final store = (await tester.runAsync(openTestNoteStore))!;
    expect(store.storageInfo.backend, core.StorageBackend.nativeMemory);

    // --- open the note -----------------------------------------------------
    final h = await pumpEditor(
      tester,
      store: store,
      title: '통합 스모크',
      pages: 3,
      recordSession: false, // CORE's own noteSessionProvider
    );
    await tester.pump();
    expect(find.text('통합 스모크'), findsOneWidget);
    // In-memory real CORE = nativeMemory → notDurable (contract 7.2.12).
    expect(find.text(EditorStrings.storageNotDurable), findsOneWidget);
    final firstSession = h.session;
    expect(h.session.history.undoDepth, 0);

    // --- three pen strokes ------------------------------------------------
    for (final y in _rows) {
      await h.driver.stylusStroke(
        pathThrough(h, 0, [
          for (var x = 100.0; x <= 300; x += 25) Offset(x, y),
        ]),
      );
      await tester.pump();
      expect(h.session.history.undoLabel, 'add-strokes');
    }
    expect(h.session.history.undoDepth, 3);
    final drawn = _strokesOn(h, 0);
    expect(drawn, hasLength(3));
    // In drawing order; each lies on its row from x 100 to 300.
    for (var i = 0; i < 3; i++) {
      final b = drawn[i].bounds;
      expect((b.top + b.bottom) / 2, closeTo(_rows[i], 1));
      expect(b.left, lessThan(101));
      expect(b.right, greaterThan(299));
    }
    final drawnIds = [for (final s in drawn) s.id];
    final drawnPoints = {for (final s in drawn) s.id: _pointsOf(s)};
    final controller = h.controllerOf(0);
    expect(_shownIds(controller), drawnIds.toSet());
    expect(controller.pendingIds, isEmpty);

    // --- the partial eraser cuts the first two --------------------------------
    await tester.tap(find.byKey(EditorToolbar.eraserKey));
    await tester.pump();
    h.container
        .read(editorToolProvider.notifier)
        .updateEraser(
          (e) => e.copyWith(mode: ink.EraserMode.partial, diameter: 12),
        );
    await h.driver.stylusStroke(pathThrough(h, 0, _eraserPath));
    await tester.pump();
    expect(h.session.history.undoLabel, 'split-strokes');
    expect(h.session.history.undoDepth, 4);
    final cut = _strokesOn(h, 0);
    final cutIds = {for (final s in cut) s.id};
    expect(cutIds.contains(drawnIds[0]), isFalse);
    expect(cutIds.contains(drawnIds[1]), isFalse);
    expect(cutIds.contains(drawnIds[2]), isTrue);
    // Each cut stroke leaves a left and a right piece, apart at x = 200.
    final pieces = [
      for (final s in cut)
        if (s.id != drawnIds[2]) s,
    ];
    expect(pieces, hasLength(4));
    for (final row in _rows.take(2)) {
      final onRow = [
        for (final s in pieces)
          if (((s.bounds.top + s.bounds.bottom) / 2 - row).abs() < 1) s,
      ];
      expect(onRow, hasLength(2), reason: 'pieces on row $row');
      expect(onRow.where((s) => s.bounds.right < 200), hasLength(1));
      expect(onRow.where((s) => s.bounds.left > 200), hasLength(1));
    }
    expect(_shownIds(controller), cutIds);
    expect(controller.pendingIds, isEmpty);

    // --- one undo restores them ---------------------------------------------
    await tester.tap(find.byKey(UndoRedoButtons.undoKey));
    await tester.pump();
    await tester.pump();
    expect(h.session.history.undoDepth, 3);
    expect(h.session.history.canRedo, isTrue);
    final restored = _strokesOn(h, 0);
    expect([for (final s in restored) s.id], drawnIds);
    for (final s in restored) {
      _expectSamePoints(_pointsOf(s), drawnPoints[s.id]!);
    }
    expect(_shownIds(controller), drawnIds.toSet());

    // --- lasso + drag moves the third --------------------------------------
    await tester.tap(find.byKey(EditorToolbar.lassoKey));
    await tester.pump();
    final third = restored[2];
    await h.driver.stylusStroke(lassoAround(h, 0, _rectOf(third)));
    await tester.pump();
    expect(h.container.read(editorSelectionProvider)?.strokeIds, {third.id});
    expect(controller.selection?.strokeIds, {third.id});

    final scale = h.viewport.camera.scale;
    final grab = h.toGlobal(0, _rectOf(third).center);
    await h.driver.down(1, grab, kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 4; i++) {
      await h.driver.wait(const Duration(milliseconds: 8));
      await h.driver.move(1, grab + _drag * (i / 4));
    }
    await h.driver.up(1);
    await tester.pump();
    expect(h.session.history.undoLabel, 'transform');
    expect(h.session.history.undoDepth, 4);
    final moved = _strokesOn(h, 0).firstWhere((s) => s.id == third.id);
    final delta = _drag / scale;
    final expectedMoved = [for (final p in drawnPoints[third.id]!) p + delta];
    final movedPoints = _pointsOf(moved);
    expect(movedPoints, hasLength(expectedMoved.length));
    for (var i = 0; i < movedPoints.length; i++) {
      // CORE quantization unit (0.01 pt) + 0.01 pt.
      expect(movedPoints[i].dx, closeTo(expectedMoved[i].dx, 0.02));
      expect(movedPoints[i].dy, closeTo(expectedMoved[i].dy, 0.02));
    }
    // The other two did not move.
    for (final id in drawnIds.take(2)) {
      final s = _strokesOn(h, 0).firstWhere((s) => s.id == id);
      _expectSamePoints(_pointsOf(s), drawnPoints[id]!);
    }
    expect(controller.pendingIds, isEmpty);
    final beforeLeaving = {
      for (final s in _strokesOn(h, 0)) s.id: _pointsOf(s),
    };

    // The last viewed position: page 1.
    await tester.tap(find.byKey(EditorToolbar.penKey));
    await tester.pump();
    await h.viewport.jumpToPage(1, animate: false);
    await tester.pump(const Duration(milliseconds: 200));
    expect(h.viewport.currentPageIndex.value, 1);
    final zoom = h.viewport.zoom;

    // --- leave: flushAll, then onClose ----------------------------------
    await tester.tap(find.byKey(EditorToolbar.backKey));
    for (var i = 0; i < 20 && h.closeCount == 0; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    expect(h.closeCount, 1);
    expect(store.persistenceStatus.pendingOps, 0);

    // The app drops the screen: the session closes and frees its pages.
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 5 && !firstSession.isClosed; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    expect(firstSession.isClosed, isTrue);

    // --- open the note again from the store -------------------------------
    var closedAgain = 0;
    await _reopen(tester, h, onClose: () => closedAgain++);
    expect(identical(h.session, firstSession), isFalse);
    expect(find.text(EditorStrings.storageNotDurable), findsOneWidget);
    expect(h.viewport.currentPageIndex.value, 1);
    expect(h.viewport.zoom, closeTo(zoom, 1e-9));
    expect(h.session.history.undoDepth, 0);

    await h.viewport.jumpToPage(0, animate: false);
    await tester.pump(const Duration(milliseconds: 200));
    await h.settlePages();
    final reopened = _strokesOn(h, 0);
    expect([for (final s in reopened) s.id], drawnIds);
    for (final s in reopened) {
      _expectSamePoints(_pointsOf(s), beforeLeaving[s.id]!);
    }
    expect(_shownIds(h.controllerOf(0)), drawnIds.toSet());

    await tester.tap(find.byKey(EditorToolbar.backKey));
    for (var i = 0; i < 20 && closedAgain == 0; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    expect(closedAgain, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(store.close);
  });
}
