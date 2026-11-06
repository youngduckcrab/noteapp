// E2-01 (m5-7/04-editor 6.11.6, 9.2): the text session on the web runtime
// (Chrome) — web compile and the session rules, both input modes. The
// developer menu's '텍스트 상자 시험' opens a new box, tester.enterText types
// '안녕 hello', the end (inline: a tap outside on the toolbar; sheet: [완료])
// stores one AddObjects whose text matches. The IME quality is not judged
// here (iPad Safari only — B-2, B-15; review S-9).
//
// Run: `dart run tool/ws.dart test --package feature_editor --platform
// chrome`.
@TestOn('browser')
library;

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/state/settings/editor_device_state.dart';
import 'package:feature_editor/src/text/text_box_editor.dart';
import 'package:feature_editor/src/text/text_edit_session.dart';
import 'package:feature_editor/src/text/text_input_sheet.dart';
import 'package:feature_editor/src/ui/toolbar/dev_menu.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:feature_editor/src/ui/toolbar/more_menu.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';

const _devOn = EditorSettings(showDevOverlay: true);

final _editor = find.byKey(textEditorKey);

Future<void> _openDevMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(EditorDevMenu.menuKey));
  await tester.pumpAndSettle();
}

Future<void> _startProbe(WidgetTester tester) async {
  await _openDevMenu(tester);
  await tester.tap(find.byKey(EditorDevMenu.textBoxProbeKey));
  await tester.pumpAndSettle();
}

List<String> _executes(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute')) c,
];

void main() {
  setUpAll(useInkTestFonts);

  testWidgets('inline: 안녕 hello → tap outside → one AddObjects', (
    tester,
  ) async {
    expect(kIsWeb, isTrue);
    expect(TextEditNotifier.isWeb, isTrue);
    final h = await pumpEditor(tester, settings: _devOn);
    await _startProbe(tester);
    final s = h.container.read(editorTextEditProvider)!;
    expect(s.mode, WebTextInputMode.inline);
    expect(find.byKey(TextInputSheet.panelKey), findsNothing);
    expect(tester.widget<TextField>(_editor).focusNode!.hasFocus, isTrue);

    await tester.enterText(_editor, '안녕 hello');
    await tester.pump();
    expect(h.container.read(editorTextEditProvider)!.draft.text, '안녕 hello');
    await tester.tap(find.byKey(EditorToolbar.titleKey));
    await tester.pump();
    final notifier = h.container.read(editorTextEditProvider.notifier);
    await notifier.ending;
    await tester.pump();

    expect(notifier.lastEndReason, TextEditEndReason.tapOutside);
    expect(_executes(h), ['execute:add-objects']);
    expect(h.session.history.undoDepth, 1);
    final stored =
        h.session.pageIfLoaded(h.pageId(0))!.objectById(s.boxId)!
            as core.TextBoxObject;
    expect(stored.text, '안녕 hello');
    expect(_editor, findsNothing);
  });

  testWidgets('sheet (chosen in the developer menu): 안녕 hello → [완료] → one '
      'AddObjects', (tester) async {
    final h = await pumpEditor(tester, settings: _devOn);
    await _openDevMenu(tester);
    await tester.tap(find.byKey(EditorDevMenu.textInputModeKey));
    await tester.pumpAndSettle();
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
    await _startProbe(tester);
    final s = h.container.read(editorTextEditProvider)!;
    expect(s.mode, WebTextInputMode.sheet);
    expect(find.byKey(TextInputSheet.panelKey), findsOneWidget);

    await tester.enterText(_editor, '안녕 hello');
    await tester.pump();
    final preview = h.controllerOf(0).previewObjects.single;
    expect(preview.id, s.boxId);
    expect((preview as core.TextBoxObject).text, '안녕 hello');
    await tester.tap(find.byKey(TextInputSheet.doneKey));
    await tester.pump();
    final notifier = h.container.read(editorTextEditProvider.notifier);
    await notifier.ending;
    await tester.pump();

    expect(notifier.lastEndReason, TextEditEndReason.done);
    expect(_executes(h), ['execute:add-objects']);
    final stored =
        h.session.pageIfLoaded(h.pageId(0))!.objectById(s.boxId)!
            as core.TextBoxObject;
    expect(stored.text, '안녕 hello');
    expect(h.controllerOf(0).previewObjects, isEmpty);
    // The device state write (500 ms debounce).
    await tester.pump(const Duration(seconds: 1));
  });
}
