import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

/// The app theme of [style] in [brightness] (01-infra 14.3): ui_kit's
/// [buildStyleTheme] — a Material 3 scheme from the style tokens, the
/// component themes and the [StyleTokens] extension. Packages read
/// `Theme.of(context).colorScheme` and [StyleTokens.of] (계약 7.4.11,
/// v2.14-ui); the app holds no colour constant of its own.
ThemeData buildAppTheme({
  AppStyle style = AppStyle.fallback,
  Brightness brightness = Brightness.light,
}) => buildStyleTheme(style, brightness);
