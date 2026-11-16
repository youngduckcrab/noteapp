// (v2.16-ui, 04-editor 24) The layout shells per editor style: 크래프트's
// docked toolbar, 미니멀's floating pill, 스튜디오's slim bar + left rail —
// present, never overflowing at the width matrix, popups placed by them,
// hide / restore, the viewport's top inset under the pill.
import 'package:feature_editor/src/state/settings/editor_device_state.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/ui/chrome/editor_chrome.dart';
import 'package:feature_editor/src/ui/chrome/editor_layout.dart';
import 'package:feature_editor/src/ui/chrome/floating_layer.dart';
import 'package:feature_editor/src/ui/chrome/pen_palette.dart';
import 'package:feature_editor/src/ui/color/basic_colors_row.dart';
import 'package:feature_editor/src/ui/eraser/eraser_popup.dart';
import 'package:feature_editor/src/ui/pen/pen_settings_popup.dart';
import 'package:feature_editor/src/ui/pen/pen_tray.dart';
import 'package:feature_editor/src/ui/pen/quick_pen_popup.dart';
import 'package:feature_editor/src/ui/shape/shape_style_controls.dart';
import 'package:feature_editor/src/ui/toolbar/editor_rail.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import '../helpers/fake_image_importer.dart';
import '../helpers/pump_editor.dart';

Future<EditorTestHandles> _pump(
  WidgetTester tester,
  AppStyle style,
  Size size, {
  Brightness brightness = Brightness.light,
}) => pumpEditor(
  tester,
  logicalSize: size,
  pages: 3,
  imageImporter: (s) => FakeImageImporter(store: s),
  theme: buildStyleTheme(style, brightness),
);

const _matrix = [
  Size(1280, 800), // landscape tablet
  Size(800, 1280), // portrait tablet
  Size(1032, 1376), // the default test tablet
  Size(600, 960), // phone-ish
  Size(420, 900), // narrow split screen
];

Finder get _pill => find.byKey(EditorToolbar.pillKey);
Finder get _rail => find.byKey(EditorRail.railKey);
Finder get _slim => find.byKey(EditorToolbar.slimKey);
Finder get _restore => find.byKey(MenuRestorePill.pillKey);

Finder _traySlots() => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith('editor.tray.pen.'),
);

void main() {
  test('resolve: 크래프트 top bar, 미니멀 floating, 스튜디오 rail from 600', () {
    const wide = Size(1280, 800);
    expect(EditorLayouts.resolve(AppStyle.craft, wide), EditorLayout.topBar);
    expect(EditorLayouts.resolve(null, wide), EditorLayout.topBar);
    expect(
      EditorLayouts.resolve(AppStyle.calm, const Size(400, 800)),
      EditorLayout.floatingBar,
    );
    expect(EditorLayouts.resolve(AppStyle.studio, wide), EditorLayout.rail);
    expect(
      EditorLayouts.resolve(AppStyle.studio, const Size(600, 900)),
      EditorLayout.rail,
    );
    expect(
      EditorLayouts.resolve(AppStyle.studio, const Size(599, 900)),
      EditorLayout.topBar,
    );
  });

  test('rail capacity follows the height', () {
    expect(EditorRail.capacityFor(1228), 8);
    expect(EditorRail.capacityFor(748), 5);
    expect(EditorRail.capacityFor(700), 4);
    expect(EditorRail.capacityFor(500), 3);
  });

  for (final style in AppStyle.values) {
    for (final size in _matrix) {
      testWidgets('${style.wireName} at ${size.width}×${size.height}: its '
          'shell, no overflow', (tester) async {
        await _pump(tester, style, size);
        expect(tester.takeException(), isNull);
        switch (EditorLayouts.resolve(style, size)) {
          case EditorLayout.topBar:
            expect(find.byKey(EditorTopMenu.menuKey), findsOneWidget);
            expect(_pill, findsNothing);
            expect(_rail, findsNothing);
          case EditorLayout.floatingBar:
            expect(_pill, findsOneWidget);
            expect(_rail, findsNothing);
            final pill = tester.getRect(_pill);
            // Floating: inside the screen with a margin, page visible
            // around it.
            expect(pill.left, greaterThanOrEqualTo(12));
            expect(pill.right, lessThanOrEqualTo(size.width - 12));
            expect(pill.top, greaterThan(0));
            if (size.width >= 1200) {
              expect(pill.width, lessThan(size.width - 100));
            }
          case EditorLayout.rail:
            expect(_rail, findsOneWidget);
            expect(_slim, findsOneWidget);
            expect(tester.getSize(_rail).width, EditorRail.width);
            // The tray stands in the rail, the tools too.
            expect(
              tester.getRect(find.byKey(EditorToolbar.penKey)).right,
              lessThanOrEqualTo(EditorRail.width),
            );
            expect(
              tester.getRect(find.byKey(EditorToolbar.textKey)).right,
              lessThanOrEqualTo(EditorRail.width),
            );
        }
        // The pen, eraser and lasso keep their keys in every shell.
        expect(find.byKey(EditorToolbar.penKey), findsOneWidget);
        expect(find.byKey(EditorToolbar.eraserKey), findsOneWidget);
        expect(find.byKey(EditorToolbar.lassoKey), findsOneWidget);
      });
    }
  }

  testWidgets('미니멀: the pages start under the pill (topInset)', (tester) async {
    final h = await _pump(tester, AppStyle.calm, const Size(800, 1280));
    final pill = tester.getRect(_pill);
    final zone =
        EditorFloatingLayer.barTop +
        EditorToolbar.heightOf(tester.element(_pill)) +
        8;
    expect(h.viewport.topInset, zone);
    expect(pill.bottom, lessThanOrEqualTo(zone + 0.5));
    // The first page's top is on screen below the pill.
    final camera = h.viewport.camera;
    final top = camera.docToScreen(h.viewport.layout.rectOf(0).topLeft).dy;
    expect(top, greaterThan(pill.bottom - 52)); // in page-area coordinates
    expect(top, greaterThanOrEqualTo(zone - 0.5));
  });

  testWidgets('미니멀: the picker hangs under the pill', (tester) async {
    await _pump(tester, AppStyle.calm, const Size(1280, 800));
    await tester.tap(find.byKey(EditorToolbar.penKey));
    await tester.pumpAndSettle();
    final panel = find.byKey(PenSettingsPanel.panelKey);
    expect(panel, findsOneWidget);
    expect(
      tester.getRect(panel).top,
      greaterThanOrEqualTo(tester.getRect(_pill).bottom),
    );
  });

  testWidgets('스튜디오: the picker, quick pen, eraser and shape popups open '
      'to the right of the rail', (tester) async {
    await _pump(tester, AppStyle.studio, const Size(1280, 800));
    final rail = tester.getRect(_rail);

    await tester.tap(find.byKey(EditorToolbar.penKey));
    await tester.pumpAndSettle();
    final picker = tester.getRect(find.byKey(PenSettingsPanel.panelKey));
    expect(picker.left, greaterThanOrEqualTo(rail.right));
    expect(picker.bottom, lessThanOrEqualTo(800));
    await tester.tapAt(const Offset(1200, 700));
    await tester.pumpAndSettle();

    await tester.longPress(_traySlots().at(1));
    await tester.pumpAndSettle();
    final quick = find.byKey(QuickPenPanel.panelKey);
    expect(quick, findsOneWidget);
    expect(tester.getRect(quick).left, greaterThanOrEqualTo(rail.right));
    await tester.tapAt(const Offset(1200, 700));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(EditorToolbar.eraserKey));
    await tester.pumpAndSettle();
    final eraser = find.byKey(EraserSettingsPanel.panelKey);
    expect(eraser, findsOneWidget);
    expect(tester.getRect(eraser).left, greaterThanOrEqualTo(rail.right));
    await tester.tapAt(const Offset(1200, 700));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(EditorToolbar.shapeKey));
    await tester.pumpAndSettle();
    final shape = find.byKey(ShapeToolPanel.panelKey);
    expect(shape, findsOneWidget);
    final rect = tester.getRect(shape);
    expect(rect.left, greaterThanOrEqualTo(rail.right));
    expect(rect.bottom, lessThanOrEqualTo(800));
  });

  testWidgets('스튜디오: the rail colours and widths set the current pen', (
    tester,
  ) async {
    final h = await _pump(tester, AppStyle.studio, const Size(1280, 800));
    await tester.tap(find.byKey(EditorRail.colorKey(3)));
    await tester.pump();
    final pen = h.container.read(editorToolProvider).currentPen;
    expect(pen.colorArgb & 0xFFFFFF, kBasicColors[6] & 0xFFFFFF);
    await tester.tap(find.byKey(EditorRail.widthKey(2)));
    await tester.pump();
    final wide = h.container.read(editorToolProvider).currentPen.width;
    await tester.tap(find.byKey(EditorRail.widthKey(0)));
    await tester.pump();
    final thin = h.container.read(editorToolProvider).currentPen.width;
    expect(thin, lessThan(wide));
  });

  for (final style in [AppStyle.calm, AppStyle.studio]) {
    testWidgets('${style.wireName}: 집중 모드 hides the shell, the restore '
        'pill and system back bring it back', (tester) async {
      final h = await _pump(tester, style, const Size(1280, 800));
      h.container
          .read(editorDeviceStateProvider.notifier)
          .setToolbarHidden(true);
      await tester.pumpAndSettle();
      expect(_pill, findsNothing);
      expect(_rail, findsNothing);
      expect(_slim, findsNothing);
      expect(_restore, findsOneWidget);
      await tester.tap(find.byKey(MenuRestorePill.showKey));
      await tester.pumpAndSettle();
      expect(_restore, findsNothing);
      expect(style == AppStyle.calm ? _pill : _rail, findsOneWidget);

      h.container
          .read(editorDeviceStateProvider.notifier)
          .setToolbarHidden(true);
      await tester.pumpAndSettle();
      // System back (EditorChrome.handleBack): the shell comes back, the
      // note stays.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(style == AppStyle.calm ? _pill : _rail, findsOneWidget);
    });
  }

  testWidgets('스튜디오: with the palette detached the rail keeps the tools; '
      'the palette tray opens its popups under itself', (tester) async {
    final h = await _pump(tester, AppStyle.studio, const Size(1280, 800));
    h.container
        .read(editorDeviceStateProvider.notifier)
        .setPaletteDetached(true);
    await tester.pumpAndSettle();
    expect(find.byKey(PenTray.trayKey), findsNothing);
    expect(find.byKey(EditorToolbar.lassoKey), findsOneWidget);
    expect(find.byKey(PenPalette.buttonKey), findsOneWidget);
    await tester.tap(find.byKey(PenPalette.buttonKey));
    await tester.pumpAndSettle();
    expect(find.byKey(PenTray.trayKey), findsOneWidget);
    await tester.tap(find.byKey(EditorToolbar.penKey));
    await tester.pumpAndSettle();
    final tray = tester.getRect(find.byKey(PenTray.trayKey));
    final picker = tester.getRect(find.byKey(PenSettingsPanel.panelKey));
    // Horizontal tray: under (or over) it, not beside.
    expect(picker.top >= tray.bottom || picker.bottom <= tray.top, isTrue);
  });

  testWidgets('dark styles build their shells too', (tester) async {
    for (final style in [AppStyle.calm, AppStyle.studio]) {
      await _pump(
        tester,
        style,
        const Size(1280, 800),
        brightness: Brightness.dark,
      );
      expect(tester.takeException(), isNull);
    }
  });
}
