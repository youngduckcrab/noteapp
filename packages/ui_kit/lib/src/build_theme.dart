/// ThemeData from a style's tokens (01-infra 14.3).
library;

import 'package:material_ui/material_ui.dart';

import 'app_style.dart';
import 'style_palettes.dart';
import 'style_tokens.dart';

/// The Material 3 theme of [style] in [brightness]: a [ColorScheme] built
/// from the style's tokens, component themes (menus, sheets, dialogs,
/// sliders, segmented buttons, chips, switches, list tiles, snack bars,
/// tooltips, …) and the [StyleTokens] extension.
ThemeData buildStyleTheme(AppStyle style, Brightness brightness) =>
    buildThemeFromTokens(styleTokensFor(style, brightness));

/// [buildStyleTheme] for any [tokens] (tests, later per-style tweaks).
ThemeData buildThemeFromTokens(StyleTokens t) {
  final scheme = styleColorScheme(t);
  final small = BorderRadius.circular(t.radiusSmall);
  final medium = BorderRadius.circular(t.radiusMedium);
  final large = BorderRadius.circular(t.radiusLarge);
  final flatSide = t.elevation == StyleElevation.flat
      ? BorderSide(color: t.hairline)
      : BorderSide.none;
  final inverseText = t.toolbar;

  return ThemeData(
    useMaterial3: true,
    brightness: t.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.toolbar,
    canvasColor: t.panel,
    dividerColor: t.hairline,
    extensions: [t],
    appBarTheme: AppBarTheme(
      backgroundColor: t.toolbar,
      foregroundColor: t.textPrimary,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: t.elevation == StyleElevation.flat ? 0 : 1,
      shadowColor: t.shadow,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.panel,
      surfaceTintColor: Colors.transparent,
      elevation: t.materialElevation(2),
      shadowColor: t.shadow,
      shape: RoundedRectangleBorder(borderRadius: medium, side: flatSide),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(t.panel),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(t.materialElevation(2)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: medium, side: flatSide),
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.panel,
      modalBackgroundColor: t.panel,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: t.outline,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(t.radiusLarge),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: large, side: flatSide),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: t.rail,
      surfaceTintColor: Colors.transparent,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: t.rail,
      indicatorColor: t.accentSoft,
    ),
    cardTheme: CardThemeData(
      color: t.card,
      surfaceTintColor: Colors.transparent,
      shadowColor: t.shadow,
      elevation: t.materialElevation(1) / 2,
      shape: RoundedRectangleBorder(
        borderRadius: medium,
        side: BorderSide(color: t.hairline),
      ),
    ),
    dividerTheme: DividerThemeData(color: t.hairline, space: 1, thickness: 1),
    sliderTheme: SliderThemeData(
      activeTrackColor: t.accent,
      inactiveTrackColor: t.hairline,
      thumbColor: t.accent,
      overlayColor: t.accent.withValues(alpha: 0.12),
      valueIndicatorColor: t.textPrimary,
      valueIndicatorTextStyle: TextStyle(color: inverseText),
      activeTickMarkColor: t.onAccent,
      inactiveTickMarkColor: t.outline,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? t.accentSoft
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return t.textTertiary;
          return states.contains(WidgetState.selected)
              ? t.onAccentSoft
              : t.textPrimary;
        }),
        side: WidgetStatePropertyAll(BorderSide(color: t.outline)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: small),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: t.card,
      selectedColor: t.accentSoft,
      secondarySelectedColor: t.accentSoft,
      disabledColor: t.card,
      checkmarkColor: t.onAccentSoft,
      deleteIconColor: t.textSecondary,
      side: BorderSide(color: t.hairline),
      labelStyle: TextStyle(color: t.textPrimary),
      secondaryLabelStyle: TextStyle(color: t.onAccentSoft),
      iconTheme: IconThemeData(color: t.textSecondary, size: 18),
      shape: RoundedRectangleBorder(borderRadius: small),
      surfaceTintColor: Colors.transparent,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? t.onAccent : t.outline,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? t.accent : t.card,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.transparent
            : t.outline,
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: t.textSecondary,
      textColor: t.textPrimary,
      selectedColor: t.accent,
      selectedTileColor: t.accentSoft,
      shape: RoundedRectangleBorder(borderRadius: small),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.textPrimary,
      contentTextStyle: TextStyle(color: inverseText),
      actionTextColor: scheme.inversePrimary,
      closeIconColor: inverseText,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: small),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: t.textPrimary.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(t.radiusSmall * 0.75),
      ),
      textStyle: TextStyle(color: inverseText, fontSize: 12),
    ),
  );
}

/// The Material 3 [ColorScheme] of [t]: primary / secondary = the accent,
/// surface = [StyleTokens.toolbar], the container ramp mixes the primary
/// text colour into the surface (3 / 5 / 8 / 11 %), outline roles = the
/// line tokens.
ColorScheme styleColorScheme(StyleTokens t) {
  Color mix(double amount) =>
      Color.alphaBlend(t.textPrimary.withValues(alpha: amount), t.toolbar);
  final dark = t.isDark;
  final opposite = styleTokensFor(
    t.style,
    dark ? Brightness.light : Brightness.dark,
  );
  return ColorScheme(
    brightness: t.brightness,
    primary: t.accent,
    onPrimary: t.onAccent,
    primaryContainer: t.accentSoft,
    onPrimaryContainer: t.onAccentSoft,
    secondary: t.accent,
    onSecondary: t.onAccent,
    secondaryContainer: t.accentSoft,
    onSecondaryContainer: t.onAccentSoft,
    tertiary: dark ? const Color(0xFFE6B98A) : const Color(0xFF8A5A2B),
    onTertiary: dark ? const Color(0xFF3A2410) : const Color(0xFFFFFFFF),
    tertiaryContainer: dark ? const Color(0xFF4D3824) : const Color(0xFFF6E3CF),
    onTertiaryContainer: dark
        ? const Color(0xFFF6E3CF)
        : const Color(0xFF3A2410),
    error: dark ? const Color(0xFFF2B8B5) : const Color(0xFFB3261E),
    onError: dark ? const Color(0xFF601410) : const Color(0xFFFFFFFF),
    errorContainer: dark ? const Color(0xFF8C1D18) : const Color(0xFFF9DEDC),
    onErrorContainer: dark ? const Color(0xFFF9DEDC) : const Color(0xFF410E0B),
    surface: t.toolbar,
    onSurface: t.textPrimary,
    onSurfaceVariant: t.textSecondary,
    surfaceDim: mix(0.10),
    surfaceBright: dark ? mix(0.12) : t.toolbar,
    surfaceContainerLowest: dark ? t.canvas : t.card,
    surfaceContainerLow: mix(0.03),
    surfaceContainer: mix(0.05),
    surfaceContainerHigh: mix(0.08),
    surfaceContainerHighest: mix(0.11),
    outline: t.outline,
    outlineVariant: t.hairline,
    shadow: t.shadow,
    scrim: const Color(0xFF000000),
    inverseSurface: t.textPrimary,
    onInverseSurface: t.toolbar,
    inversePrimary: opposite.accent,
    surfaceTint: Colors.transparent,
  );
}
