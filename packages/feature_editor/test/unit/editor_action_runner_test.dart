// m5-7/04-editor 8.2 E2-05, 6.4.1 · 6.4.3: EditorActionRunner on the editor
// screen (fake store, R2-B3 INK) — what each of the 11 actions does (tools,
// popups, undo / redo calls), ignored while a tool interaction runs except
// the palettes, the read-only rules, followSystem through the preferred
// action, and undo during a text edit session (the session's command first).
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/actions/editor_action_runner.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/popup.dart';
import 'package:feature_editor/src/text/text_box_placement.dart';
import 'package:feature_editor/src/text/text_edit_session.dart';
import 'package:feature_editor/src/tools/interaction_host.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/color/color_palette_popup.dart';
import 'package:feature_editor/src/ui/pen/quick_pen_popup.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

const List<Offset> _points = [
  Offset(100, 150),
  Offset(140, 170),
  Offset(190, 185),
  Offset(240, 200),
];

const GestureSource _tap = GestureSource(Offset(400, 500));

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _draw(EditorTestHandles h, {double dy = 0}) =>
    h.driver.stylusStroke(
      pathThrough(h, 0, [for (final p in _points) p + Offset(0, dy)]),
    );

EditorActionRunner _runner(EditorTestHandles h) =>
    h.container.read(editorActionRunnerProvider);
ToolState _tools(EditorTestHandles h) => h.container.read(editorToolProvider);
EditorPopup? _popup(EditorTestHandles h) =>
    h.container.read(editorPopupProvider);
ContextMenuRequest? _menu(EditorTestHandles h) =>
    h.container.read(editorInteractionHostProvider).contextMenu.value;

/// What an action may touch: the tool, the popup, the context menu and the
/// history calls.
({
  ToolState tools,
  EditorPopup? popup,
  ContextMenuRequest? menu,
  int undo,
  int redo,
})
_snapshot(EditorTestHandles h) => (
  tools: _tools(h),
  popup: _popup(h),
  menu: _menu(h),
  undo: h.recorder!.countOf('undo'),
  redo: h.recorder!.countOf('redo'),
);

Future<void> _makeReadOnly(WidgetTester tester, EditorTestHandles h) async {
  await h.store.library.trashItems([core.NoteRef(h.noteId)]);
  await tester.pump();
  expect(h.container.read(editorReadOnlyProvider), isTrue);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await useInkTestFonts();
  });

  testWidgets('none, eraserWhileHeld, lassoWhileHeld → nothing; '
      'followSystem from a finger gesture → nothing', (tester) async {
    final h = await pumpEditor(tester);
    await _draw(h);
    final before = _snapshot(h);
    for (final a in [
      EditorAction.none,
      EditorAction.eraserWhileHeld,
      EditorAction.lassoWhileHeld,
      EditorAction.followSystem,
    ]) {
      _runner(h).run(a, _tap);
    }
    await _settle(tester);
    expect(_snapshot(h), before);
  });

  testWidgets('undo → one session undo, redo → one session redo', (
    tester,
  ) async {
    final h = await pumpEditor(tester);
    await _draw(h);
    _runner(h).run(EditorAction.undo, _tap);
    await _settle(tester);
    expect(h.recorder!.countOf('undo'), 1);
    expect(h.session.pageIfLoaded(h.pageId(0))!.strokes, isEmpty);
    _runner(h).run(EditorAction.redo, _tap);
    await _settle(tester);
    expect(h.recorder!.countOf('redo'), 1);
    expect(h.session.pageIfLoaded(h.pageId(0))!.strokes, hasLength(1));
    expect(h.session.history.undoDepth, 1);
  });

  testWidgets('undo during a text edit session: the session ends first '
      '(undoRedo — its one AddObjects), then the note undo takes it back', (
    tester,
  ) async {
    final h = await pumpEditor(tester);
    final notifier = h.container.read(editorTextEditProvider.notifier);
    notifier.start(
      newTextBoxAt(
        id: 'tb-new',
        pageId: h.pageId(0),
        point: const Offset(100, 100),
        pageWidth: 595,
        style: const core.TextBoxStyle(),
        createdAt: 1,
      ),
      isNew: true,
    );
    notifier.updateText('안녕');
    await tester.pump();

    _runner(h).run(EditorAction.undo, _tap);
    await _settle(tester);
    expect(h.container.read(editorTextEditProvider), isNull);
    expect(notifier.lastEndReason, TextEditEndReason.undoRedo);
    expect(h.recorder!.calls.where((c) => c.startsWith('execute')), [
      'execute:add-objects',
    ]);
    expect(h.recorder!.countOf('undo'), 1);
    expect(h.session.pageIfLoaded(h.pageId(0))!.objects, isEmpty);
    expect(h.session.history.undoDepth, 0);
  });

  testWidgets('contextMenu → the context menu at the point (viewport px); '
      'a pencil source has no point → none', (tester) async {
    final h = await pumpEditor(tester);
    _runner(h).run(EditorAction.contextMenu, _tap);
    await tester.pump();
    expect(_menu(h), const ContextMenuRequest(position: Offset(400, 500)));
    h.container.read(editorInteractionHostProvider).closeContextMenu();

    _runner(h).run(
      EditorAction.contextMenu,
      const PencilSource(preferred: StylusPreferredAction.unknown),
    );
    await tester.pump();
    expect(_menu(h), isNull);
  });

  testWidgets('toggleEraser: pen → eraser → back to the previous tool (lasso '
      '→ eraser → lasso)', (tester) async {
    final h = await pumpEditor(tester);
    expect(_tools(h).activeTool, EditorTool.pen);
    _runner(h).run(EditorAction.toggleEraser, _tap);
    expect(_tools(h).activeTool, EditorTool.eraser);
    _runner(h).run(EditorAction.toggleEraser, _tap);
    expect(_tools(h).activeTool, EditorTool.pen);

    h.container.read(editorToolProvider.notifier).selectTool(EditorTool.lasso);
    _runner(h).run(EditorAction.toggleEraser, _tap);
    expect(_tools(h).activeTool, EditorTool.eraser);
    _runner(h).run(EditorAction.toggleEraser, _tap);
    expect(_tools(h).activeTool, EditorTool.lasso);
    expect(h.recorder!.calls.where((c) => c.startsWith('execute')), isEmpty);
  });

  testWidgets('previousTool → swapWithLast (pen ⇄ lasso; nothing before a '
      'first switch)', (tester) async {
    final h = await pumpEditor(tester);
    _runner(h).run(EditorAction.previousTool, _tap);
    expect(_tools(h).activeTool, EditorTool.pen); // lastTool null
    final tools = h.container.read(editorToolProvider.notifier)
      ..selectPenType(core.PenTool.highlighter)
      ..selectTool(EditorTool.lasso);
    expect(_tools(h).lastTool, EditorTool.pen);
    _runner(h).run(EditorAction.previousTool, _tap);
    expect(_tools(h).activeTool, EditorTool.pen);
    expect(_tools(h).penType, core.PenTool.highlighter);
    _runner(h).run(EditorAction.previousTool, _tap);
    expect(_tools(h).activeTool, EditorTool.lasso);
    tools.selectTool(EditorTool.pen);
  });

  testWidgets('toolPalette → the quick pen popup at the hover point, or '
      'below the pen button without one', (tester) async {
    final h = await pumpEditor(tester);
    const hover = Offset(300, 400);
    _runner(h).run(
      EditorAction.toolPalette,
      const PencilSource(
        hoverGlobal: hover,
        preferred: StylusPreferredAction.unknown,
      ),
    );
    await tester.pump();
    expect(_popup(h), const QuickPenPopup(globalPosition: hover));
    expect(find.byKey(QuickPenPanel.panelKey), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(QuickPenPanel.panelKey)),
      hover + const Offset(12, 12),
    );

    h.container.read(editorPopupProvider.notifier).close();
    await tester.pump();
    _runner(h).run(
      EditorAction.toolPalette,
      const PencilSource(preferred: StylusPreferredAction.unknown),
    );
    await tester.pump();
    expect(_popup(h), const QuickPenPopup());
    expect(find.byKey(QuickPenPanel.panelKey), findsOneWidget);
  });

  testWidgets('colorPalette → the colour palette popup (recent colours + '
      'palette); near the screen edge it stays on screen', (tester) async {
    final h = await pumpEditor(tester);
    const hover = Offset(1020, 1370); // bottom-right corner of 1032 × 1376
    _runner(h).run(
      EditorAction.colorPalette,
      const PencilSource(
        hoverGlobal: hover,
        preferred: StylusPreferredAction.unknown,
      ),
    );
    await tester.pump();
    expect(_popup(h), const ColorPalettePopup(globalPosition: hover));
    final panel = find.byKey(ColorPalettePanel.panelKey);
    expect(panel, findsOneWidget);
    final rect = tester.getRect(panel);
    expect(rect.right, lessThanOrEqualTo(1032 - 8));
    expect(rect.bottom, lessThanOrEqualTo(1376 - 8));
    expect(rect.left, greaterThanOrEqualTo(8));
    expect(rect.top, greaterThanOrEqualTo(8));
  });

  testWidgets('followSystem from the pencil → the preferred action '
      '(switchEraser, showColorPalette, showInkAttributes, ignore)', (
    tester,
  ) async {
    final h = await pumpEditor(tester);
    void pencil(StylusPreferredAction p) =>
        _runner(h).run(EditorAction.followSystem, PencilSource(preferred: p));

    pencil(StylusPreferredAction.switchEraser);
    expect(_tools(h).activeTool, EditorTool.eraser);
    pencil(StylusPreferredAction.switchEraser);
    expect(_tools(h).activeTool, EditorTool.pen);
    pencil(StylusPreferredAction.showColorPalette);
    expect(_popup(h), const ColorPalettePopup());
    pencil(StylusPreferredAction.showInkAttributes);
    expect(_popup(h), const QuickPenPopup());
    h.container.read(editorPopupProvider.notifier).close();
    final before = _snapshot(h);
    pencil(StylusPreferredAction.ignore);
    pencil(StylusPreferredAction.runSystemShortcut);
    pencil(StylusPreferredAction.unknown);
    await _settle(tester);
    expect(_snapshot(h), before);
  });

  testWidgets('while a tool interaction runs: undo, redo, toggleEraser, '
      'previousTool, contextMenu ignored; the palettes still open', (
    tester,
  ) async {
    final h = await pumpEditor(tester);
    await _draw(h);
    h.container.read(editorToolProvider.notifier).selectTool(EditorTool.lasso);
    h.container.read(editorToolProvider.notifier).selectTool(EditorTool.pen);
    final points = pathThrough(h, 0, [
      for (final p in _points) p + const Offset(0, 120),
    ]);
    await h.driver.down(1, points.first, kind: PointerDeviceKind.stylus);
    await h.driver.move(1, points[1]);
    expect(
      h.container.read(editorInputRouterProvider).hasActiveInteraction,
      isTrue,
    );
    final before = _snapshot(h);
    for (final a in [
      EditorAction.undo,
      EditorAction.redo,
      EditorAction.toggleEraser,
      EditorAction.previousTool,
      EditorAction.contextMenu,
    ]) {
      _runner(h).run(a, _tap);
    }
    await tester.pump();
    expect(_snapshot(h), before);

    _runner(h).run(
      EditorAction.toolPalette,
      const PencilSource(preferred: StylusPreferredAction.unknown),
    );
    expect(_popup(h), const QuickPenPopup());
    _runner(h).run(
      EditorAction.colorPalette,
      const PencilSource(preferred: StylusPreferredAction.unknown),
    );
    expect(_popup(h), const ColorPalettePopup());

    await h.driver.move(1, points[2]);
    await h.driver.up(1);
    await tester.pump();
    expect(h.session.history.undoDepth, 2);
  });

  testWidgets('read-only note: toggleEraser, previousTool and the palettes '
      'ignored; undo / redo do nothing (as the toolbar); contextMenu none', (
    tester,
  ) async {
    final h = await pumpEditor(tester);
    await _draw(h);
    h.container.read(editorToolProvider.notifier).selectTool(EditorTool.lasso);
    h.container.read(editorToolProvider.notifier).selectTool(EditorTool.pen);
    await _makeReadOnly(tester, h);
    final before = _snapshot(h);
    for (final a in EditorAction.values) {
      _runner(h).run(
        a,
        a == EditorAction.toolPalette || a == EditorAction.colorPalette
            ? const PencilSource(
                hoverGlobal: Offset(300, 400),
                preferred: StylusPreferredAction.unknown,
              )
            : _tap,
      );
    }
    await _settle(tester);
    expect(_snapshot(h), before);
    expect(h.session.history.undoDepth, 1);
  });

  test('sources compare by value', () {
    expect(
      const GestureSource(Offset(1, 2)),
      const GestureSource(Offset(1, 2)),
    );
    expect(
      const GestureSource(Offset(1, 2)) == const GestureSource(Offset(1, 3)),
      isFalse,
    );
    expect(
      const PencilSource(
        hoverGlobal: Offset(1, 2),
        preferred: StylusPreferredAction.ignore,
      ),
      const PencilSource(
        hoverGlobal: Offset(1, 2),
        preferred: StylusPreferredAction.ignore,
      ),
    );
    expect(
      const PencilSource(preferred: StylusPreferredAction.ignore) ==
          const PencilSource(preferred: StylusPreferredAction.unknown),
      isFalse,
    );
  });
}
