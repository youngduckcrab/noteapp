// E-09: the eraser through the whole editor (04-editor 6.6.2, 6.6.4, 6.6.9, 6.7):
// PointerDriver → Listener → InputRouter → InteractionHost → EraseInteraction →
// B3 INK EraserSession → EditorCommands.commitInkEdit → fake CORE session, and
// clearing the current page (confirmation dialog → core.ClearPage).
//
// B3 INK erases by bounds (stroke and partial mode alike, contract 7.6 B3), so
// a partial erase commits RemoveStrokes here and SplitStrokes with the real INK;
// the assertions accept either where the mode is partial.
import 'dart:ui' show Rect;

import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/tools/erase_interaction.dart';
import 'package:feature_editor/src/tools/interaction_host.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/eraser/eraser_popup.dart';
import 'package:feature_editor/src/viewport/page_viewport.dart';
import 'package:feature_editor/src/viewport/viewport_constants.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

/// Page-0 fixtures: strokeA (y 150), highlighterStroke (y 300), strokeB (y 400).
const Map<int, List<core.Stroke>> _noStrokes = {};
Map<int, List<core.Stroke>> get _threeStrokes => {
  0: [strokeA, highlighterStroke, strokeB],
};

/// A vertical eraser path at x = 150 pt from y 100 to 450: crosses all three.
List<Offset> _acrossAll(EditorTestHandles h) =>
    pathThrough(h, 0, [for (var y = 100.0; y <= 450; y += 25) Offset(150, y)]);

/// A vertical path at x = 150 pt from y 100 to 320: crosses strokeA and the
/// highlighter stroke only.
List<Offset> _acrossAAndHighlighter(EditorTestHandles h) =>
    pathThrough(h, 0, [for (var y = 100.0; y <= 320; y += 20) Offset(150, y)]);

List<String> _commands(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute') || c.startsWith('undo')) c,
];

Set<String> _coreIds(EditorTestHandles h) => {
  for (final s in h.session.pageIfLoaded(h.pageId(0))!.strokes) s.id,
};

Set<String> _shownIds(ink.InkPageController c) => {
  for (final s in c.content!.strokes) s.id,
};

/// True when INK displays stroke [id] (not pending removal): a hit test at a
/// point of the stroke finds it, and it is among the strokes in its bounds.
bool _displayed(ink.InkPageController c, core.Stroke stroke) {
  final p = Offset(stroke.points.x(1), stroke.points.y(1));
  final hit = c.hitTest(p, tolerance: 0.5);
  return hit?.id == stroke.id &&
      c
          .strokeIdsInRect(Rect.fromCircle(center: p, radius: 0.5))
          .contains(stroke.id);
}

ToolController _tools(EditorTestHandles h) =>
    h.container.read(editorToolProvider.notifier);

void _useEraser(
  EditorTestHandles h, {
  ink.EraserMode mode = ink.EraserMode.stroke,
  double diameter = 12,
  core.StrokeFilter filter = core.StrokeFilter.all,
  bool returnToPreviousTool = false,
}) {
  _tools(h)
    ..selectTool(EditorTool.eraser)
    ..updateEraser(
      (e) => e.copyWith(
        mode: mode,
        diameter: diameter,
        filter: filter,
        returnToPreviousTool: returnToPreviousTool,
      ),
    );
}

void main() {
  for (final mode in ink.EraserMode.values) {
    testWidgets(
      '${mode.name} mode: across several strokes → one command, one undo '
      'restores them all',
      (tester) async {
        final h = await pumpEditor(tester, strokesByPageIndex: _threeStrokes);
        _useEraser(h, mode: mode);
        await h.driver.stylusStroke(_acrossAll(h));

        final executes = _commands(h);
        expect(executes, hasLength(1));
        if (mode == ink.EraserMode.stroke) {
          expect(executes.single, 'execute:remove-strokes');
        } else {
          expect(
            executes.single,
            anyOf('execute:remove-strokes', 'execute:split-strokes'),
          );
        }
        expect(h.session.history.undoDepth, 1);
        expect(h.session.history.undoLabel, executes.single.substring(8));
        expect(
          _coreIds(h)
              .intersection({strokeA.id, strokeB.id, highlighterStroke.id}),
          isEmpty,
        );
        final controller = h.controllerOf(0);
        expect(controller.pendingIds, isEmpty);
        expect(controller.activeSession, isNull);
        expect(h.recorder!.executeDuringDelivery, isFalse);

        await h.container.read(editorCommandsProvider).undo();
        await tester.pump();
        expect(_commands(h).last, 'undo');
        expect(_coreIds(h), {strokeA.id, strokeB.id, highlighterStroke.id});
        expect(h.session.history.undoDepth, 0);
        expect(_shownIds(controller), _coreIds(h));
        expect(controller.pendingIds, isEmpty);
      },
    );
  }

  testWidgets(
    'radius = diameter / 2 pt: a stroke d pt from the path goes with 2d + 1, '
    'stays with 2d − 1, at any zoom',
    (tester) async {
      // A thin horizontal stroke (0.1 pt) so its width does not matter.
      final thin = lineStroke(
        id: 'thin',
        x0: 150,
        y0: 300,
        x1: 300,
        y1: 300,
        width: 0.1,
        createdAt: 1,
      );
      final h = await pumpEditor(
        tester,
        strokesByPageIndex: {
          0: [thin],
        },
      );
      const d = 10.0;
      // The eraser path runs parallel to the stroke, d pt above it.
      List<Offset> path() => pathThrough(h, 0, [
        for (var x = 150.0; x <= 300; x += 15) Offset(x, 300 - d),
      ]);
      final commands = h.container.read(editorCommandsProvider);

      Future<void> check() async {
        _useEraser(h, diameter: 2 * d - 1);
        await h.driver.stylusStroke(path());
        expect(_commands(h).where((c) => c.startsWith('execute')), isEmpty);
        expect(_coreIds(h), {'thin'});

        _useEraser(h, diameter: 2 * d + 1);
        await h.driver.stylusStroke(path());
        expect(_commands(h).where((c) => c.startsWith('execute')), [
          'execute:remove-strokes',
        ]);
        expect(_coreIds(h), isEmpty);

        await commands.undo();
        await tester.pump();
        expect(_coreIds(h), {'thin'});
        h.recorder!.clearCalls();
      }

      await check(); // fit width
      final fit = h.viewport.camera.scale;

      // Zoomed in ×2.5 around the stroke.
      final focal = h.viewport.pageToScreen(0, const Offset(225, 295));
      h.viewport.zoomBy(2.5, focal);
      await tester.pump(ViewportConstants.settleDelay * 2);
      await h.settlePages();
      expect(h.viewport.camera.scale, closeTo(fit * 2.5, 1e-9));
      await check();

      // Zoomed out to half the fit scale.
      h.viewport.zoomBy(0.2, focal);
      await tester.pump(ViewportConstants.settleDelay * 2);
      await h.settlePages();
      expect(h.viewport.camera.scale, lessThan(fit));
      await check();
    },
  );

  testWidgets('the filter reaches INK: highlighter only / except highlighter', (
    tester,
  ) async {
    final h = await pumpEditor(tester, strokesByPageIndex: _threeStrokes);
    final commands = h.container.read(editorCommandsProvider);

    _useEraser(h, filter: core.StrokeFilter.highlighterOnly);
    await h.driver.stylusStroke(_acrossAAndHighlighter(h));
    expect(_coreIds(h), {strokeA.id, strokeB.id}); // the ballpoint stays
    expect(h.session.history.undoDepth, 1);

    await commands.undo();
    await tester.pump();
    expect(_coreIds(h), {strokeA.id, strokeB.id, highlighterStroke.id});

    _useEraser(h, filter: core.StrokeFilter.exceptHighlighter);
    await h.driver.stylusStroke(_acrossAAndHighlighter(h));
    expect(_coreIds(h), {strokeB.id, highlighterStroke.id});
  });

  testWidgets('nothing touched → no command', (tester) async {
    final h = await pumpEditor(tester, strokesByPageIndex: _threeStrokes);
    _useEraser(h, returnToPreviousTool: true);
    await h.driver.stylusStroke(
      pathThrough(h, 0, [
        for (var x = 100.0; x <= 400; x += 50) Offset(x, 650),
      ]),
    );
    expect(_commands(h), isEmpty);
    expect(h.session.history.undoDepth, 0);
    final controller = h.controllerOf(0);
    expect(controller.pendingIds, isEmpty);
    expect(controller.activeSession, isNull);
    // No commit → no return to the previous tool.
    expect(h.container.read(editorToolProvider).activeTool, EditorTool.eraser);
  });

  testWidgets('a cancelled erase runs no command and shows every stroke', (
    tester,
  ) async {
    final h = await pumpEditor(tester, strokesByPageIndex: _threeStrokes);
    _useEraser(h, mode: ink.EraserMode.partial, returnToPreviousTool: true);
    final points = _acrossAll(h);
    await h.driver.down(1, points.first, kind: PointerDeviceKind.stylus);
    for (final p in points.skip(1)) {
      await h.driver.wait(const Duration(milliseconds: 4));
      await h.driver.move(1, p);
    }
    final controller = h.controllerOf(0);
    final erase = controller.activeSession! as ink.EraserSession;
    expect(erase.touchedStrokeIds, {
      strokeA.id,
      strokeB.id,
      highlighterStroke.id,
    });
    expect(erase.spec.mode, ink.EraserMode.partial);

    await h.driver.cancel(1);
    expect(_commands(h), isEmpty);
    expect(controller.pendingIds, isEmpty);
    expect(controller.activeSession, isNull);
    for (final s in [strokeA, strokeB, highlighterStroke]) {
      expect(_displayed(controller, s), isTrue, reason: s.id);
    }
    expect(_coreIds(h), {strokeA.id, strokeB.id, highlighterStroke.id});
    expect(h.container.read(editorToolProvider).activeTool, EditorTool.eraser);
  });

  testWidgets('a committed erase returns to the previous tool when asked', (
    tester,
  ) async {
    final h = await pumpEditor(tester, strokesByPageIndex: _threeStrokes);
    EditorTool active() => h.container.read(editorToolProvider).activeTool;

    // Pen → eraser (return on) → erase → pen.
    _useEraser(h, returnToPreviousTool: true);
    await h.driver.stylusStroke(
      pathThrough(h, 0, [const Offset(150, 130), const Offset(150, 170)]),
    );
    expect(_coreIds(h), isNot(contains(strokeA.id)));
    expect(active(), EditorTool.pen);

    // Lasso → eraser (return on) → erase → lasso.
    _tools(h).selectTool(EditorTool.lasso);
    _useEraser(h, returnToPreviousTool: true);
    await h.driver.stylusStroke(
      pathThrough(h, 0, [const Offset(150, 380), const Offset(150, 420)]),
    );
    expect(_coreIds(h), isNot(contains(strokeB.id)));
    expect(active(), EditorTool.lasso);

    // Return off → the eraser stays.
    _useEraser(h);
    await h.driver.stylusStroke(
      pathThrough(h, 0, [const Offset(150, 280), const Offset(150, 320)]),
    );
    expect(_coreIds(h), isEmpty);
    expect(active(), EditorTool.eraser);
  });

  for (final mode in ink.EraserMode.values) {
    testWidgets(
      '${mode.name} mode: a rejected commit (read-only race) → discardEdit, '
      'the strokes show again, no return to the previous tool',
      (tester) async {
        final h = await pumpEditor(tester, strokesByPageIndex: _threeStrokes);
        _useEraser(h, mode: mode, returnToPreviousTool: true);
        h.recorder!.rejectNext(const core.ReadOnlyNoteException('race'));

        await h.driver.stylusStroke(_acrossAll(h));
        await tester.pump(); // snackbar entrance

        final executes = _commands(h);
        expect(executes, hasLength(1));
        expect(executes.single, endsWith(':rejected'));
        final controller = h.controllerOf(0);
        expect(controller.pendingIds, isEmpty);
        expect(controller.activeSession, isNull);
        expect(_shownIds(controller), {
          strokeA.id,
          strokeB.id,
          highlighterStroke.id,
        });
        for (final s in [strokeA, strokeB, highlighterStroke]) {
          expect(_displayed(controller, s), isTrue, reason: s.id);
        }
        expect(_coreIds(h), {strokeA.id, strokeB.id, highlighterStroke.id});
        expect(h.session.history.undoDepth, 0);
        expect(
          h.container.read(editorToolProvider).activeTool,
          EditorTool.eraser,
        );
        expect(find.text(EditorStrings.readOnlyToast), findsOneWidget);

        // The next erase commits normally (and returns to the pen).
        await h.driver.stylusStroke(_acrossAll(h));
        expect(h.session.history.undoDepth, 1);
        expect(h.container.read(editorToolProvider).activeTool, EditorTool.pen);
        await tester.pump(const Duration(seconds: 5)); // snackbar timer
      },
    );
  }

  group('clear the current page', () {
    Future<bool> openDialog(WidgetTester tester, EditorTestHandles h) {
      final result = confirmClearCurrentPage(
        tester.element(find.byType(PageViewport)),
        commands: h.container.read(editorCommandsProvider),
        filter: h.container.read(editorToolProvider).eraser.filter,
      );
      return result;
    }

    Future<void> settleDialog(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('confirm → one clear-page step on the current page', (
      tester,
    ) async {
      final h = await pumpEditor(tester, strokesByPageIndex: _threeStrokes);
      final done = openDialog(tester, h);
      await settleDialog(tester);
      expect(find.text(EditorStrings.clearPageTitle), findsOneWidget);
      expect(find.text(EditorStrings.clearPageBody), findsOneWidget);

      await tester.tap(find.byKey(ClearPageDialog.confirmKey));
      await settleDialog(tester);
      expect(await done, isTrue);
      expect(find.byType(ClearPageDialog), findsNothing);

      expect(_commands(h), ['executeAsync:clear-page']);
      expect(h.session.history.undoDepth, 1);
      expect(h.session.history.undoLabel, 'clear-page');
      expect(_coreIds(h), isEmpty);
      expect(h.controllerOf(0).content!.strokes, isEmpty);

      await h.container.read(editorCommandsProvider).undo();
      await tester.pump();
      expect(_coreIds(h), {strokeA.id, strokeB.id, highlighterStroke.id});
    });

    testWidgets('the eraser filter words the dialog and reaches ClearPage', (
      tester,
    ) async {
      final h = await pumpEditor(tester, strokesByPageIndex: _threeStrokes);
      _useEraser(h, filter: core.StrokeFilter.highlighterOnly);
      var done = openDialog(tester, h);
      await settleDialog(tester);
      expect(
        find.text(EditorStrings.clearPageTitleHighlighterOnly),
        findsOneWidget,
      );
      await tester.tap(find.byKey(ClearPageDialog.confirmKey));
      await settleDialog(tester);
      expect(await done, isTrue);
      expect(_coreIds(h), {strokeA.id, strokeB.id});
      expect(h.session.history.undoDepth, 1);

      _useEraser(h, filter: core.StrokeFilter.exceptHighlighter);
      done = openDialog(tester, h);
      await settleDialog(tester);
      expect(
        find.text(EditorStrings.clearPageTitleExceptHighlighter),
        findsOneWidget,
      );
      await tester.tap(find.byKey(ClearPageDialog.confirmKey));
      await settleDialog(tester);
      expect(await done, isTrue);
      expect(_coreIds(h), isEmpty);
      expect(h.session.history.undoDepth, 2);
    });

    testWidgets('cancel → no command', (tester) async {
      final h = await pumpEditor(tester, strokesByPageIndex: _threeStrokes);
      final done = openDialog(tester, h);
      await settleDialog(tester);
      await tester.tap(find.byKey(ClearPageDialog.cancelKey));
      await settleDialog(tester);
      expect(await done, isFalse);
      expect(_commands(h), isEmpty);
      expect(_coreIds(h), {strokeA.id, strokeB.id, highlighterStroke.id});
    });

    testWidgets('the current page is the one cleared', (tester) async {
      final h = await pumpEditor(
        tester,
        pages: 3,
        strokesByPageIndex: {
          0: [strokeA],
          1: [strokeB],
        },
      );
      await h.viewport.jumpToPage(1, animate: false);
      await tester.pump(ViewportConstants.settleDelay * 2);
      await h.settlePages();
      expect(h.viewport.currentPageIndex.value, 1);

      final done = openDialog(tester, h);
      await settleDialog(tester);
      await tester.tap(find.byKey(ClearPageDialog.confirmKey));
      await settleDialog(tester);
      expect(await done, isTrue);
      expect(h.session.pageIfLoaded(h.pageId(1))!.strokes, isEmpty);
      expect(h.session.pageIfLoaded(h.pageId(0))!.strokes.map((s) => s.id), [
        strokeA.id,
      ]);
    });
  });

  group('eraser cursor', () {
    testWidgets('the ring follows the pen while erasing and hides at the end', (
      tester,
    ) async {
      final h = await pumpEditor(tester, strokesByPageIndex: _noStrokes);
      _useEraser(h, diameter: 20);
      final host = h.container.read(editorInteractionHostProvider);
      final scale = h.viewport.camera.scale;
      final a = pageCenterOf(h, 0);
      final b = a + const Offset(40, 25);

      await h.driver.hover(a);
      expect(host.cursor.value, isA<EraserRingCursor>());

      await h.driver.down(1, a, kind: PointerDeviceKind.stylus);
      expect(host.lastStarted, isA<EraseInteraction>());
      var ring = host.cursor.value! as EraserRingCursor;
      expect(ring.position, a - h.viewportOrigin);
      expect(ring.diameter, closeTo(20 * scale, 1e-9));

      // No hover timeout while erasing.
      await h.driver.wait(kHoverCursorTimeout * 2);
      expect(host.cursor.value, isA<EraserRingCursor>());

      await h.driver.move(1, b);
      ring = host.cursor.value! as EraserRingCursor;
      expect(ring.position, b - h.viewportOrigin);

      await h.driver.up(1);
      expect(host.cursor.value, isNull);

      // Cancel hides it too; so does a mouse erase.
      await h.driver.down(1, a, kind: PointerDeviceKind.stylus);
      expect(host.cursor.value, isA<EraserRingCursor>());
      await h.driver.cancel(1);
      expect(host.cursor.value, isNull);

      await h.driver.down(7, a, kind: PointerDeviceKind.mouse);
      await h.driver.move(7, b);
      expect(
        (host.cursor.value! as EraserRingCursor).position,
        b - h.viewportOrigin,
      );
      await h.driver.up(7);
      expect(host.cursor.value, isNull);
    });

    testWidgets('the pen shows no ring while drawing', (tester) async {
      final h = await pumpEditor(tester, strokesByPageIndex: _noStrokes);
      final host = h.container.read(editorInteractionHostProvider);
      final a = pageCenterOf(h, 0);
      await h.driver.down(1, a, kind: PointerDeviceKind.stylus);
      expect(host.cursor.value, isNull);
      await h.driver.move(1, a + const Offset(30, 10));
      expect(host.cursor.value, isNull);
      await h.driver.up(1);
    });
  });
}
