// E-10: lasso, selection, transform, menus, clipboard and selection
// revalidation through the whole editor (04-editor 6.6.2, 6.6.5–6.6.7):
// PointerDriver → InputRouter → InteractionHost → Lasso / SelectionTransform
// interactions → B3 INK → EditorCommands → fake CORE session.
import 'dart:ui' show Rect;

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/tools/selection_hit_test.dart';
import 'package:feature_editor/src/tools/selection_transform_interaction.dart';
import 'package:feature_editor/src/tools/stroke_clipboard.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/overlays/context_menu.dart';
import 'package:feature_editor/src/ui/overlays/selection_frame_painter.dart';
import 'package:feature_editor/src/ui/overlays/selection_menu.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart' show CustomPaint;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

Rect _rectOf(core.Stroke s) =>
    Rect.fromLTRB(s.bounds.left, s.bounds.top, s.bounds.right, s.bounds.bottom);

List<String> _edits(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute')) c,
];

EditorSelection? _selection(EditorTestHandles h) =>
    h.container.read(editorSelectionProvider);

Future<void> _useLasso(WidgetTester tester, EditorTestHandles h) async {
  h.container.read(editorCommandsProvider).selectTool(EditorTool.lasso);
  await tester.pump();
}

/// Lassoes [strokes] on page [pageIndex] with the stylus.
Future<void> _lasso(
  WidgetTester tester,
  EditorTestHandles h,
  List<core.Stroke> strokes, {
  int pageIndex = 0,
}) async {
  final rect = strokes.map(_rectOf).reduce((a, b) => a.expandToInclude(b));
  await h.driver.stylusStroke(lassoAround(h, pageIndex, rect));
  await tester.pump();
}

/// The selection frame on screen (viewport coordinates).
Rect _frame(EditorTestHandles h) =>
    selectionRectOnScreen(h.viewport, h.mountedPages, _selection(h))!;

/// The CORE stroke [id] on page [pageIndex].
core.Stroke? _coreStroke(EditorTestHandles h, String id, {int pageIndex = 0}) =>
    h.session.pageIfLoaded(h.pageId(pageIndex))!.strokeById(id);

const _penOnly = EditorSettings(inputMode: InputMode.penOnly);

/// Longer than the palm-rejection cooldown after the pen lifts (6.5.4).
const _afterPen = Duration(seconds: 1);

void main() {
  testWidgets('a lasso selects → frame and menu, no command', (tester) async {
    final h = await pumpEditor(
      tester,
      strokesByPageIndex: {
        0: [strokeA, strokeB],
      },
    );
    await _useLasso(tester, h);
    await _lasso(tester, h, [strokeA]);

    expect(
      _selection(h),
      EditorSelection(pageId: h.pageId(0), elementIds: {strokeA.id}),
    );
    expect(h.controllerOf(0).selection!.strokeIds, {strokeA.id});
    expect(_edits(h), isEmpty);

    // The frame: INK's bounds on screen, dashed, with 4 corner handles.
    final frame = _frame(h);
    final bounds = h.controllerOf(0).selection!.bounds;
    expect(frame.topLeft, h.viewport.pageToScreen(0, bounds.topLeft));
    expect(frame.bottomRight, h.viewport.pageToScreen(0, bounds.bottomRight));
    final painted = find.descendant(
      of: find.byType(SelectionFrame),
      matching: find.byType(CustomPaint),
    );
    expect(
      tester.renderObject(painted),
      paints
        ..line()
        ..circle(
          x: frame.topLeft.dx,
          y: frame.topLeft.dy,
          radius: SelectionHitTest.handleVisualRadius,
        ),
    );

    // The menu: 복사 · 삭제 · 선택 해제, 8 px above the frame.
    expect(find.text(EditorStrings.selectionCopy), findsOneWidget);
    expect(find.text(EditorStrings.selectionDelete), findsOneWidget);
    expect(find.text(EditorStrings.selectionClear), findsOneWidget);
    final menuBottom = tester
        .getBottomLeft(find.byKey(SelectionMenu.copyKey))
        .dy;
    expect(
      menuBottom,
      lessThanOrEqualTo(h.viewportOrigin.dy + frame.top - SelectionMenu.gap),
    );

    // 선택 해제.
    await tester.tap(find.byKey(SelectionMenu.clearKey));
    await tester.pump();
    expect(_selection(h), isNull);
    expect(h.controllerOf(0).selection, isNull);
    expect(find.byKey(SelectionMenu.copyKey), findsNothing);
    expect(tester.renderObject(painted), isNot(paints..circle()));
  });

  testWidgets('a lasso around nothing, or a tap in the gap, selects nothing', (
    tester,
  ) async {
    final h = await pumpEditor(
      tester,
      strokesByPageIndex: {
        0: [strokeA],
      },
    );
    await _useLasso(tester, h);
    await _lasso(tester, h, [strokeA]);
    expect(_selection(h), isNotNull);

    // A new lasso elsewhere clears the old selection and selects nothing.
    await h.driver.stylusStroke(
      lassoAround(h, 0, const Rect.fromLTWH(300, 600, 80, 80)),
    );
    await tester.pump();
    expect(_selection(h), isNull);
    expect(h.controllerOf(0).selection, isNull);

    // A one-finger tap clears the selection.
    await _lasso(tester, h, [strokeA]);
    expect(_selection(h), isNotNull);
    await h.driver.wait(_afterPen); // past the palm cooldown
    await h.driver.multiTap([h.toGlobal(0, const Offset(400, 700))]);
    await tester.pump();
    expect(_selection(h), isNull);

    // Switching to the pen clears it too.
    await _lasso(tester, h, [strokeA]);
    expect(_selection(h), isNotNull);
    h.container.read(editorToolProvider.notifier).selectTool(EditorTool.pen);
    await tester.pump();
    expect(_selection(h), isNull);
    expect(h.controllerOf(0).selection, isNull);
    expect(_edits(h), isEmpty);
  });

  testWidgets('dragging the selection commits one transform; ids and the '
      'selection are kept', (tester) async {
    final h = await pumpEditor(
      tester,
      strokesByPageIndex: {
        0: [strokeA, strokeB],
      },
    );
    await _useLasso(tester, h);
    await _lasso(tester, h, [strokeA]);
    final before = h.session.history.undoDepth;
    final scale = h.viewport.camera.scale;

    final centre = h.toGlobal(0, _rectOf(strokeA).center);
    await h.driver.down(1, centre, kind: PointerDeviceKind.stylus);
    expect(
      h.container.read(editorInteractionHostProvider).lastStarted,
      isA<SelectionTransformInteraction>(),
    );
    await h.driver.move(1, centre + const Offset(20, 0));
    await h.driver.move(1, centre + const Offset(40, 0));
    await tester.pump();
    // While dragging: the menu hides, INK previews the move.
    expect(_selection(h)!.isDragging, isTrue);
    expect(find.byKey(SelectionMenu.copyKey), findsNothing);
    final preview = h.controllerOf(0).selection!.previewTransform;
    expect(preview.isIdentity, isFalse);
    await h.driver.up(1);
    await tester.pump();

    expect(_edits(h), ['execute:transform']);
    expect(h.session.history.undoDepth, before + 1);
    expect(h.session.history.undoLabel, 'transform');
    final moved = _coreStroke(h, strokeA.id)!; // id kept
    expect(moved.points.x(0), closeTo(strokeA.points.x(0) + 40 / scale, 0.02));
    expect(moved.points.y(0), closeTo(strokeA.points.y(0), 0.02));
    expect(_coreStroke(h, strokeB.id)!.points.x(0), strokeB.points.x(0));
    expect(h.controllerOf(0).selection!.strokeIds, {strokeA.id});
    expect(h.controllerOf(0).selection!.previewTransform.isIdentity, isTrue);
    expect(h.controllerOf(0).pendingIds, isEmpty);
    expect(_selection(h)!.elementIds, {strokeA.id});
    expect(_selection(h)!.isDragging, isFalse);
    expect(find.byKey(SelectionMenu.copyKey), findsOneWidget);
    expect(h.recorder!.executeDuringDelivery, isFalse);
  });

  testWidgets('pen-only mode: a finger on the selection moves it', (
    tester,
  ) async {
    final h = await pumpEditor(
      tester,
      settings: _penOnly,
      strokesByPageIndex: {
        0: [strokeA],
      },
    );
    await _useLasso(tester, h);
    await _lasso(tester, h, [strokeA]);
    await h.driver.wait(_afterPen);
    final scale = h.viewport.camera.scale;
    final camera = h.viewport.camera;
    final centre = h.toGlobal(0, _rectOf(strokeA).center);
    await h.driver.fingerDrag(centre, centre + const Offset(0, 50));
    await tester.pump();
    expect(_edits(h), ['execute:transform']);
    expect(h.viewport.camera, camera); // no scrolling
    final moved = _coreStroke(h, strokeA.id)!;
    expect(moved.points.y(0), closeTo(strokeA.points.y(0) + 50 / scale, 0.02));

    // Away from the selection the finger scrolls.
    await h.driver.fingerDrag(
      h.toGlobal(0, const Offset(400, 700)),
      h.toGlobal(0, const Offset(400, 600)),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(_edits(h), ['execute:transform']);
    expect(h.viewport.camera, isNot(camera));
  });

  testWidgets('a move keeps the selection centre on the page', (tester) async {
    final h = await pumpEditor(
      tester,
      strokesByPageIndex: {
        0: [strokeA],
      },
    );
    await _useLasso(tester, h);
    await _lasso(tester, h, [strokeA]);
    final bounds = h.controllerOf(0).selection!.bounds;
    final centre = h.toGlobal(0, bounds.center);
    // Far to the left: the centre stops at x = 0.
    await h.driver.stylusStroke([
      centre,
      centre + const Offset(-200, 0),
      centre + const Offset(-900, 0),
    ]);
    await tester.pump();
    final moved = _coreStroke(h, strokeA.id)!;
    final dx = moved.points.x(0) - strokeA.points.x(0);
    expect(dx, closeTo(-bounds.center.dx, 0.02));
  });

  testWidgets('a corner handle resizes with the aspect kept', (tester) async {
    final h = await pumpEditor(
      tester,
      strokesByPageIndex: {
        0: [strokeA, strokeB],
      },
    );
    await _useLasso(tester, h);
    await _lasso(tester, h, [strokeA, strokeB]);
    expect(_selection(h)!.elementIds, {strokeA.id, strokeB.id});
    final bounds = h.controllerOf(0).selection!.bounds;
    final frame = _frame(h);

    // Drag the bottom-right handle 30 px right and down.
    final handle = h.viewportToGlobal(frame.bottomRight);
    await h.driver.stylusStroke([
      handle,
      handle + const Offset(15, 15),
      handle + const Offset(30, 30),
    ]);
    await tester.pump();

    expect(_edits(h), ['execute:transform']);
    final scale = h.viewport.camera.scale;
    final expected = ink.SelectionGeometry.resize(
      bounds: bounds,
      handle: ink.SelectionHandle.bottomRight,
      delta: const Offset(30, 30) / scale,
      keepAspect: true,
    );
    for (final s in [strokeA, strokeB]) {
      final after = _coreStroke(h, s.id)!;
      for (final k in [0, s.points.length - 1]) {
        final (x, y) = expected.apply(s.points.x(k), s.points.y(k));
        expect(after.points.x(k), closeTo(x, 0.02));
        expect(after.points.y(k), closeTo(y, 0.02));
      }
    }
    // The top-left corner is the fixed anchor; the box grew.
    final grown = h.controllerOf(0).selection!.bounds;
    expect(grown.width, greaterThan(bounds.width));
    expect(_selection(h)!.elementIds, {strokeA.id, strokeB.id});
  });

  testWidgets('삭제 → one remove-strokes, the selection ends', (tester) async {
    final h = await pumpEditor(
      tester,
      strokesByPageIndex: {
        0: [strokeA, strokeB],
      },
    );
    await _useLasso(tester, h);
    await _lasso(tester, h, [strokeA]);
    await tester.tap(find.byKey(SelectionMenu.deleteKey));
    await tester.pump();

    expect(_edits(h), ['execute:remove-strokes']);
    expect(h.session.history.undoLabel, 'remove-strokes');
    expect(_coreStroke(h, strokeA.id), isNull);
    expect(_coreStroke(h, strokeB.id), isNotNull);
    expect(_selection(h), isNull);
    expect(h.controllerOf(0).selection, isNull);
    expect(h.controllerOf(0).pendingIds, isEmpty);
    expect(find.byKey(SelectionMenu.copyKey), findsNothing);
  });

  testWidgets('복사 and paste on another page → add-strokes, the pasted '
      'strokes selected', (tester) async {
    final h = await pumpEditor(
      tester,
      pages: 3,
      strokesByPageIndex: {
        0: [strokeA, strokeB],
      },
    );
    await _useLasso(tester, h);
    await _lasso(tester, h, [strokeA, strokeB]);
    await tester.tap(find.byKey(SelectionMenu.copyKey));
    await tester.pump();
    final clip = h.container.read(editorClipboardProvider)!;
    expect(clip.strokes.map((s) => s.id), [strokeA.id, strokeB.id]);
    expect(_edits(h), isEmpty); // copying runs no command

    // Secondary click on page 1 → context menu → 붙여넣기 there.
    await h.viewport.jumpToPage(1, animate: false);
    await tester.pump(const Duration(milliseconds: 200));
    await h.settlePages();
    const at = Offset(300, 300);
    final point = h.toGlobal(1, at);
    await h.driver.down(
      7,
      point,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await h.driver.up(7);
    await tester.pump();
    expect(find.text(EditorStrings.paste), findsOneWidget);
    await tester.tap(find.byKey(EditorContextMenu.pasteKey));
    await tester.pump();
    await tester.pump();

    expect(_edits(h), ['executeAsync:add-strokes']);
    expect(h.session.history.undoLabel, 'add-strokes');
    final pasted = h.session.pageIfLoaded(h.pageId(1))!.strokes;
    expect(pasted, hasLength(2));
    final ids = {for (final s in pasted) s.id};
    expect(ids.intersection({strokeA.id, strokeB.id}), isEmpty); // new ids
    final union = pasted.map(_rectOf).reduce((a, b) => a.expandToInclude(b));
    expect(union.center.dx, closeTo(at.dx, 0.05));
    expect(union.center.dy, closeTo(at.dy, 0.05));
    // The lasso tool with the pasted strokes selected (controller.select).
    expect(h.container.read(editorToolProvider).activeTool, EditorTool.lasso);
    expect(h.controllerOf(1).selection!.strokeIds, ids);
    expect(
      _selection(h),
      EditorSelection(pageId: h.pageId(1), elementIds: ids),
    );
    expect(h.controllerOf(0).selection, isNull);
    expect(find.byKey(EditorContextMenu.pasteKey), findsNothing);
    expect(h.recorder!.executeDuringDelivery, isFalse);

    // ⌘V-style paste (no point): the screen centre on the current page, +16 pt
    // on the next one.
    final commands = h.container.read(editorCommandsProvider);
    await commands.paste();
    await commands.paste();
    await tester.pump();
    final current = h.viewport.currentPageIndex.value;
    final centre = h.viewport.screenToPage(
      current,
      h.viewport.viewportSize.center(Offset.zero),
    );
    final page = h.session.pageIfLoaded(h.pageId(current))!;
    final second = page.strokes.where((s) => !ids.contains(s.id)).toList();
    expect(second, hasLength(4));
    Rect unionOf(Iterable<core.Stroke> s) =>
        s.map(_rectOf).reduce((a, b) => a.expandToInclude(b));
    final first = unionOf(second.take(2));
    final next = unionOf(second.skip(2));
    expect(first.center.dx, closeTo(centre.dx, 0.05));
    expect(first.center.dy, closeTo(centre.dy, 0.05));
    expect(next.center.dx - first.center.dx, closeTo(16, 0.05));
    expect(next.center.dy - first.center.dy, closeTo(16, 0.05));
  });

  testWidgets('selected strokes removed another way leave the selection', (
    tester,
  ) async {
    final h = await pumpEditor(
      tester,
      strokesByPageIndex: {
        0: [strokeA, strokeB, highlighterStroke],
      },
    );
    await _useLasso(tester, h);
    await _lasso(tester, h, [strokeA, strokeB]);
    expect(_selection(h)!.elementIds, {
      strokeA.id,
      strokeB.id,
      highlighterStroke.id,
    });

    // One of them removed (not through the selection): the rest stays selected.
    h.session.execute(
      core.RemoveStrokes(pageId: h.pageId(0), strokeIds: [strokeB.id]),
    );
    await tester.pump();
    expect(_selection(h)!.elementIds, {strokeA.id, highlighterStroke.id});
    expect(h.controllerOf(0).selection!.strokeIds, {
      strokeA.id,
      highlighterStroke.id,
    });

    // All of them gone → no selection.
    h.session.execute(
      core.RemoveStrokes(
        pageId: h.pageId(0),
        strokeIds: [strokeA.id, highlighterStroke.id],
      ),
    );
    await tester.pump();
    expect(_selection(h), isNull);
    expect(h.controllerOf(0).selection, isNull);
    expect(find.byKey(SelectionMenu.copyKey), findsNothing);

    // Undo brings them back but not the selection.
    await h.container.read(editorCommandsProvider).undo();
    await tester.pump();
    expect(_coreStroke(h, strokeA.id), isNotNull);
    expect(_selection(h), isNull);
  });

  testWidgets('a deleted page drops its selection', (tester) async {
    final h = await pumpEditor(
      tester,
      pages: 2,
      strokesByPageIndex: {
        0: [strokeA],
      },
    );
    await _useLasso(tester, h);
    await _lasso(tester, h, [strokeA]);
    expect(_selection(h), isNotNull);
    h.session.execute(core.DeletePages(pageIds: [h.pageId(0)]));
    await tester.pump();
    await tester.pump();
    expect(_selection(h), isNull);
  });

  group('long press / secondary click', () {
    testWidgets('a finger long press away from the selection → context menu', (
      tester,
    ) async {
      final h = await pumpEditor(
        tester,
        settings: _penOnly,
        strokesByPageIndex: {
          0: [strokeA],
        },
      );
      final host = h.container.read(editorInteractionHostProvider);
      final at = h.toGlobal(0, const Offset(300, 600));

      // Empty clipboard: only 올가미 도구.
      await h.driver.down(11, at);
      await h.driver.wait(const Duration(milliseconds: 600));
      await h.driver.up(11);
      await tester.pump();
      expect(host.contextMenu.value, isNotNull);
      expect(find.text(EditorStrings.lassoTool), findsOneWidget);
      expect(find.text(EditorStrings.paste), findsNothing);
      // The menu sits at the press point.
      expect(
        tester.getTopLeft(find.byKey(EditorContextMenu.lassoKey)),
        offsetMoreOrLessEquals(at, epsilon: 1),
      );

      // A one-finger tap elsewhere closes it.
      await h.driver.multiTap([h.toGlobal(0, const Offset(100, 700))]);
      await tester.pump();
      expect(host.contextMenu.value, isNull);
      expect(find.text(EditorStrings.lassoTool), findsNothing);

      // 올가미 도구 switches the tool and closes the menu.
      await h.driver.down(11, at);
      await h.driver.wait(const Duration(milliseconds: 600));
      await h.driver.up(11);
      await tester.pump();
      await tester.tap(find.byKey(EditorContextMenu.lassoKey));
      await tester.pump();
      expect(h.container.read(editorToolProvider).activeTool, EditorTool.lasso);
      expect(host.contextMenu.value, isNull);

      // With strokes copied, 붙여넣기 appears and pastes at the press point.
      await _lasso(tester, h, [strokeA]);
      await tester.tap(find.byKey(SelectionMenu.copyKey));
      await tester.pump();
      await h.driver.wait(_afterPen); // past the palm cooldown
      await h.driver.down(11, at);
      await h.driver.wait(const Duration(milliseconds: 600));
      await h.driver.up(11);
      await tester.pump();
      expect(find.text(EditorStrings.paste), findsOneWidget);
      await tester.tap(find.byKey(EditorContextMenu.pasteKey));
      await tester.pump();
      await tester.pump();
      expect(_edits(h), ['executeAsync:add-strokes']);
      final pasted = h.session
          .pageIfLoaded(h.pageId(0))!
          .strokes
          .where((s) => s.id != strokeA.id)
          .single;
      expect(
        _rectOf(pasted).center,
        offsetMoreOrLessEquals(h.toPage(0, at), epsilon: 0.05),
      );
      expect(_selection(h)!.elementIds, {pasted.id});
    });

    testWidgets('on the selection → no context menu (the selection menu)', (
      tester,
    ) async {
      final h = await pumpEditor(
        tester,
        strokesByPageIndex: {
          0: [strokeA],
        },
      );
      final host = h.container.read(editorInteractionHostProvider);
      await _useLasso(tester, h);
      await _lasso(tester, h, [strokeA]);
      final centre = h.viewportToGlobal(_frame(h).center);
      await h.driver.down(
        7,
        centre,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await h.driver.up(7);
      await tester.pump();
      expect(host.contextMenu.value, isNull);
      expect(find.byKey(SelectionMenu.copyKey), findsOneWidget);
    });

    testWidgets('a read-only note shows no context menu', (tester) async {
      final h = await pumpEditor(tester);
      await h.store.library.trashItems([core.NoteRef(h.noteId)]);
      await tester.pump();
      final host = h.container.read(editorInteractionHostProvider);
      final at = h.toGlobal(0, const Offset(300, 600));
      await h.driver.down(
        7,
        at,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await h.driver.up(7);
      await tester.pump();
      expect(host.contextMenu.value, isNull);
    });
  });

  group('rejected commits (read-only race)', () {
    testWidgets('a move: discardEdit, the strokes at their old place, still '
        'selected', (tester) async {
      final h = await pumpEditor(
        tester,
        strokesByPageIndex: {
          0: [strokeA, strokeB],
        },
      );
      await _useLasso(tester, h);
      await _lasso(tester, h, [strokeA]);
      final bounds = h.controllerOf(0).selection!.bounds;
      h.recorder!.rejectNext(const core.ReadOnlyNoteException('race'));

      final centre = h.toGlobal(0, bounds.center);
      await h.driver.stylusStroke([
        centre,
        centre + const Offset(30, 10),
        centre + const Offset(60, 20),
      ]);
      await tester.pump();

      expect(_edits(h), ['execute:transform:rejected']);
      final controller = h.controllerOf(0);
      expect(controller.pendingIds, isEmpty);
      final sel = controller.selection!;
      expect(sel.strokeIds, {strokeA.id});
      expect(sel.previewTransform.isIdentity, isTrue); // drawn at the old place
      expect(sel.previewBounds, bounds);
      expect(_coreStroke(h, strokeA.id)!.points.x(0), strokeA.points.x(0));
      expect(h.session.history.undoDepth, 0);
      expect(_selection(h)!.elementIds, {strokeA.id});
      expect(_selection(h)!.isDragging, isFalse);
      expect(find.text(EditorStrings.readOnlyToast), findsOneWidget);
      await tester.pump(const Duration(seconds: 5)); // snackbar timer
    });

    testWidgets('삭제: discardEdit, the strokes show again', (tester) async {
      final h = await pumpEditor(
        tester,
        strokesByPageIndex: {
          0: [strokeA, strokeB],
        },
      );
      await _useLasso(tester, h);
      await _lasso(tester, h, [strokeA, strokeB]);
      h.recorder!.rejectNext(const core.ReadOnlyNoteException('race'));
      await tester.tap(find.byKey(SelectionMenu.deleteKey));
      await tester.pump();

      expect(_edits(h), ['execute:remove-strokes:rejected']);
      final controller = h.controllerOf(0);
      expect(controller.pendingIds, isEmpty);
      for (final s in [strokeA, strokeB]) {
        final p = Offset(s.points.x(1), s.points.y(1));
        expect(controller.hitTest(p, tolerance: 0.5)?.id, s.id);
        expect(_coreStroke(h, s.id), isNotNull);
      }
      expect(controller.content!.strokes, hasLength(2));
      expect(h.session.history.undoDepth, 0);
      expect(_selection(h)!.elementIds, {strokeA.id, strokeB.id});
      await tester.pump(const Duration(seconds: 5)); // snackbar timer
    });
  });
}
