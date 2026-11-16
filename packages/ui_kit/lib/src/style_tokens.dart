/// Style tokens: the values a screen style gives the UI packages beyond the
/// Material [ColorScheme] (contract 7.1 v2.14-ui, 01-infra 14).
library;

import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'app_style.dart';
import 'contrast.dart';

/// When the tool names under toolbar icons show.
enum ToolLabelMode {
  /// Always under the icon (크래프트, 스튜디오).
  always,

  /// Only while a pointer or a hovering stylus is over the tool (미니멀).
  onHover,
}

/// How raised surfaces (toolbar, popovers, cards) are set off.
enum StyleElevation {
  /// Short warm shadows (크래프트).
  soft,

  /// Wide, light shadows of a floating bar (미니멀).
  floating,

  /// Hairline borders, almost no shadow (스튜디오).
  flat,
}

/// The tokens of one style in one brightness, as a [ThemeExtension].
///
/// Read with [StyleTokens.of]: a theme without the extension (tests, a
/// package's own preview) gets [StyleTokens.fromScheme], which maps every
/// token to the [ColorScheme] role the UI used before the tokens existed —
/// so such a theme looks exactly as before.
///
/// Page paper and ink colours are document data and are **not** tokens: in a
/// dark style the canvas around the pages darkens, the paper stays the colour
/// the note says (01-infra 14.4).
@immutable
final class StyleTokens extends ThemeExtension<StyleTokens>
    with Diagnosticable {
  const StyleTokens({
    required this.style,
    required this.brightness,
    required this.canvas,
    required this.toolbar,
    required this.panel,
    required this.rail,
    required this.card,
    required this.inkSwatch,
    required this.paperAccent,
    required this.paperInk,
    required this.paperHighlight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.onAccentSoft,
    required this.outline,
    required this.hairline,
    required this.shadow,
    required this.radiusSmall,
    required this.radiusMedium,
    required this.radiusLarge,
    required this.elevation,
    required this.toolbarHeight,
    required this.toolLabels,
    required this.iconStrokeWidth,
  });

  /// The tokens of a theme that has no [StyleTokens] extension: each token
  /// is the [ColorScheme] role the screens used before (canvas =
  /// `surfaceContainer`, toolbar = `surface`, panel = `surfaceContainerLow`,
  /// …), so nothing changes for such a theme.
  factory StyleTokens.fromScheme(ColorScheme scheme) => StyleTokens(
    style: AppStyle.fallback,
    brightness: scheme.brightness,
    canvas: scheme.surfaceContainer,
    toolbar: scheme.surface,
    panel: scheme.surfaceContainerLow,
    rail: scheme.surfaceContainerLow,
    card: scheme.surfaceContainerHighest,
    inkSwatch: scheme.surface,
    paperAccent: scheme.primary,
    paperInk: scheme.onSurface,
    paperHighlight: scheme.tertiary,
    textPrimary: scheme.onSurface,
    textSecondary: scheme.onSurfaceVariant,
    textTertiary: scheme.outline,
    accent: scheme.primary,
    onAccent: scheme.onPrimary,
    accentSoft: scheme.primaryContainer,
    onAccentSoft: scheme.onPrimaryContainer,
    outline: scheme.outline,
    hairline: scheme.outlineVariant,
    shadow: scheme.shadow,
    radiusSmall: 8,
    radiusMedium: 12,
    radiusLarge: 16,
    elevation: StyleElevation.soft,
    toolbarHeight: 52,
    toolLabels: ToolLabelMode.always,
    iconStrokeWidth: 1.7,
  );

  /// The tokens of the nearest theme ([StyleTokens.fromScheme] when the
  /// theme has none).
  static StyleTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<StyleTokens>() ??
        StyleTokens.fromScheme(theme.colorScheme);
  }

  /// Which style these tokens belong to.
  final AppStyle style;

  /// Light or dark variant.
  final Brightness brightness;

  // --- surfaces -------------------------------------------------------------

  /// The desk around the pages in the editor (the pages themselves keep
  /// their paper colour).
  final Color canvas;

  /// Toolbars, app bars and full screens (library, settings).
  final Color toolbar;

  /// Popovers, menus, sheets, dialogs and side panels.
  final Color panel;

  /// Side rails and the library sidebar.
  final Color rail;

  /// Cards and wells on [toolbar] / [panel] (library tiles, chips).
  final Color card;

  /// Background of pen previews and ink swatches. Ink colours are document
  /// data, so this stays paper-light in every brightness: a black pen must
  /// stay readable in a dark style.
  final Color inkSwatch;

  // --- marks drawn on the page paper ---------------------------------------
  // The paper stays light in every brightness, so what the editor draws on
  // it (selection frame, text cursor, eraser ring, search / position
  // highlights) uses these, never the chrome's accent or text colours.

  /// Selection frames, new text box outline and the text cursor on paper.
  final Color paperAccent;

  /// Neutral marks on paper (the eraser / pen hover ring).
  final Color paperInk;

  /// Search and position highlights on paper.
  final Color paperHighlight;

  // --- text and icons -------------------------------------------------------

  /// Titles and body text (≥ 4.5:1 on every surface token).
  final Color textPrimary;

  /// Secondary text and icons (≥ 4.5:1 on every surface token).
  final Color textSecondary;

  /// Hints and disabled text (decorative; not for content).
  final Color textTertiary;

  // --- accent ---------------------------------------------------------------

  /// The one accent: selection, the active tool, primary buttons.
  final Color accent;

  /// Text and icons on [accent].
  final Color onAccent;

  /// Quiet accent fill (selected chips, the active tool's well).
  final Color accentSoft;

  /// Text and icons on [accentSoft].
  final Color onAccentSoft;

  // --- lines and depth ------------------------------------------------------

  /// Borders of inputs and outlined controls (≥ 3:1 on surfaces).
  final Color outline;

  /// Dividers and card borders (decorative).
  final Color hairline;

  /// Shadow colour (alpha applied by [shadows]).
  final Color shadow;

  /// Corner radii: chips and small buttons / popovers and cards / sheets and
  /// dialogs.
  final double radiusSmall;
  final double radiusMedium;
  final double radiusLarge;

  /// How raised surfaces are drawn.
  final StyleElevation elevation;

  // --- layout hints for later stages (stage 1 does not change layouts) ------

  /// Toolbar height the style is drawn for.
  final double toolbarHeight;

  /// When tool names show under the toolbar icons.
  final ToolLabelMode toolLabels;

  /// Stroke weight of the line icons (stage 2).
  final double iconStrokeWidth;

  /// Whether this is a dark variant.
  bool get isDark => brightness == Brightness.dark;

  /// Fill of a small badge or banner drawn OVER the page paper (page
  /// counter, rotation label, eyedropper banner): fixed dark-on-paper in
  /// every brightness. A role that flips with the theme (inverseSurface)
  /// would turn near-white on white paper in dark mode.
  Color get paperBadge => paperInk;

  /// Text and icons on [paperBadge].
  Color get onPaperBadge => inkSwatch;

  /// Menus and popovers that open OVER other content (popup menus, menu
  /// anchors). Light: [panel] plus the shadow. Dark: a step above every
  /// card and container surface (14 % [textPrimary] over [toolbar]; the
  /// highest container is 11 %), since a dark shadow barely shows and a
  /// menu darker than the cards it covers reads as sunk below them.
  Color get popover => isDark
      ? Color.alphaBlend(textPrimary.withValues(alpha: 0.14), toolbar)
      : panel;

  /// Outline of a [popover]: none in light (the shadow separates it), a
  /// soft [outline] edge in dark.
  BorderSide get popoverSide => isDark
      ? BorderSide(color: outline.withValues(alpha: 0.45))
      : BorderSide.none;

  /// Shadows for a raised surface at [level] (1 = toolbar / card,
  /// 2 = popover, 3 = dialog) in this style.
  List<BoxShadow> shadows([int level = 1]) {
    final l = level.clamp(1, 3).toDouble();
    final dark = isDark;
    switch (elevation) {
      case StyleElevation.soft:
        return [
          BoxShadow(
            color: shadow.withValues(alpha: dark ? 0.40 : 0.10),
            blurRadius: 4 * l,
            offset: Offset(0, l),
          ),
        ];
      case StyleElevation.floating:
        return [
          BoxShadow(
            color: shadow.withValues(alpha: dark ? 0.45 : 0.08),
            blurRadius: 12 * l,
            offset: Offset(0, 3 * l),
          ),
          BoxShadow(
            color: shadow.withValues(alpha: dark ? 0.30 : 0.04),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ];
      case StyleElevation.flat:
        return [
          if (level > 1)
            BoxShadow(
              color: shadow.withValues(alpha: dark ? 0.50 : 0.12),
              blurRadius: 8 * l,
              offset: Offset(0, 2 * l),
            ),
        ];
    }
  }

  /// Border colour for a colour swatch (an ink dot, a pen chip) of [swatch]
  /// drawn on [background]: [hairline] when the swatch stands out by itself,
  /// [textSecondary] when it would vanish (black ink on a dark toolbar, white
  /// ink on a light one).
  Color swatchRing(Color swatch, Color background) {
    final shown = swatch.a >= 1 ? swatch : Color.alphaBlend(swatch, background);
    return contrastRatio(shown, background) < 1.6 ? textSecondary : hairline;
  }

  /// Material elevation of a surface at [level] for this style (the
  /// component themes use it).
  double materialElevation([int level = 1]) => switch (elevation) {
    StyleElevation.soft => 1.0 + level,
    StyleElevation.floating => 2.0 + 2 * level,
    StyleElevation.flat => level > 1 ? 2.0 * level : 0,
  };

  @override
  StyleTokens copyWith({
    AppStyle? style,
    Brightness? brightness,
    Color? canvas,
    Color? toolbar,
    Color? panel,
    Color? rail,
    Color? card,
    Color? inkSwatch,
    Color? paperAccent,
    Color? paperInk,
    Color? paperHighlight,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? onAccent,
    Color? accentSoft,
    Color? onAccentSoft,
    Color? outline,
    Color? hairline,
    Color? shadow,
    double? radiusSmall,
    double? radiusMedium,
    double? radiusLarge,
    StyleElevation? elevation,
    double? toolbarHeight,
    ToolLabelMode? toolLabels,
    double? iconStrokeWidth,
  }) => StyleTokens(
    style: style ?? this.style,
    brightness: brightness ?? this.brightness,
    canvas: canvas ?? this.canvas,
    toolbar: toolbar ?? this.toolbar,
    panel: panel ?? this.panel,
    rail: rail ?? this.rail,
    card: card ?? this.card,
    inkSwatch: inkSwatch ?? this.inkSwatch,
    paperAccent: paperAccent ?? this.paperAccent,
    paperInk: paperInk ?? this.paperInk,
    paperHighlight: paperHighlight ?? this.paperHighlight,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textTertiary: textTertiary ?? this.textTertiary,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    accentSoft: accentSoft ?? this.accentSoft,
    onAccentSoft: onAccentSoft ?? this.onAccentSoft,
    outline: outline ?? this.outline,
    hairline: hairline ?? this.hairline,
    shadow: shadow ?? this.shadow,
    radiusSmall: radiusSmall ?? this.radiusSmall,
    radiusMedium: radiusMedium ?? this.radiusMedium,
    radiusLarge: radiusLarge ?? this.radiusLarge,
    elevation: elevation ?? this.elevation,
    toolbarHeight: toolbarHeight ?? this.toolbarHeight,
    toolLabels: toolLabels ?? this.toolLabels,
    iconStrokeWidth: iconStrokeWidth ?? this.iconStrokeWidth,
  );

  @override
  StyleTokens lerp(covariant StyleTokens? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    double d(double a, double b) => lerpDouble(a, b, t)!;
    final near = t < 0.5 ? this : other;
    return StyleTokens(
      style: near.style,
      brightness: near.brightness,
      canvas: c(canvas, other.canvas),
      toolbar: c(toolbar, other.toolbar),
      panel: c(panel, other.panel),
      rail: c(rail, other.rail),
      card: c(card, other.card),
      inkSwatch: c(inkSwatch, other.inkSwatch),
      paperAccent: c(paperAccent, other.paperAccent),
      paperInk: c(paperInk, other.paperInk),
      paperHighlight: c(paperHighlight, other.paperHighlight),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      accent: c(accent, other.accent),
      onAccent: c(onAccent, other.onAccent),
      accentSoft: c(accentSoft, other.accentSoft),
      onAccentSoft: c(onAccentSoft, other.onAccentSoft),
      outline: c(outline, other.outline),
      hairline: c(hairline, other.hairline),
      shadow: c(shadow, other.shadow),
      radiusSmall: d(radiusSmall, other.radiusSmall),
      radiusMedium: d(radiusMedium, other.radiusMedium),
      radiusLarge: d(radiusLarge, other.radiusLarge),
      elevation: near.elevation,
      toolbarHeight: d(toolbarHeight, other.toolbarHeight),
      toolLabels: near.toolLabels,
      iconStrokeWidth: d(iconStrokeWidth, other.iconStrokeWidth),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StyleTokens &&
      other.style == style &&
      other.brightness == brightness &&
      other.canvas == canvas &&
      other.toolbar == toolbar &&
      other.panel == panel &&
      other.rail == rail &&
      other.card == card &&
      other.inkSwatch == inkSwatch &&
      other.paperAccent == paperAccent &&
      other.paperInk == paperInk &&
      other.paperHighlight == paperHighlight &&
      other.textPrimary == textPrimary &&
      other.textSecondary == textSecondary &&
      other.textTertiary == textTertiary &&
      other.accent == accent &&
      other.onAccent == onAccent &&
      other.accentSoft == accentSoft &&
      other.onAccentSoft == onAccentSoft &&
      other.outline == outline &&
      other.hairline == hairline &&
      other.shadow == shadow &&
      other.radiusSmall == radiusSmall &&
      other.radiusMedium == radiusMedium &&
      other.radiusLarge == radiusLarge &&
      other.elevation == elevation &&
      other.toolbarHeight == toolbarHeight &&
      other.toolLabels == toolLabels &&
      other.iconStrokeWidth == iconStrokeWidth;

  @override
  int get hashCode => Object.hashAll([
    style,
    brightness,
    canvas,
    toolbar,
    panel,
    rail,
    card,
    inkSwatch,
    paperAccent,
    paperInk,
    paperHighlight,
    textPrimary,
    textSecondary,
    textTertiary,
    accent,
    onAccent,
    accentSoft,
    onAccentSoft,
    outline,
    hairline,
    shadow,
    radiusSmall,
    radiusMedium,
    radiusLarge,
    elevation,
    toolbarHeight,
    toolLabels,
    iconStrokeWidth,
  ]);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(EnumProperty<AppStyle>('style', style))
      ..add(EnumProperty<Brightness>('brightness', brightness))
      ..add(ColorProperty('canvas', canvas))
      ..add(ColorProperty('toolbar', toolbar))
      ..add(ColorProperty('panel', panel))
      ..add(ColorProperty('accent', accent));
  }
}
