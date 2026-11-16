// E-20: the four settings section widgets (04-editor 4.9) in a ListView
// without the settings screen: every control → notifier value and CORE key
// (500 ms debounce), the pressure mode → ink.pressureModeProvider, the
// detection state text (INK state overridden), the pen section edits the same
// editorToolProvider values as the pen popup (any P0 type), the resets, the
// read-only gesture table, '합성 노트 만들기' and the hint texts. (v2) The
// gesture rows pick an action in a sheet (m5-7/04-editor 6.4.4).
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:feature_editor/src/state/settings/pre_roll.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/pen/pen_advanced_controls.dart';
import 'package:feature_editor/src/ui/pen/pen_type_selector.dart';
import 'package:feature_editor/src/ui/settings/editor_settings_sections.dart';
import 'package:feature_editor/src/ui/settings/gesture_action_tile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

typedef _Env = ({core.NoteStore store, ProviderContainer container});

/// INK detection state fixed to [stylus] (contract 7.2.15 — INK owns it).
class _FixedCapability extends ink.PressureCapabilityNotifier {
  _FixedCapability(this._stylus);
  final ink.PressureCapability _stylus;

  @override
  ink.PressureCapabilityState build() =>
      ink.PressureCapabilityState(stylus: _stylus);
}

Override _capability(ink.PressureCapability stylus) =>
    ink.pressureCapabilityProvider.overrideWith(() => _FixedCapability(stylus));

/// The sections in a ListView (as INFRA's settings screen puts them), on an
/// iPad Pro 13" portrait view, with a fake store at the root.
Future<_Env> _pump(
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
      child: const MaterialApp(home: Scaffold(body: _Sections())),
    ),
  );
  await tester.pump(); // settings load
  final container = ProviderScope.containerOf(
    tester.element(find.byType(_Sections)),
  );
  return (store: store, container: container);
}

class _Sections extends StatelessWidget {
  const _Sections();

  @override
  Widget build(BuildContext context) => ListView(
    children: const [
      EditorInputSettingsSection(),
      EditorPenSettingsSection(),
      EditorPageSettingsSection(),
      EditorDeveloperSettingsSection(),
    ],
  );
}

Future<void> _show(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _show(tester, finder);
  await tester.tap(finder);
  await tester.pump();
}

/// Lets the 500 ms debounce write and returns what CORE holds for [key].
Future<Map<String, Object?>> _stored(
  WidgetTester tester,
  _Env env,
  core.SettingKey<Map<String, Object?>> key,
) async {
  await tester.pump(const Duration(milliseconds: 600));
  return env.store.settings.get(key);
}

EditorSettings _settings(_Env env) =>
    env.container.read(editorSettingsProvider);
ToolState _tools(_Env env) => env.container.read(editorToolProvider);

Slider _slider(WidgetTester tester, Key key) =>
    tester.widget<Slider>(find.byKey(key));

void main() {
  testWidgets('input mode: 3 choices with their hint → inputMode, '
      'editor.settings.device', (tester) async {
    final env = await _pump(tester);
    expect(_settings(env).inputMode, InputMode.auto);
    expect(find.text(EditorStrings.inputModeAutoHint), findsOneWidget);
    await _tap(tester, find.text(EditorStrings.inputModePenOnly));
    expect(_settings(env).inputMode, InputMode.penOnly);
    expect(find.text(EditorStrings.inputModePenOnlyHint), findsOneWidget);
    expect(
      (await _stored(
        tester,
        env,
        EditorSettingKeys.deviceSettings,
      ))['inputMode'],
      'penOnly',
    );
    await _tap(tester, find.text(EditorStrings.inputModeFingerDrawing));
    expect(_settings(env).inputMode, InputMode.fingerDrawing);
    expect(find.text(EditorStrings.inputModeFingerDrawingHint), findsOneWidget);
    expect(
      (await _stored(
        tester,
        env,
        EditorSettingKeys.deviceSettings,
      ))['inputMode'],
      'fingerDrawing',
    );
  });

  testWidgets('palm rejection: cooldown 0–1500 ms in 50 ms steps, hover, '
      'touch radius 20–120 px in 5 px steps, the hints', (tester) async {
    final env = await _pump(tester);
    await _show(tester, find.byKey(SettingsSectionKeys.penCooldown));
    expect(find.text(EditorStrings.penCooldownLabel(400)), findsOneWidget);
    final cooldown = _slider(tester, SettingsSectionKeys.penCooldown);
    expect((cooldown.min, cooldown.max, cooldown.divisions), (0, 1500, 30));
    await tester.drag(
      find.byKey(SettingsSectionKeys.penCooldown),
      const Offset(2000, 0),
    );
    await tester.pump();
    expect(
      _settings(env).palmRejection.penCooldown,
      const Duration(milliseconds: 1500),
    );
    expect(find.text(EditorStrings.penCooldownLabel(1500)), findsOneWidget);
    _slider(tester, SettingsSectionKeys.penCooldown).onChanged!(726);
    await tester.pump();
    expect(
      _settings(env).palmRejection.penCooldown,
      const Duration(milliseconds: 750),
    );

    await _tap(tester, find.byKey(SettingsSectionKeys.hoverAsPen));
    expect(_settings(env).palmRejection.treatHoverAsPenActivity, isFalse);
    expect(find.text(EditorStrings.hoverAsPenHint), findsOneWidget);

    await _show(tester, find.byKey(SettingsSectionKeys.maxTouchRadius));
    final radius = _slider(tester, SettingsSectionKeys.maxTouchRadius);
    expect((radius.min, radius.max, radius.divisions), (20, 120, 20));
    await tester.drag(
      find.byKey(SettingsSectionKeys.maxTouchRadius),
      const Offset(-2000, 0),
    );
    await tester.pump();
    expect(_settings(env).palmRejection.maxTouchRadius, 20);
    _slider(tester, SettingsSectionKeys.maxTouchRadius).onChanged!(63.4);
    await tester.pump();
    expect(_settings(env).palmRejection.maxTouchRadius, 65);
    expect(find.text(EditorStrings.maxTouchRadiusLabel(65)), findsOneWidget);
    expect(find.text(EditorStrings.maxTouchRadiusHint), findsOneWidget);

    expect(
      (await _stored(tester, env, EditorSettingKeys.deviceSettings))['palm'],
      {'cooldownMs': 750, 'hover': false, 'maxRadius': 65.0},
    );
  });

  testWidgets('gestures: the three finger gestures set to 없음 → '
      'editor.settings.synced; the fixed gestures as a read-only table; '
      'reset of the input settings', (tester) async {
    final env = await _pump(tester);
    // (v2, m5-7/04-editor 6.4.4) each row opens a sheet of its actions —
    // the details are in gesture_settings_section_test.
    for (final g in [
      EditorGesture.twoFingerTap,
      EditorGesture.threeFingerTap,
      EditorGesture.fingerLongPress,
    ]) {
      await _tap(tester, find.byKey(GestureActionTiles.rowKey(g)));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(GestureActionTiles.optionKey(EditorAction.none)),
      );
      await tester.pumpAndSettle();
    }
    expect(
      _settings(env).gestures,
      const GestureSettings(
        twoFingerTapUndo: false,
        threeFingerTapRedo: false,
        longPressMenu: false,
        actions: {
          EditorGesture.twoFingerTap: EditorAction.none,
          EditorGesture.threeFingerTap: EditorAction.none,
          EditorGesture.fingerLongPress: EditorAction.none,
        },
      ),
    );
    expect(
      (await _stored(
        tester,
        env,
        EditorSettingKeys.syncedSettings,
      ))['gestures'],
      {
        'twoFingerUndo': false,
        'threeFingerRedo': false,
        'longPressMenu': false,
        'actions': {
          'fingerLongPress': 'none',
          'threeFingerTap': 'none',
          'twoFingerTap': 'none',
        }, // 2nd round: v1.4 bools + actions
      },
    );

    await _show(tester, find.byKey(SettingsSectionKeys.fixedGestures));
    final table = find.byKey(SettingsSectionKeys.fixedGestures);
    for (final (gesture, action) in EditorStrings.fixedGestureTable) {
      expect(
        find.descendant(of: table, matching: find.text(gesture)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: table, matching: find.text(action)),
        findsWidgets,
      );
    }
    // Nothing in the table can be tapped.
    expect(
      find.descendant(of: table, matching: find.byType(InkWell)),
      findsNothing,
    );

    env.container.read(editorSettingsProvider.notifier)
      ..setInputMode(InputMode.penOnly)
      ..setPalmRejection(const PalmRejectionSettings(maxTouchRadius: 90));
    await _tap(tester, find.byKey(SettingsSectionKeys.resetInput));
    expect(_settings(env).inputMode, InputMode.auto);
    expect(_settings(env).palmRejection, const PalmRejectionSettings());
    expect(_settings(env).gestures, GestureSettings.defaults);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('pressure mode: 3 choices → ink.pressureModeProvider and '
      'editor.settings.device; simulated disables sensitivity and curve', (
    tester,
  ) async {
    final env = await _pump(tester);
    expect(env.container.read(ink.pressureModeProvider), ink.PressureMode.auto);
    for (final (label, mode) in [
      (EditorStrings.pressureModeReal, ink.PressureMode.alwaysReal),
      (EditorStrings.pressureModeSimulated, ink.PressureMode.alwaysSimulated),
      (EditorStrings.pressureModeAuto, ink.PressureMode.auto),
    ]) {
      await _tap(
        tester,
        find.descendant(
          of: find.byKey(SettingsSectionKeys.pressureMode),
          matching: find.text(label),
        ),
      );
      expect(_settings(env).pressureMode, mode);
      expect(env.container.read(ink.pressureModeProvider), mode);
      expect(
        (await _stored(
          tester,
          env,
          EditorSettingKeys.deviceSettings,
        ))['pressure'],
        mode.name,
      );
      final disabled = mode == ink.PressureMode.alwaysSimulated;
      expect(
        tester
                .widget<SegmentedButton<PressureFeel>>(
                  find.byKey(PenAdvancedControls.pressureKey),
                )
                .onSelectionChanged ==
            null,
        disabled,
      );
      expect(
        find.byKey(PenAdvancedControls.noPressureKey),
        disabled ? findsOneWidget : findsNothing,
      );
    }
  });

  for (final (stylus, text) in [
    (ink.PressureCapability.unknown, EditorStrings.pressureDetecting),
    (ink.PressureCapability.supported, EditorStrings.pressureSupported),
    (ink.PressureCapability.unsupported, EditorStrings.pressureUnsupported),
  ]) {
    testWidgets('detection state ${stylus.name} → "$text"', (tester) async {
      await _pump(tester, overrides: [_capability(stylus)]);
      await _show(tester, find.byKey(SettingsSectionKeys.pressureState));
      expect(
        tester.widget<Text>(find.byKey(SettingsSectionKeys.pressureState)).data,
        EditorStrings.pressureState(text),
      );
      // auto + unsupported → no pressure controls (6.5.7).
      expect(
        find.byKey(PenAdvancedControls.noPressureKey),
        stylus == ink.PressureCapability.unsupported
            ? findsOneWidget
            : findsNothing,
      );
    });
  }

  testWidgets('pen section: the same editorToolProvider values as the pen '
      'popup — current type by default, any P0 type by its chip; reset to '
      'the defaults', (tester) async {
    final env = await _pump(tester);
    final tools = env.container.read(editorToolProvider.notifier);
    await _show(tester, find.byKey(PenAdvancedControls.smoothingKey));
    // Starts on the current pen type.
    expect(
      tester
          .widget<PenTypeSelector>(find.byKey(SettingsSectionKeys.penType))
          .selected,
      core.PenTool.ballpoint,
    );
    // A change made elsewhere (the pen popup) shows here.
    tools.setSmoothing(0.3);
    await tester.pump();
    expect(_slider(tester, PenAdvancedControls.smoothingKey).value, 0.3);
    // A change here is the pen popup's value.
    _slider(tester, PenAdvancedControls.smoothingKey).onChanged!(0.81);
    await tester.pump();
    expect(_tools(env).currentPen.smoothing, 0.8);
    // (v2.15-ui) one pressure control: 약하게 → 0.5 linear, 강하게 → 1 firm.
    await _tap(
      tester,
      find.byKey(PenAdvancedControls.pressureFeelKey(PressureFeel.light)),
    );
    expect(_tools(env).currentPen.pressureSensitivity, 0.5);
    await _tap(
      tester,
      find.byKey(PenAdvancedControls.pressureFeelKey(PressureFeel.strong)),
    );
    expect(_tools(env).currentPen.pressureSensitivity, 1);
    expect(_tools(env).currentPen.pressureCurve, core.PressureCurve.firm);
    expect(find.text(EditorStrings.straightening), findsNothing);

    // The highlighter chip edits the highlighter without changing the pen.
    await _tap(
      tester,
      find.byKey(PenTypeSelector.keyOf(core.PenTool.highlighter)),
    );
    expect(_tools(env).penType, core.PenTool.ballpoint);
    expect(find.text(EditorStrings.straightening), findsOneWidget);
    await _tap(tester, find.text(EditorStrings.straighteningAlways));
    final highlighter = _tools(env).penStyles[core.PenTool.highlighter]!;
    expect(
      ink.StrokeStyleInk(highlighter).highlighterStraightening,
      ink.HighlighterStraightening.alwaysStraight,
    );
    _slider(tester, PenAdvancedControls.smoothingKey).onChanged!(0.1);
    await tester.pump();
    expect(_tools(env).penStyles[core.PenTool.highlighter]!.smoothing, 0.1);
    expect(_tools(env).currentPen.smoothing, 0.8, reason: 'ballpoint kept');

    // Stored in editor.penStyles (synced).
    final stored = await _stored(tester, env, EditorSettingKeys.penStyles);
    final styles = stored['styles']! as Map<String, Object?>;
    expect(
      core.StrokeStyle.fromJson(styles['highlighter']! as Map<String, Object?>),
      _tools(env).penStyles[core.PenTool.highlighter],
    );

    // Reset (asks first).
    await _tap(tester, find.byKey(SettingsSectionKeys.resetPenDefaults));
    expect(find.text(EditorStrings.resetPenDefaultsTitle), findsOneWidget);
    await tester.tap(find.text(EditorStrings.cancel));
    await tester.pumpAndSettle();
    expect(_tools(env).currentPen.smoothing, 0.8);
    await _tap(tester, find.byKey(SettingsSectionKeys.resetPenDefaults));
    await tester.tap(find.byKey(SettingsSectionKeys.resetPenDefaultsConfirm));
    await tester.pumpAndSettle();
    expect(_tools(env).penStyles, ToolState.defaultPenStyles());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('page section: 세로 스크롤 / 좌우 넘기기 → pageFlipMode, '
      'editor.settings.synced', (tester) async {
    final env = await _pump(tester);
    await _tap(
      tester,
      find.descendant(
        of: find.byKey(SettingsSectionKeys.pageFlip),
        matching: find.text(EditorStrings.pageFlipHorizontal),
      ),
    );
    expect(_settings(env).pageFlipMode, PageFlipMode.horizontalPaged);
    expect(find.text(EditorStrings.pageFlipHint), findsOneWidget);
    expect(
      (await _stored(
        tester,
        env,
        EditorSettingKeys.syncedSettings,
      ))['pageFlip'],
      'horizontalPaged',
    );
    await _tap(
      tester,
      find.descendant(
        of: find.byKey(SettingsSectionKeys.pageFlip),
        matching: find.text(EditorStrings.pageFlipVertical),
      ),
    );
    expect(_settings(env).pageFlipMode, PageFlipMode.verticalScroll);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('(v2, E2-17) page section 필기 재생: tap-to-seek switch '
      '(device), pre-roll 0–5 s in 0.5 s steps stored on release '
      '(editor.playback.preRollMs), the highlight style (synced)', (
    tester,
  ) async {
    final env = await _pump(tester);
    await _show(tester, find.text(EditorStrings.playbackSection));
    expect(find.text(EditorStrings.playbackSection), findsOneWidget);

    await _tap(tester, find.byKey(SettingsSectionKeys.playbackTapToSeek));
    expect(_settings(env).tapToSeek, isFalse);
    expect(
      (await _stored(
        tester,
        env,
        EditorSettingKeys.deviceSettings,
      ))['tapToSeek'],
      false,
    );

    await _show(tester, find.byKey(SettingsSectionKeys.playbackPreRoll));
    final slider = _slider(tester, SettingsSectionKeys.playbackPreRoll);
    expect((slider.min, slider.max, slider.divisions), (0, 5000, 10));
    expect(slider.value, 1500);
    expect(find.text(EditorStrings.playbackPreRollLabel(1500)), findsOneWidget);
    // While dragging only the label moves; the value is set on release.
    slider.onChanged!(3100);
    await tester.pump();
    expect(env.container.read(editorPreRollMsProvider), 1500);
    expect(find.text(EditorStrings.playbackPreRollLabel(3000)), findsWidgets);
    _slider(tester, SettingsSectionKeys.playbackPreRoll).onChangeEnd!(3100);
    await tester.pump();
    expect(env.container.read(editorPreRollMsProvider), 3000);
    await tester.drag(
      find.byKey(SettingsSectionKeys.playbackPreRoll),
      const Offset(2000, 0),
    );
    await tester.pump();
    expect(env.container.read(editorPreRollMsProvider), 5000);
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      await env.store.settings.get(EditorSettingKeys.playbackPreRollMs),
      5000,
    );

    await _tap(
      tester,
      find.descendant(
        of: find.byKey(SettingsSectionKeys.playbackHighlight),
        matching: find.text(EditorStrings.playbackHighlightRecent),
      ),
    );
    expect(
      _settings(env).playbackHighlight,
      ink.InkPlaybackStyle.highlightRecent,
    );
    expect(
      (await _stored(
        tester,
        env,
        EditorSettingKeys.syncedSettings,
      ))['playbackHighlight'],
      'highlightRecent',
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('developer section: the overlay switch (editor.settings.device '
      'dev), the other ways to turn it on, 합성 노트 만들기', (tester) async {
    final env = await _pump(tester);
    await _tap(tester, find.byKey(SettingsSectionKeys.devOverlay));
    expect(_settings(env).showDevOverlay, isTrue);
    expect(
      (await _stored(tester, env, EditorSettingKeys.deviceSettings))['dev'],
      isTrue,
    );
    expect(find.text(EditorStrings.devOverlayHint), findsOneWidget);

    // A second tap while it runs does nothing (one note).
    final seed = find.byKey(SettingsSectionKeys.seedSyntheticNote);
    await _show(tester, seed);
    await tester.tap(seed);
    await tester.tap(seed, warnIfMissed: false);
    for (var i = 0; i < 400; i++) {
      if (find
          .text(EditorStrings.seedSyntheticNoteDone)
          .evaluate()
          .isNotEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(find.text(EditorStrings.seedSyntheticNoteDone), findsOneWidget);
    expect(
      tester
          .widget<ListTile>(find.byKey(SettingsSectionKeys.seedSyntheticNote))
          .enabled,
      isTrue,
    );
    final found = await env.store.library.searchLibrary('perf-test');
    expect(found.notes.single.title, 'perf-test');
    final session = await env.store.openSession(found.notes.single.id);
    expect(session.pages, hasLength(50));
    await session.close();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 1)); // the snack bar
    }
  });

  testWidgets('each section is a Column without a Scaffold or scrolling of '
      'its own', (tester) async {
    await _pump(tester);
    for (final type in [
      EditorInputSettingsSection,
      EditorPenSettingsSection,
      EditorPageSettingsSection,
      EditorDeveloperSettingsSection,
    ]) {
      final section = find.byType(type, skipOffstage: false);
      await _show(tester, section);
      expect(
        find.descendant(
          of: section,
          matching: find.byType(Scrollable, skipOffstage: false),
          skipOffstage: false,
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: section,
          matching: find.byType(Scaffold, skipOffstage: false),
          skipOffstage: false,
        ),
        findsNothing,
      );
    }
  });
}
