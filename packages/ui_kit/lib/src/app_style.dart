/// The user-selectable screen styles ('화면 스타일', contract 7.1 v2.14-ui).
library;

/// One of the three screen styles. [wireName] is what the settings store
/// keeps: it never changes, even if an enum value is renamed.
enum AppStyle {
  /// A. 크래프트 — warm paper, top toolbar (the default).
  craft('craft'),

  /// B. 미니멀 — near-white neutral, one accent, slim floating bar.
  calm('calm'),

  /// C. 스튜디오 — cool grey frame (dark: the mockup's dark frame).
  studio('studio');

  const AppStyle(this.wireName);

  /// Stable stored name.
  final String wireName;

  /// The default style.
  static const AppStyle fallback = AppStyle.craft;

  /// The style stored as [wire]; an unknown or missing value → [fallback].
  static AppStyle fromWire(String? wire) {
    for (final style in values) {
      if (style.wireName == wire) return style;
    }
    return fallback;
  }
}

/// How bright the screen is ('밝기'): follow the system, or force one.
enum AppBrightnessMode {
  /// 시스템 따라 (the default).
  system('system'),

  /// 밝게.
  light('light'),

  /// 어둡게.
  dark('dark');

  const AppBrightnessMode(this.wireName);

  /// Stable stored name.
  final String wireName;

  /// The default mode.
  static const AppBrightnessMode fallback = AppBrightnessMode.system;

  /// The mode stored as [wire]; an unknown or missing value → [fallback].
  static AppBrightnessMode fromWire(String? wire) {
    for (final mode in values) {
      if (mode.wireName == wire) return mode;
    }
    return fallback;
  }
}
