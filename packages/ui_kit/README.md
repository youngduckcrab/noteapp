# ui_kit — owned by INFRA: the shared design layer. Plan: [docs/plans/m5-7/01-infra.md](../../docs/plans/m5-7/01-infra.md) 14, contract [00-overview 7.1 / 7.9 v2.14-ui](../../docs/plans/m5-7/00-overview.md)

The three user-selectable screen styles ('화면 스타일') and their light and dark values, as one `ThemeExtension` every UI package can read. No dependency on any other workspace member (only `flutter` and `material_ui`), so `feature_editor`, `feature_library`, `pdf_io`, `media_io`, `ink_recognition` and the app may all depend on it (R8).

## Entry point `package:ui_kit/ui_kit.dart`

- `AppStyle` — `craft` (크래프트, default), `calm` (미니멀), `studio` (스튜디오). `wireName` is what the settings store keeps and never changes; `fromWire` falls back to `craft`.
- `AppBrightnessMode` — `system` (default), `light`, `dark`; same wire rules.
- `StyleTokens` (`ThemeExtension`) — surfaces (`canvas` around the pages, `toolbar`, `panel`, `rail`, `card`), `inkSwatch` (paper-light background for ink previews), marks on paper (`paperAccent`, `paperInk`, `paperHighlight`), text (`textPrimary`, `textSecondary`, `textTertiary`), the one accent (`accent`, `onAccent`, `accentSoft`, `onAccentSoft`), lines (`outline`, `hairline`), `shadow`, radii, `elevation` (`StyleElevation`), and layout hints for later stages (`toolbarHeight`, `toolLabels`, `iconStrokeWidth`). `StyleTokens.of(context)` returns the theme's tokens or, for a theme without them, `StyleTokens.fromScheme` — every token mapped to the `ColorScheme` role the UI used before, so a plain test theme looks exactly as before. Helpers: `shadows(level)`, `materialElevation(level)`, `swatchRing(swatch, background)`.
- `styleTokensFor(style, brightness)` — the six token sets.
- `buildStyleTheme(style, brightness)` / `buildThemeFromTokens(tokens)` — Material 3 `ThemeData`: a `ColorScheme` built from the tokens (`styleColorScheme`), component themes (app bar, popup menus, menus, bottom sheets, dialogs, drawer, cards, dividers, sliders, segmented buttons, chips, switches, list tiles, snack bars, tooltips) and the extension.
- `contrastRatio(a, b)` — WCAG contrast (tests: text ≥ 4.5:1, icons ≥ 3:1).

## Rules

- Page paper and ink colours are document data, not tokens: in a dark style only the chrome and the canvas around the pages darken.
- UI packages never hard-code chrome colours (`tool/test/ui_colors_test.dart` guards their `lib/`); ui_kit is the only place colour values live.
