// (v2.16-ui, 04-editor 24) The layout shells per editor style: 크래프트's
// docked toolbar, 미니멀's floating pill, 스튜디오's slim bar + left rail —
// present, never overflowing at the width matrix, popups placed by them,
// hide / restore, the viewport's top inset under the pill.
import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/panel.dart';
import 'package:feature_editor/src/state/settings/editor_device_state.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/chrome/editor_chrome.dart';
import 'package:feature_editor/src/ui/chrome/editor_layout.dart';
import 'package:feature_editor/src/ui/chrome/floating_layer.dart';
import 'package:feature_editor/src/ui/chrome/pen_palette.dart';
import 'package:feature_editor/src/ui/color/basic_colors_row.dart';
import 'package:feature_editor/src/ui/eraser/eraser_popup.dart';
import 'package:feature_editor/src/ui/overlays/context_menu.dart';
import 'package:feature_editor/src/ui/overlays/selection_menu.dart';
import 'package:feature_editor/src/ui/pen/pen_settings_popup.dart';
import 'package:feature_editor/src/ui/pen/pen_tray.dart';
import 'package:feature_editor/src/ui/pen/quick_pen_popup.dart';
import 'package:feature_editor/src/ui/shape/shape_style_controls.dart';
import 'package:feature_editor/src/ui/text/text_style_controls.dart';
import 'package:feature_editor/src/ui/toolbar/editor_rail.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:feature_editor/src/ui/toolbar/insert_menu.dart';
import 'package:feature_editor/src/ui/toolbar/mic_button.dart';
import 'package:feature_editor/src/viewport/viewport_camera.dart';
import 'package:feature_editor/src/viewport/viewport_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:ui_kit/ui_kit.dart';

import '../helpers/fake_extensions.dart';
import '../helpers/fake_image_importer.dart';
import '../helpers/fake_math_pen.dart';
import '../helpers/fake_text_pen.dart';
import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

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
  Size(1280, 600), // short landscape (split screen, keyboard)
  Size(960, 540), // phone landscape
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
    // A real landscape tablet less its status bar keeps 5 pens.
    expect(EditorRail.capacityFor(724), 5);
    expect(EditorRail.capacityFor(660), 4);
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
    final top = h.viewportToGlobal(h.viewport.pageRectOnScreen(0).topLeft).dy;
    expect(top, greaterThanOrEqualTo(pill.bottom));
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
      expect(find.byType(EditorScreen), findsOneWidget);
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

  // ---- review fixes ----

  testWidgets('스튜디오: the picker open across a resize below 600 and back '
      'never overflows and stays placed', (tester) async {
    await _pump(tester, AppStyle.studio, const Size(1280, 800));
    await tester.tap(find.byKey(EditorToolbar.penKey));
    await tester.pumpAndSettle();
    final panel = find.byKey(PenSettingsPanel.panelKey);
    expect(panel, findsOneWidget);
    for (final size in const [
      Size(560, 800),
      Size(1280, 800),
      Size(620, 800),
      Size(1280, 800),
    ]) {
      tester.view.physicalSize = size * tester.view.devicePixelRatio;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size');
      if (panel.evaluate().isEmpty) continue;
      final rect = tester.getRect(panel);
      expect(rect.left, greaterThanOrEqualTo(0), reason: '$size');
      expect(rect.right, lessThanOrEqualTo(size.width), reason: '$size');
      if (EditorLayouts.resolve(AppStyle.studio, size) == EditorLayout.rail &&
          size.width >= 1000) {
        expect(rect.left, greaterThanOrEqualTo(EditorRail.width));
      }
    }
  });

  testWidgets('스튜디오 ↔ 미니멀 ↔ 크래프트 at run time: the shell follows, '
      'the page stays visible', (tester) async {
    final theme = ValueNotifier(
      buildStyleTheme(AppStyle.studio, Brightness.light),
    );
    addTearDown(theme.dispose);
    final h = await pumpEditor(
      tester,
      logicalSize: const Size(1280, 800),
      wrap: (child) => ValueListenableBuilder<ThemeData>(
        valueListenable: theme,
        builder: (context, t, _) => Theme(data: t, child: child),
      ),
    );
    expect(_rail, findsOneWidget);
    for (final style in const [
      AppStyle.calm,
      AppStyle.craft,
      AppStyle.studio,
      AppStyle.calm,
    ]) {
      theme.value = buildStyleTheme(style, Brightness.light);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: style.wireName);
      expect(_rail, style == AppStyle.studio ? findsOneWidget : findsNothing);
      expect(_pill, style == AppStyle.calm ? findsOneWidget : findsNothing);
      expect(
        h.viewport.topInset,
        style == AppStyle.calm ? greaterThan(0) : 0,
        reason: style.wireName,
      );
      // At the top of the note: the first page's top stays on screen
      // below the bar.
      final top = h.viewportToGlobal(h.viewport.pageRectOnScreen(0).topLeft);
      if (style == AppStyle.calm) {
        expect(top.dy, greaterThanOrEqualTo(tester.getRect(_pill).bottom));
      } else {
        expect(top.dy, greaterThanOrEqualTo(h.viewportOrigin.dy));
      }
    }
  });

  for (final size in const [Size(1280, 800), Size(800, 1280)]) {
    testWidgets('미니멀 + 가로 넘기기 at ${size.width}×${size.height}: the page '
        'fits under the pill', (tester) async {
      final h = await pumpEditor(
        tester,
        logicalSize: size,
        settings: const EditorSettings(
          pageFlipMode: PageFlipMode.horizontalPaged,
        ),
        theme: buildStyleTheme(AppStyle.calm, Brightness.light),
      );
      await tester.pumpAndSettle();
      final pill = tester.getRect(_pill);
      final page = h.viewport.pageRectOnScreen(
        h.viewport.currentPageIndex.value,
      );
      final top = h.viewportToGlobal(page.topLeft).dy;
      expect(top, greaterThanOrEqualTo(pill.bottom));
      expect(
        h.viewportToGlobal(page.bottomLeft).dy,
        lessThanOrEqualTo(size.height),
      );
      // Flip to the next page: also under the pill.
      unawaited(h.viewport.jumpToPage(1));
      await tester.pumpAndSettle();
      final next = h.viewport.pageRectOnScreen(1);
      expect(
        h.viewportToGlobal(next.topLeft).dy,
        greaterThanOrEqualTo(pill.bottom),
      );
    });
  }

  testWidgets('스튜디오: 집중 모드 keeps the zoom (the rail folds away, the '
      'page does not grow under the pen)', (tester) async {
    final h = await _pump(tester, AppStyle.studio, const Size(1280, 800));
    final scale = h.viewport.camera.scale;
    final device = h.container.read(editorDeviceStateProvider.notifier);
    device.setToolbarHidden(true);
    // During the fold too.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      expect(h.viewport.camera.scale, closeTo(scale, 1e-6));
    }
    await tester.pumpAndSettle();
    expect(h.viewport.camera.scale, closeTo(scale, 1e-6));
    device.setToolbarHidden(false);
    await tester.pumpAndSettle();
    expect(h.viewport.camera.scale, closeTo(scale, 1e-6));
  });

  testWidgets('미니멀: a stroke beside the pill reaches the page', (tester) async {
    final h = await _pump(tester, AppStyle.calm, const Size(1280, 800));
    // Scroll so the page runs under the pill's row.
    final c = h.viewport.camera;
    await h.viewport.animateTo(
      c.copyWith(origin: c.origin + Offset(0, 200 / c.scale)),
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();
    final pill = tester.getRect(_pill);
    final before = h.session.pageIfLoaded(h.pageId(0))!.strokes.length;
    final y = pill.center.dy;
    await h.driver.stylusStroke([
      for (var x = 30.0; x <= pill.left - 20; x += 10) Offset(x, y),
    ]);
    await tester.pumpAndSettle();
    final pages = [
      for (var i = 0; i < 3; i++)
        h.session.pageIfLoaded(h.pageId(i))?.strokes.length ?? 0,
    ];
    expect(pages.reduce((a, b) => a + b), greaterThan(before));
  });

  testWidgets('미니멀: the selection menu and the context menu stay below the '
      'pill when the content is near the top', (tester) async {
    final h = await pumpEditor(
      tester,
      logicalSize: const Size(1280, 800),
      strokesByPageIndex: {
        0: [strokeA, strokeB],
      },
      theme: buildStyleTheme(AppStyle.calm, Brightness.light),
    );
    final pill = tester.getRect(_pill);
    // The page's top 120 pt just under the pill's strip.
    final c = h.viewport.camera;
    final page = h.viewport.layout.rectOf(0);
    await h.viewport.animateTo(
      ViewportCamera(
        scale: c.scale,
        origin: Offset(c.origin.dx, page.top + 140 - 130 / c.scale),
      ),
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();

    // A finger long press just under the pill row, beside it.
    final host = h.container.read(editorInteractionHostProvider);
    final at = Offset(pill.left - 60, pill.bottom - 20);
    await h.driver.down(11, at);
    await h.driver.wait(const Duration(milliseconds: 600));
    await h.driver.up(11);
    await tester.pump();
    if (host.contextMenu.value != null) {
      final menu = tester.getTopLeft(find.byKey(EditorContextMenu.lassoKey));
      expect(menu.dy, greaterThanOrEqualTo(pill.bottom));
    }
    await tester.tapAt(const Offset(640, 700));
    await tester.pumpAndSettle();

    h.container.read(editorCommandsProvider).selectTool(EditorTool.lasso);
    h.container.read(editorSelectionProvider.notifier).select(h.pageId(0), {
      strokeA.id,
      strokeB.id,
    }, origin: SelectionOrigin.lasso);
    await tester.pumpAndSettle();
    final bar = find.byKey(SelectionMenu.copyKey);
    expect(bar, findsOneWidget);
    expect(tester.getRect(bar).top, greaterThanOrEqualTo(pill.bottom));
  });

  testWidgets('스튜디오: the text popup and [삽입] menu open right of the '
      'rail', (tester) async {
    await _pump(tester, AppStyle.studio, const Size(1280, 800));
    final rail = tester.getRect(_rail);
    await tester.longPress(find.byKey(EditorToolbar.textKey));
    await tester.pumpAndSettle();
    final text = find.byKey(TextToolPanel.panelKey);
    expect(text, findsOneWidget);
    expect(tester.getRect(text).left, greaterThanOrEqualTo(rail.right));
    await tester.tapAt(const Offset(1200, 700));
    await tester.pumpAndSettle();

    final insert = find.byKey(InsertMenu.buttonKey);
    expect(insert, findsOneWidget);
    expect(tester.getRect(insert).right, lessThanOrEqualTo(rail.right));
    await tester.tap(insert);
    await tester.pumpAndSettle();
    final image = find.byKey(InsertMenu.imageKey);
    expect(image, findsOneWidget);
    expect(tester.getRect(image).left, greaterThanOrEqualTo(rail.right));
  });

  testWidgets('스튜디오: a rail colour picks the pen when the eraser is in '
      'hand; only an exact colour is ringed', (tester) async {
    final h = await _pump(tester, AppStyle.studio, const Size(1280, 800));
    h.container.read(editorCommandsProvider).selectTool(EditorTool.eraser);
    await tester.pump();
    await tester.tap(find.byKey(EditorRail.colorKey(2)));
    await tester.pump();
    final tools = h.container.read(editorToolProvider);
    expect(tools.activeTool, EditorTool.pen);
    expect(tools.currentPen.colorArgb & 0xFFFFFF, kBasicColors[3] & 0xFFFFFF);
    bool ringed(int i) =>
        tester.widget<InkDot>(find.byKey(EditorRail.colorKey(i))).selected;
    expect(ringed(2), isTrue);
    // A custom ink (close to 파랑) rings none.
    h.container
        .read(editorToolProvider.notifier)
        .setColor((kBasicColors[3] + 0x000101) | 0xFF000000);
    await tester.pump();
    for (var i = 0; i < EditorRail.colorIndexes.length; i++) {
      expect(ringed(i), isFalse, reason: 'colour $i');
    }
  });

  testWidgets('스튜디오 portrait: [모든 펜] opens the picker; the colours sit '
      'at the rail foot', (tester) async {
    await _pump(tester, AppStyle.studio, const Size(800, 1280));
    final rail = tester.getRect(_rail);
    final all = find.byKey(EditorRail.allPensKey);
    expect(all, findsOneWidget);
    final width = tester.getRect(find.byKey(EditorRail.widthKey(2)));
    expect(width.bottom, greaterThan(rail.bottom - 40));
    await tester.tap(all);
    await tester.pumpAndSettle();
    final picker = find.byKey(PenSettingsPanel.panelKey);
    expect(picker, findsOneWidget);
    expect(tester.getRect(picker).left, greaterThanOrEqualTo(rail.right));
  });

  testWidgets('스튜디오 1280×600: the rail scrolls to its widths', (tester) async {
    await _pump(tester, AppStyle.studio, const Size(1280, 600));
    expect(find.byKey(EditorRail.allPensKey), findsNothing);
    final last = find.byKey(EditorRail.widthKey(2));
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    expect(tester.getRect(last).bottom, lessThanOrEqualTo(600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('스튜디오 at 600 with [🎤] and the recording panel open: '
      'the slim bar fits, the rail stays', (tester) async {
    final h = await pumpEditor(
      tester,
      logicalSize: const Size(600, 960),
      theme: buildStyleTheme(AppStyle.studio, Brightness.light),
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
    h.container.read(editorPanelProvider.notifier).open();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_slim, findsOneWidget);
    expect(_rail, findsOneWidget);
    expect(find.byKey(MicButton.micKey), findsOneWidget);
  });

  testWidgets('미니멀 portrait 800: five ink chips in the pill, no blank '
      'stretch after ←', (tester) async {
    await _pump(tester, AppStyle.calm, const Size(800, 1280));
    expect(_traySlots(), findsNWidgets(5));
    final back = tester.getRect(find.byKey(EditorToolbar.backKey));
    final tray = tester.getRect(find.byKey(PenTray.trayKey));
    expect(tray.left - back.right, lessThan(12));
  });

  testWidgets('viewport: a reveal, page-down and zoom steps use the room '
      'under the floating bar', (tester) async {
    final v = ViewportController()
      ..updatePages([
        for (var i = 0; i < 4; i++)
          core.Page(
            id: 'p$i',
            noteId: 'n',
            sortKey: 'p$i',
            size: kA4,
            background: const core.BlankBackground(),
            createdAt: 0,
            updatedAt: 0,
            contentRevision: 0,
          ),
      ])
      ..updateViewportSize(const Size(1280, 800))
      ..restore(null)
      ..setTopInset(68);
    Future<void> frames() async {
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    final s = v.camera.scale;
    final page = v.layout.rectOf(0);
    // The page scrolled so that its y 300 pt is the viewport's top edge.
    unawaited(
      v.animateTo(
        ViewportCamera(
          scale: s,
          origin: Offset(v.camera.origin.dx, page.top + 300),
        ),
        duration: Duration.zero,
      ),
    );
    await tester.pump();
    // A rect inside the strip the bar covers is not visible: revealed.
    final hidden = Rect.fromLTWH(100, 300 + 10 / s, 50, 20 / s);
    unawaited(v.revealPageRect(0, focusRectPt: hidden, animate: false));
    await tester.pump();
    final shown = v.camera.docToScreen(hidden.topLeft + page.topLeft);
    expect(shown.dy, greaterThanOrEqualTo(68));
    // Centred in the room under the bar.
    final centre = v.camera.docToScreen(hidden.center + page.topLeft);
    expect(centre.dy, closeTo((800 + 68) / 2, 1));
    // Is a page whose only visible part is under the bar "visible"? No.
    // Page-down: 90 % of the room under the bar.
    final y0 = v.camera.origin.dy;
    unawaited(v.scrollByViewport(1));
    await frames();
    expect((v.camera.origin.dy - y0) * s, closeTo((800 - 68) * 0.9, 1));
    // A zoom step keeps the centre of the room under the bar.
    final focal = v.camera.screenToDoc(const Offset(640, (800 + 68) / 2));
    unawaited(v.zoomStep(zoomIn: true));
    await frames();
    expect(v.camera.docToScreen(focal).dy, closeTo((800 + 68) / 2, 1));
    await frames();
    v.dispose();
  });
}
