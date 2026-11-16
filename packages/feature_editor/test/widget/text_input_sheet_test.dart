// E2-01 (m5-7/04-editor 6.11.6 안 A, 6.20): the sheet input mode (web
// fallback A), driven on the VM with TextEditNotifier.debugIsWebOverride.
// - the panel sits at the top of the editor body (just below the toolbar),
//   at most 40 % of the screen high;
// - with the keyboard up (viewInsets.bottom 400 / 600) the panel stays above
//   it and gets lower when the room is short (landscape, 600);
// - while typing: getter previewObjects has the same-id draft and
//   hiddenObjectIds == {id} (preview wins), the draft height = measureSync;
// - [완료] → one command (reason done), the preview and hidden ids cleared;
//   a tap on the panel keeps the session, a tap outside ends it;
// - the developer menu's input-mode row: only on the web, sheet chosen →
//   the next session is a sheet session, textarea disabled (E2-11).
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/state/settings/editor_device_state.dart';
import 'package:feature_editor/src/text/text_box_editor.dart';
import 'package:feature_editor/src/text/text_edit_session.dart';
import 'package:feature_editor/src/text/text_input_sheet.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/toolbar/dev_menu.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:feature_editor/src/ui/toolbar/more_menu.dart';
import 'package:feature_editor/src/viewport/page_viewport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/pump_editor.dart';

const _devOn = EditorSettings(showDevOverlay: true);

final _panel = find.byKey(TextInputSheet.panelKey);
final _editor = find.byKey(textEditorKey);

List<String> _executes(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute')) c,
];

/// Opens a sheet-mode session on the seeded box 'tb-1' of page 0.
Future<(EditorTestHandles, core.TextBoxObject)> _openSheet(
  WidgetTester tester, {
  Size logicalSize = const Size(1032, 1376),
}) async {
  TextEditNotifier.debugIsWebOverride = true;
  final seeded = PageObjectFixtures.textBox(pageId: 'x', id: 'tb-1');
  final h = await pumpEditor(
    tester,
    logicalSize: logicalSize,
    objectsByPageIndex: {
      0: [seeded],
    },
  );
  h.container
      .read(editorDeviceStateProvider.notifier)
      .setWebTextInput(WebTextInputMode.sheet);
  final box =
      h.session.pageIfLoaded(h.pageId(0))!.objectById('tb-1')!
          as core.TextBoxObject;
  h.container.read(editorTextEditProvider.notifier).start(box, isNew: false);
  await tester.pump();
  await tester.pump();
  return (h, box);
}

/// Sets the keyboard height (logical px; the test view has DPR 2).
Future<void> _keyboard(WidgetTester tester, double height) async {
  tester.view.viewInsets = FakeViewPadding(bottom: height * 2);
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await useInkTestFonts();
  });
  tearDown(() => TextEditNotifier.debugIsWebOverride = null);

  testWidgets('the panel is at the top of the editor body, ≤ 40 % high, '
      'with the focused field and no inline editor', (tester) async {
    final (h, _) = await _openSheet(tester);
    expect(
      h.container.read(editorTextEditProvider)!.mode,
      WebTextInputMode.sheet,
    );
    final panel = tester.getRect(_panel);
    final area = tester.getRect(find.byType(PageViewport));
    expect(panel.top, area.top, reason: 'right below the toolbar');
    expect(panel.left, area.left);
    expect(panel.width, area.width);
    expect(panel.height, lessThanOrEqualTo(0.4 * 1376 + 1e-9));
    expect(
      tester.getRect(find.byType(EditorToolbar)).bottom,
      lessThanOrEqualTo(panel.top),
    );
    // One field, in the panel (no transformed editor over the box).
    expect(_editor, findsOneWidget);
    expect(find.descendant(of: _panel, matching: _editor), findsOneWidget);
    expect(tester.widget<TextField>(_editor).focusNode!.hasFocus, isTrue);
  });

  testWidgets('keyboard 400 → the panel stays above it; landscape with 600 → '
      'the panel gets lower', (tester) async {
    final (h, _) = await _openSheet(tester);
    await _keyboard(tester, 400);
    var panel = tester.getRect(_panel);
    expect(panel.bottom, lessThanOrEqualTo(1376 - 400));
    expect(panel.height, lessThanOrEqualTo(0.4 * 1376 + 1e-9));
    expect(h.container.read(editorTextEditProvider), isNotNull);

    // Landscape: 40 % = 412.8; a 600 px keyboard leaves less room.
    tester.view.physicalSize = const Size(1376, 1032) * 2;
    await _keyboard(tester, 0);
    final full = tester.getRect(_panel).height;
    expect(full, closeTo(0.4 * 1032, 1e-6));
    await _keyboard(tester, 400);
    panel = tester.getRect(_panel);
    expect(panel.bottom, lessThanOrEqualTo(1032 - 400));
    await _keyboard(tester, 600);
    panel = tester.getRect(_panel);
    expect(panel.height, lessThan(full), reason: 'lower above the keyboard');
    expect(
      panel.bottom,
      lessThanOrEqualTo(1032 - 600 - TextInputSheet.keyboardGap + 1e-6),
    );
    expect(h.container.read(editorTextEditProvider), isNotNull);
  });

  test('heightFor: min(40 %, area − inset − 120), within [96, area]', () {
    expect(
      TextInputSheet.heightFor(
        screenHeight: 1376,
        areaHeight: 1279,
        insetBottom: 0,
      ),
      closeTo(550.4, 1e-9),
    );
    // A body the Scaffold did not shrink: the inset is taken off here.
    expect(
      TextInputSheet.heightFor(
        screenHeight: 1032,
        areaHeight: 935,
        insetBottom: 600,
      ),
      215,
    );
    expect(
      TextInputSheet.heightFor(
        screenHeight: 1032,
        areaHeight: 300,
        insetBottom: 0,
      ),
      180,
    );
    expect(
      TextInputSheet.heightFor(
        screenHeight: 1032,
        areaHeight: 150,
        insetBottom: 0,
      ),
      96,
    );
    expect(
      TextInputSheet.heightFor(
        screenHeight: 1032,
        areaHeight: 60,
        insetBottom: 0,
      ),
      60,
    );
  });

  testWidgets('typing: the same-id draft as preview, the id hidden (preview '
      'wins), the draft height = measureSync', (tester) async {
    final (h, box) = await _openSheet(tester);
    final c = h.controllerOf(0);
    expect(c.hiddenObjectIds, {'tb-1'});
    expect(c.previewObjects.single.id, 'tb-1');

    const text = '시트에서 쓴 글이 여러 줄로 늘어나도록 길게 써 봐요 hello world again';
    await tester.enterText(_editor, text);
    await tester.pump();
    expect(c.hiddenObjectIds, {'tb-1'});
    final preview = c.previewObjects.single as core.TextBoxObject;
    expect(preview.id, 'tb-1');
    expect(preview.text, text);
    final width = box.frame.rect.width;
    final measured = ink.InkTextLayout.measureSync(
      text,
      box.style,
      widthPt: width,
    )!;
    final r = preview.frame.rect;
    expect(r.bottom - r.top, closeTo(measured.height, 1e-9));
    expect(r.right - r.left, width);
    expect(_executes(h), isEmpty, reason: 'no command while typing');
  });

  testWidgets('[완료] → one command (done), the preview and hidden ids '
      'cleared', (tester) async {
    final (h, _) = await _openSheet(tester);
    await tester.enterText(_editor, '완료로 끝');
    await tester.pump();
    await tester.tap(find.byKey(TextInputSheet.doneKey));
    await tester.pump();
    final notifier = h.container.read(editorTextEditProvider.notifier);
    await notifier.ending;
    await tester.pump();

    expect(notifier.lastEndReason, TextEditEndReason.done);
    expect(_executes(h), ['execute:update-objects']);
    expect(h.session.history.undoDepth, 1);
    final c = h.controllerOf(0);
    expect(c.previewObjects, isEmpty);
    expect(c.hiddenObjectIds, isEmpty);
    expect(_panel, findsNothing);
    final stored =
        h.session.pageIfLoaded(h.pageId(0))!.objectById('tb-1')!
            as core.TextBoxObject;
    expect(stored.text, '완료로 끝');
  });

  testWidgets('a tap on the panel keeps the session; a tap outside ends it '
      '(tapOutside)', (tester) async {
    final (h, _) = await _openSheet(tester);
    await tester.enterText(_editor, '밖을 눌러 끝');
    await tester.pump();
    // The panel's title row: inside the tap group.
    await tester.tap(find.text(EditorStrings.textInputSheetTitle));
    await tester.pump();
    expect(h.container.read(editorTextEditProvider), isNotNull);

    await tapToolbarBlank(tester);
    await tester.pump();
    final notifier = h.container.read(editorTextEditProvider.notifier);
    await notifier.ending;
    expect(notifier.lastEndReason, TextEditEndReason.tapOutside);
    expect(_executes(h), ['execute:update-objects']);
  });

  group('developer menu: 텍스트 입력 방식', () {
    Future<void> openDevMenu(WidgetTester tester) async {
      await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(EditorDevMenu.menuKey));
      await tester.pumpAndSettle();
    }

    testWidgets('not on native', (tester) async {
      TextEditNotifier.debugIsWebOverride = false;
      await pumpEditor(tester, settings: _devOn);
      await openDevMenu(tester);
      expect(find.byKey(EditorDevMenu.textBoxProbeKey), findsOneWidget);
      expect(find.byKey(EditorDevMenu.textInputModeKey), findsNothing);
    });

    testWidgets('web: sheet chosen → the probe opens a sheet session; '
        'textarea disabled', (tester) async {
      TextEditNotifier.debugIsWebOverride = true;
      final h = await pumpEditor(tester, settings: _devOn);
      await openDevMenu(tester);
      await tester.tap(find.byKey(EditorDevMenu.textInputModeKey));
      await tester.pumpAndSettle();
      RadioMenuButton<WebTextInputMode> item(WebTextInputMode m) =>
          tester.widget<RadioMenuButton<WebTextInputMode>>(
            // RadioMenuButton hands its key to its MenuItemButton too.
            find.byKey(EditorDevMenu.textInputModeItemKey(m)).first,
          );
      expect(item(WebTextInputMode.inline).groupValue, WebTextInputMode.inline);
      expect(item(WebTextInputMode.textarea).onChanged, isNull);
      await tester.tap(
        find
            .byKey(EditorDevMenu.textInputModeItemKey(WebTextInputMode.sheet))
            .first,
      );
      await tester.pumpAndSettle();
      expect(
        h.container.read(editorDeviceStateProvider).webTextInput,
        WebTextInputMode.sheet,
      );

      await openDevMenu(tester);
      await tester.tap(find.byKey(EditorDevMenu.textBoxProbeKey));
      await tester.pumpAndSettle();
      final s = h.container.read(editorTextEditProvider)!;
      expect(s.mode, WebTextInputMode.sheet);
      expect(s.isNew, isTrue);
      expect(_panel, findsOneWidget);
      // A new box: nothing hidden, the empty draft as preview.
      expect(h.controllerOf(0).hiddenObjectIds, isEmpty);
      expect(h.controllerOf(0).previewObjects.single.id, s.boxId);
      await tester.enterText(_editor, '새 상자');
      await tester.tap(find.byKey(TextInputSheet.doneKey));
      await tester.pump();
      await h.container.read(editorTextEditProvider.notifier).ending;
      expect(_executes(h), ['execute:add-objects']);
      expect(
        (h.session.pageIfLoaded(h.pageId(0))!.objectById(s.boxId)!
                as core.TextBoxObject)
            .text,
        '새 상자',
      );
      // The device state write (500 ms debounce).
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
