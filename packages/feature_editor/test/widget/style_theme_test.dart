// (v2.14-ui, docs/plans/m5-7/04-editor.md 20) The editor chrome picks up the
// screen style in light and dark: toolbar = the style's toolbar surface, the
// desk around the pages = its canvas, while the page paper stays white and
// pen previews sit on a paper-light swatch. Pixel probe on the rendered
// layer plus the widget colours.
import 'dart:ui' as ui;

import 'package:feature_editor/src/ui/overlays/page_indicator.dart';
import 'package:feature_editor/src/ui/pen/pen_preview.dart';
import 'package:feature_editor/src/ui/presets/preset_chip.dart';
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
        await pumpEditor(
          tester,
          logicalSize: const Size(1280, 800),
          theme: buildStyleTheme(style, brightness),
        );
        await tester.pump(const Duration(milliseconds: 100));

        // The page counter pill sits over the paper: a fixed dark badge.
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

        // Preset chips: the ink disc on a paper-light backing; the width
        // dot is judged on paper, so it is the same in both brightnesses.
        final light = styleTokensFor(style, Brightness.light);
        for (final chip in tester.widgetList<PresetChip>(
          find.byType(PresetChip),
        )) {
          final at = find.byWidget(chip);
          final paper = tester.widget<DecoratedBox>(
            find.descendant(of: at, matching: find.byKey(PresetChip.paperKey)),
          );
          expect((paper.decoration as BoxDecoration).color, tokens.inkSwatch);
          final dot = tester.widget<DecoratedBox>(
            find.descendant(of: at, matching: find.byKey(PresetChip.dotKey)),
          );
          final c = Color(chip.preset.style.colorArgb)
              .withValues(alpha: chip.preset.style.opacity);
          final dotColor = (dot.decoration as BoxDecoration).color!;
          final lightDot = PresetChip.dotColorOnPaper(
            Color.alphaBlend(c, light.inkSwatch),
            light,
          );
          // Same choice (paper or ink) as in the light variant.
          expect(
            dotColor.computeLuminance() > 0.5,
            lightDot.computeLuminance() > 0.5,
            reason: '${chip.preset.name} width dot',
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
