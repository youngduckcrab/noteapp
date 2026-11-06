// m5-7/04-editor 8.2 E2-04a: temporary tools through the whole editor
// (6.2.3, 6.3.3, 6.3.6 4): PointerDriver pen-button / eraser-tip strokes →
// InputRouter (contact rule, gesture at contact) → InteractionHost
// (GestureSettings.actionFor) → Erase / Lasso interaction → fake CORE
// session. ToolState never changes.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/input/stylus_contact.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/tools/erase_interaction.dart';
import 'package:feature_editor/src/tools/eyedropper_interaction.dart';
import 'package:feature_editor/src/tools/interaction_host.dart';
import 'package:feature_editor/src/tools/lasso_interaction.dart';
import 'package:feature_editor/src/tools/pen_interaction.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_interaction.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

Map<int, List<core.Stroke>> get _strokes => {
  0: [strokeA, strokeB],
};

/// A vertical path at x = 150 pt across strokeA (y 150) only.
List<Offset> _acrossA(EditorTestHandles h) =>
    pathThrough(h, 0, [for (var y = 110.0; y <= 190; y += 10) Offset(150, y)]);

List<String> _executes(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute')) c,
];

Set<String> _coreIds(EditorTestHandles h) => {
  for (final s in h.session.pageIfLoaded(h.pageId(0))!.strokes) s.id,
};

ToolState _tools(EditorTestHandles h) => h.container.read(editorToolProvider);

ToolInteraction? _lastStarted(EditorTestHandles h) =>
    h.container.read(editorInteractionHostProvider).lastStarted;

/// The temporary eraser uses the eraser settings (6.2.3): stroke mode here so
/// the command is RemoveStrokes with both INKs.
Future<void> _strokeEraser(WidgetTester tester, EditorTestHandles h) async {
  h.container
      .read(editorToolProvider.notifier)
      .updateEraser((e) => e.copyWith(mode: ink.EraserMode.stroke));
  await tester.pump();
}

EditorSettings _withPenButton(EditorAction action) => EditorSettings(
  gestures: GestureSettings(actions: {EditorGesture.penButton: action}),
);

void main() {
  testWidgets('pen tool + native pen button (default eraserWhileHeld) → a '
      'temporary eraser: strokeA erased, the tool stays pen', (tester) async {
    final h = await pumpEditor(tester, strokesByPageIndex: _strokes);
    await _strokeEraser(tester, h);
    final before = _tools(h);
    await h.driver.nativePenButtonStroke(_acrossA(h));
    await tester.pump();
    expect(_lastStarted(h), isA<EraseInteraction>());
    expect(_executes(h), ['execute:remove-strokes']);
    expect(_coreIds(h), {strokeB.id});
    expect(_tools(h), before);
    expect(_tools(h).activeTool, EditorTool.pen);

    // The next plain stroke draws again.
    await h.driver.stylusStroke(_acrossA(h));
    expect(_lastStarted(h), isA<PenInteraction>());
    expect(_executes(h), ['execute:remove-strokes', 'execute:add-strokes']);
  });

  testWidgets('the eraser tip (invertedStylus) → a temporary eraser in every '
      'tool', (tester) async {
    final h = await pumpEditor(tester, strokesByPageIndex: _strokes);
    await _strokeEraser(tester, h);
    final commands = h.container.read(editorCommandsProvider);
    for (final tool in [EditorTool.lasso, EditorTool.shape, EditorTool.pen]) {
      commands.selectTool(tool);
      await tester.pump();
      final before = _tools(h);
      await h.driver.eraserTipStroke(_acrossA(h));
      await tester.pump();
      expect(_lastStarted(h), isA<EraseInteraction>(), reason: tool.name);
      expect(_tools(h), before, reason: tool.name);
    }
    expect(_executes(h), ['execute:remove-strokes']); // strokeA, once
    expect(_coreIds(h), {strokeB.id});
  });

  testWidgets('a temporary eraser ignores "return to the previous tool" and '
      'the eraser settings stay', (tester) async {
    final h = await pumpEditor(tester, strokesByPageIndex: _strokes);
    await _strokeEraser(tester, h);
    h.container
        .read(editorToolProvider.notifier)
        .updateEraser((e) => e.copyWith(returnToPreviousTool: true));
    await tester.pump();
    final before = _tools(h);
    await h.driver.nativePenButtonStroke(_acrossA(h));
    await tester.pump();
    expect(_executes(h), ['execute:remove-strokes']);
    expect(_tools(h), before);
    expect(_tools(h).previousTool, before.previousTool);
  });

  testWidgets('penButton = lassoWhileHeld → a temporary lasso: the selection '
      'stays with the pen tool', (tester) async {
    final h = await pumpEditor(
      tester,
      strokesByPageIndex: _strokes,
      settings: _withPenButton(EditorAction.lassoWhileHeld),
    );
    final rect = Rect.fromLTRB(
      strokeA.bounds.left,
      strokeA.bounds.top,
      strokeA.bounds.right,
      strokeA.bounds.bottom,
    );
    await h.driver.nativePenButtonStroke(lassoAround(h, 0, rect));
    await tester.pump();
    expect(_lastStarted(h), isA<LassoInteraction>());
    final EditorSelection? selection = h.container.read(
      editorSelectionProvider,
    );
    expect(selection?.elementIds, {strokeA.id});
    expect(_tools(h).activeTool, EditorTool.pen);
    expect(_executes(h), isEmpty);
  });

  testWidgets('penButton = none → the current tool (a pen stroke)', (
    tester,
  ) async {
    final h = await pumpEditor(
      tester,
      strokesByPageIndex: _strokes,
      settings: _withPenButton(EditorAction.none),
    );
    await h.driver.nativePenButtonStroke(_acrossA(h));
    expect(_lastStarted(h), isA<PenInteraction>());
    expect(_executes(h), ['execute:add-strokes']);
    expect(_coreIds(h), hasLength(3));
  });

  testWidgets('invertedStylus = none → the current tool', (tester) async {
    final h = await pumpEditor(
      tester,
      strokesByPageIndex: _strokes,
      settings: const EditorSettings(
        gestures: GestureSettings(
          actions: {EditorGesture.invertedStylus: EditorAction.none},
        ),
      ),
    );
    await h.driver.eraserTipStroke(_acrossA(h));
    expect(_lastStarted(h), isA<PenInteraction>());
    expect(_executes(h), ['execute:add-strokes']);
  });

  testWidgets('the eyedropper wins over the pen button', (tester) async {
    final h = await pumpEditor(tester, strokesByPageIndex: _strokes);
    h.container.read(editorCommandsProvider).startEyedropper();
    await tester.pump();
    await h.driver.nativePenButtonStroke([
      h.toGlobal(0, const Offset(150, 150)),
    ]);
    await tester.pump();
    expect(_lastStarted(h), isA<EyedropperInteraction>());
    expect(_executes(h), isEmpty);
    expect(_coreIds(h), {strokeA.id, strokeB.id});
    await tester.pump(const Duration(seconds: 5)); // snack bar
    await tester.pumpAndSettle();
  });

  testWidgets('a read-only note: no temporary eraser either', (tester) async {
    final h = await pumpEditor(tester, strokesByPageIndex: _strokes);
    await h.store.library.trashItems([core.NoteRef(h.noteId)]);
    await tester.pump();
    expect(h.container.read(editorReadOnlyProvider), isTrue);
    await h.driver.nativePenButtonStroke(_acrossA(h));
    await h.driver.eraserTipStroke(_acrossA(h));
    expect(_lastStarted(h), isNull);
    expect(_executes(h), isEmpty);
    expect(_coreIds(h), {strokeA.id, strokeB.id});
  });

  testWidgets('web order (down 0x02 → move 0x03 … → move 0x02 → up) → one '
      'temporary erase, no stroke from the airborne down', (tester) async {
    StylusContact.debugRuleOverride = StylusContactRule.web;
    addTearDown(() => StylusContact.debugRuleOverride = null);
    final h = await pumpEditor(tester, strokesByPageIndex: _strokes);
    await _strokeEraser(tester, h);
    expect(
      h.container.read(editorInputRouterProvider).contactRule,
      StylusContactRule.web,
    );
    final before = _tools(h);
    await h.driver.webPenButtonStroke(_acrossA(h));
    await tester.pump();
    expect(_lastStarted(h), isA<EraseInteraction>());
    expect(_executes(h), ['execute:remove-strokes']);
    expect(_coreIds(h), {strokeB.id});
    expect(_tools(h), before);
  });
}
