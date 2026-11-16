// (v2.15-ui review) The tray's look per style: toolbar heights, the rim
// light on dark wells, the calm chips' plate and edge rules, the line
// eraser glyph.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  test(
    'toolbar heights: craft 64, calm 52, studio 60 in both brightnesses',
    () {
      for (final b in Brightness.values) {
        expect(styleTokensFor(AppStyle.craft, b).toolbarHeight, 64);
        expect(styleTokensFor(AppStyle.calm, b).toolbarHeight, 52);
        expect(styleTokensFor(AppStyle.studio, b).toolbarHeight, 60);
      }
    },
  );

  test('rim light only where the well is dark', () {
    PenTrayStyle look(AppStyle s, Brightness b) =>
        PenTrayStyle.of(styleTokensFor(s, b));
    expect(look(AppStyle.craft, Brightness.light).rimLight, isNull);
    expect(look(AppStyle.craft, Brightness.dark).rimLight, isNotNull);
    expect(look(AppStyle.studio, Brightness.light).rimLight, isNotNull);
    expect(look(AppStyle.studio, Brightness.dark).rimLight, isNotNull);
    expect(look(AppStyle.calm, Brightness.dark).rimLight, isNull);
  });

  test('calm chips: no plates; a dark ink gets one in dark, a pale ink an '
      'edge in light', () {
    final light = PenTrayStyle.of(
      styleTokensFor(AppStyle.calm, Brightness.light),
    );
    final dark = PenTrayStyle.of(
      styleTokensFor(AppStyle.calm, Brightness.dark),
    );
    const black = Color(0xFF1A1A1A);
    const yellow = Color(0xFFFFE600);
    expect(light.chipFill.a, 0);
    expect(dark.chipFill.a, 0);
    expect(dark.needsPlate(black), isTrue);
    expect(dark.needsPlate(yellow), isFalse);
    expect(light.needsPlate(black), isFalse);
    expect(light.needsEdge(yellow), isTrue);
    expect(light.needsEdge(black), isFalse);
    expect(dark.needsEdge(yellow), isFalse);
  });

  testWidgets('the eraser glyph and a rim-lit pen paint without errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            CustomPaint(
              size: Size.square(24),
              painter: EraserGlyphPainter(color: Color(0xFF333333)),
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomPaint(
          size: const Size(26, 80),
          painter: PenArtPainter(
            kind: PenArtKind.ballpoint,
            color: const Color(0xFF1A1A1A),
            rimLight: const Color(0x2EFFFFFF),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
