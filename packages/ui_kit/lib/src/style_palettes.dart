/// The token values of the three styles in light and dark (01-infra 14.2).
///
/// Light values come from the design mockups (ui-overhaul design-craft /
/// design-calm / design-pro); dark values keep each style's character:
/// craft = warm charcoal, calm = neutral graphite with the same single
/// accent, studio = the mockup's dark frame. Studio light is a cool grey
/// variant of the same frame.
library;

import 'package:material_ui/material_ui.dart';

import 'app_style.dart';
import 'style_tokens.dart';

/// The tokens of [style] in [brightness].
StyleTokens styleTokensFor(AppStyle style, Brightness brightness) =>
    switch ((style, brightness)) {
      (AppStyle.craft, Brightness.light) => _craftLight,
      (AppStyle.craft, Brightness.dark) => _craftDark,
      (AppStyle.calm, Brightness.light) => _calmLight,
      (AppStyle.calm, Brightness.dark) => _calmDark,
      (AppStyle.studio, Brightness.light) => _studioLight,
      (AppStyle.studio, Brightness.dark) => _studioDark,
    };

// --- A. 크래프트 ------------------------------------------------------------

const _craftLight = StyleTokens(
  style: AppStyle.craft,
  brightness: Brightness.light,
  canvas: Color(0xFFECE6DC), // warm desk
  toolbar: Color(0xFFFBF9F5), // paper
  panel: Color(0xFFFBF9F5),
  rail: Color(0xFFF4F0E8),
  card: Color(0xFFFFFFFF),
  inkSwatch: Color(0xFFFFFEFB),
  paperAccent: Color(0xFF2F5D8A),
  paperInk: Color(0xFF2A2825),
  paperHighlight: Color(0xFF8A5A2B),
  textPrimary: Color(0xFF2A2825),
  textSecondary: Color(0xFF615A50),
  textTertiary: Color(0xFF9A9285),
  accent: Color(0xFF2F5D8A), // ink blue
  onAccent: Color(0xFFFFFFFF),
  accentSoft: Color(0xFFE2EAF2),
  onAccentSoft: Color(0xFF1E3F60),
  outline: Color(0xFF8F8679),
  hairline: Color(0xFFE3DCD0),
  shadow: Color(0xFF3B2F1E),
  radiusSmall: 8,
  radiusMedium: 12,
  radiusLarge: 16,
  elevation: StyleElevation.soft,
  toolbarHeight: 64,
  toolLabels: ToolLabelMode.always,
  iconStrokeWidth: 1.7,
);

const _craftDark = StyleTokens(
  style: AppStyle.craft,
  brightness: Brightness.dark,
  canvas: Color(0xFF1B1916), // dark warm desk
  toolbar: Color(0xFF282521),
  panel: Color(0xFF2E2B26),
  rail: Color(0xFF221F1C),
  card: Color(0xFF34302B),
  inkSwatch: Color(0xFFF6F2EA),
  paperAccent: Color(0xFF2F5D8A),
  paperInk: Color(0xFF2A2825),
  paperHighlight: Color(0xFF8A5A2B),
  textPrimary: Color(0xFFEFE9DF),
  textSecondary: Color(0xFFBDB4A7),
  textTertiary: Color(0xFF857D72),
  accent: Color(0xFF8DB4DB),
  onAccent: Color(0xFF10263C),
  accentSoft: Color(0xFF2F3E4D),
  onAccentSoft: Color(0xFFD3E3F3),
  outline: Color(0xFF8C8478),
  hairline: Color(0xFF3F3A34),
  shadow: Color(0xFF000000),
  radiusSmall: 8,
  radiusMedium: 12,
  radiusLarge: 16,
  elevation: StyleElevation.soft,
  toolbarHeight: 64,
  toolLabels: ToolLabelMode.always,
  iconStrokeWidth: 1.7,
);

// --- B. 미니멀 --------------------------------------------------------------

const _calmLight = StyleTokens(
  style: AppStyle.calm,
  brightness: Brightness.light,
  canvas: Color(0xFFEDEBE6),
  toolbar: Color(0xFFFFFFFF),
  panel: Color(0xFFFFFFFF),
  rail: Color(0xFFF6F5F2),
  card: Color(0xFFF7F7F5),
  inkSwatch: Color(0xFFFDFDFB),
  paperAccent: Color(0xFF3F5BD9),
  paperInk: Color(0xFF1D1E22),
  paperHighlight: Color(0xFF8A5A2B),
  textPrimary: Color(0xFF1D1E22),
  textSecondary: Color(0xFF55585F),
  textTertiary: Color(0xFF9A9CA3),
  accent: Color(0xFF3F5BD9),
  onAccent: Color(0xFFFFFFFF),
  accentSoft: Color(0xFFE9EDFC),
  onAccentSoft: Color(0xFF243A9E),
  outline: Color(0xFF8E9098),
  hairline: Color(0xFFE5E3DE),
  shadow: Color(0xFF1D2440),
  radiusSmall: 10,
  radiusMedium: 14,
  radiusLarge: 20,
  elevation: StyleElevation.floating,
  toolbarHeight: 52,
  toolLabels: ToolLabelMode.onHover,
  iconStrokeWidth: 1.5,
);

const _calmDark = StyleTokens(
  style: AppStyle.calm,
  brightness: Brightness.dark,
  canvas: Color(0xFF151618),
  toolbar: Color(0xFF212225),
  panel: Color(0xFF26272A),
  rail: Color(0xFF1B1C1F),
  card: Color(0xFF2C2D31),
  inkSwatch: Color(0xFFF7F7F5),
  paperAccent: Color(0xFF3F5BD9),
  paperInk: Color(0xFF1D1E22),
  paperHighlight: Color(0xFF8A5A2B),
  textPrimary: Color(0xFFECEDEF),
  textSecondary: Color(0xFFAEB1B8),
  textTertiary: Color(0xFF74777E),
  accent: Color(0xFF93A6FF),
  onAccent: Color(0xFF121C4D),
  accentSoft: Color(0xFF2B3258),
  onAccentSoft: Color(0xFFDCE2FF),
  outline: Color(0xFF85888F),
  hairline: Color(0xFF35373B),
  shadow: Color(0xFF000000),
  radiusSmall: 10,
  radiusMedium: 14,
  radiusLarge: 20,
  elevation: StyleElevation.floating,
  toolbarHeight: 52,
  toolLabels: ToolLabelMode.onHover,
  iconStrokeWidth: 1.5,
);

// --- C. 스튜디오 ------------------------------------------------------------

const _studioLight = StyleTokens(
  style: AppStyle.studio,
  brightness: Brightness.light,
  canvas: Color(0xFFDDE0E5), // cool grey desk
  toolbar: Color(0xFFF3F4F6),
  panel: Color(0xFFFFFFFF),
  rail: Color(0xFFE8EAEE),
  card: Color(0xFFFFFFFF),
  inkSwatch: Color(0xFFFFFFFF),
  paperAccent: Color(0xFF2E62D9),
  paperInk: Color(0xFF16181C),
  paperHighlight: Color(0xFF8A5A2B),
  textPrimary: Color(0xFF16181C),
  textSecondary: Color(0xFF50565F),
  textTertiary: Color(0xFF8D939C),
  accent: Color(0xFF2E62D9),
  onAccent: Color(0xFFFFFFFF),
  accentSoft: Color(0xFFDCE6FB),
  onAccentSoft: Color(0xFF1A3F94),
  outline: Color(0xFF878D96),
  hairline: Color(0xFFD9DCE1),
  shadow: Color(0xFF0B0D12),
  radiusSmall: 6,
  radiusMedium: 8,
  radiusLarge: 12,
  elevation: StyleElevation.flat,
  toolbarHeight: 60,
  toolLabels: ToolLabelMode.always,
  iconStrokeWidth: 1.6,
);

const _studioDark = StyleTokens(
  style: AppStyle.studio,
  brightness: Brightness.dark,
  canvas: Color(0xFF2D3138), // the mockup's desk
  toolbar: Color(0xFF20242A), // bar
  panel: Color(0xFF2A2E35), // raised
  rail: Color(0xFF1B1E23),
  card: Color(0xFF32373F), // raised2
  inkSwatch: Color(0xFFF7F7F5),
  paperAccent: Color(0xFF2E62D9),
  paperInk: Color(0xFF16181C),
  paperHighlight: Color(0xFF8A5A2B),
  textPrimary: Color(0xFFF1F2F4),
  textSecondary: Color(0xFFA9AFB9),
  textTertiary: Color(0xFF6F7680),
  accent: Color(0xFF5B8CFF),
  onAccent: Color(0xFF0A1633),
  accentSoft: Color(0xFF283550),
  onAccentSoft: Color(0xFFD6E2FF),
  outline: Color(0xFF7D848F),
  hairline: Color(0xFF353A42),
  shadow: Color(0xFF000000),
  radiusSmall: 6,
  radiusMedium: 8,
  radiusLarge: 12,
  elevation: StyleElevation.flat,
  toolbarHeight: 60,
  toolLabels: ToolLabelMode.always,
  iconStrokeWidth: 1.6,
);
