// m5-7/04-editor 8.2 E2-15, 6.10: the auto shape assist through the editor
// (fake CORE, R2-B3 INK — its StrokeSession takes shapeAssist as given and
// never previews a shape, so no addShape here; the commit path is P-A E2-09
// widget/shape_tool_test.dart). A pen down hands INK the table value
// (getter StrokeSession.shapeAssist); with INK's NoShapeFitter (a build
// without recognition) every stroke gets off and the toggle rows are
// hidden; with a fitter wired (FakeInkShapeFitter) the pen settings popup
// '고급' and settings > 펜 show the same synced switch.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/pen/pen_advanced_controls.dart';
import 'package:feature_editor/src/ui/pen/pen_settings_popup.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart' as ink_testing;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/pump_editor.dart';

Override get _fitter => ink.inkShapeFitterProvider.overrideWithValue(
  ink_testing.FakeInkShapeFitter(),
);

/// The shapeAssist INK received for a pen down with [pen] at (200, 200) pt
/// on page 0; the stroke is then finished.
Future<ink.ShapeAssist> _assistAtDown(
  WidgetTester tester,
  EditorTestHandles h,
  core.PenTool pen,
) async {
  h.container.read(editorToolProvider.notifier).selectPenType(pen);
  await tester.pump();
  await h.driver.down(
    1,
    h.toGlobal(0, const Offset(200, 200)),
    kind: PointerDeviceKind.stylus,
  );
  await h.driver.move(1, h.toGlobal(0, const Offset(260, 230)));
  await tester.pump();
  final session = h.controllerOf(0).activeSession;
  expect(session, isA<ink.StrokeSession>(), reason: '$pen');
  final assist = (session! as ink.StrokeSession).shapeAssist;
  await h.driver.up(1);
  await tester.pump();
  return assist;
}

/// Opens the pen settings popup of [pen] and its '고급' part.
Future<void> _openAdvanced(
  WidgetTester tester,
  EditorTestHandles h,
  core.PenTool pen,
) async {
  h.container.read(editorToolProvider.notifier).selectPenType(pen);
  await tester.pump();
  await tester.tap(find.byKey(EditorToolbar.penKey)); // the active pen
  await tester.pump();
  expect(find.byKey(PenSettingsPanel.panelKey), findsOneWidget);
  await tester.ensureVisible(find.text(EditorStrings.advanced));
  await tester.pump();
  await tester.tap(find.text(EditorStrings.advanced));
  await tester.pumpAndSettle();
}

/// Settings > 펜 alone, iPad Pro 13" portrait, a fake store at the root.
Future<ProviderContainer> _pumpPenSection(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(1032, 1376) * 2;
  addTearDown(tester.view.reset);
  final store = createFakeNoteStore();
  addTearDown(store.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        core.noteStoreProvider.overrideWithValue(store),
        ...overrides,
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ListView(children: const [EditorPenSettingsSection()]),
        ),
      ),
    ),
  );
  await tester.pump(); // settings load
  return ProviderScope.containerOf(
    tester.element(find.byType(EditorPenSettingsSection)),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await ink_testing.useInkTestFonts();
  });

  testWidgets('a fitter wired: pen down → StrokeSession.shapeAssist = the '
      'table value for each pen', (tester) async {
    final h = await pumpEditor(tester, overrides: [_fitter]);
    for (final pen in core.PenTool.values) {
      final expected = switch (pen) {
        core.PenTool.highlighter ||
        core.PenTool.laser ||
        core.PenTool.tape => ink.ShapeAssist.off,
        // (C211-01) the texture / decoration pens keep their look: no snap
        _ when pen.index > core.PenTool.tape.index => ink.ShapeAssist.off,
        _ => ink.ShapeAssist.holdToSnap,
      };
      expect(await _assistAtDown(tester, h, pen), expected, reason: '$pen');
    }
  });

  testWidgets('a fitter wired, the setting off → off', (tester) async {
    final h = await pumpEditor(
      tester,
      overrides: [_fitter],
      settings: const EditorSettings(shapeAssist: false),
    );
    expect(h.container.read(editorSettingsProvider).shapeAssist, isFalse);
    expect(
      await _assistAtDown(tester, h, core.PenTool.ballpoint),
      ink.ShapeAssist.off,
    );
  });

  testWidgets('NoShapeFitter (no recognition): every pen off, no toggle in '
      'the pen popup', (tester) async {
    final h = await pumpEditor(tester);
    expect(
      h.container.read(ink.inkShapeFitterProvider),
      isA<ink.NoShapeFitter>(),
    );
    expect(h.container.read(editorSettingsProvider).shapeAssist, isTrue);
    for (final pen in [core.PenTool.ballpoint, core.PenTool.calligraphy]) {
      expect(await _assistAtDown(tester, h, pen), ink.ShapeAssist.off);
    }
    await _openAdvanced(tester, h, core.PenTool.ballpoint);
    expect(find.byKey(PenAdvancedControls.smoothingKey), findsOneWidget);
    expect(find.byKey(PenAdvancedControls.shapeAssistKey), findsNothing);
    expect(find.text(EditorStrings.shapeAssist), findsNothing);
  });

  testWidgets('a fitter wired: the popup 고급 shows the switch for an assist '
      'pen; turning it off is the synced setting and the next stroke is off', (
    tester,
  ) async {
    final h = await pumpEditor(tester, overrides: [_fitter]);
    await _openAdvanced(tester, h, core.PenTool.ballpoint);
    final toggle = find.byKey(PenAdvancedControls.shapeAssistKey);
    expect(toggle, findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(find.text(EditorStrings.shapeAssistHint), findsOneWidget);
    await tester.ensureVisible(toggle);
    await tester.pump();
    await tester.tap(toggle);
    await tester.pump();
    expect(h.container.read(editorSettingsProvider).shapeAssist, isFalse);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    // Close the popup (Esc) and draw: off now.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(PenSettingsPanel.panelKey), findsNothing);
    expect(
      await _assistAtDown(tester, h, core.PenTool.ballpoint),
      ink.ShapeAssist.off,
    );
  });

  testWidgets('a fitter wired: the highlighter popup has no switch (no '
      'assist for it)', (tester) async {
    final h = await pumpEditor(tester, overrides: [_fitter]);
    await _openAdvanced(tester, h, core.PenTool.highlighter);
    expect(find.byKey(PenAdvancedControls.smoothingKey), findsOneWidget);
    expect(find.byKey(PenAdvancedControls.shapeAssistKey), findsNothing);
  });

  testWidgets('settings > 펜, a fitter wired: the same synced switch', (
    tester,
  ) async {
    final container = await _pumpPenSection(tester, overrides: [_fitter]);
    final toggle = find.byKey(PenAdvancedControls.shapeAssistKey);
    await tester.scrollUntilVisible(
      toggle,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(toggle, findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pump();
    expect(container.read(editorSettingsProvider).shapeAssist, isFalse);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
  });

  testWidgets('settings > 펜, NoShapeFitter: no switch', (tester) async {
    final container = await _pumpPenSection(tester);
    expect(
      container.read(ink.inkShapeFitterProvider),
      isA<ink.NoShapeFitter>(),
    );
    expect(
      find.byKey(PenAdvancedControls.smoothingKey, skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byKey(PenAdvancedControls.shapeAssistKey, skipOffstage: false),
      findsNothing,
    );
  });
}
