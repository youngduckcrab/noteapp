import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

/// The app theme of [style] in [brightness] (01-infra 14.3): ui_kit's
/// [buildStyleTheme] — a Material 3 scheme from the style tokens, the
/// component themes and the [StyleTokens] extension. Packages read
/// `Theme.of(context).colorScheme` and [StyleTokens.of] (계약 7.4.11,
/// v2.14-ui); the app holds no colour constant of its own.
///
/// Built once per (style, brightness, platform): NoteApp and EditorStyleScope
/// get the same instance on every rebuild, so a Theme whose data did not
/// change does not compare two fresh ThemeData objects. The platform is part
/// of the key because ThemeData takes [defaultTargetPlatform] (typography,
/// page transitions, scroll physics) when it is built — tests that override
/// the platform must not get a theme built for another one.
ThemeData buildAppTheme({
  AppStyle style = AppStyle.fallback,
  Brightness brightness = Brightness.light,
}) => _themes.putIfAbsent((
  style,
  brightness,
  defaultTargetPlatform,
), () => buildStyleTheme(style, brightness));

final Map<(AppStyle, Brightness, TargetPlatform), ThemeData> _themes = {};
