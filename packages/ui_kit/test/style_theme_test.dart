// Themes of the three styles × two brightnesses (01-infra 14.5).
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  const brightnesses = [Brightness.light, Brightness.dark];

  test('wire names are stable; unknown → defaults', () {
    expect(
      [for (final s in AppStyle.values) s.wireName],
      ['craft', 'calm', 'studio'],
    );
    expect(
      [for (final m in AppBrightnessMode.values) m.wireName],
      ['system', 'light', 'dark'],
    );
    expect(AppStyle.fromWire('studio'), AppStyle.studio);
    expect(AppStyle.fromWire('pro'), AppStyle.craft);
    expect(AppStyle.fromWire(null), AppStyle.craft);
    expect(AppBrightnessMode.fromWire('dark'), AppBrightnessMode.dark);
    expect(AppBrightnessMode.fromWire('x'), AppBrightnessMode.system);
  });

  for (final style in AppStyle.values) {
    for (final brightness in brightnesses) {
      group('${style.wireName} ${brightness.name}', () {
        final theme = buildStyleTheme(style, brightness);
        final t = theme.extension<StyleTokens>()!;
        final scheme = theme.colorScheme;
        final surfaces = {
          'canvas': t.canvas,
          'toolbar': t.toolbar,
          'panel': t.panel,
          'rail': t.rail,
          'card': t.card,
          'surfaceContainerHigh': scheme.surfaceContainerHigh,
          'surfaceContainerHighest': scheme.surfaceContainerHighest,
        };

        test('tokens, brightness and scheme agree', () {
          expect(t.style, style);
          expect(t.brightness, brightness);
          expect(theme.brightness, brightness);
          expect(scheme.brightness, brightness);
          expect(scheme.primary, t.accent);
          expect(scheme.surface, t.toolbar);
          expect(scheme.onSurface, t.textPrimary);
          expect(scheme.onSurfaceVariant, t.textSecondary);
          expect(scheme.outlineVariant, t.hairline);
          expect(theme.scaffoldBackgroundColor, t.toolbar);
          expect(theme.popupMenuTheme.color, t.panel);
          expect(theme.bottomSheetTheme.backgroundColor, t.panel);
          expect(theme.dialogTheme.backgroundColor, t.panel);
          expect(theme.sliderTheme.activeTrackColor, t.accent);
          expect(theme.snackBarTheme.backgroundColor, t.textPrimary);
          expect(theme.listTileTheme.iconColor, t.textSecondary);
          expect(theme.chipTheme.selectedColor, t.accentSoft);
          expect(theme.segmentedButtonTheme.style, isNotNull);
          expect(theme.switchTheme.trackColor, isNotNull);
          expect(theme.tooltipTheme.decoration, isNotNull);
        });

        test('dark variants are dark, light variants are light', () {
          final dark = brightness == Brightness.dark;
          for (final MapEntry(:key, :value) in surfaces.entries) {
            expect(
              value.computeLuminance() < 0.2,
              dark,
              reason: '$key ${value.toARGB32().toRadixString(16)}',
            );
          }
          // The ink swatch stays paper-light in both (ink is document data).
          expect(t.inkSwatch.computeLuminance(), greaterThan(0.8));
        });

        test('text on surfaces ≥ 4.5:1, icons and outlines ≥ 3:1', () {
          for (final MapEntry(:key, :value) in surfaces.entries) {
            expect(
              contrastRatio(t.textPrimary, value),
              greaterThanOrEqualTo(4.5),
              reason: 'textPrimary on $key',
            );
            expect(
              contrastRatio(t.textSecondary, value),
              greaterThanOrEqualTo(4.5),
              reason: 'textSecondary on $key',
            );
            expect(
              contrastRatio(t.accent, value),
              greaterThanOrEqualTo(3),
              reason: 'accent (icons) on $key',
            );
          }
          for (final surface in [t.toolbar, t.panel]) {
            expect(contrastRatio(t.outline, surface), greaterThanOrEqualTo(3));
          }
          expect(
            contrastRatio(t.onAccent, t.accent),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrastRatio(t.onAccentSoft, t.accentSoft),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrastRatio(scheme.onError, scheme.error),
            greaterThanOrEqualTo(4.5),
          );
          expect(contrastRatio(scheme.error, t.panel), greaterThanOrEqualTo(3));
          // Snack bars and tooltips are inverse.
          expect(
            contrastRatio(scheme.onInverseSurface, scheme.inverseSurface),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrastRatio(scheme.inversePrimary, scheme.inverseSurface),
            greaterThanOrEqualTo(3),
          );
        });

        test('marks on paper stay visible on the paper-light swatch', () {
          // The paper stays light in dark styles too: selection frames,
          // cursors and highlights use the paper tokens, not the chrome's.
          expect(
            contrastRatio(t.paperAccent, t.inkSwatch),
            greaterThanOrEqualTo(3),
          );
          expect(
            contrastRatio(t.paperHighlight, t.inkSwatch),
            greaterThanOrEqualTo(3),
          );
          expect(
            contrastRatio(t.paperInk, t.inkSwatch),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrastRatio(t.paperAccent, const Color(0xFFFFFFFF)),
            greaterThanOrEqualTo(3),
          );
        });

        test('swatchRing: a stronger ring only where the ink would vanish', () {
          const black = Color(0xFF000000);
          const white = Color(0xFFFFFFFF);
          final dark = brightness == Brightness.dark;
          expect(
            t.swatchRing(black, t.toolbar),
            dark ? t.textSecondary : t.hairline,
          );
          expect(
            t.swatchRing(white, t.toolbar),
            dark ? t.hairline : t.textSecondary,
          );
        });

        test('copyWith / lerp keep the values', () {
          expect(t.copyWith(), t);
          expect(t.lerp(t, 0.5), t);
          final other = styleTokensFor(
            style,
            brightness == Brightness.dark ? Brightness.light : Brightness.dark,
          );
          expect(t.lerp(other, 0), t);
          expect(t.lerp(other, 1), other);
        });
      });
    }
  }

  test('the three styles differ in every brightness', () {
    for (final brightness in brightnesses) {
      final canvases = {
        for (final s in AppStyle.values) styleTokensFor(s, brightness).canvas,
      };
      expect(canvases, hasLength(3));
    }
    expect(
      styleTokensFor(AppStyle.calm, Brightness.light).toolLabels,
      ToolLabelMode.onHover,
    );
    expect(
      styleTokensFor(AppStyle.craft, Brightness.dark).toolLabels,
      ToolLabelMode.always,
    );
  });

  testWidgets('StyleTokens.of: the extension, else the scheme fallback', (
    tester,
  ) async {
    late StyleTokens withExtension;
    late StyleTokens without;
    final plain = ThemeData(useMaterial3: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildStyleTheme(AppStyle.studio, Brightness.dark),
        home: Builder(
          builder: (context) {
            withExtension = StyleTokens.of(context);
            return Theme(
              data: plain,
              child: Builder(
                builder: (context) {
                  without = StyleTokens.of(context);
                  return const SizedBox();
                },
              ),
            );
          },
        ),
      ),
    );
    expect(withExtension, styleTokensFor(AppStyle.studio, Brightness.dark));
    expect(without.canvas, plain.colorScheme.surfaceContainer);
    expect(without.toolbar, plain.colorScheme.surface);
    expect(without.panel, plain.colorScheme.surfaceContainerLow);
    expect(without.inkSwatch, plain.colorScheme.surface);
  });

  test('shadows follow the elevation style', () {
    final studio = styleTokensFor(AppStyle.studio, Brightness.light);
    expect(studio.shadows(1), isEmpty);
    expect(studio.shadows(2), hasLength(1));
    expect(
      styleTokensFor(AppStyle.calm, Brightness.light).shadows(),
      hasLength(2),
    );
    expect(
      styleTokensFor(AppStyle.craft, Brightness.dark).shadows(),
      hasLength(1),
    );
  });
}
