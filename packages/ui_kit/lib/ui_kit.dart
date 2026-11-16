/// Shared design layer (INFRA, docs/plans/m5-7/01-infra.md 14, contract
/// 00-overview 7.1 v2.14-ui): the three screen styles, their light and dark
/// [StyleTokens] and the [ThemeData] built from them.
///
/// UI packages read [StyleTokens.of] (a theme without the extension falls
/// back to the [ColorScheme] roles); only the app builds themes.
library;

export 'src/app_style.dart' show AppBrightnessMode, AppStyle;
export 'src/build_theme.dart'
    show buildStyleTheme, buildThemeFromTokens, styleColorScheme;
export 'src/contrast.dart' show contrastRatio;
export 'src/pen_art.dart'
    show EraserArtPainter, PenArtColors, PenArtKind, PenArtPainter;
export 'src/pen_tray_style.dart' show PenTrayLook, PenTrayStyle;
export 'src/style_palettes.dart' show styleTokensFor;
export 'src/style_tokens.dart' show StyleElevation, StyleTokens, ToolLabelMode;
