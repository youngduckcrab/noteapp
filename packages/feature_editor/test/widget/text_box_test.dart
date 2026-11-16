// m5-7/04-editor 8.2 E2-10, 6.11.1, 6.11.3, 6.11.5, 6.11.7: the text box
// through the whole editor (fake CORE, R2-B3 INK) — the text tool's starts
// (tap rule, drag → the EDITOR outline, an existing box), the session's
// hidden ids, the router-side ends (pen contact, one-finger tap, long press)
// and what keeps a session (navigation, rejected palms, pen-only finger
// scrolls, the web's airborne pen), the canvas focus yield (V7 — on the real
// PageViewport with the 1st-round EditorCanvasFocus, a pump after every
// action), the other ends (focus loss, another text field, the toolbar,
// tool change, Esc, back, app hidden, toolbar undo) and the command rules
// (remove when emptied, a remotely deleted original → a new box, a
// read-only rejection → the system clipboard).
import 'dart:math' as math;

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/input/stylus_contact.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/text/text_box_editor.dart';
import 'package:feature_editor/src/text/text_box_placement.dart';
import 'package:feature_editor/src/text/text_edit_session.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_options.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/overlays/new_text_box_outline.dart';
import 'package:feature_editor/src/ui/text/text_style_controls.dart';
import 'package:feature_editor/src/ui/toolbar/undo_redo_buttons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/pump_editor.dart';

const _penOnly = EditorSettings(inputMode: InputMode.penOnly);

final core.TextBoxObject _box = PageObjectFixtures.textBox(
  pageId: 'x',
  id: 'tb-1',
  text: '메모',
  rect: const core.PageRect(100, 300, 400, 340),
);

final core.ShapeObject _shape = PageObjectFixtures.shape(
  pageId: 'x',
  id: 'shape-1',
  rect: const core.PageRect(320, 520, 470, 620),
  createdAt: 2,
);

final _editor = find.byKey(textEditorKey);

Future<EditorTestHandles> _pump(
  WidgetTester tester, {
  EditorTool tool = EditorTool.text,
  EditorSettings settings = _penOnly,
}) async {
  final h = await pumpEditor(
    tester,
    settings: settings,
    objectsByPageIndex: {
      0: [_box, _shape],
    },
  );
  h.container.read(editorCommandsProvider).selectTool(tool);
  await tester.pump();
  return h;
}

TextEditNotifier _notifier(EditorTestHandles h) =>
    h.container.read(editorTextEditProvider.notifier);

TextEditState? _state(EditorTestHandles h) =>
    h.container.read(editorTextEditProvider);

List<String> _edits(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute')) c,
];

core.PageContent _page(EditorTestHandles h) =>
    h.session.pageIfLoaded(h.pageId(0))!;

core.TextBoxObject _stored(EditorTestHandles h, String id) =>
    _page(h).objectById(id)! as core.TextBoxObject;

FocusNode _editorFocus(WidgetTester tester) =>
    tester.widget<TextField>(_editor).focusNode!;

bool _canvasHasPrimaryFocus() =>
    FocusManager.instance.primaryFocus?.debugLabel == 'EditorCanvas';

/// The stored box's edit session, the editor focused.
Future<void> _editBox(WidgetTester tester, EditorTestHandles h) async {
  _notifier(h).start(_stored(h, _box.id), isNew: false);
  await tester.pump();
  await tester.pump();
  expect(_editorFocus(tester).hasFocus, isTrue);
}

/// Waits for the session end's command and the frames after it.
Future<void> _settle(WidgetTester tester, EditorTestHandles h) async {
  await _notifier(h).ending;
  await tester.pump();
  await tester.pump();
}

/// A stylus tap at page point [p] (1 px of movement).
Future<void> _penTap(WidgetTester tester, EditorTestHandles h, Offset p) async {
  final at = h.toGlobal(0, p);
  await h.driver.down(1, at, kind: PointerDeviceKind.stylus);
  await h.driver.wait(const Duration(milliseconds: 20));
  await h.driver.move(1, at + const Offset(1, 0));
  await h.driver.wait(const Duration(milliseconds: 20));
  await h.driver.up(1);
  await tester.pump();
}

/// A stylus drag from page point [a] to [b] in 6 moves.
Future<void> _penDrag(
  WidgetTester tester,
  EditorTestHandles h,
  Offset a,
  Offset b, {
  bool lift = true,
}) async {
  final from = h.toGlobal(0, a), to = h.toGlobal(0, b);
  await h.driver.down(1, from, kind: PointerDeviceKind.stylus);
  for (var i = 1; i <= 6; i++) {
    await h.driver.wait(const Duration(milliseconds: 8));
    await h.driver.move(1, Offset.lerp(from, to, i / 6)!);
  }
  if (lift) {
    await h.driver.wait(const Duration(milliseconds: 8));
    await h.driver.up(1);
  }
  await tester.pump();
}

/// A one-finger tap at page point [p] (past the pen cooldown first).
Future<void> _fingerTap(
  WidgetTester tester,
  EditorTestHandles h,
  Offset p,
) async {
  await h.driver.wait(const Duration(seconds: 1));
  final at = h.toGlobal(0, p);
  await h.driver.down(11, at);
  await h.driver.wait(const Duration(milliseconds: 60));
  await h.driver.up(11);
  await tester.pump();
}

/// The editor's top-left in viewport coordinates.
Offset _editorTopLeft(WidgetTester tester, EditorTestHandles h) =>
    tester.getTopLeft(_editor) - h.viewportOrigin;

/// Where the session's frame top-left is on screen now.
Offset _frameTopLeftOnScreen(EditorTestHandles h) {
  final r = _state(h)!.draft.frame.rect;
  return h.viewport.pageToScreen(0, Offset(r.left, r.top));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await useInkTestFonts();
  });
  tearDown(() {
    TextEditNotifier.debugIsWebOverride = null;
    StylusContact.debugRuleOverride = null;
  });

  group('starts (6.11.1)', () {
    testWidgets('a tap on empty space → a new box by the tap rule in '
        'ToolOptions.textStyle; at the right edge it is 40 pt, pushed left', (
      tester,
    ) async {
      final h = await _pump(tester);
      const style = core.TextBoxStyle(fontSizePt: 20, bold: true);
      h.container.read(editorToolOptionsProvider.notifier).setTextStyle(style);
      await _penTap(tester, h, const Offset(120, 450));

      final s = _state(h)!;
      expect(s.isNew, isTrue);
      expect(s.original, isNull);
      expect(s.draft.style, style);
      final r = s.draft.frame.rect;
      final tapped = h.toPage(0, h.toGlobal(0, const Offset(120, 450)));
      expect(r.left, closeTo(tapped.dx, 1e-6));
      expect(r.top, closeTo(tapped.dy, 1e-6));
      expect(r.right - r.left, TextBoxPlacement.tapWidth);
      expect(_edits(h), isEmpty, reason: 'nothing stored before the end');
      expect(h.controllerOf(0).hiddenObjectIds, isEmpty, reason: 'new box');
      expect(_editorFocus(tester).hasFocus, isTrue);

      // An empty new box ends without a command; the next tap at the right
      // edge: 40 pt wide, moved left to keep 16 pt from the edge.
      final width = h.session.pages[0].size.width;
      await _penTap(tester, h, Offset(width - 20, 200));
      await _settle(tester, h);
      expect(_edits(h), isEmpty);
      final edge = _state(h)!.draft.frame.rect;
      expect(edge.right - edge.left, TextBoxPlacement.minWidth);
      expect(edge.left, closeTo(width - 16 - 40, 1e-9));
    });

    testWidgets('a drag on empty space → the EDITOR outline (no INK preview) '
        '→ a new box as wide as the drag, at its top-left', (tester) async {
      final h = await _pump(tester);
      await _penDrag(
        tester,
        h,
        const Offset(300, 420),
        const Offset(120, 440),
        lift: false,
      );
      expect(find.byKey(NewTextBoxOutline.outlineKey), findsOneWidget);
      expect(h.controllerOf(0).previewObjects, isEmpty);
      expect(_state(h), isNull, reason: 'no session while dragging');

      await h.driver.up(1);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(NewTextBoxOutline.outlineKey), findsNothing);
      final s = _state(h)!;
      expect(s.isNew, isTrue);
      final a = h.toPage(0, h.toGlobal(0, const Offset(300, 420)));
      final b = h.toPage(0, h.toGlobal(0, const Offset(120, 440)));
      final r = s.draft.frame.rect;
      expect(r.left, closeTo(b.dx, 1e-6));
      expect(r.top, closeTo(a.dy, 1e-6));
      expect(r.right - r.left, closeTo(a.dx - b.dx, 1e-6));
      expect(_editorFocus(tester).hasFocus, isTrue);
    });

    testWidgets('a narrow drag → 40 pt; an outline drag cancelled → nothing', (
      tester,
    ) async {
      final h = await _pump(tester);
      await _penDrag(tester, h, const Offset(200, 200), const Offset(215, 230));
      await tester.pump();
      final r = _state(h)!.draft.frame.rect;
      expect(r.right - r.left, TextBoxPlacement.minWidth);
      await _notifier(h).end(reason: TextEditEndReason.escape);
      await tester.pump();

      await _penDrag(
        tester,
        h,
        const Offset(200, 120),
        const Offset(320, 120),
        lift: false,
      );
      expect(find.byKey(NewTextBoxOutline.outlineKey), findsOneWidget);
      await h.driver.cancel(1);
      await tester.pump();
      expect(find.byKey(NewTextBoxOutline.outlineKey), findsNothing);
      expect(_state(h), isNull);
      expect(_edits(h), isEmpty);
    });

    testWidgets('a tap on a text box → its session: hiddenIdsOf == {id} and '
        'INK hides it; the end → {}', (tester) async {
      final h = await _pump(tester);
      await _penTap(tester, h, const Offset(200, 320));
      await tester.pump();

      final s = _state(h)!;
      expect(s.isNew, isFalse);
      expect(s.boxId, _box.id);
      expect(s.original!.text, '메모');
      expect(hiddenIdsOf(s), {_box.id});
      expect(h.controllerOf(0).hiddenObjectIds, {_box.id});
      expect(tester.widget<TextField>(_editor).controller!.text, '메모');

      await _notifier(h).end(reason: TextEditEndReason.escape);
      await tester.pump();
      expect(h.controllerOf(0).hiddenObjectIds, isEmpty);
      expect(_edits(h), isEmpty, reason: 'unchanged');
    });

    testWidgets('a tap on another object selects it (origin tap — no edit); '
        'its body down then starts a new box', (tester) async {
      final h = await _pump(tester);
      // On the unfilled shape's left edge: INK hits an unfilled shape on its
      // outline only (03-ink 6.14). The second tap is inside its frame (the
      // selection's body).
      await _penTap(tester, h, const Offset(320, 570));
      final selection = h.container.read(editorSelectionProvider)!;
      expect(selection.elementIds, {_shape.id});
      expect(selection.origin, SelectionOrigin.tap);
      expect(_state(h), isNull);

      await _penTap(tester, h, const Offset(400, 570));
      expect(h.container.read(editorSelectionProvider), isNull);
      expect(_state(h)!.isNew, isTrue);
    });

    testWidgets('pen-only finger taps: a text box → its session, empty space '
        '→ the selection cleared (no new box)', (tester) async {
      final h = await _pump(tester);
      await _fingerTap(tester, h, const Offset(120, 470));
      expect(_state(h), isNull);
      await _fingerTap(tester, h, const Offset(200, 320));
      await tester.pump();
      expect(_state(h)!.boxId, _box.id);
    });

    testWidgets('emptied → ONE RemoveElements(elementIds: [id])', (
      tester,
    ) async {
      final h = await _pump(tester);
      await _editBox(tester, h);
      await tester.enterText(_editor, '   ');
      await tester.pump();
      await _notifier(h).end(reason: TextEditEndReason.escape);
      await _settle(tester, h);
      expect(_edits(h), ['execute:remove-elements']);
      expect(_page(h).objectById(_box.id), isNull);
      expect(h.session.history.undoDepth, 1);
    });
  });

  group('kept while editing (6.11.5 — V7, the real PageViewport)', () {
    testWidgets('a two-finger drag and a pinch: kept, no command, the editor '
        'follows the camera, its focus stays, no focus loss', (tester) async {
      final h = await _pump(tester, tool: EditorTool.pen);
      await _editBox(tester, h);
      final before = _editorTopLeft(tester, h);

      final a = h.toGlobal(0, const Offset(150, 450));
      final b = h.toGlobal(0, const Offset(350, 450));
      await h.driver.down(31, a);
      await tester.pump();
      expect(_editorFocus(tester).hasFocus, isTrue, reason: 'first down');
      await h.driver.down(32, b);
      for (var i = 1; i <= 8; i++) {
        await h.driver.wait(const Duration(milliseconds: 8));
        await h.driver.move(31, a + Offset(0, -12.0 * i));
        await h.driver.move(32, b + Offset(0, -12.0 * i));
      }
      await h.driver.up(31);
      await h.driver.up(32);
      await tester.pump();
      await tester.pump();

      final after = _editorTopLeft(tester, h);
      expect((after - before).distance, greaterThan(40));
      expect(after.dx, closeTo(_frameTopLeftOnScreen(h).dx, 1e-3));
      expect(after.dy, closeTo(_frameTopLeftOnScreen(h).dy, 1e-3));

      await h.driver.pinch(
        center: h.toGlobal(0, const Offset(250, 450)),
        startSpan: 120,
        endSpan: 240,
      );
      await tester.pump();
      await tester.pump();
      expect(h.viewport.camera.scale, isNot(closeTo(1, 1e-3)));
      final zoomed = _editorTopLeft(tester, h);
      expect(zoomed.dx, closeTo(_frameTopLeftOnScreen(h).dx, 1e-3));
      expect(zoomed.dy, closeTo(_frameTopLeftOnScreen(h).dy, 1e-3));

      expect(_state(h), isNotNull);
      expect(_notifier(h).lastEndReason, isNull, reason: 'no focus loss');
      expect(_editorFocus(tester).hasFocus, isTrue);
      expect(_edits(h), isEmpty);
    });

    testWidgets('a rejected palm, a pen-only one-finger scroll: kept, the '
        'focus stays', (tester) async {
      final h = await _pump(tester, tool: EditorTool.pen);
      await _editBox(tester, h);

      // P5: a contact wider than maxTouchRadius (45) is a palm.
      await h.driver.down(
        12,
        h.toGlobal(0, const Offset(200, 450)),
        radiusMajor: 80,
      );
      await tester.pump();
      await h.driver.wait(const Duration(milliseconds: 60));
      await h.driver.up(12);
      await tester.pump();
      expect(_state(h), isNotNull);
      expect(_editorFocus(tester).hasFocus, isTrue);

      final scrollBefore = h.viewport.camera.origin;
      await h.driver.fingerDrag(
        h.toGlobal(0, const Offset(200, 480)),
        h.toGlobal(0, const Offset(200, 380)),
      );
      await tester.pump();
      await tester.pump();
      expect(h.viewport.camera.origin, isNot(scrollBefore));
      expect(_state(h), isNotNull);
      expect(_editorFocus(tester).hasFocus, isTrue);
      expect(_notifier(h).lastEndReason, isNull);
      expect(_edits(h), isEmpty);
    });

    testWidgets('finger drawing: a one-finger drag scrolls during a session '
        '(no stroke), the session stays', (tester) async {
      final h = await _pump(
        tester,
        tool: EditorTool.pen,
        settings: const EditorSettings(inputMode: InputMode.fingerDrawing),
      );
      await _editBox(tester, h);
      await h.driver.fingerDrag(
        h.toGlobal(0, const Offset(200, 480)),
        h.toGlobal(0, const Offset(200, 380)),
      );
      await tester.pump();
      expect(_state(h), isNotNull);
      expect(_editorFocus(tester).hasFocus, isTrue);
      expect(_edits(h), isEmpty);
    });

    testWidgets('web rule: an airborne pen down 0x02 is no contact — kept, '
        'the focus stays', (tester) async {
      StylusContact.debugRuleOverride = StylusContactRule.web;
      final h = await _pump(tester, tool: EditorTool.pen);
      await _editBox(tester, h);
      await h.driver.down(
        1,
        h.toGlobal(0, const Offset(200, 450)),
        kind: PointerDeviceKind.stylus,
        buttons: kPrimaryStylusButton,
      );
      await tester.pump();
      expect(_state(h), isNotNull);
      expect(_editorFocus(tester).hasFocus, isTrue);
      await h.driver.up(1);
      await tester.pump();
      expect(_state(h), isNotNull);
      expect(_edits(h), isEmpty);
    });
  });

  group('router-side ends (6.11.5)', () {
    testWidgets('a one-finger tap → ONE end (canvasTap), the tap used up; '
        'the canvas has the primary focus again (key E → eraser)', (
      tester,
    ) async {
      final h = await _pump(tester, tool: EditorTool.lasso);
      await _editBox(tester, h);
      await tester.enterText(_editor, '메모 추가');
      await tester.pump();
      await _fingerTap(tester, h, const Offset(400, 570));
      await _settle(tester, h);

      expect(_notifier(h).lastEndReason, TextEditEndReason.canvasTap);
      expect(_edits(h), ['execute:update-objects']);
      expect(_stored(h, _box.id).text, '메모 추가');
      expect(
        h.container.read(editorSelectionProvider),
        isNull,
        reason: 'the tap is used up — the shape under it is not selected',
      );
      expect(_canvasHasPrimaryFocus(), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.pump();
      expect(
        h.container.read(editorToolProvider).activeTool,
        EditorTool.eraser,
      );
    });

    testWidgets('a pen contact → the end (penContact), then the contact goes '
        'on with the pen: two commands, one step each; key P works again', (
      tester,
    ) async {
      final h = await _pump(tester, tool: EditorTool.pen);
      await _editBox(tester, h);
      await tester.enterText(_editor, '메모 2');
      await tester.pump();
      await _penDrag(tester, h, const Offset(150, 450), const Offset(300, 470));
      await _settle(tester, h);

      expect(_notifier(h).lastEndReason, TextEditEndReason.penContact);
      expect(_edits(h), hasLength(2));
      expect(_edits(h).first, 'execute:update-objects');
      expect(_page(h).strokes, hasLength(1));
      expect(h.session.history.undoDepth, 2);
      expect(_canvasHasPrimaryFocus(), isTrue);
      h.container.read(editorCommandsProvider).selectTool(EditorTool.lasso);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.pump();
      expect(h.container.read(editorToolProvider).activeTool, EditorTool.pen);
    });

    testWidgets('the text tool: a pen contact elsewhere ends the session and '
        'that tap starts a new box', (tester) async {
      final h = await _pump(tester);
      await _editBox(tester, h);
      await _penTap(tester, h, const Offset(150, 200));
      await tester.pump();
      expect(_notifier(h).lastEndReason, TextEditEndReason.penContact);
      expect(_state(h)!.isNew, isTrue);
      expect(_edits(h), isEmpty, reason: 'the box was not changed');
    });

    testWidgets('a long press → the end (longPress), then the menu', (
      tester,
    ) async {
      final h = await _pump(tester, tool: EditorTool.pen);
      await _editBox(tester, h);
      await h.driver.wait(const Duration(seconds: 1));
      await h.driver.down(11, h.toGlobal(0, const Offset(200, 450)));
      await h.driver.wait(const Duration(milliseconds: 600));
      await tester.pump();
      expect(_notifier(h).lastEndReason, TextEditEndReason.longPress);
      expect(_state(h), isNull);
      expect(
        h.container.read(editorInteractionHostProvider).contextMenu.value,
        isNotNull,
      );
      await h.driver.up(11);
      await tester.pump();
    });
  });

  group('other ends', () {
    testWidgets('unfocus (keyboard hide) → focusLost → the canvas is the '
        'primary focus', (tester) async {
      final h = await _pump(tester, tool: EditorTool.pen);
      await _editBox(tester, h);
      _editorFocus(tester).unfocus();
      await tester.pump();
      await tester.pump();
      expect(_notifier(h).lastEndReason, TextEditEndReason.focusLost);
      expect(_state(h), isNull);
      expect(_canvasHasPrimaryFocus(), isTrue);
    });

    testWidgets('another text field takes the focus → focusLost, that field '
        'keeps the primary focus (the canvas does not take it)', (
      tester,
    ) async {
      final h = await _pump(tester, tool: EditorTool.pen);
      final other = FocusNode(debugLabel: 'other field');
      addTearDown(other.dispose);
      final entry = OverlayEntry(
        builder: (_) => Positioned(
          left: 8,
          bottom: 8,
          width: 200,
          child: Material(child: TextField(focusNode: other)),
        ),
      );
      tester.state<OverlayState>(find.byType(Overlay).first).insert(entry);
      addTearDown(entry.remove);
      await tester.pump();
      await _editBox(tester, h);

      other.requestFocus();
      await tester.pump();
      await tester.pump();
      expect(_notifier(h).lastEndReason, TextEditEndReason.focusLost);
      expect(FocusManager.instance.primaryFocus, other);
    });

    testWidgets('a tap on the toolbar → tapOutside', (tester) async {
      final h = await _pump(tester, tool: EditorTool.pen);
      await _editBox(tester, h);
      await tapToolbarBlank(tester);
      await tester.pump();
      expect(_notifier(h).lastEndReason, TextEditEndReason.tapOutside);
    });

    testWidgets('a tool change → toolChange; Esc → escape', (tester) async {
      final h = await _pump(tester, tool: EditorTool.pen);
      await _editBox(tester, h);
      h.container.read(editorCommandsProvider).selectTool(EditorTool.lasso);
      await tester.pump();
      expect(_notifier(h).lastEndReason, TextEditEndReason.toolChange);
      expect(_state(h), isNull);

      await _editBox(tester, h);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(_notifier(h).lastEndReason, TextEditEndReason.escape);
      expect(_state(h), isNull);
    });

    testWidgets('system back → leaving, its command before the flush', (
      tester,
    ) async {
      final h = await _pump(tester, tool: EditorTool.pen);
      await _editBox(tester, h);
      await tester.enterText(_editor, '떠나기 전');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump();
      expect(_notifier(h).lastEndReason, TextEditEndReason.leaving);
      final calls = h.recorder!.calls;
      final update = calls.indexOf('execute:update-objects');
      expect(update, isNonNegative);
      expect(calls.indexOf('flush'), greaterThan(update));
      expect(h.closeCount, 1);
    });

    testWidgets('app inactive keeps the session (FocusManager suspends the '
        'focus); hidden → appHidden, then the flush', (tester) async {
      final h = await _pump(tester, tool: EditorTool.pen);
      await _editBox(tester, h);
      await tester.enterText(_editor, '숨기기 전');
      await tester.pump();
      final binding = tester.binding;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(_state(h), isNotNull);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      await tester.pump();
      expect(_notifier(h).lastEndReason, TextEditEndReason.appHidden);
      final calls = h.recorder!.calls;
      expect(
        calls.indexOf('flush'),
        greaterThan(calls.indexOf('execute:update-objects')),
      );
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    });

    testWidgets('toolbar undo → the session ends, then undo → as before', (
      tester,
    ) async {
      final h = await _pump(tester, tool: EditorTool.pen);
      await _editBox(tester, h);
      await tester.enterText(_editor, '바꾼 글');
      await tester.pump();
      await tester.tap(find.byKey(UndoRedoButtons.undoKey));
      await _settle(tester, h);
      await tester.pump();

      expect(_state(h), isNull);
      expect(_edits(h), ['execute:update-objects']);
      expect(h.recorder!.calls.where((c) => c == 'undo'), hasLength(1));
      expect(_stored(h, _box.id).text, '메모');
      expect(h.session.history.undoDepth, 0);
    });
  });

  group('commands (6.11.5)', () {
    testWidgets('the format bar: pressing it keeps the session; size 24 + '
        'a text edit → ONE UpdateObjects at the end, height = measure', (
      tester,
    ) async {
      final h = await _pump(tester, tool: EditorTool.pen);
      await _editBox(tester, h);
      final bar = find.byKey(TextFormatBar.barKey);
      expect(bar, findsOneWidget);
      Future<void> tapBar(Key key) async {
        await tester.tap(find.descendant(of: bar, matching: find.byKey(key)));
        await tester.pump();
        await tester.pump();
      }

      await tapBar(TextStyleControls.sizeKey);
      await tapBar(TextStyleControls.presetKey(24));
      expect(_state(h), isNotNull, reason: 'the bar is in the tap group');
      expect(_notifier(h).lastEndReason, isNull);
      expect(_editorFocus(tester).hasFocus, isTrue);
      expect(_state(h)!.draft.style.fontSizePt, 24);
      await tester.enterText(_editor, '큰 글자로 바꾼 메모');
      await tester.pump();
      expect(_edits(h), isEmpty, reason: 'nothing before the end');

      await _notifier(h).end(reason: TextEditEndReason.escape);
      await _settle(tester, h);
      expect(_edits(h), ['execute:update-objects']);
      final stored = _stored(h, _box.id);
      expect(stored.style.fontSizePt, 24);
      expect(stored.text, '큰 글자로 바꾼 메모');
      final measured = await tester.runAsync(
        () => ink.InkTextLayout.measure(
          stored.text,
          stored.style,
          widthPt: stored.frame.rect.width,
        ),
      );
      final r = stored.frame.rect;
      expect(r.top, closeTo(_box.frame.rect.top, 1e-9));
      expect(
        r.bottom - r.top,
        closeTo(math.max(measured!.height, 24 * stored.style.lineHeight), 1e-6),
      );
    });

    testWidgets('the original deleted remotely while editing → AddObjects '
        'with a new id, no UpdateObjects, no snack bar', (tester) async {
      final h = await _pump(tester, tool: EditorTool.pen);
      await _editBox(tester, h);
      // A remote delete: the inner session, past the recording wrapper.
      h.session.execute(
        core.RemoveElements(pageId: h.pageId(0), elementIds: [_box.id]),
      );
      await tester.pump();
      expect(_state(h), isNotNull, reason: 'the session stays open');
      await tester.enterText(_editor, '살린 글');
      await tester.pump();
      await _notifier(h).end(reason: TextEditEndReason.escape);
      await _settle(tester, h);

      expect(_edits(h), ['execute:add-objects']);
      final objects = _page(h).objects.whereType<core.TextBoxObject>();
      expect(objects.single.text, '살린 글');
      expect(objects.single.id, isNot(_box.id));
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a read-only rejection → the text on the system clipboard '
        'and the notice; the hidden id cleared', (tester) async {
      final h = await _pump(tester, tool: EditorTool.pen);
      final copied = <String?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String?);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _editBox(tester, h);
      await tester.enterText(_editor, '거절된 글');
      await tester.pump();
      h.recorder!.rejectNext(const core.ReadOnlyNoteException('race'));
      await _notifier(h).end(reason: TextEditEndReason.escape);
      await _settle(tester, h);

      expect(copied, ['거절된 글']);
      expect(_stored(h, _box.id).text, '메모');
      expect(h.controllerOf(0).hiddenObjectIds, isEmpty);
      expect(
        find.textContaining(EditorStrings.textCopiedToClipboard),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5)); // the snack bar timer
    });
  });
}
