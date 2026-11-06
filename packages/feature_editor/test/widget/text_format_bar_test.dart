// m5-7/04-editor 8.2 E2-10, 6.11.4, 6.7.5, 6.2.4: the text format bar of an
// edit session (fake CORE, R2-B3 INK) — above the box (below it when there
// is no room), size 6 – 144 and the presets, colour (recent + '더 보기' with
// [적용]), bold, alignment and background change the draft style and
// ToolOptions.textStyle, no button takes the focus (the session goes on, no
// command until its end); the sheet panel has the bar too; the selection
// menu's '서식' (outside a session: ONE UpdateObjects per change, the
// height measured again) and the text tool popup (ToolOptions.textStyle).
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/popup.dart';
import 'package:feature_editor/src/state/settings/editor_device_state.dart';
import 'package:feature_editor/src/text/text_box_editor.dart';
import 'package:feature_editor/src/text/text_edit_session.dart';
import 'package:feature_editor/src/text/text_input_sheet.dart';
import 'package:feature_editor/src/tools/object_resize.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/tools/tool_options.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/color/sv_square.dart';
import 'package:feature_editor/src/ui/overlays/selection_menu.dart';
import 'package:feature_editor/src/ui/text/text_style_controls.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/pump_editor.dart';

final core.TextBoxObject _box = PageObjectFixtures.textBox(
  pageId: 'x',
  id: 'tb-1',
  text: '서식 시험',
  rect: const core.PageRect(100, 300, 400, 340),
);

/// Near the top of page 0: no room above it for the bar on screen.
final core.TextBoxObject _topBox = PageObjectFixtures.textBox(
  pageId: 'x',
  id: 'tb-top',
  text: '위',
  rect: const core.PageRect(100, 4, 300, 30),
  createdAt: 2,
);

final _editor = find.byKey(textEditorKey);
final _bar = find.byKey(TextFormatBar.barKey);

Future<EditorTestHandles> _pump(WidgetTester tester) async {
  final h = await pumpEditor(
    tester,
    objectsByPageIndex: {
      0: [_box, _topBox],
    },
  );
  h.container.read(editorCommandsProvider).selectTool(EditorTool.pen);
  await tester.pump();
  return h;
}

TextEditNotifier _notifier(EditorTestHandles h) =>
    h.container.read(editorTextEditProvider.notifier);

core.TextBoxStyle _draftStyle(EditorTestHandles h) =>
    h.container.read(editorTextEditProvider)!.draft.style;

core.TextBoxStyle _toolStyle(EditorTestHandles h) =>
    h.container.read(editorToolOptionsProvider).textStyle;

List<String> _edits(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute')) c,
];

core.TextBoxObject _stored(EditorTestHandles h, String id) =>
    h.session.pageIfLoaded(h.pageId(0))!.objectById(id)! as core.TextBoxObject;

Future<void> _edit(
  WidgetTester tester,
  EditorTestHandles h,
  core.TextBoxObject box,
) async {
  _notifier(h).start(_stored(h, box.id), isNew: false);
  await tester.pump();
  await tester.pump();
}

/// Taps [key] inside the bar and checks the session went on: no end, the
/// editor focused, no command.
Future<void> _tapInBar(
  WidgetTester tester,
  EditorTestHandles h,
  Key key,
) async {
  await tester.tap(find.descendant(of: _bar, matching: find.byKey(key)));
  await tester.pump();
  await tester.pump();
  expect(h.container.read(editorTextEditProvider), isNotNull);
  expect(_notifier(h).lastEndReason, isNull, reason: 'pressing $key');
  expect(
    tester.widget<TextField>(_editor).focusNode!.hasFocus,
    isTrue,
    reason: 'the bar never takes the focus ($key)',
  );
  expect(_edits(h), isEmpty);
}

bool _enabled(WidgetTester tester, Key key) =>
    tester
        .widget<IconButton>(
          find.descendant(of: _bar, matching: find.byKey(key)),
        )
        .onPressed !=
    null;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await useInkTestFonts();
  });
  tearDown(() => TextEditNotifier.debugIsWebOverride = null);

  testWidgets('the bar sits 8 px above the box; a box at the top of the '
      'screen gets it below', (tester) async {
    final h = await _pump(tester);
    await _edit(tester, h, _box);
    expect(_bar, findsOneWidget);
    final editorRect = tester.getRect(_editor);
    final barRect = tester.getRect(_bar);
    expect(barRect.bottom, lessThanOrEqualTo(editorRect.top - 8 + 0.5));
    await _notifier(h).end(reason: TextEditEndReason.escape);
    await tester.pump();
    expect(_bar, findsNothing);

    // Scroll so the top box is at the very top of the page area.
    final topOnScreen = h.viewport.pageToScreen(0, const Offset(100, 4));
    h.viewport.panBy(Offset(0, topOnScreen.dy - 4));
    h.viewport.settleNow();
    await tester.pump();
    await _edit(tester, h, _topBox);
    final top = tester.getRect(_editor);
    expect(tester.getRect(_bar).top, greaterThanOrEqualTo(top.top + 8));
  });

  testWidgets('size: [−] / [+] by one pt, clamped to 6 – 144 (the buttons '
      'turn off at the ends); the presets set 24', (tester) async {
    final h = await _pump(tester);
    await _edit(tester, h, _box);
    _notifier(h).updateStyle(_draftStyle(h).copyWith(fontSizePt: 7));
    await tester.pump();
    await _tapInBar(tester, h, TextStyleControls.sizeDownKey);
    expect(_draftStyle(h).fontSizePt, 6);
    expect(_enabled(tester, TextStyleControls.sizeDownKey), isFalse);

    _notifier(h).updateStyle(_draftStyle(h).copyWith(fontSizePt: 143));
    await tester.pump();
    await _tapInBar(tester, h, TextStyleControls.sizeUpKey);
    expect(_draftStyle(h).fontSizePt, 144);
    expect(_enabled(tester, TextStyleControls.sizeUpKey), isFalse);
    expect(_toolStyle(h).fontSizePt, 144);

    await _tapInBar(tester, h, TextStyleControls.sizeKey);
    expect(find.byKey(TextStyleControls.presetsKey), findsOneWidget);
    for (final p in TextStyleControls.presets) {
      expect(find.byKey(TextStyleControls.presetKey(p)), findsOneWidget);
    }
    await _tapInBar(tester, h, TextStyleControls.presetKey(24));
    expect(_draftStyle(h).fontSizePt, 24);
    expect(_toolStyle(h).fontSizePt, 24);
    expect(find.byKey(TextStyleControls.presetsKey), findsNothing);
    expect(TextStyleControls.stepped(5, -1), 6);
    expect(TextStyleControls.stepped(200, 1), 144);
  });

  testWidgets('colour, bold, alignment, background → the draft style and '
      'ToolOptions.textStyle; the editor keeps the focus', (tester) async {
    final h = await _pump(tester);
    await _edit(tester, h, _box);

    const red = 0xFFE53935;
    await _tapInBar(tester, h, TextStyleControls.colorKey(red));
    expect(_draftStyle(h).colorArgb, red);
    await _tapInBar(tester, h, TextStyleControls.boldKey);
    expect(_draftStyle(h).bold, isTrue);
    await _tapInBar(
      tester,
      h,
      TextStyleControls.alignKey(core.TextAlignKind.center),
    );
    expect(_draftStyle(h).align, core.TextAlignKind.center);
    expect(tester.widget<TextField>(_editor).textAlign, TextAlign.center);
    final yellow = TextStyleControls.backgrounds.first;
    await _tapInBar(tester, h, TextStyleControls.backgroundKey(yellow));
    expect(_draftStyle(h).backgroundArgb, yellow);
    expect(_toolStyle(h), _draftStyle(h));
    await _tapInBar(tester, h, TextStyleControls.backgroundNoneKey);
    expect(_draftStyle(h).backgroundArgb, isNull);
    expect(
      tester.widget<TextField>(_editor).style,
      ink.InkTextLayout.textStyleOf(_draftStyle(h)),
      reason: 'the editor paints what INK will',
    );
    expect(_toolStyle(h), _draftStyle(h));

    // The end: ONE UpdateObjects with the style.
    await _notifier(h).end(reason: TextEditEndReason.escape);
    await _notifier(h).ending;
    await tester.pump();
    expect(_edits(h), ['execute:update-objects']);
    final stored = _stored(h, _box.id).style;
    expect(stored.bold, isTrue);
    expect(stored.colorArgb, red);
  });

  testWidgets("'더 보기': the picker (no HEX field) → [적용] sets the colour", (
    tester,
  ) async {
    final h = await _pump(tester);
    await _edit(tester, h, _box);
    await _tapInBar(tester, h, TextStyleControls.moreColorsKey);
    final picker = find.byKey(TextStyleControls.pickerKey);
    expect(picker, findsOneWidget);
    expect(
      find.descendant(of: picker, matching: find.byType(TextField)),
      findsNothing,
      reason: 'a field would take the focus and end the session',
    );
    // The square's top-right corner: saturation 1, value 1, hue 0 → red.
    final square = tester.getRect(find.byType(SvSquare));
    await tester.tapAt(square.topRight + const Offset(-1, 1));
    await tester.pump();
    expect(_notifier(h).lastEndReason, isNull);
    await _tapInBar(tester, h, TextStyleControls.pickerApplyKey);
    final c = Color(_draftStyle(h).colorArgb);
    expect((c.r * 255).round(), greaterThan(240));
    expect((c.g * 255).round(), lessThan(20));
    expect(find.byKey(TextStyleControls.pickerKey), findsNothing);
  });

  testWidgets('sheet mode: the panel has the bar; B keeps the session', (
    tester,
  ) async {
    TextEditNotifier.debugIsWebOverride = true;
    final h = await _pump(tester);
    h.container
        .read(editorDeviceStateProvider.notifier)
        .setWebTextInput(WebTextInputMode.sheet);
    await _edit(tester, h, _box);
    expect(
      h.container.read(editorTextEditProvider)!.mode,
      WebTextInputMode.sheet,
    );
    expect(
      find.descendant(of: find.byKey(TextInputSheet.panelKey), matching: _bar),
      findsOneWidget,
    );
    await _tapInBar(tester, h, TextStyleControls.boldKey);
    expect(_draftStyle(h).bold, isTrue);
    final preview =
        h.controllerOf(0).previewObjects.single as core.TextBoxObject;
    expect(preview.style.bold, isTrue, reason: 'the canvas preview follows');
  });

  testWidgets("the selection menu '서식': each change = ONE UpdateObjects, "
      'the height measured again; ToolOptions follows', (tester) async {
    final h = await _pump(tester);
    h.container.read(editorSelectionProvider.notifier).select(h.pageId(0), {
      _box.id,
    }, origin: SelectionOrigin.lasso);
    await tester.pump();
    await tester.tap(find.byKey(SelectionMenu.moreKey));
    await tester.pump();
    await tester.tap(find.byKey(SelectionMenu.formatKey));
    await tester.pump();
    await tester.pump();
    expect(h.container.read(editorPopupProvider), isA<TextFormatPopup>());
    expect(find.byKey(TextFormatPanel.panelKey), findsOneWidget);
    expect(h.container.read(editorTextEditProvider), isNull);

    Future<void> tapPanel(Key key) async {
      await tester.tap(
        find.descendant(
          of: find.byKey(TextFormatPanel.panelKey),
          matching: find.byKey(key),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    await tapPanel(TextStyleControls.sizeKey);
    await tapPanel(TextStyleControls.presetKey(32));
    expect(_edits(h), ['execute:update-objects']);
    var stored = _stored(h, _box.id);
    expect(stored.style.fontSizePt, 32);
    final measured = ink.InkTextLayout.measureSync(
      stored.text,
      stored.style,
      widthPt: stored.frame.rect.width,
    )!;
    final expected = ObjectResize.withMeasuredHeight(
      _box.copyWith(style: stored.style),
      measured.height,
    );
    expect(stored.frame.rect.top, closeTo(_box.frame.rect.top, 1e-6));
    expect(
      stored.frame.rect.bottom - stored.frame.rect.top,
      closeTo(expected.frame.rect.bottom - expected.frame.rect.top, 1e-6),
    );
    expect(_toolStyle(h).fontSizePt, 32);

    await tapPanel(TextStyleControls.boldKey);
    expect(_edits(h), ['execute:update-objects', 'execute:update-objects']);
    stored = _stored(h, _box.id);
    expect(stored.style.bold, isTrue);
    expect(stored.style.fontSizePt, 32);
    expect(h.session.history.undoDepth, 2);
  });

  testWidgets('the text tool popup edits ToolOptions.textStyle; the next new '
      'box starts with it', (tester) async {
    final h = await _pump(tester);
    h.container.read(editorPopupProvider.notifier).open(const TextToolPopup());
    await tester.pump();
    final panel = find.byKey(TextToolPanel.panelKey);
    expect(panel, findsOneWidget);
    await tester.tap(
      find.descendant(
        of: panel,
        matching: find.byKey(TextStyleControls.boldKey),
      ),
    );
    await tester.pump();
    expect(_toolStyle(h).bold, isTrue);
    expect(_edits(h), isEmpty);
    h.container.read(editorPopupProvider.notifier).close();
    h.container.read(editorCommandsProvider).selectTool(EditorTool.text);
    await tester.pump();

    final at = h.toGlobal(0, const Offset(150, 470));
    await h.driver.down(1, at, kind: PointerDeviceKind.stylus);
    await h.driver.wait(const Duration(milliseconds: 20));
    await h.driver.up(1);
    await tester.pump();
    expect(_draftStyle(h).bold, isTrue);
  });
}
