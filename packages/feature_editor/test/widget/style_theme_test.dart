// (v2.14-ui, docs/plans/m5-7/04-editor.md 20) The editor chrome picks up the
// screen style in light and dark: toolbar = the style's toolbar surface, the
// desk around the pages = its canvas, while the page paper stays white and
// pen previews sit on a paper-light swatch. Pixel probe on the rendered
// layer plus the widget colours.
import 'dart:ui' as ui;

import 'package:feature_editor/src/state/settings/editor_device_state.dart';
import 'package:feature_editor/src/ui/overlays/page_indicator.dart';
import 'package:feature_editor/src/ui/pen/pen_art_view.dart';
import 'package:feature_editor/src/ui/pen/pen_preview.dart';
import 'package:feature_editor/src/ui/pen/pen_tray.dart';
import 'package:feature_editor/src/ui/search/note_search_panel.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:feature_editor/src/viewport/page_viewport.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import '../helpers/pump_editor.dart';

Future<Color> _pixelAt(WidgetTester tester, Offset logical) async {
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  final dpr = tester.view.devicePixelRatio;
  final image = (await tester.runAsync(
    () => layer.toImage(Offset.zero & (view.size * dpr), pixelRatio: 1 / dpr),
  ))!;
  final data = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final i = (logical.dy.round() * image.width + logical.dx.round()) * 4;
  final color = Color.fromARGB(
    data.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
  image.dispose();
  return color;
}

bool _near(Color a, Color b) =>
    ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs()) < 0.03;

void main() {
  for (final style in AppStyle.values) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('${style.wireName} ${brightness.name}: toolbar, canvas and '
          'paper', (tester) async {
        final tokens = styleTokensFor(style, brightness);
        await pumpEditor(
          tester,
          logicalSize: const Size(1280, 800),
          theme: buildStyleTheme(style, brightness),
        );
        await tester.pump(const Duration(milliseconds: 100));

        // The toolbar's Material and the viewport's desk.
        final toolbar = find.byType(EditorToolbar);
        final material = tester.widget<Material>(
          find.descendant(of: toolbar, matching: find.byType(Material)).first,
        );
        expect(material.color, tokens.toolbar);
        final viewport = find.byType(PageViewport);
        final desk = tester.widget<ColoredBox>(
          find
              .descendant(of: viewport, matching: find.byType(ColoredBox))
              .first,
        );
        expect(desk.color, tokens.canvas);

        // Pixels: the toolbar's top edge, the desk above the first page and
        // the paper in the page's middle.
        final bar = tester.getRect(toolbar);
        final barPixel = await _pixelAt(
          tester,
          Offset(bar.width * 0.5, bar.top + 2),
        );
        expect(_near(barPixel, tokens.toolbar), isTrue, reason: '$barPixel');
        final area = tester.getRect(viewport);
        final deskPixel = await _pixelAt(
          tester,
          Offset(area.left + 3, area.top + 6),
        );
        expect(_near(deskPixel, tokens.canvas), isTrue, reason: '$deskPixel');
        final paperPixel = await _pixelAt(
          tester,
          Offset(area.center.dx, area.top + 200),
        );
        expect(
          _near(paperPixel, const Color(0xFFFFFFFF)),
          isTrue,
          reason: 'paper stays white: $paperPixel',
        );
        expect(
          deskPixel.computeLuminance() < 0.2,
          brightness == Brightness.dark,
        );

        // Pen settings: the preview swatch is paper-light in every style.
        await tester.tap(find.byKey(EditorToolbar.penKey));
        await tester.pump(const Duration(milliseconds: 300));
        final preview = find.byType(PenPreview);
        expect(preview, findsWidgets);
        final box = tester.widget<Container>(
          find
              .descendant(of: preview.first, matching: find.byType(Container))
              .first,
        );
        expect((box.decoration! as BoxDecoration).color, tokens.inkSwatch);
      });
    }
  }

  // (v2.14-ui review fixes)
  for (final style in AppStyle.values) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('${style.wireName} ${brightness.name}: the page counter is '
          'dark-on-paper; preset chips look the same in light and dark', (
        tester,
      ) async {
        final tokens = styleTokensFor(style, brightness);
        final h = await pumpEditor(
          tester,
          logicalSize: const Size(1280, 800),
          theme: buildStyleTheme(style, brightness),
        );
        await tester.pump(const Duration(milliseconds: 100));

        // The page counter pill sits over the paper: a fixed dark badge.
        // (UI stage 2) It shows while the menu is hidden (the toolbar's
        // page button has the count otherwise).
        final device = h.container.read(editorDeviceStateProvider.notifier);
        device.setToolbarHidden(true);
        await tester.pump(const Duration(milliseconds: 300));
        final label = find.byKey(PageIndicator.indicatorKey);
        expect(label, findsOneWidget);
        final pill = tester.widget<DecoratedBox>(
          find.ancestor(of: label, matching: find.byType(DecoratedBox)).first,
        );
        final fill = (pill.decoration as ShapeDecoration).color!;
        final onPaper = Color.alphaBlend(fill, const Color(0xFFFFFFFF));
        expect(
          contrastRatio(onPaper, const Color(0xFFFFFFFF)),
          greaterThanOrEqualTo(3),
          reason: 'pill edge on white paper',
        );
        expect(
          contrastRatio(tester.widget<Text>(label).style!.color!, onPaper),
          greaterThanOrEqualTo(4.5),
        );

        device.setToolbarHidden(false);
        await tester.pump(const Duration(milliseconds: 300));

        // (v2.15-ui) The pen tray follows the style: a recessed well with
        // the pen drawings (크래프트, 스튜디오) or flat ink-stroke chips
        // (미니멀); the chip ink sits on a paper-light swatch in dark.
        final look = PenTrayStyle.of(tokens);
        final tray = find.byKey(PenTray.trayKey);
        expect(tray, findsOneWidget);
        final decoration =
            tester.widget<Container>(tray).decoration as BoxDecoration?;
        if (style == AppStyle.calm) {
          expect(look.look, PenTrayLook.strokes);
          expect(decoration, isNull);
          expect(
            find.descendant(of: tray, matching: find.byType(PenArt)),
            findsNothing,
          );
          expect(
            find.descendant(of: tray, matching: find.byType(InkStroke)),
            findsWidgets,
          );
          // (v2.15-ui review) No plates; in dark only a dark ink gets the
          // small paper-light plate.
          expect(look.chipFill.a, 0);
          if (brightness == Brightness.dark) {
            expect(look.chipPlate.a, greaterThan(0.5));
            expect(look.needsPlate(const Color(0xFF1A1A1A)), isTrue);
            expect(look.needsPlate(const Color(0xFFFFD526)), isFalse);
          } else {
            expect(look.chipPlate.a, 0);
            expect(look.needsEdge(const Color(0xFFFFE600)), isTrue);
          }
        } else {
          expect(look.look, PenTrayLook.drawings);
          expect((decoration!.gradient! as LinearGradient).colors, [
            look.wellTop,
            look.wellBottom,
          ]);
          expect(
            find.descendant(of: tray, matching: find.byType(PenArt)),
            findsNWidgets(5),
          );
        }
      });
    }
  }

  test('(review) the matched word in the search list reads ≥ 4.5:1 in every '
      'style and brightness', () {
    for (final style in AppStyle.values) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final t = styleTokensFor(style, brightness);
        expect(
          contrastRatio(
            NoteSearchColors.listMatchText(t),
            NoteSearchColors.listMatchFill(t),
          ),
          greaterThanOrEqualTo(4.5),
          reason: '${style.wireName} ${brightness.name}',
        );
      }
    }
  });
}
