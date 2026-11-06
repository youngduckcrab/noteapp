// m5-7/04-editor 8.2 E2-05, 6.4.4: the gesture rows of the input settings
// section (outside the editor, as INFRA's settings screen shows it) — the 7
// rows and the 3 fixed rows, the Apple Pencil rows only with the
// capabilities (squeeze also after a first squeeze event on the device), no
// '펜 뒤쪽 지우개' on the web, the sheet offers only allowedFor, a pick writes
// `actions` into editor.settings.synced, [기본값으로].
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/state/settings/editor_device_state.dart';
import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/settings/editor_settings_sections.dart';
import 'package:feature_editor/src/ui/settings/gesture_action_tile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/fake_stylus_extras.dart';

typedef _Env = ({core.NoteStore store, ProviderContainer container});

Future<_Env> _pump(WidgetTester tester, {StylusExtrasSource? stylus}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(1032, 1376) * 2;
  addTearDown(tester.view.reset);
  final store = createFakeNoteStore();
  addTearDown(store.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        core.noteStoreProvider.overrideWithValue(store),
        if (stylus != null) stylusExtrasProvider.overrideWithValue(stylus),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ListView(children: const [EditorInputSettingsSection()]),
        ),
      ),
    ),
  );
  await tester.pump(); // settings load
  final container = ProviderScope.containerOf(
    tester.element(find.byType(EditorInputSettingsSection)),
  );
  return (store: store, container: container);
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

/// The gesture rows present, in screen order.
List<EditorGesture> _rows(WidgetTester tester) {
  final found = <(double, EditorGesture)>[
    for (final g in EditorGesture.values)
      if (find
          .byKey(GestureActionTiles.rowKey(g), skipOffstage: false)
          .evaluate()
          .isNotEmpty)
        (
          tester
              .getTopLeft(
                find.byKey(GestureActionTiles.rowKey(g), skipOffstage: false),
              )
              .dy,
          g,
        ),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final (_, g) in found) g];
}

/// The action the row of [g] shows.
String _shown(WidgetTester tester, EditorGesture g) {
  final row = find.byKey(GestureActionTiles.rowKey(g), skipOffstage: false);
  return GestureActionTiles.actionName(
    tester.widget<GestureActionTile>(row).action,
  );
}

Future<void> _openSheet(WidgetTester tester, EditorGesture g) async {
  await _show(tester, find.byKey(GestureActionTiles.rowKey(g)));
  await tester.tap(find.byKey(GestureActionTiles.rowKey(g)));
  await tester.pumpAndSettle();
  expect(find.byKey(GestureActionTiles.sheetKey), findsOneWidget);
}

/// The actions the open sheet offers, in order.
List<EditorAction> _options(WidgetTester tester) {
  final found = <(double, EditorAction)>[
    for (final a in EditorAction.values)
      if (find.byKey(GestureActionTiles.optionKey(a)).evaluate().isNotEmpty)
        (tester.getTopLeft(find.byKey(GestureActionTiles.optionKey(a))).dy, a),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final (_, a) in found) a];
}

EditorAction? _checked(WidgetTester tester) => tester
    .widget<RadioGroup<EditorAction>>(find.byType(RadioGroup<EditorAction>))
    .groupValue;

Future<Map<String, Object?>> _storedGestures(
  WidgetTester tester,
  _Env env,
) async {
  await tester.pump(const Duration(milliseconds: 600));
  final synced = await env.store.settings.get(EditorSettingKeys.syncedSettings);
  return synced['gestures']! as Map<String, Object?>;
}

void main() {
  tearDown(() => GestureActionTiles.debugIsWebOverride = null);

  testWidgets('no Pencil (NoStylusExtras), not the web: the 5 rows with '
      'their default actions, no Pencil hint, the 3 fixed grey rows', (
    tester,
  ) async {
    await _pump(tester);
    expect(_rows(tester), [
      EditorGesture.twoFingerTap,
      EditorGesture.threeFingerTap,
      EditorGesture.fingerLongPress,
      EditorGesture.penButton,
      EditorGesture.invertedStylus,
    ]);
    expect(
      _shown(tester, EditorGesture.twoFingerTap),
      EditorStrings.actionUndo,
    );
    expect(
      _shown(tester, EditorGesture.threeFingerTap),
      EditorStrings.actionRedo,
    );
    expect(
      _shown(tester, EditorGesture.fingerLongPress),
      EditorStrings.actionContextMenu,
    );
    expect(
      _shown(tester, EditorGesture.penButton),
      EditorStrings.actionEraserWhileHeld,
    );
    expect(
      _shown(tester, EditorGesture.invertedStylus),
      EditorStrings.actionEraserWhileHeld,
    );
    expect(find.text(EditorStrings.gesturePenButtonHint), findsOneWidget);
    expect(find.text(EditorStrings.gestureInvertedStylusHint), findsOneWidget);
    expect(
      find.byKey(GestureActionTiles.pencilHintKey, skipOffstage: false),
      findsNothing,
    );

    await _show(tester, find.byKey(SettingsSectionKeys.fixedGestures));
    final table = find.byKey(SettingsSectionKeys.fixedGestures);
    expect(EditorStrings.fixedGestureTable, hasLength(3));
    for (final (gesture, action) in EditorStrings.fixedGestureTable) {
      final g = find.descendant(of: table, matching: find.text(gesture));
      expect(g, findsOneWidget);
      expect(
        find.descendant(of: table, matching: find.text(action)),
        findsWidgets,
      );
      // Grey text, nothing to tap.
      expect(
        tester.widget<Text>(g).style?.color,
        Theme.of(tester.element(table)).colorScheme.onSurfaceVariant,
      );
    }
    expect(
      find.descendant(of: table, matching: find.byType(InkWell)),
      findsNothing,
    );
  });

  testWidgets('on the web: no 펜 뒤쪽 지우개 row', (tester) async {
    GestureActionTiles.debugIsWebOverride = true;
    await _pump(tester);
    expect(_rows(tester), [
      EditorGesture.twoFingerTap,
      EditorGesture.threeFingerTap,
      EditorGesture.fingerLongPress,
      EditorGesture.penButton,
    ]);
    expect(find.text(EditorStrings.gestureInvertedStylusHint), findsNothing);
  });

  testWidgets('Pencil rows: double tap with capabilities.doubleTap; squeeze '
      'only after seenSqueeze; the next-launch hint under them', (
    tester,
  ) async {
    final env = await _pump(tester, stylus: FakeStylusExtras());
    expect(_rows(tester), [
      EditorGesture.twoFingerTap,
      EditorGesture.threeFingerTap,
      EditorGesture.fingerLongPress,
      EditorGesture.penButton,
      EditorGesture.invertedStylus,
      EditorGesture.pencilDoubleTap,
    ]);
    expect(
      _shown(tester, EditorGesture.pencilDoubleTap),
      EditorStrings.actionFollowSystem,
    );
    expect(
      find.byKey(GestureActionTiles.pencilHintKey, skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.text(EditorStrings.pencilNextLaunch, skipOffstage: false),
      findsOneWidget,
    );

    env.container.read(editorDeviceStateProvider.notifier).markSeenSqueeze();
    await tester.pump();
    expect(_rows(tester), [
      EditorGesture.twoFingerTap,
      EditorGesture.threeFingerTap,
      EditorGesture.fingerLongPress,
      EditorGesture.penButton,
      EditorGesture.invertedStylus,
      EditorGesture.pencilDoubleTap,
      EditorGesture.pencilSqueeze,
    ]);
    await tester.pump(const Duration(seconds: 1)); // device write
  });

  testWidgets('squeeze capability alone (no event yet) → no squeeze row; no '
      'doubleTap capability → no double tap row', (tester) async {
    await _pump(
      tester,
      stylus: FakeStylusExtras(
        capabilities: const StylusCapabilities(squeeze: true),
      ),
    );
    expect(_rows(tester), isNot(contains(EditorGesture.pencilSqueeze)));
    expect(_rows(tester), isNot(contains(EditorGesture.pencilDoubleTap)));
    expect(
      find.byKey(GestureActionTiles.pencilHintKey, skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets('every sheet offers exactly allowedFor (table order), the '
      'current action checked', (tester) async {
    final env = await _pump(tester, stylus: FakeStylusExtras());
    env.container.read(editorDeviceStateProvider.notifier).markSeenSqueeze();
    await tester.pump();
    for (final g in EditorGesture.values) {
      await _openSheet(tester, g);
      expect(
        _options(tester),
        GestureSettings.allowedFor(g).toList(),
        reason: '$g',
      );
      expect(_checked(tester), GestureSettings.defaultFor(g), reason: '$g');
      expect(
        find.descendant(
          of: find.byKey(GestureActionTiles.sheetKey),
          matching: find.text(GestureActionTiles.gestureName(g)),
        ),
        findsOneWidget,
      );
      // Dismiss without picking → nothing changes.
      await tester.tapAt(const Offset(516, 20));
      await tester.pumpAndSettle();
      expect(find.byKey(GestureActionTiles.sheetKey), findsNothing);
    }
    expect(
      env.container.read(editorSettingsProvider).gestures,
      GestureSettings.defaults,
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('picking an action → withAction → editor.settings.synced '
      '`actions`; the row follows; [기본값으로] → defaults', (tester) async {
    final env = await _pump(tester, stylus: FakeStylusExtras());

    await _openSheet(tester, EditorGesture.penButton);
    await tester.tap(
      find.byKey(GestureActionTiles.optionKey(EditorAction.lassoWhileHeld)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(GestureActionTiles.sheetKey), findsNothing);
    await _openSheet(tester, EditorGesture.twoFingerTap);
    await tester.tap(
      find.byKey(GestureActionTiles.optionKey(EditorAction.toggleEraser)),
    );
    await tester.pumpAndSettle();
    await _openSheet(tester, EditorGesture.pencilDoubleTap);
    expect(_checked(tester), EditorAction.followSystem);
    await tester.tap(
      find.byKey(GestureActionTiles.optionKey(EditorAction.undo)),
    );
    await tester.pumpAndSettle();

    final gestures = env.container.read(editorSettingsProvider).gestures;
    expect(
      gestures.actionFor(EditorGesture.penButton),
      EditorAction.lassoWhileHeld,
    );
    expect(
      gestures.actionFor(EditorGesture.twoFingerTap),
      EditorAction.toggleEraser,
    );
    expect(
      gestures.actionFor(EditorGesture.pencilDoubleTap),
      EditorAction.undo,
    );
    expect(
      _shown(tester, EditorGesture.penButton),
      EditorStrings.actionLassoWhileHeld,
    );
    expect(
      _shown(tester, EditorGesture.twoFingerTap),
      EditorStrings.actionToggleEraser,
    );
    expect(await _storedGestures(tester, env), {
      'twoFingerUndo': true,
      'threeFingerRedo': true,
      'longPressMenu': true,
      'actions': {
        'pencilDoubleTap': 'undo',
        'penButton': 'lassoWhileHeld',
        'twoFingerTap': 'toggleEraser',
      },
    });

    // Back to the default of one gesture → its explicit entry goes.
    await _openSheet(tester, EditorGesture.penButton);
    expect(_checked(tester), EditorAction.lassoWhileHeld);
    await tester.tap(
      find.byKey(GestureActionTiles.optionKey(EditorAction.eraserWhileHeld)),
    );
    await tester.pumpAndSettle();
    expect(
      ((await _storedGestures(tester, env))['actions']! as Map).keys,
      unorderedEquals(['pencilDoubleTap', 'twoFingerTap']),
    );

    await _show(tester, find.byKey(SettingsSectionKeys.resetGestures));
    await tester.tap(find.byKey(SettingsSectionKeys.resetGestures));
    await tester.pump();
    expect(
      env.container.read(editorSettingsProvider).gestures,
      GestureSettings.defaults,
    );
    expect(await _storedGestures(tester, env), {
      'twoFingerUndo': true,
      'threeFingerRedo': true,
      'longPressMenu': true,
      'actions': <String, Object?>{},
    });
    expect(find.text(EditorStrings.resetGestures), findsOneWidget);
  });

  testWidgets('a rebuild from another writer (the editor) shows the new '
      'action at once', (tester) async {
    final env = await _pump(tester);
    env.container
        .read(editorSettingsProvider.notifier)
        .setGestures(
          GestureSettings.defaults.withAction(
            EditorGesture.threeFingerTap,
            EditorAction.none,
          ),
        );
    await tester.pump();
    expect(
      _shown(tester, EditorGesture.threeFingerTap),
      EditorStrings.actionNone,
    );
    await tester.pump(const Duration(seconds: 1));
  });
}
