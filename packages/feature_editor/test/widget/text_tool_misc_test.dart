// m5-7/04-editor 8.2 E2-10, 6.11.1, 6.11.3, 6.11.5, 6.11.7, 6.7.6: the
// text tool's remaining rules (fake CORE, R2-B3 INK) — a read-only note
// starts no session (pen tap, finger tap, the menu's 편집 · 서식 off), the
// 10,000-character limit (cut, the notice, the stored text), the tool keys
// typed as letters while editing (P · E · L · S · T — no tool change, no
// command), and the keyboard covering the box → the page scrolls just that
// much.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/text/text_box_editor.dart';
import 'package:feature_editor/src/text/text_edit_session.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/overlays/selection_menu.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

/// Low on the first screen: a 500 px keyboard covers it.
final core.TextBoxObject _lowBox = PageObjectFixtures.textBox(
  pageId: 'x',
  id: 'tb-low',
  text: '아래',
  rect: const core.PageRect(100, 600, 400, 640),
  createdAt: 2,
);

final _editor = find.byKey(textEditorKey);

Future<EditorTestHandles> _pump(
  WidgetTester tester, {
  EditorTool tool = EditorTool.text,
}) async {
  final h = await pumpEditor(
    tester,
    settings: _penOnly,
    objectsByPageIndex: {
      0: [_box, _lowBox],
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

Future<void> _penTap(WidgetTester tester, EditorTestHandles h, Offset p) async {
  final at = h.toGlobal(0, p);
  await h.driver.down(1, at, kind: PointerDeviceKind.stylus);
  await h.driver.wait(const Duration(milliseconds: 20));
  await h.driver.up(1);
  await tester.pump();
}

Future<void> _fingerTap(
  WidgetTester tester,
  EditorTestHandles h,
  Offset p,
) async {
  await h.driver.wait(const Duration(seconds: 1));
  await h.driver.down(11, h.toGlobal(0, p));
  await h.driver.wait(const Duration(milliseconds: 60));
  await h.driver.up(11);
  await tester.pump();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await useInkTestFonts();
  });

  testWidgets('a read-only note: the text tool starts nothing — pen taps on '
      'empty space and on a box, a finger tap on the box; 편집 · 서식 off', (
    tester,
  ) async {
    final h = await _pump(tester);
    await h.store.library.trashItems([core.NoteRef(h.noteId)]);
    await tester.pump();
    expect(h.container.read(editorReadOnlyProvider), isTrue);

    await _penTap(tester, h, const Offset(150, 470));
    expect(_state(h), isNull);
    await _penTap(tester, h, const Offset(200, 320));
    expect(_state(h), isNull);
    await _fingerTap(tester, h, const Offset(200, 320));
    expect(_state(h), isNull);
    expect(_edits(h), isEmpty);

    h.container.read(editorSelectionProvider.notifier).select(h.pageId(0), {
      _box.id,
    }, origin: SelectionOrigin.lasso);
    await tester.pump();
    await tester.tap(find.byKey(SelectionMenu.moreKey));
    await tester.pump();
    for (final key in [SelectionMenu.editTextKey, SelectionMenu.formatKey]) {
      final item = find.byKey(key);
      expect(item, findsOneWidget);
      await tester.tap(item, warnIfMissed: false);
      await tester.pump();
      expect(_state(h), isNull, reason: '$key is off');
    }
    expect(_edits(h), isEmpty);
  });

  testWidgets('10,000 characters: the rest is cut, the notice shows, the '
      'stored text is 10,000 long', (tester) async {
    final h = await _pump(tester);
    await _penTap(tester, h, const Offset(150, 470));
    expect(_state(h)!.isNew, isTrue);
    const max = core.PageObjectLimits.maxTextLength;
    await tester.enterText(_editor, '가' * (max + 5));
    await tester.pump();
    final field = tester.widget<TextField>(_editor);
    expect(field.controller!.text.length, max);
    expect(_state(h)!.draft.text.length, max);
    await tester.pump();
    expect(find.text(EditorStrings.textTooLong(max)), findsOneWidget);
    expect(_state(h), isNotNull, reason: 'the notice keeps the session');

    await _notifier(h).end(reason: TextEditEndReason.escape);
    await _notifier(h).ending;
    await tester.pump();
    expect(_edits(h), ['execute:add-objects']);
    final stored = h.session
        .pageIfLoaded(h.pageId(0))!
        .objects
        .whereType<core.TextBoxObject>()
        .firstWhere((b) => b.id != _box.id && b.id != _lowBox.id);
    expect(stored.text.length, max);
    await tester.pump(const Duration(seconds: 5)); // the snack bar timer
  });

  testWidgets('while editing, P · E · L · S · T are letters: no tool change, '
      'no command', (tester) async {
    final h = await _pump(tester, tool: EditorTool.pen);
    _notifier(h).start(
      h.session.pageIfLoaded(h.pageId(0))!.objectById(_box.id)!
          as core.TextBoxObject,
      isNew: false,
    );
    await tester.pump();
    await tester.pump();
    expect(tester.widget<TextField>(_editor).focusNode!.hasFocus, isTrue);
    for (final key in [
      LogicalKeyboardKey.keyP,
      LogicalKeyboardKey.keyE,
      LogicalKeyboardKey.keyL,
      LogicalKeyboardKey.keyS,
      LogicalKeyboardKey.keyT,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }
    // The platform's text input sends the letters themselves.
    tester.testTextInput.enterText('메모 pelst');
    await tester.pump();
    expect(h.container.read(editorToolProvider).activeTool, EditorTool.pen);
    expect(_state(h)!.draft.text, '메모 pelst');
    expect(_notifier(h).lastEndReason, isNull);
    expect(_edits(h), isEmpty);
  });

  testWidgets('the keyboard covers the box → the page scrolls just that much '
      '(the box bottom + 16 px stays above the keyboard)', (tester) async {
    final h = await _pump(tester, tool: EditorTool.pen);
    final viewport = h.viewport;
    final low = viewport.pageToScreen(0, const Offset(100, 640)).dy;
    expect(low, lessThan(viewport.viewportSize.height), reason: 'on screen');
    _notifier(h).start(
      h.session.pageIfLoaded(h.pageId(0))!.objectById(_lowBox.id)!
          as core.TextBoxObject,
      isNew: false,
    );
    await tester.pump();
    await tester.pump();
    final before = viewport.camera.origin;

    // A 500 px keyboard (the view's insets are physical px — ratio 2).
    tester.view.viewInsets = const FakeViewPadding(bottom: 1000);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(viewport.camera.origin, isNot(before));
    final r = _state(h)!.draft.frame.rect;
    final bottom =
        h.viewportOrigin.dy +
        viewport.pageToScreen(0, Offset(r.left, r.bottom)).dy;
    final keyboardTop = tester.view.physicalSize.height / 2 - 500;
    expect(bottom, lessThanOrEqualTo(keyboardTop - 16 + 0.5));
    expect(
      bottom,
      greaterThan(keyboardTop - 16 - 40),
      reason: 'just that much',
    );
    expect(_state(h), isNotNull);
  });
}
