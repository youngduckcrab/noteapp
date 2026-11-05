import 'package:material_ui/material_ui.dart';

/// Seed of the app's Material 3 color scheme (docs/plans/01-infra.md 4.4).
/// The one shell color constant; everything else reads `colorScheme`
/// (계약 7.4.11).
const Color _seedColor = Color(0xFF3949AB);

/// Material 3 theme from [_seedColor]. Packages only read
/// `Theme.of(context).colorScheme`. [brightness] is there for dark mode later
/// (PLAN 5.2); the app uses light only for now.
ThemeData buildAppTheme({Brightness brightness = Brightness.light}) =>
    ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: brightness,
      ),
    );
