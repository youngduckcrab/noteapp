// 04-editor 19: hiding the top menu (toolbar button, ⋯, restore pill, system
// back, undo / redo while hidden, the first-hide hint, the stored choice) and
// the floating pen palette (detach / re-dock, expand / select / collapse,
// drag and clamp, a pen stroke while it is open), the device-state fields'
// JSON, no overflow at phone and tablet widths.
import 'dart:ui' show PointerDeviceKind;

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/actions/editor_action_runner.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/popup.dart';
import 'package:feature_editor/src/state/settings/editor_device_state.dart';
import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/chrome/editor_chrome.dart';
import 'package:feature_editor/src/ui/chrome/floating_layer.dart';
import 'package:feature_editor/src/ui/chrome/pen_palette.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/pen/quick_pen_popup.dart';
import 'package:feature_editor/src/ui/popup_host.dart';
import 'package:feature_editor/src/ui/presets/preset_bar_view.dart';
import 'package:feature_editor/src/ui/presets/preset_chip.dart';
import 'package:feature_editor/src/ui/presets/save_preset_dialog.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:feature_editor/src/ui/toolbar/more_menu.dart';
import 'package:feature_editor/src/ui/toolbar/undo_redo_buttons.dart';
import 'package:feature_editor/src/viewport/page_viewport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/fake_extensions.dart';
import '../helpers/fake_image_importer.dart';
import '../helpers/fake_math_pen.dart';
import '../helpers/fake_text_pen.dart';
import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

const List<Offset> _points = [
  Offset(300, 500),
  Offset(330, 520),
  Offset(370, 540),
  Offset(420, 555),
];

/// Lets the slide (200 ms) finish.
Future<void> _slide(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

/// Lets a snack bar (4 s) and its animations finish.
Future<void> _settleSnackBar(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

EditorDeviceState _device(EditorTestHandles h) =>
    h.container.read(editorDeviceStateProvider);

Future<Map<String, Object?>> _stored(EditorTestHandles h) async {
  await h.container.read(editorDeviceStateProvider.notifier).flush();
  return h.store.settings.get(EditorSettingKeys.deviceState);
}

Finder get _toolbar => find.byType(EditorToolbar);
Finder get _pill => find.byKey(MenuRestorePill.pillKey);
Finder get _paletteButton => find.byKey(PenPalette.buttonKey);
Finder get _panel => find.byKey(PenPalette.panelKey);

Future<void> _hideWithButton(WidgetTester tester) async {
  await tester.tap(find.byKey(MenuHideButton.buttonKey));
  await _slide(tester);
}

Future<void> _detach(WidgetTester tester) async {
  await tester.tap(find.byKey(PaletteDetachButton.buttonKey));
  await tester.pump();
}

Future<void> _openMore(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(EditorMoreMenu.buttonKey));
  await tester.pump();
  await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
  await tester.pump();
}

/// MenuItemButton runs onPressed after the next frame.
Future<void> _pickMore(WidgetTester tester, Key item) async {
  await tester.tap(find.byKey(item));
  await tester.pump();
  await tester.pump();
}

Rect _rect(WidgetTester tester, Finder f) => tester.getRect(f);

void main() {
  group('hiding the top menu', () {
    testWidgets('[⌃] hides both rows (the page gets the room), the pill '
        'shows; the first time a hint; the pill brings them back', (
      tester,
    ) async {
      final h = await pumpEditor(tester);
      final topBefore = tester.getTopLeft(find.byType(PageViewport)).dy;
      expect(_toolbar, findsOneWidget);
      expect(find.byKey(PresetBarView.barKey), findsOneWidget);
      expect(_pill, findsNothing);

      await _hideWithButton(tester);
      expect(_toolbar, findsNothing);
      expect(find.byKey(PresetBarView.barKey), findsNothing);
      expect(_pill, findsOneWidget);
      expect(_device(h).toolbarHidden, isTrue);
      expect(
        tester.getTopLeft(find.byType(PageViewport)).dy,
        lessThan(topBefore - EditorToolbar.height - PresetBarView.height + 1),
      );
      expect(find.text(EditorStrings.menuHiddenHint), findsOneWidget);
      await _settleSnackBar(tester);

      await tester.tap(find.byKey(MenuRestorePill.showKey));
      await _slide(tester);
      expect(_toolbar, findsOneWidget);
      expect(find.byKey(PresetBarView.barKey), findsOneWidget);
      expect(_pill, findsNothing);
      expect(tester.getTopLeft(find.byType(PageViewport)).dy, topBefore);

      // The hint only once per device.
      await _hideWithButton(tester);
      expect(find.text(EditorStrings.menuHiddenHint), findsNothing);
      expect((await _stored(h))['seenToolbarHideHint'], isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the slide: half way the rows are clipped, not removed', (
      tester,
    ) async {
      await pumpEditor(tester);
      await tester.tap(find.byKey(MenuHideButton.buttonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_toolbar, findsOneWidget);
      final menu = tester.getSize(find.byType(EditorTopMenu));
      expect(menu.height, greaterThan(0));
      expect(
        menu.height,
        lessThan(EditorToolbar.height + PresetBarView.height),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(_toolbar, findsNothing);
    });

    testWidgets("⋯ '메뉴 숨기기' hides the menu", (tester) async {
      final h = await pumpEditor(tester);
      await _openMore(tester);
      await _pickMore(tester, EditorChrome.moreHideKey);
      await _slide(tester);
      expect(_device(h).toolbarHidden, isTrue);
      expect(_toolbar, findsNothing);
      expect(_pill, findsOneWidget);
    });

    testWidgets('system back while hidden shows the menu (the note stays '
        'open); the next back leaves', (tester) async {
      final h = await pumpEditor(tester);
      await _hideWithButton(tester);
      await tester.binding.handlePopRoute();
      await _slide(tester);
      expect(h.closeCount, 0);
      expect(_toolbar, findsOneWidget);
      expect(_device(h).toolbarHidden, isFalse);

      await tester.binding.handlePopRoute();
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(h.closeCount, 1);
    });

    testWidgets('undo / redo on the pill while hidden', (tester) async {
      final h = await pumpEditor(tester);
      await _hideWithButton(tester);
      await _settleSnackBar(tester);
      expect(
        tester
            .widget<IconButton>(find.byKey(UndoRedoButtons.pillUndoKey))
            .onPressed,
        isNull,
      );
      await h.driver.stylusStroke(pathThrough(h, 0, _points));
      await tester.pump();
      expect(h.session.pageIfLoaded(h.pageId(0))!.strokes, hasLength(1));

      await tester.tap(find.byKey(UndoRedoButtons.pillUndoKey));
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      expect(h.session.pageIfLoaded(h.pageId(0))!.strokes, isEmpty);
      await tester.tap(find.byKey(UndoRedoButtons.pillRedoKey));
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      expect(h.session.pageIfLoaded(h.pageId(0))!.strokes, hasLength(1));
      // The pen kept working with the menu hidden.
      expect(_toolbar, findsNothing);
    });

    testWidgets('the pill drags along the top edge, clamped; stored', (
      tester,
    ) async {
      final h = await pumpEditor(tester);
      await _hideWithButton(tester);
      final area = _rect(tester, find.byType(EditorFloatingLayer));
      final before = _rect(tester, _pill);
      expect(before.center.dx, closeTo(area.center.dx, 1));
      await tester.drag(
        find.byKey(MenuRestorePill.showKey),
        const Offset(-5000, 40),
      );
      await tester.pump();
      final after = _rect(tester, _pill);
      expect(after.left, area.left);
      expect(after.top, before.top); // only sideways
      expect((await _stored(h))['restorePillX'], 0.0);
      expect(_toolbar, findsNothing); // a drag is not a tap
    });

    testWidgets('a stored hidden menu opens hidden (no slide)', (tester) async {
      await pumpEditor(
        tester,
        beforePump: (store, _, _) => store.settings.set(
          EditorSettingKeys.deviceState,
          const EditorDeviceState(toolbarHidden: true).toJson(),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(_toolbar, findsNothing);
      expect(_pill, findsOneWidget);
    });
  });

  group('device state JSON', () {
    test('round trip of the chrome fields', () {
      const s = EditorDeviceState(
        toolbarHidden: true,
        seenToolbarHideHint: true,
        paletteDetached: true,
        palettePosition: Offset(0.75, 0.5),
        restorePillX: 0.25,
      );
      final json = s.toJson();
      expect(json['v'], 2);
      expect(EditorDeviceState.fromJson(json), s);
    });

    test('a v1 value decodes with the chrome defaults', () {
      final s = EditorDeviceState.fromJson(const {
        'v': 1,
        'webTextInput': 'sheet',
        'collectShapeSamples': true,
        'seenSqueeze': true,
        'seenBarrelRoll': false,
      });
      expect(s.webTextInput, WebTextInputMode.sheet);
      expect(s.collectShapeSamples, isTrue);
      expect(s.seenSqueeze, isTrue);
      expect(s.toolbarHidden, isFalse);
      expect(s.paletteDetached, isFalse);
      expect(s.palettePosition, EditorDeviceState.defaultPalettePosition);
      expect(s.restorePillX, EditorDeviceState.defaultRestorePillX);
    });

    test('wrong-typed or out-of-range chrome values', () {
      final s = EditorDeviceState.fromJson(const {
        'toolbarHidden': 'yes',
        'palettePosition': {'x': 3, 'y': 'a'},
        'restorePillX': -2,
      });
      expect(s.toolbarHidden, isFalse);
      expect(s.palettePosition, EditorDeviceState.defaultPalettePosition);
      expect(s.restorePillX, 0.0);
      final t = EditorDeviceState.fromJson(const {
        'palettePosition': {'x': 3, 'y': -1},
      });
      expect(t.palettePosition, const Offset(1, 0));
    });
  });

  group('the pen palette', () {
    testWidgets('detach from the preset row: the row leaves, the button '
        'shows; tap → the presets; a preset → selected, pen tool, closed', (
      tester,
    ) async {
      final h = await pumpEditor(tester);
      h.container.read(editorCommandsProvider).selectTool(EditorTool.eraser);
      await _detach(tester);
      expect(find.byKey(PresetBarView.barKey), findsNothing);
      expect(_paletteButton, findsOneWidget);
      expect(_device(h).paletteDetached, isTrue);
      expect(_toolbar, findsOneWidget);

      await tester.tap(_paletteButton);
      await tester.pump();
      expect(_panel, findsOneWidget);
      final presets = await h.store.penPresets.getPresets();
      expect(presets, isNotEmpty);
      for (final p in presets.where((p) => p.pinned)) {
        expect(find.byKey(PenPalette.chipKey(p.id)), findsOneWidget);
      }
      final highlighter = presets.firstWhere(
        (p) => p.style.tool == core.PenTool.highlighter,
      );
      await tester.tap(find.byKey(PenPalette.chipKey(highlighter.id)));
      await tester.pump();
      final tools = h.container.read(editorToolProvider);
      expect(tools.activeTool, EditorTool.pen);
      expect(tools.currentPen, highlighter.style.normalized());
      expect(_panel, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the current preset is bordered in the palette', (
      tester,
    ) async {
      final h = await pumpEditor(tester);
      await _detach(tester);
      final presets = await h.store.penPresets.getPresets();
      h.container
          .read(editorToolProvider.notifier)
          .applyStyle(presets[1].style);
      await tester.tap(_paletteButton);
      await tester.pump();
      final chips = tester.widgetList<PresetChip>(
        find.descendant(of: _panel, matching: find.byType(PresetChip)),
      );
      expect(
        [
          for (final c in chips)
            if (c.active) c.preset.id,
        ],
        [presets[1].id],
      );
    });

    testWidgets('⋯ detaches and re-docks; the palette re-docks too', (
      tester,
    ) async {
      final h = await pumpEditor(tester);
      await _openMore(tester);
      await _pickMore(tester, EditorChrome.moreDetachKey);
      expect(_device(h).paletteDetached, isTrue);
      expect(find.byKey(PresetBarView.barKey), findsNothing);
      await _openMore(tester);
      await _pickMore(tester, EditorChrome.moreDockKey);
      expect(_device(h).paletteDetached, isFalse);
      expect(find.byKey(PresetBarView.barKey), findsOneWidget);
      expect(_paletteButton, findsNothing);

      await _detach(tester);
      await tester.tap(_paletteButton);
      await tester.pump();
      await tester.tap(find.byKey(PenPalette.dockKey));
      await tester.pump();
      expect(find.byKey(PresetBarView.barKey), findsOneWidget);
      expect(_paletteButton, findsNothing);
      expect((await _stored(h))['paletteDetached'], isFalse);
    });

    testWidgets('[+] opens the save dialog, the palette closes', (
      tester,
    ) async {
      await pumpEditor(tester);
      await _detach(tester);
      await tester.tap(_paletteButton);
      await tester.pump();
      await tester.tap(find.byKey(PenPalette.addKey));
      await tester.pump();
      expect(find.byKey(SavePresetDialog.panelKey), findsOneWidget);
      expect(_panel, findsNothing);
    });

    testWidgets('a pen stroke on the page while open: the palette closes and '
        'the stroke is drawn', (tester) async {
      final h = await pumpEditor(tester);
      h.container.read(editorCommandsProvider).selectTool(EditorTool.pen);
      await _detach(tester);
      await tester.tap(_paletteButton);
      await tester.pump();
      final path = pathThrough(h, 0, _points);
      expect(_rect(tester, _panel).contains(path.first), isFalse);
      await h.driver.stylusStroke(path);
      await tester.pump();
      expect(_panel, findsNothing);
      expect(h.session.pageIfLoaded(h.pageId(0))!.strokes, hasLength(1));
    });

    testWidgets('a finger tap outside closes it', (tester) async {
      await pumpEditor(tester);
      await _detach(tester);
      await tester.tap(_paletteButton);
      await tester.pump();
      await tester.tap(find.byKey(EditorToolbar.lassoKey));
      await tester.pump();
      expect(_panel, findsNothing);
    });

    testWidgets('drag (finger or stylus) moves the button and clamps it '
        'inside the page area; a short move is still a tap; stored; a '
        'rotation keeps it inside', (tester) async {
      final h = await pumpEditor(tester);
      await _detach(tester);
      final area = _rect(tester, find.byType(EditorFloatingLayer));
      await tester.drag(_paletteButton, const Offset(5000, 5000));
      await tester.pump();
      var button = _rect(tester, _paletteButton);
      expect(button.right, area.right - PenPalette.margin);
      expect(button.bottom, area.bottom - PenPalette.margin);
      expect(_panel, findsNothing);
      final stored = await _stored(h);
      expect(stored['palettePosition'], {'x': 1.0, 'y': 1.0});

      await tester.drag(
        _paletteButton,
        const Offset(-300, -200),
        kind: PointerDeviceKind.stylus,
      );
      await tester.pump();
      final moved = _rect(tester, _paletteButton);
      expect(moved.left, closeTo(button.left - 300, 20));
      expect(moved.top, closeTo(button.top - 200, 20));

      // A move under the slop is a tap.
      final g = await tester.startGesture(tester.getCenter(_paletteButton));
      await g.moveBy(const Offset(3, 2));
      await g.up();
      await tester.pump();
      expect(_panel, findsOneWidget);
      expect(_rect(tester, _paletteButton), moved);

      // The panel sits inside the area.
      final panel = _rect(tester, _panel);
      expect(panel.left, greaterThanOrEqualTo(area.left));
      expect(panel.right, lessThanOrEqualTo(area.right));
      expect(panel.bottom, lessThanOrEqualTo(area.bottom));
      expect(panel.overlaps(_rect(tester, _paletteButton)), isFalse);

      tester.view.physicalSize = const Size(1376, 1032) * 2;
      await tester.pump();
      await tester.pump();
      final turned = _rect(tester, find.byType(EditorFloatingLayer));
      button = _rect(tester, _paletteButton);
      expect(turned.contains(button.topLeft), isTrue);
      expect(turned.contains(button.bottomRight - const Offset(1, 1)), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with the menu hidden the palette stays (detached) and never '
        'covers the pill; docked, it hides with the menu', (tester) async {
      await pumpEditor(tester);
      await _detach(tester);
      await tester.drag(_paletteButton, const Offset(5000, -5000));
      await tester.pump();
      await _hideWithButton(tester);
      expect(_paletteButton, findsOneWidget);
      final pill = _rect(tester, _pill);
      expect(_rect(tester, _paletteButton).top, greaterThan(pill.bottom));
      await tester.tap(_paletteButton);
      await tester.pump();
      expect(_rect(tester, _panel).overlaps(pill), isFalse);

      await tester.tap(find.byKey(PenPalette.dockKey));
      await tester.pump();
      expect(_paletteButton, findsNothing);
      expect(find.byKey(PresetBarView.barKey), findsNothing); // with the menu
      await tester.tap(find.byKey(MenuRestorePill.showKey));
      await _slide(tester);
      expect(find.byKey(PresetBarView.barKey), findsOneWidget);
    });

    testWidgets('semantics: the button names the pen and its state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpEditor(tester);
      await _detach(tester);
      expect(find.bySemanticsLabel(RegExp('^펜 팔레트, 지금 ')), findsOneWidget);
      await tester.tap(_paletteButton);
      await tester.pump();
      expect(find.bySemanticsLabel(RegExp('펼쳐짐')), findsOneWidget);
      expect(find.bySemanticsLabel(EditorStrings.dockPalette), findsOneWidget);
      handle.dispose();
    });
  });

  group('layout', () {
    for (final size in const [
      Size(360, 780),
      Size(780, 360),
      Size(1280, 800),
    ]) {
      testWidgets('${size.width.toInt()}×${size.height.toInt()}: shown, '
          'hidden, palette open — no overflow', (tester) async {
        await pumpEditor(tester, logicalSize: size);
        expect(tester.takeException(), isNull);
        expect(find.byKey(MenuHideButton.buttonKey), findsOneWidget);
        await _detach(tester);
        await tester.tap(_paletteButton);
        await tester.pump();
        expect(tester.takeException(), isNull);
        final area = _rect(tester, find.byType(EditorFloatingLayer));
        final panel = _rect(tester, _panel);
        expect(panel.top, greaterThanOrEqualTo(area.top));
        expect(panel.bottom, lessThanOrEqualTo(area.bottom + 0.01));
        expect(panel.left, greaterThanOrEqualTo(area.left));
        expect(panel.right, lessThanOrEqualTo(area.right + 0.01));
        await tester.tap(find.byKey(MenuHideButton.buttonKey));
        await _slide(tester);
        expect(tester.takeException(), isNull);
        expect(_pill, findsOneWidget);
      });
    }

    // [⌃] after [←] where it fits (else in ⋯ only), with every optional
    // button on (insert, mic, math pen, text pen, sync badge; 19.1 [🔍]).
    // (v2.14-ui) Without [✋] (and the [100%] chip at fit) the row is about
    // 112 px shorter, so [⌃] now fits at every width here.
    for (final (width, shown) in const [
      (360.0, true), // the row scrolls: right after [←]
      (800.0, true), // folded (Android portrait, with [🔍])
      (900.0, true), // folded (19.1: foldWidth 952)
      (960.0, true), // unfolded with [🔍]
      // With the title: [⌃] while the title keeps titleLeastWidth.
      (1000.0, true),
      (1024.0, true),
      (1048.0, true),
      (1080.0, true),
    ]) {
      testWidgets('[⌃] at $width px: ${shown ? 'in the row' : 'in ⋯ only'}, '
          'no overflow', (tester) async {
        await pumpEditor(
          tester,
          logicalSize: Size(width, 1000),
          imageImporter: (s) => FakeImageImporter(store: s),
          overrides: [
            core.syncBadgeProvider.overrideWith(
              (ref) => Stream.value(
                // (v2.14-ui) 'done' is hidden: syncing keeps it shown.
                const core.SyncBadge(display: core.SyncDisplayState.inProgress),
              ),
            ),
          ],
          extensions: EditorExtensions(
            recordingPanel: TestRecordingPanelBuilder().builder,
            mathPen: FakeMathPen().slot,
            textPen: FakeTextPen().slot,
          ),
        );
        expect(tester.takeException(), isNull);
        final button = find.byKey(MenuHideButton.buttonKey).hitTestable();
        expect(button, shown ? findsOneWidget : findsNothing);
        if (shown) {
          // Right after [←].
          final back = tester.getRect(find.byKey(EditorToolbar.backKey));
          expect(tester.getRect(button).left, closeTo(back.right, 1));
        }
        await _openMore(tester);
        expect(find.byKey(EditorChrome.moreHideKey), findsOneWidget);
      });
    }

    testWidgets('the fullest unfolded row (zoom chip and sync badge on) '
        'does not overflow; [⌃] stays in ⋯ either way (UI stage 2: the page '
        'count takes its room in the row)', (tester) async {
      final h = await pumpEditor(
        tester,
        logicalSize: const Size(EditorToolbar.foldWidth, 1000),
        imageImporter: (s) => FakeImageImporter(store: s),
        overrides: [
          core.syncBadgeProvider.overrideWith(
            (ref) => Stream.value(
              const core.SyncBadge(display: core.SyncDisplayState.error),
            ),
          ),
        ],
        extensions: EditorExtensions(
          recordingPanel: TestRecordingPanelBuilder().builder,
          mathPen: FakeMathPen().slot,
          textPen: FakeTextPen().slot,
        ),
      );
      h.container.read(editorCommandsProvider).zoomIn();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      // (UI stage 2) The page button's '2 / 4' takes the room [⌃] had in
      // this fullest row: here [⌃] is in ⋯ only (never an overflow).
      expect(find.byKey(MenuHideButton.buttonKey), findsNothing);
      await _openMore(tester);
      expect(find.byKey(EditorChrome.moreHideKey), findsOneWidget);
    });
  });

  group('review fixes', () {
    testWidgets('menu hidden: a pen-anchored popup (pencil quick pen with no '
        'hover point) opens in the middle, visible and hit-testable', (
      tester,
    ) async {
      final h = await pumpEditor(tester);
      h.container.read(editorCommandsProvider).selectTool(EditorTool.pen);
      await _hideWithButton(tester);
      await _settleSnackBar(tester);
      h.container
          .read(editorActionRunnerProvider)
          .run(EditorAction.toolPalette, const GestureSource(Offset(100, 100)));
      await tester.pump();
      await tester.pump();
      expect(h.container.read(editorPopupProvider), isA<QuickPenPopup>());
      final panel = find.byKey(QuickPenPanel.panelKey);
      expect(panel, findsOneWidget);
      // Not a follower of the (missing) pen button: centred on screen.
      expect(
        find.ancestor(
          of: panel,
          matching: find.byType(CompositedTransformFollower),
        ),
        findsNothing,
      );
      final screen =
          Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
      final rect = _rect(tester, panel);
      expect(screen.contains(rect.center), isTrue);
      expect(rect.center.dx, closeTo(screen.center.dx, 1));
      // A tap on it reaches the panel, not the barrier.
      final panelBox = tester.renderObject(panel);
      final targets = tester
          .hitTestOnBinding(rect.center)
          .path
          .map((e) => e.target)
          .toList();
      expect(targets, contains(panelBox));
      expect(
        targets,
        isNot(contains(tester.renderObject(find.byKey(PopupHost.barrierKey)))),
      );
      // With the menu shown it hangs from the pen button again.
      h.container.read(editorPopupProvider.notifier).close();
      await tester.pump();
      await tester.tap(find.byKey(MenuRestorePill.showKey));
      await _slide(tester);
      h.container
          .read(editorActionRunnerProvider)
          .run(EditorAction.toolPalette, const GestureSource(Offset(100, 100)));
      await tester.pump();
      await tester.pump();
      expect(
        find.ancestor(
          of: find.byKey(QuickPenPanel.panelKey),
          matching: find.byType(CompositedTransformFollower),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a stored hidden menu on a note without pages: back leaves '
        'at once (no menu to bring back)', (tester) async {
      final h = await pumpEditor(
        tester,
        // A note whose page list comes back empty (6.17.1 guard).
        overrides: [
          core.notePagesProvider.overrideWith(
            (ref, id) => Stream.value(const <core.Page>[]),
          ),
        ],
        beforePump: (store, _, _) => store.settings.set(
          EditorSettingKeys.deviceState,
          const EditorDeviceState(toolbarHidden: true).toJson(),
        ),
      );
      expect(find.text(EditorStrings.noPages), findsOneWidget);
      await tester.binding.handlePopRoute();
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(h.closeCount, 1);
    });

    testWidgets('system back closes an open palette first (menu shown), '
        'then leaves', (tester) async {
      final h = await pumpEditor(tester);
      await _detach(tester);
      await tester.tap(_paletteButton);
      await tester.pump();
      expect(_panel, findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(_panel, findsNothing);
      expect(h.closeCount, 0);
      await tester.binding.handlePopRoute();
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(h.closeCount, 1);
    });

    testWidgets('menu hidden + palette open: back closes the palette, then '
        'shows the menu, then leaves', (tester) async {
      final h = await pumpEditor(tester);
      await _detach(tester);
      await _hideWithButton(tester);
      await _settleSnackBar(tester);
      await tester.tap(_paletteButton);
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(_panel, findsNothing);
      expect(_device(h).toolbarHidden, isTrue);
      await tester.binding.handlePopRoute();
      await _slide(tester);
      expect(_device(h).toolbarHidden, isFalse);
      expect(h.closeCount, 0);
    });

    testWidgets('the pill\'s four targets are at least 48 dp', (tester) async {
      await pumpEditor(tester);
      await _hideWithButton(tester);
      for (final key in const [
        UndoRedoButtons.pillUndoKey,
        MenuRestorePill.showKey,
        MenuRestorePill.searchKey,
        UndoRedoButtons.pillRedoKey,
      ]) {
        final size = tester.getSize(find.byKey(key));
        expect(size.width, greaterThanOrEqualTo(48), reason: '$key');
        expect(size.height, greaterThanOrEqualTo(48), reason: '$key');
      }
    });

    testWidgets("the palette's re-dock action is a labelled button", (
      tester,
    ) async {
      final h = await pumpEditor(tester);
      await _detach(tester);
      await tester.tap(_paletteButton);
      await tester.pump();
      final dock = find.byKey(PenPalette.dockKey);
      expect(
        find.descendant(
          of: dock,
          matching: find.text(EditorStrings.dockPalette),
        ),
        findsOneWidget,
      );
      expect(
        _rect(tester, _panel).contains(_rect(tester, dock).center),
        isTrue,
      );
      await tester.tap(dock);
      await tester.pump();
      expect(_device(h).paletteDetached, isFalse);
      expect(find.byKey(PresetBarView.barKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'the palette button starts at the bottom-left (off the '
      'writing start and the page indicator) and stays put on screen when the menu hides / shows',
      (tester) async {
        await pumpEditor(tester);
        await _detach(tester);
        final area = _rect(tester, find.byType(EditorFloatingLayer));
        final at = _rect(tester, _paletteButton);
        expect(at.left, closeTo(area.left + PenPalette.margin, 0.5));
        expect(at.bottom, closeTo(area.bottom - PenPalette.margin, 0.5));
        await _hideWithButton(tester);
        expect(_rect(tester, _paletteButton), at);
        await _settleSnackBar(tester);
        await tester.tap(find.byKey(MenuRestorePill.showKey));
        await _slide(tester);
        expect(_rect(tester, _paletteButton), at);
      },
    );
  });
}
