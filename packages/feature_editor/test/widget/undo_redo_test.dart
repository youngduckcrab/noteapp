// E-11: undo / redo wiring (04-editor 6.8): [↶] [↷] enabled from
// core.historyStateProvider, two- / three-finger taps, ignored during an
// interaction, scrolling to the first affected page in note order, read-only,
// and a racing ReadOnlyNoteException (N-4 v1.1).
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/toolbar/undo_redo_buttons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

const List<Offset> _points = [
  Offset(100, 150),
  Offset(140, 170),
  Offset(190, 185),
  Offset(240, 200),
];

/// Longer than the palm-rejection cooldown after the pen lifts (6.5.4).
const Duration _afterPen = Duration(seconds: 1);

bool _enabled(WidgetTester tester, Key key) =>
    tester.widget<IconButton>(find.byKey(key)).onPressed != null;

/// Lets an undo / redo (and a page scroll animation) finish.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _draw(EditorTestHandles h, {double dy = 0}) =>
    h.driver.stylusStroke(
      pathThrough(h, 0, [for (final p in _points) p + Offset(0, dy)]),
    );

void main() {
  testWidgets('[↶] [↷] follow canUndo / canRedo', (tester) async {
    final h = await pumpEditor(tester);
    await tester.pump();
    expect(_enabled(tester, UndoRedoButtons.undoKey), isFalse);
    expect(_enabled(tester, UndoRedoButtons.redoKey), isFalse);
    expect(find.bySemanticsLabel(EditorStrings.undo), findsOneWidget);
    expect(find.bySemanticsLabel(EditorStrings.redo), findsOneWidget);

    await _draw(h);
    await tester.pump();
    expect(_enabled(tester, UndoRedoButtons.undoKey), isTrue);
    expect(_enabled(tester, UndoRedoButtons.redoKey), isFalse);

    await tester.tap(find.byKey(UndoRedoButtons.undoKey));
    await _settle(tester);
    expect(h.recorder!.countOf('undo'), 1);
    expect(h.session.pageIfLoaded(h.pageId(0))!.strokes, isEmpty);
    expect(h.controllerOf(0).content!.strokes, isEmpty);
    expect(_enabled(tester, UndoRedoButtons.undoKey), isFalse);
    expect(_enabled(tester, UndoRedoButtons.redoKey), isTrue);

    await tester.tap(find.byKey(UndoRedoButtons.redoKey));
    await _settle(tester);
    expect(h.recorder!.countOf('redo'), 1);
    expect(h.session.pageIfLoaded(h.pageId(0))!.strokes, hasLength(1));
    expect(_enabled(tester, UndoRedoButtons.undoKey), isTrue);
    expect(_enabled(tester, UndoRedoButtons.redoKey), isFalse);
  });

  testWidgets('two-finger tap → undo once, three-finger tap → redo once', (
    tester,
  ) async {
    final h = await pumpEditor(tester);
    await _draw(h);
    await _draw(h, dy: 80);
    expect(h.session.history.undoDepth, 2);
    await h.driver.wait(_afterPen);

    final c = pageCenterOf(h, 0);
    await h.driver.multiTap([c, c + const Offset(60, 0)]);
    await _settle(tester);
    expect(h.recorder!.countOf('undo'), 1);
    expect(h.recorder!.countOf('redo'), 0);
    expect(h.session.history.undoDepth, 1);
    expect(h.session.history.redoDepth, 1);

    await h.driver.multiTap([
      c,
      c + const Offset(60, 0),
      c + const Offset(120, 0),
    ]);
    await _settle(tester);
    expect(h.recorder!.countOf('undo'), 1);
    expect(h.recorder!.countOf('redo'), 1);
    expect(h.session.history.undoDepth, 2);
    expect(h.session.history.redoDepth, 0);
  });

  testWidgets('ignored while a tool interaction runs', (tester) async {
    final h = await pumpEditor(tester);
    await _draw(h);
    final commands = h.container.read(editorCommandsProvider);
    final points = pathThrough(h, 0, [
      for (final p in _points) p + const Offset(0, 120),
    ]);
    await h.driver.down(1, points.first, kind: PointerDeviceKind.stylus);
    await h.driver.move(1, points[1]);
    expect(
      h.container.read(editorInputRouterProvider).hasActiveInteraction,
      isTrue,
    );

    await commands.undo();
    await commands.redo();
    await tester.pump();
    expect(h.recorder!.countOf('undo'), 0);
    expect(h.recorder!.countOf('redo'), 0);

    await h.driver.move(1, points[2]);
    await h.driver.up(1);
    expect(h.session.history.undoDepth, 2);
    await commands.undo();
    await tester.pump();
    expect(h.recorder!.countOf('undo'), 1);
    expect(h.session.history.undoDepth, 1);
  });

  testWidgets('undoing a change off screen scrolls to the first affected page '
      'in note order', (tester) async {
    final h = await pumpEditor(tester, pages: 6);
    final viewport = h.viewport;
    expect(viewport.currentPageIndex.value, 0);
    final ids = [for (var i = 0; i < 6; i++) h.pageId(i)];
    // Pages 5 and 3 deleted in one step (listed out of note order).
    h.session.execute(core.DeletePages(pageIds: [ids[5], ids[3]]));
    await tester.pump();
    expect(h.session.pages, hasLength(4));
    final camera = viewport.camera;

    // Undo restores both; page 3 comes first in note order.
    await h.driver.multiTap([
      pageCenterOf(h, 0),
      pageCenterOf(h, 0) + const Offset(60, 0),
    ]);
    await _settle(tester);
    expect(h.recorder!.countOf('undo'), 1);
    expect(h.session.pages.map((p) => p.id), ids);
    expect(viewport.camera, isNot(camera));
    expect(viewport.currentPageIndex.value, 3);
    final rect = viewport.pageRectOnScreen(3);
    expect(rect.overlaps(Offset.zero & viewport.viewportSize), isTrue);
  });

  testWidgets('undoing a change on screen does not scroll', (tester) async {
    final h = await pumpEditor(tester);
    await _draw(h);
    final camera = h.viewport.camera;
    await tester.tap(find.byKey(UndoRedoButtons.undoKey));
    await _settle(tester);
    expect(h.recorder!.countOf('undo'), 1);
    expect(h.viewport.camera, camera);
  });

  testWidgets('a read-only note: both disabled, finger taps do nothing', (
    tester,
  ) async {
    final h = await pumpEditor(tester);
    await _draw(h);
    await tester.pump();
    expect(_enabled(tester, UndoRedoButtons.undoKey), isTrue);

    await h.store.library.trashItems([core.NoteRef(h.noteId)]);
    await tester.pump();
    expect(h.container.read(editorReadOnlyProvider), isTrue);
    expect(_enabled(tester, UndoRedoButtons.undoKey), isFalse);
    expect(_enabled(tester, UndoRedoButtons.redoKey), isFalse);

    await h.driver.wait(_afterPen);
    final c = pageCenterOf(h, 0);
    await h.driver.multiTap([c, c + const Offset(60, 0)]);
    await _settle(tester);
    await h.container.read(editorCommandsProvider).undo();
    expect(h.recorder!.countOf('undo'), 0);
    expect(h.session.history.undoDepth, 1);
  });

  testWidgets('a racing ReadOnlyNoteException: a notice only — no scroll, '
      'nothing thrown', (tester) async {
    final h = await pumpEditor(tester, pages: 6);
    // A change on page 4 (off screen) to undo.
    await h.session.executeAsync(
      core.AddStrokes(
        pageId: h.pageId(4),
        strokes: [strokeA.copyWith(pageId: h.pageId(4))],
      ),
    );
    await tester.pump();
    final camera = h.viewport.camera;
    final depth = h.session.history.undoDepth;

    h.recorder!.rejectNext(const core.ReadOnlyNoteException('race'));
    await tester.tap(find.byKey(UndoRedoButtons.undoKey));
    await _settle(tester);

    expect(h.recorder!.calls.where((c) => c.startsWith('undo')), [
      'undo:rejected',
    ]);
    expect(tester.takeException(), isNull);
    expect(find.text(EditorStrings.readOnlyToast), findsOneWidget);
    expect(h.viewport.camera, camera);
    expect(h.session.history.undoDepth, depth);
    await tester.pump(const Duration(seconds: 5)); // snackbar timer

    // The next undo goes through and scrolls to page 4.
    await tester.tap(find.byKey(UndoRedoButtons.undoKey));
    await _settle(tester);
    expect(h.recorder!.countOf('undo'), 1);
    expect(h.viewport.currentPageIndex.value, 4);
  });
}
