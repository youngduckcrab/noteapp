// m5-7/04-editor 8.2 E2-18, 6.5: the Apple Pencil events on the editor
// screen through FakeStylusExtras (INFRA wires PencilStylusExtrasSource in
// the app — contract 7.2.10 v2.4):
// - subscription while the screen is open, none when isSupported is false,
//   stream errors ignored (6.5.1);
// - double tap → actionFor(pencilDoubleTap) (followSystem: switchEraser →
//   eraser ↔ back; set to undo → one undo);
// - squeeze: began / changed / cancelled ignored, ended +
//   showContextualPalette → the quick pen popup at the hover point;
// - the first squeeze / roll → seenSqueeze / seenBarrelRoll stored and the
//   settings rows shown (not before);
// - hover pose → the pen dot cursor (sized by the height), the developer
//   hover source, a finger down after it rejected (its timestamp, else the
//   router clock);
// - barrel roll → the calligraphy nib of the next stroke only (6.5.4);
// - prefersPencilOnlyDrawing → auto is pen only (6.5.3).
import 'dart:async';
import 'dart:math' as math;

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/popup.dart';
import 'package:feature_editor/src/state/settings/editor_device_state.dart';
import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:feature_editor/src/tools/interaction_host.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/dev/dev_metrics.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/pen/pen_extras_controls.dart';
import 'package:feature_editor/src/ui/pen/quick_pen_popup.dart';
import 'package:feature_editor/src/ui/settings/editor_settings_sections.dart';
import 'package:feature_editor/src/ui/settings/gesture_action_tile.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/fake_stylus_extras.dart';
import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

const List<Offset> _points = [
  Offset(100, 150),
  Offset(140, 170),
  Offset(190, 185),
  Offset(240, 200),
];

ToolState _tools(EditorTestHandles h) => h.container.read(editorToolProvider);
EditorPopup? _popup(EditorTestHandles h) =>
    h.container.read(editorPopupProvider);
InteractionHost _host(EditorTestHandles h) =>
    h.container.read(editorInteractionHostProvider);
List<core.Stroke> _strokes(EditorTestHandles h) =>
    h.session.pageIfLoaded(h.pageId(0))!.strokes;

/// The root container (device state, settings — outside the note scope).
ProviderContainer _root(WidgetTester tester) => tester
    .widget<UncontrolledProviderScope>(
      find.byType(UncontrolledProviderScope).first,
    )
    .container;

Future<void> _emit(
  WidgetTester tester,
  FakeStylusExtras s,
  StylusExtraEvent e,
) async {
  s.emit(e);
  await tester.pump(); // the event (a microtask of the broadcast stream)
  await tester.pump(); // the widgets that watch what it changed
}

/// Puts [body] on a route over the editor (the editor stays mounted and
/// subscribed underneath) — the settings screen INFRA shows.
Future<void> _pushOver(WidgetTester tester, Widget body) async {
  unawaited(
    Navigator.of(tester.element(find.byType(EditorScreen))).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(body: ListView(children: [body])),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

bool _shown(Key key) =>
    find.byKey(key, skipOffstage: false).evaluate().isNotEmpty;

Future<void> _draw(EditorTestHandles h) =>
    h.driver.stylusStroke(pathThrough(h, 0, _points));

Future<void> _fingerStroke(EditorTestHandles h) => h.driver.fingerDrag(
  pathThrough(h, 0, [_points.first]).single,
  pathThrough(h, 0, [_points.last]).single,
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await useInkTestFonts();
  });

  group('subscription (6.5.1)', () {
    testWidgets('listens while the screen is open; stops when it closes; '
        'stream errors are ignored', (tester) async {
      final stylus = FakeStylusExtras();
      final h = await pumpEditor(tester, stylusExtras: stylus);
      expect(stylus.listenCount, 1);
      expect(stylus.hasListener, isTrue);

      stylus.emitError(StateError('adapter'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await _emit(
        tester,
        stylus,
        const StylusDoubleTap(
          preferredAction: StylusPreferredAction.switchEraser,
        ),
      );
      expect(_tools(h).activeTool, EditorTool.eraser); // still subscribed

      await tester.pumpWidget(const SizedBox());
      expect(stylus.hasListener, isFalse);
      expect(stylus.cancelCount, 1);
    });

    testWidgets('isSupported == false → no subscription, events do nothing', (
      tester,
    ) async {
      final stylus = FakeStylusExtras(isSupported: false);
      final h = await pumpEditor(tester, stylusExtras: stylus);
      expect(stylus.listenCount, 0);
      expect(stylus.hasListener, isFalse);
      stylus.emit(
        const StylusDoubleTap(
          preferredAction: StylusPreferredAction.switchEraser,
        ),
      );
      await tester.pump();
      expect(_tools(h).activeTool, EditorTool.pen);
    });
  });

  group('double tap', () {
    testWidgets('followSystem (default) + switchEraser → eraser, again → '
        'back to the pen; showColorPalette → colour palette at the hover '
        'point; ignore → nothing; no command', (tester) async {
      final stylus = FakeStylusExtras();
      final h = await pumpEditor(tester, stylusExtras: stylus);
      expect(
        h.container
            .read(editorSettingsProvider)
            .gestures
            .actionFor(EditorGesture.pencilDoubleTap),
        EditorAction.followSystem,
      );
      const tap = StylusDoubleTap(
        preferredAction: StylusPreferredAction.switchEraser,
      );
      await _emit(tester, stylus, tap);
      expect(_tools(h).activeTool, EditorTool.eraser);
      await _emit(tester, stylus, tap);
      expect(_tools(h).activeTool, EditorTool.pen);

      await _emit(
        tester,
        stylus,
        const StylusDoubleTap(preferredAction: StylusPreferredAction.ignore),
      );
      expect(_tools(h).activeTool, EditorTool.pen);
      expect(_popup(h), isNull);

      const hover = Offset(300, 420);
      await _emit(
        tester,
        stylus,
        const StylusDoubleTap(
          preferredAction: StylusPreferredAction.showColorPalette,
          hoverPosition: hover,
        ),
      );
      expect(_popup(h), const ColorPalettePopup(globalPosition: hover));
      expect(h.recorder!.calls.where((c) => c.startsWith('execute')), isEmpty);
      await tester.pump(const Duration(seconds: 1)); // tool selection write
    });

    testWidgets('set to undo in the settings → one undo per double tap', (
      tester,
    ) async {
      final stylus = FakeStylusExtras();
      final h = await pumpEditor(
        tester,
        stylusExtras: stylus,
        settings: const EditorSettings(
          gestures: GestureSettings(
            actions: {EditorGesture.pencilDoubleTap: EditorAction.undo},
          ),
        ),
      );
      await _draw(h);
      expect(_strokes(h), hasLength(1));
      await _emit(
        tester,
        stylus,
        // the preferred action does not matter for a fixed action
        const StylusDoubleTap(
          preferredAction: StylusPreferredAction.switchEraser,
        ),
      );
      await tester.pump();
      expect(h.recorder!.countOf('undo'), 1);
      expect(_strokes(h), isEmpty);
      expect(_tools(h).activeTool, EditorTool.pen);
    });
  });

  group('squeeze', () {
    testWidgets('began / changed / cancelled → ignored; ended + '
        'showContextualPalette → the quick pen popup at hoverPosition', (
      tester,
    ) async {
      final stylus = FakeStylusExtras();
      final h = await pumpEditor(tester, stylusExtras: stylus);
      const hover = Offset(320, 460);
      for (final phase in [
        StylusSqueezePhase.began,
        StylusSqueezePhase.changed,
        StylusSqueezePhase.cancelled,
      ]) {
        await _emit(
          tester,
          stylus,
          StylusSqueeze(
            phase: phase,
            preferredAction: StylusPreferredAction.showContextualPalette,
            hoverPosition: hover,
          ),
        );
        expect(_popup(h), isNull, reason: phase.name);
        expect(_tools(h).activeTool, EditorTool.pen);
      }
      await _emit(
        tester,
        stylus,
        const StylusSqueeze(
          preferredAction: StylusPreferredAction.showContextualPalette,
          hoverPosition: hover,
        ),
      );
      expect(_popup(h), const QuickPenPopup(globalPosition: hover));
      await tester.pump();
      // _AtPointLayout: 12 px right of and below the point.
      expect(
        tester.getTopLeft(find.byType(QuickPenPanel)),
        hover + const Offset(12, 12),
      );
    });

    testWidgets('the first squeeze stores seenSqueeze and shows the squeeze '
        'settings row (not before); the next-launch hint', (tester) async {
      final stylus = FakeStylusExtras();
      final h = await pumpEditor(tester, stylusExtras: stylus);
      final note = h.container; // the editor goes offstage under the route
      await _pushOver(tester, const EditorInputSettingsSection());
      final squeezeRow = GestureActionTiles.rowKey(EditorGesture.pencilSqueeze);
      expect(
        _shown(GestureActionTiles.rowKey(EditorGesture.pencilDoubleTap)),
        isTrue,
      );
      expect(_shown(squeezeRow), isFalse);
      expect(_shown(GestureActionTiles.pencilHintKey), isTrue);
      expect(
        find.text(EditorStrings.pencilNextLaunch, skipOffstage: false),
        findsOneWidget,
      );

      // A squeeze that only began counts as seen (the event handling is
      // separate).
      await _emit(
        tester,
        stylus,
        const StylusSqueeze(phase: StylusSqueezePhase.began),
      );
      expect(_root(tester).read(editorDeviceStateProvider).seenSqueeze, isTrue);
      expect(_shown(squeezeRow), isTrue);
      expect(note.read(editorPopupProvider), isNull);

      await tester.pump(const Duration(seconds: 1)); // the device key write
      final stored = await h.store.settings.get(EditorSettingKeys.deviceState);
      expect(stored['seenSqueeze'], isTrue);
      expect(stored['seenBarrelRoll'], isFalse);
    });
  });

  group('hover pose (6.5.3)', () {
    testWidgets('capabilities.hoverPose → the pen dot at the pose (viewport '
        'px), × (1 + 0.5 × height), 50 % pen colour; a mouse hover leaves it; '
        'hidden 300 ms after the last pose', (tester) async {
      final stylus = FakeStylusExtras();
      final h = await pumpEditor(tester, stylusExtras: stylus);
      final host = _host(h);
      final at = pageCenterOf(h, 0);
      final pen = _tools(h).currentPen;
      final base = math.max(
        4,
        2 * ink.StrokeStyleInk(pen).previewRadius * h.viewport.camera.scale,
      );

      for (final (height, factor) in [(0.0, 1.0), (0.4, 1.2), (1.0, 1.5)]) {
        await _emit(
          tester,
          stylus,
          StylusHoverPose(position: at, height: height),
        );
        final cursor = host.cursor.value! as PenDotCursor;
        expect(cursor.position, at - h.viewportOrigin);
        expect(
          cursor.diameter,
          closeTo(base * factor, 1e-9),
          reason: '$height',
        );
        expect(cursor.color, Color(pen.colorArgb).withValues(alpha: 0.5));
      }
      await _emit(tester, stylus, StylusHoverPose(position: at)); // no height
      expect(
        (host.cursor.value! as PenDotCursor).diameter,
        closeTo(base, 1e-9),
      );

      // iPad: the pencil hover also comes as a mouse hover — no change.
      await h.driver.hover(
        at + const Offset(30, 0),
        kind: PointerDeviceKind.mouse,
      );
      expect(host.cursor.value, isA<PenDotCursor>());
      expect(
        (host.cursor.value! as PenDotCursor).position,
        at - h.viewportOrigin,
      );

      await tester.pump(kHoverCursorTimeout);
      expect(host.cursor.value, isNull);

      // Other tools keep the Flutter hover's cursor.
      h.container
          .read(editorToolProvider.notifier)
          .selectTool(EditorTool.lasso);
      await _emit(tester, stylus, StylusHoverPose(position: at, height: 0.5));
      expect(host.cursor.value, isNull);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('without capabilities.hoverPose → no pose cursor (the 1st '
        'mouse rule stays)', (tester) async {
      final stylus = FakeStylusExtras(
        capabilities: const StylusCapabilities(doubleTap: true),
      );
      final h = await pumpEditor(tester, stylusExtras: stylus);
      await _emit(
        tester,
        stylus,
        StylusHoverPose(position: pageCenterOf(h, 0), height: 0.2),
      );
      expect(_host(h).cursor.value, isNull);
    });

    testWidgets('developer metrics: hover source pencilPose(<height>)', (
      tester,
    ) async {
      final stylus = FakeStylusExtras();
      final h = await pumpEditor(tester, stylusExtras: stylus);
      final metrics = h.container.read(editorDevMetricsProvider)..start();
      await _emit(
        tester,
        stylus,
        StylusHoverPose(position: pageCenterOf(h, 0), height: 0.4),
      );
      await tester.pump(metrics.publishInterval);
      expect(metrics.snapshot.hoverSource, 'pencilPose(0.40)');
      await _emit(
        tester,
        stylus,
        StylusHoverPose(position: pageCenterOf(h, 0)),
      );
      await tester.pump(metrics.publishInterval);
      expect(metrics.snapshot.hoverSource, 'pencilPose(-)');
      metrics.stop();
      await tester.pump(const Duration(seconds: 1));
    });

    Future<EditorTestHandles> fingerDrawing(
      WidgetTester tester,
      FakeStylusExtras stylus,
    ) => pumpEditor(
      tester,
      stylusExtras: stylus,
      settings: const EditorSettings(
        inputMode: InputMode.fingerDrawing,
        // the longest cooldown: the stamp-less case runs on real time
        palmRejection: PalmRejectionSettings(
          penCooldown: Duration(milliseconds: 1500),
        ),
      ),
    );

    testWidgets('a finger down right after a stamp-less pose → rejected '
        '(palm, the router clock on both sides)', (tester) async {
      final stylus = FakeStylusExtras();
      final h = await fingerDrawing(tester, stylus);
      final metrics = h.container.read(editorDevMetricsProvider)..start();
      await _emit(
        tester,
        stylus,
        StylusHoverPose(position: pageCenterOf(h, 0)),
      );
      await _fingerStroke(h);
      expect(_strokes(h), isEmpty);
      await tester.pump(metrics.publishInterval);
      expect(metrics.snapshot.palmRejectedCount, 1);
      metrics.stop();
    });

    testWidgets('a timestamped pose is compared with the down timestamp: '
        '2 s older → the finger draws; the down time itself → rejected', (
      tester,
    ) async {
      final stylus = FakeStylusExtras();
      final h = await fingerDrawing(tester, stylus);
      final metrics = h.container.read(editorDevMetricsProvider)..start();
      final at = pageCenterOf(h, 0);

      await _emit(
        tester,
        stylus,
        StylusHoverPose(
          position: at,
          timestamp: h.driver.now - const Duration(seconds: 2),
        ),
      );
      await _fingerStroke(h);
      expect(_strokes(h), hasLength(1));

      await h.driver.wait(const Duration(seconds: 2));
      await _emit(
        tester,
        stylus,
        StylusHoverPose(position: at, timestamp: h.driver.now),
      );
      await h.driver.wait(const Duration(milliseconds: 100));
      await _fingerStroke(h);
      expect(_strokes(h), hasLength(1));
      await tester.pump(metrics.publishInterval);
      expect(metrics.snapshot.palmRejectedCount, 1);
      metrics.stop();
    });
  });

  group('barrel roll (6.5.4)', () {
    Future<EditorTestHandles> calligraphy(
      WidgetTester tester,
      FakeStylusExtras stylus,
    ) async {
      final h = await pumpEditor(tester, stylusExtras: stylus);
      h.container
          .read(editorToolProvider.notifier)
          .selectPenType(core.PenTool.calligraphy);
      await tester.pump();
      return h;
    }

    double nib(core.Stroke s) => ink.StrokeStyleInk(s.style).nibAngleDeg;

    testWidgets('a roll of 30° turns the next calligraphy stroke 45° → 75°; '
        'the pen setting keeps 45°; a hover pose roll counts too', (
      tester,
    ) async {
      final stylus = FakeStylusExtras();
      final h = await calligraphy(tester, stylus);
      await _emit(
        tester,
        stylus,
        StylusBarrelRoll(math.pi / 6, timestamp: h.driver.now),
      );
      await _draw(h);
      expect(_strokes(h), hasLength(1));
      expect(nib(_strokes(h).single), closeTo(75, 1e-6));
      expect(ink.StrokeStyleInk(_tools(h).currentPen).nibAngleDeg, 45);

      // 170° from a hover pose: (45 + 170) mod 180 = 35.
      await _emit(
        tester,
        stylus,
        StylusHoverPose(
          position: pageCenterOf(h, 0),
          roll: 170 * math.pi / 180,
          timestamp: h.driver.now,
        ),
      );
      await h.driver.stylusStroke(
        pathThrough(h, 0, [for (final p in _points) p + const Offset(0, 80)]),
      );
      expect(nib(_strokes(h).last), closeTo(35, 1e-6));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a roll older than 500 ms (event time) → the base angle; '
        'followBarrelRoll off → the base angle', (tester) async {
      final stylus = FakeStylusExtras();
      final h = await calligraphy(tester, stylus);
      await _emit(
        tester,
        stylus,
        StylusBarrelRoll(math.pi / 6, timestamp: h.driver.now),
      );
      await h.driver.wait(const Duration(milliseconds: 600));
      await _draw(h);
      expect(nib(_strokes(h).single), 45);

      h.container
          .read(editorToolProvider.notifier)
          .updateStyleOf(
            core.PenTool.calligraphy,
            (s) => ink.StrokeStyleInk(s).withInkExtras(followBarrelRoll: false),
          );
      await _emit(
        tester,
        stylus,
        StylusBarrelRoll(math.pi / 6, timestamp: h.driver.now),
      );
      await h.driver.stylusStroke(
        pathThrough(h, 0, [for (final p in _points) p + const Offset(0, 80)]),
      );
      expect(nib(_strokes(h).last), 45);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('capabilities.barrelRoll false → the base angle', (
      tester,
    ) async {
      final stylus = FakeStylusExtras(
        capabilities: const StylusCapabilities(
          doubleTap: true,
          hoverPose: true,
        ),
      );
      final h = await calligraphy(tester, stylus);
      await _emit(
        tester,
        stylus,
        StylusBarrelRoll(math.pi / 6, timestamp: h.driver.now),
      );
      await _draw(h);
      expect(nib(_strokes(h).single), 45);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the first roll stores seenBarrelRoll and shows '
        '"펜슬 돌리기로 각도 조절" (not before)', (tester) async {
      final stylus = FakeStylusExtras();
      final h = await calligraphy(tester, stylus);
      await _pushOver(
        tester,
        const PenExtrasControls(tool: core.PenTool.calligraphy),
      );
      expect(_shown(PenExtrasControls.nibAngleKey), isTrue);
      expect(_shown(PenExtrasControls.followBarrelRollKey), isFalse);

      await _emit(tester, stylus, const StylusBarrelRoll(0.2));
      expect(
        _root(tester).read(editorDeviceStateProvider).seenBarrelRoll,
        isTrue,
      );
      expect(_shown(PenExtrasControls.followBarrelRollKey), isTrue);
      await tester.pump(const Duration(seconds: 1));
      final stored = await h.store.settings.get(EditorSettingKeys.deviceState);
      expect(stored['seenBarrelRoll'], isTrue);
    });
  });

  group("iPadOS '펜슬로만 그리기' (6.5.3)", () {
    testWidgets('prefersPencilOnlyDrawing → auto is pen only before any '
        'stylus: a finger does not draw, [✋] shows pen only, the input '
        'mode hint says it follows the iPad', (tester) async {
      final stylus = FakeStylusExtras(
        capabilities: const StylusCapabilities(prefersPencilOnlyDrawing: true),
      );
      final h = await pumpEditor(tester, stylusExtras: stylus);
      final settings = h.container.read(editorSettingsProvider);
      expect(settings.inputMode, InputMode.auto);
      expect(settings.stylusSeen, isFalse);
      expect(settings.isPenOnlyEffective, isFalse); // settings-only getter
      expect(_host(h).policy.penOnly, isTrue);
      expect(
        tester
            .widget<IconButton>(find.byKey(EditorToolbar.fingerKey))
            .isSelected,
        isFalse,
      );
      await _fingerStroke(h);
      expect(_strokes(h), isEmpty);

      await _pushOver(tester, const EditorInputSettingsSection());
      expect(_shown(SettingsSectionKeys.inputModePencilOnly), isTrue);
      expect(
        find.text(EditorStrings.pencilFollowsSystem, skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('without it auto draws with a finger until a stylus is seen; '
        'a penOnly / fingerDrawing choice is not overridden', (tester) async {
      final stylus = FakeStylusExtras(
        capabilities: const StylusCapabilities(doubleTap: true),
      );
      final h = await pumpEditor(tester, stylusExtras: stylus);
      expect(_host(h).policy.penOnly, isFalse);
      await _fingerStroke(h);
      expect(_strokes(h), hasLength(1));
      await _pushOver(tester, const EditorInputSettingsSection());
      expect(_shown(SettingsSectionKeys.inputModePencilOnly), isFalse);
    });

    testWidgets('fingerDrawing chosen + prefersPencilOnlyDrawing → fingers '
        'still draw (only auto follows the iPad)', (tester) async {
      final stylus = FakeStylusExtras(
        capabilities: const StylusCapabilities(prefersPencilOnlyDrawing: true),
      );
      final h = await pumpEditor(
        tester,
        stylusExtras: stylus,
        settings: const EditorSettings(inputMode: InputMode.fingerDrawing),
      );
      expect(_host(h).policy.penOnly, isFalse);
      await _fingerStroke(h);
      expect(_strokes(h), hasLength(1));
    });
  });
}
