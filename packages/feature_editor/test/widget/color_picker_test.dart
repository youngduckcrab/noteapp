// E-14: the colour part of the pen settings panel (04-editor 6.9.3 #4–#6,
// 6.9.5) and the stroke eyedropper (6.6.8): wheel and square drags, HEX and
// R/G/B input with reverting, recent colours, the palette (add, delete, 40
// limit) stored in editor.colors (synced), and the eyedropper flow
// (controller.hitTest → the CORE stroke colour), its banner and cancelling.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/color_palette.dart';
import 'package:feature_editor/src/state/popup.dart';
import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:feature_editor/src/tools/eyedropper_interaction.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/ui/color/color_math.dart';
import 'package:feature_editor/src/ui/color/color_picker_panel.dart';
import 'package:feature_editor/src/ui/color/hex_rgb_fields.dart';
import 'package:feature_editor/src/ui/color/hsv_wheel.dart';
import 'package:feature_editor/src/ui/color/recent_colors_row.dart';
import 'package:feature_editor/src/ui/color/user_palette_grid.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/overlays/eyedropper_banner.dart';
import 'package:feature_editor/src/ui/pen/pen_settings_popup.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

/// A red stroke in the upper part of page 0 (no overlap with strokeA / B).
final core.Stroke _redStroke = () {
  final s = lineStroke(id: 'stroke-red', x0: 300, y0: 220, x1: 460, y1: 220);
  return s.copyWith(style: s.style.copyWith(colorArgb: 0xFFCC2200));
}();

core.StrokeStyle _pen(EditorTestHandles h) =>
    h.container.read(editorToolProvider).currentPen;

ColorPaletteState _palette(EditorTestHandles h) =>
    h.container.read(editorColorPaletteProvider);

/// Opens the pen picker; (v2.15-ui) with [otherColor] also '다른 색…' (the
/// wheel, HEX / RGB and 내 팔레트 are there now).
Future<void> _openPenSettings(
  WidgetTester tester, {
  bool otherColor = true,
}) async {
  await tester.tap(find.byKey(EditorToolbar.penKey)); // the active pen
  await tester.pump();
  expect(find.byKey(PenSettingsPanel.panelKey), findsOneWidget);
  if (otherColor) {
    await tester.tap(find.byKey(PenSettingsPanel.otherColorKey));
    await tester.pump();
  }
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
}

/// Lets the snack bar (4 s) and its animations finish.
Future<void> _settleSnackBar(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  testWidgets('wheel: the value slider sets the value, a drag on the wheel '
      'sets hue (clockwise from +x) and saturation (distance / radius)', (
    tester,
  ) async {
    final h = await pumpEditor(tester);
    await _openPenSettings(tester);
    await _scrollTo(tester, find.byKey(ColorPickerPanel.wheelKey));
    // Default ballpoint 0xFF1A1A1A: grey, value ≈ 0.1.
    final slider = tester.getRect(find.byKey(ColorPickerPanel.valueSliderKey));
    await tester.tapAt(slider.centerRight - const Offset(2, 0));
    await tester.pump();
    expect(_pen(h).colorArgb, 0xFFFFFFFF); // saturation 0, value 1

    final wheel = tester.getRect(find.byKey(ColorPickerPanel.wheelKey));
    expect(wheel.size, const Size.square(HsvWheel.defaultDiameter));
    final r = wheel.width / 2;
    final g = await tester.startGesture(wheel.center);
    await g.moveTo(wheel.center + Offset(0, r / 2)); // straight down: 90°
    await tester.pump();
    expect(
      _pen(h).colorArgb,
      ColorMath.fromHsv(HSVColor.fromAHSV(1, 90, 0.5, 1)),
    );
    await g.moveTo(wheel.center + Offset(-r * 2, 0)); // outside, left: 180°
    await g.up();
    await tester.pump();
    expect(
      _pen(h).colorArgb,
      ColorMath.fromHsv(HSVColor.fromAHSV(1, 180, 1, 1)), // cut at 1
    );
    final painted = tester.widget<HsvWheel>(
      find.byKey(ColorPickerPanel.wheelKey),
    );
    expect(painted.hsv.hue, closeTo(180, 1e-9));
    expect(painted.hsv.saturation, 1);

    // The value slider in the middle keeps hue and saturation.
    await tester.tapAt(slider.center);
    await tester.pump();
    final hsv = ColorMath.toHsv(_pen(h).colorArgb);
    expect(hsv.hue, closeTo(180, 1));
    expect(hsv.saturation, closeTo(1, 0.01));
    expect(hsv.value, closeTo(0.5, 0.01));
  });

  testWidgets('the panel scrolls, but a drag on the wheel changes the colour '
      'and does not scroll it', (tester) async {
    final h = await pumpEditor(tester);
    await _openPenSettings(tester);
    final wheel = find.byKey(ColorPickerPanel.wheelKey);
    await _scrollTo(tester, wheel);
    final before = tester.getRect(wheel);
    final g = await tester.startGesture(before.center + const Offset(0, 80));
    for (var i = 1; i <= 5; i++) {
      await g.moveTo(before.center + Offset(0, 80 - i * 20.0));
      await tester.pump();
    }
    await g.up();
    await tester.pump();
    expect(tester.getRect(wheel), before);
    final hsv = tester.widget<HsvWheel>(wheel).hsv;
    expect(hsv.hue, closeTo(270, 1e-9)); // straight up
    expect(hsv.saturation, closeTo(20 / 110, 1e-9));
    expect(_pen(h).colorArgb, ColorMath.fromHsv(hsv));
  });

  testWidgets('square: x = saturation, y = value; the hue slider sets the '
      'hue', (tester) async {
    final h = await pumpEditor(tester);
    await _openPenSettings(tester);
    await _scrollTo(tester, find.byKey(ColorPickerPanel.squareSegmentKey));
    await tester.tap(find.byKey(ColorPickerPanel.squareSegmentKey));
    await tester.pump();
    expect(find.byKey(ColorPickerPanel.wheelKey), findsNothing);
    await _scrollTo(tester, find.byKey(ColorPickerPanel.squareKey));
    final square = tester.getRect(find.byKey(ColorPickerPanel.squareKey));
    expect(square.size, const Size(220, 180));
    final g = await tester.startGesture(square.topLeft + const Offset(1, 1));
    await g.moveTo(
      square.topLeft + Offset(square.width * 0.25, square.height * 0.25),
    );
    await g.up();
    await tester.pump();
    // Default grey has hue 0.
    expect(
      _pen(h).colorArgb,
      ColorMath.fromHsv(HSVColor.fromAHSV(1, 0, 0.25, 0.75)),
    );

    final hue = tester.getRect(find.byKey(ColorPickerPanel.hueSliderKey));
    await tester.tapAt(hue.center);
    await tester.pump();
    expect(
      _pen(h).colorArgb,
      ColorMath.fromHsv(HSVColor.fromAHSV(1, 180, 0.25, 0.75)),
    );
  });

  testWidgets('a colour from elsewhere is picked up; saturation 0 keeps the '
      'picker hue', (tester) async {
    final h = await pumpEditor(tester);
    await _openPenSettings(tester);
    final tools = h.container.read(editorToolProvider.notifier);
    tools.setColor(ColorMath.fromHsv(HSVColor.fromAHSV(1, 120, 0.8, 0.9)));
    await tester.pump();
    HSVColor shown() =>
        tester.widget<HsvWheel>(find.byKey(ColorPickerPanel.wheelKey)).hsv;
    expect(shown().hue, closeTo(120, 1));
    expect(shown().saturation, closeTo(0.8, 0.01));

    tools.setColor(0xFF808080); // grey: no hue of its own
    await tester.pump();
    expect(shown().hue, closeTo(120, 1));
    expect(shown().saturation, 0);
    tools.setColor(0xFF000000); // black
    await tester.pump();
    expect(shown().hue, closeTo(120, 1));
    expect(shown().value, 0);
  });

  testWidgets('HEX: applied as soon as it is valid, reverted on submit or '
      'focus loss when not; 8 digits set the opacity (≥ 5%)', (tester) async {
    final h = await pumpEditor(tester);
    await _openPenSettings(tester);
    final hex = find.byKey(HexRgbFields.hexKey);
    await _scrollTo(tester, hex);
    String text(Finder f) => tester.widget<TextField>(f).controller!.text;
    expect(text(hex), '#1A1A1A');

    await tester.enterText(hex, '#3366cc');
    await tester.pump();
    expect(_pen(h).colorArgb, 0xFF3366CC);
    expect(text(hex), '#3366cc'); // the typed text stays while it is valid
    expect(text(find.byKey(HexRgbFields.redKey)), '51');
    expect(text(find.byKey(HexRgbFields.greenKey)), '102');
    expect(text(find.byKey(HexRgbFields.blueKey)), '204');

    await tester.enterText(hex, '#12');
    await tester.pump();
    expect(_pen(h).colorArgb, 0xFF3366CC); // invalid: nothing applied
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(text(hex), '#3366CC');

    await tester.enterText(hex, 'zz#80ff00');
    await tester.pump();
    expect(text(hex), '#80ff00'); // only HEX characters are taken
    expect(_pen(h).colorArgb, 0xFF80FF00);

    await tester.enterText(hex, '#80FF0000');
    await tester.pump();
    expect(_pen(h).colorArgb, 0xFFFF0000); // the colour is stored opaque
    expect(_pen(h).opacity, 0.5); // 0x80 / 255, rounded to 0.01
    await tester.enterText(hex, '#00FF0000');
    await tester.pump();
    expect(_pen(h).opacity, 0.05);

    await tester.enterText(hex, '#ABCD');
    await tester.pump();
    await tester.tap(find.byKey(HexRgbFields.greenKey)); // focus moves
    await tester.pump();
    expect(text(hex), '#FF0000');
    expect(_pen(h).colorArgb, 0xFFFF0000);
  });

  testWidgets('R/G/B: digits only, 0..255 applied at once, otherwise '
      'reverted', (tester) async {
    final h = await pumpEditor(tester);
    await _openPenSettings(tester);
    final red = find.byKey(HexRgbFields.redKey);
    await _scrollTo(tester, red);
    String text(Finder f) => tester.widget<TextField>(f).controller!.text;

    await tester.enterText(red, '200');
    await tester.pump();
    expect(_pen(h).colorArgb, 0xFFC81A1A);
    expect(text(find.byKey(HexRgbFields.hexKey)), '#C81A1A');

    await tester.enterText(red, '1a2');
    await tester.pump();
    expect(text(red), '12'); // letters are dropped
    expect(_pen(h).colorArgb, 0xFF0C1A1A);

    await tester.enterText(red, '300');
    await tester.pump();
    expect(_pen(h).colorArgb, 0xFF0C1A1A); // out of range: not applied
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(text(red), '12');

    final blue = find.byKey(HexRgbFields.blueKey);
    await tester.enterText(blue, '');
    await tester.pump();
    await tester.tap(red); // focus moves away
    await tester.pump();
    expect(text(blue), '26');
    expect(_pen(h).colorArgb, 0xFF0C1A1A);
  });

  testWidgets('recent colours: newest first, a tap sets the pen colour; a '
      'committed stroke puts its colour in front', (tester) async {
    final h = await pumpEditor(tester);
    final palette = h.container.read(editorColorPaletteProvider.notifier);
    palette.pushRecent(0xFF00AA00);
    palette.pushRecent(0xFF0000AA);
    await _openPenSettings(tester, otherColor: false);
    await _scrollTo(tester, find.byKey(RecentColorsRow.swatchKey(1)));
    expect(find.byKey(RecentColorsRow.swatchKey(2)), findsNothing);
    expect(find.bySemanticsLabel('#0000AA'), findsOneWidget);

    await tester.tap(find.byKey(RecentColorsRow.swatchKey(1)));
    await tester.pump();
    expect(_pen(h).colorArgb, 0xFF00AA00);
    expect(_palette(h).recent, [0xFF0000AA, 0xFF00AA00]); // tapping keeps order

    // Close the popup (barrier) and draw: the stroke's colour moves to the
    // front.
    await tester.tapAt(const Offset(100, 1300));
    await tester.pump();
    expect(h.container.read(editorPopupProvider), isNull);
    await h.driver.stylusStroke(
      pathThrough(h, 0, const [Offset(100, 300), Offset(200, 320)]),
    );
    await tester.pump();
    expect(_palette(h).recent, [0xFF00AA00, 0xFF0000AA]);
  });

  testWidgets('palette: [+] adds the current colour (no duplicate), a long '
      'press offers 삭제, 40 colours disable [+]; stored in editor.colors '
      '(synced) after 1000 ms', (tester) async {
    final h = await pumpEditor(tester);
    await _openPenSettings(tester);
    final add = find.byKey(UserPaletteGrid.addKey);
    await _scrollTo(tester, add);
    await tester.tap(add);
    await tester.pump();
    expect(_palette(h).palette, [0xFF1A1A1A]);
    await tester.tap(add); // duplicate: not added
    await tester.pump();
    expect(_palette(h).palette, [0xFF1A1A1A]);
    expect(find.byKey(UserPaletteGrid.swatchKey(0)), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1000));
    final stored = await h.store.settings.get(EditorSettingKeys.colors);
    expect(EditorSettingKeys.colors.scope, core.SettingScope.synced);
    expect(stored['palette'], [0xFF1A1A1A]);

    // A palette colour sets the pen colour.
    h.container.read(editorToolProvider.notifier).setColor(0xFF123456);
    await tester.pump();
    await tester.tap(find.byKey(UserPaletteGrid.swatchKey(0)));
    await tester.pump();
    expect(_pen(h).colorArgb, 0xFF1A1A1A);

    // Fill to 40.
    final notifier = h.container.read(editorColorPaletteProvider.notifier);
    for (var i = 1; i < ColorPaletteState.maxPalette; i++) {
      expect(notifier.addToPalette(0xFF000000 + i), isTrue);
    }
    expect(notifier.addToPalette(0xFF00FF00), isFalse); // full
    await tester.pump();
    await _scrollTo(tester, add);
    expect(tester.widget<IconButton>(add).onPressed, isNull);

    // Long press → 삭제.
    final first = find.byKey(UserPaletteGrid.swatchKey(0));
    await _scrollTo(tester, first);
    await tester.longPress(first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(UserPaletteGrid.deleteKey));
    await tester.pumpAndSettle();
    expect(_palette(h).palette, hasLength(ColorPaletteState.maxPalette - 1));
    expect(_palette(h).palette.first, 0xFF000001);
    expect(tester.widget<IconButton>(add).onPressed, isNotNull);
    // Still open: the menu's own barrier took the taps.
    expect(find.byKey(PenSettingsPanel.panelKey), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1000));
    final again = await h.store.settings.get(EditorSettingKeys.colors);
    expect(again['palette'], hasLength(ColorPaletteState.maxPalette - 1));
  });

  group('eyedropper', () {
    testWidgets('[스포이드] closes the popup and shows the banner; a stylus '
        'tap on a stroke takes its CORE colour (opacity kept)', (tester) async {
      final h = await pumpEditor(
        tester,
        strokesByPageIndex: {
          0: [strokeA, _redStroke],
        },
      );
      h.container.read(editorToolProvider.notifier).setOpacity(0.6);
      await _openPenSettings(tester);
      final button = find.byKey(ColorPickerPanel.eyedropperKey);
      await _scrollTo(tester, button);
      await tester.tap(button);
      await tester.pump();
      expect(h.container.read(editorPopupProvider), isNull);
      expect(h.container.read(editorToolProvider).eyedropperActive, isTrue);
      expect(find.byKey(EyedropperBanner.bannerKey), findsOneWidget);
      expect(find.text(EditorStrings.eyedropperBanner), findsOneWidget);

      final before = h.session.history.undoDepth;
      final at = h.toGlobal(0, const Offset(380, 222)); // 2 pt off the line
      await h.driver.stylusStroke([at]);
      await tester.pump();
      expect(
        h.container.read(editorInteractionHostProvider).lastStarted,
        isA<EyedropperInteraction>(),
      );
      expect(_pen(h).colorArgb, 0xFFCC2200);
      expect(_pen(h).opacity, 0.6);
      expect(h.container.read(editorToolProvider).eyedropperActive, isFalse);
      expect(find.byKey(EyedropperBanner.bannerKey), findsNothing);
      expect(find.text(EditorStrings.eyedropperPicked), findsOneWidget);
      // No CORE command, nothing drawn.
      expect(h.session.history.undoDepth, before);
      expect(h.session.pageIfLoaded(h.pageId(0))!.strokes, hasLength(2));
      await _settleSnackBar(tester);
    });

    testWidgets('a tap away from strokes → 여기엔 획이 없어요, colour kept, '
        'mode ends', (tester) async {
      final h = await pumpEditor(
        tester,
        strokesByPageIndex: {
          0: [_redStroke],
        },
      );
      h.container.read(editorCommandsProvider).startEyedropper();
      await tester.pump();
      await h.driver.stylusStroke([h.toGlobal(0, const Offset(380, 600))]);
      await tester.pump();
      expect(_pen(h).colorArgb, 0xFF1A1A1A);
      expect(find.text(EditorStrings.eyedropperMissed), findsOneWidget);
      expect(h.container.read(editorToolProvider).eyedropperActive, isFalse);
      await _settleSnackBar(tester);
    });

    testWidgets('the tolerance is 6 screen px at any zoom', (tester) async {
      final h = await pumpEditor(
        tester,
        strokesByPageIndex: {
          0: [_redStroke],
        },
      );
      final scale = h.viewport.camera.scale;
      // The red line's CORE bounds reach width / 2 below y = 220 (B3 hit
      // test = bounds inflated by the tolerance).
      final bottom = _redStroke.bounds.bottom;
      final commands = h.container.read(editorCommandsProvider);
      commands.startEyedropper();
      await tester.pump();
      await h.driver.stylusStroke([
        h.toGlobal(0, Offset(380, bottom + 5 / scale)),
      ]);
      await tester.pump();
      expect(_pen(h).colorArgb, 0xFFCC2200); // 5 px away: taken
      await _settleSnackBar(tester);

      h.container.read(editorToolProvider.notifier).setColor(0xFF1A1A1A);
      commands.startEyedropper();
      await tester.pump();
      await h.driver.stylusStroke([
        h.toGlobal(0, Offset(380, bottom + 7 / scale)),
      ]);
      await tester.pump();
      expect(_pen(h).colorArgb, 0xFF1A1A1A); // 7 px away: missed
      await _settleSnackBar(tester);
    });

    testWidgets('a finger picks in pen-only mode (R30) and on a read-only '
        'note', (tester) async {
      final h = await pumpEditor(
        tester,
        settings: const EditorSettings(inputMode: InputMode.penOnly),
        strokesByPageIndex: {
          0: [_redStroke],
        },
      );
      await h.store.library.trashItems([core.NoteRef(h.noteId)]);
      await tester.pump();
      expect(h.container.read(editorReadOnlyProvider), isTrue);
      h.container.read(editorCommandsProvider).startEyedropper();
      await tester.pump();
      final at = h.toGlobal(0, const Offset(380, 220));
      await h.driver.down(11, at);
      await h.driver.wait(const Duration(milliseconds: 30));
      await h.driver.up(11);
      await tester.pump();
      expect(_pen(h).colorArgb, 0xFFCC2200);
      expect(h.container.read(editorToolProvider).eyedropperActive, isFalse);
      await _settleSnackBar(tester);
    });

    testWidgets('a mouse click picks too', (tester) async {
      final h = await pumpEditor(
        tester,
        strokesByPageIndex: {
          0: [_redStroke],
        },
      );
      h.container.read(editorCommandsProvider).startEyedropper();
      await tester.pump();
      await h.driver.down(
        7,
        h.toGlobal(0, const Offset(380, 220)),
        kind: PointerDeviceKind.mouse,
      );
      await h.driver.up(7);
      await tester.pump();
      expect(_pen(h).colorArgb, 0xFFCC2200);
      await _settleSnackBar(tester);
    });

    testWidgets('[취소] on the banner and Esc end the mode without picking; no '
        'hover cursor meanwhile', (tester) async {
      final h = await pumpEditor(
        tester,
        strokesByPageIndex: {
          0: [_redStroke],
        },
      );
      final commands = h.container.read(editorCommandsProvider);
      commands.startEyedropper();
      await tester.pump();
      await h.driver.hover(h.toGlobal(0, const Offset(380, 300)));
      await tester.pump();
      expect(
        h.container.read(editorInteractionHostProvider).cursor.value,
        isNull,
      );
      await tester.tap(find.byKey(EyedropperBanner.cancelKey));
      await tester.pump();
      expect(h.container.read(editorToolProvider).eyedropperActive, isFalse);
      expect(find.byKey(EyedropperBanner.bannerKey), findsNothing);

      commands.startEyedropper();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(h.container.read(editorToolProvider).eyedropperActive, isFalse);

      // Pen again: a stroke is drawn, the colour is unchanged.
      final before = h.session.history.undoDepth;
      await h.driver.stylusStroke(
        pathThrough(h, 0, const [Offset(100, 500), Offset(200, 520)]),
      );
      await tester.pump();
      expect(h.session.history.undoDepth, before + 1);
      expect(_pen(h).colorArgb, 0xFF1A1A1A);
      expect(
        h.container.read(editorInteractionHostProvider).lastStarted,
        isNot(isA<EyedropperInteraction>()),
      );
    });

    testWidgets('choosing a tool ends the mode', (tester) async {
      final h = await pumpEditor(tester);
      h.container.read(editorCommandsProvider).startEyedropper();
      await tester.pump();
      await tester.tap(find.byKey(EditorToolbar.eraserKey));
      await tester.pump();
      expect(h.container.read(editorToolProvider).eyedropperActive, isFalse);
      expect(find.byKey(EyedropperBanner.bannerKey), findsNothing);
    });
  });
}
