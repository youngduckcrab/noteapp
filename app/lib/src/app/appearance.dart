/// '화면' settings: screen style and brightness (01-infra 14.3, contract
/// 7.4.4 v2.14-ui).
///
/// Both are device settings (SettingScope.device): how the screen looks is a
/// matter of the device (a dark tablet at night, a bright phone), and a
/// device key never syncs. NoteApp watches [appAppearanceProvider], so a
/// change applies at once, without a restart.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart'
    show SettingKey, SettingScope, settingsSnapshotProvider;
import 'package:ui_kit/ui_kit.dart';

/// Setting keys of the '화면' group (prefix `app.` — contract 7.4.4). The
/// stored values are the wire names of [AppStyle] / [AppBrightnessMode].
abstract final class AppearanceKeys {
  static final SettingKey<String> style = SettingKey.string(
    'app.appearance.style',
    AppStyle.fallback.wireName,
    scope: SettingScope.device,
  );
  static final SettingKey<String> brightness = SettingKey.string(
    'app.appearance.brightness',
    AppBrightnessMode.fallback.wireName,
    scope: SettingScope.device,
  );
}

/// The chosen style and brightness.
@immutable
final class AppAppearance {
  const AppAppearance({
    this.style = AppStyle.fallback,
    this.brightness = AppBrightnessMode.fallback,
  });

  /// From the stored wire names; unknown values → the defaults.
  factory AppAppearance.fromWire(String style, String brightness) =>
      AppAppearance(
        style: AppStyle.fromWire(style),
        brightness: AppBrightnessMode.fromWire(brightness),
      );

  final AppStyle style;
  final AppBrightnessMode brightness;

  /// MaterialApp.themeMode for [brightness].
  ThemeMode get themeMode => switch (brightness) {
    AppBrightnessMode.system => ThemeMode.system,
    AppBrightnessMode.light => ThemeMode.light,
    AppBrightnessMode.dark => ThemeMode.dark,
  };

  @override
  bool operator ==(Object other) =>
      other is AppAppearance &&
      other.style == style &&
      other.brightness == brightness;

  @override
  int get hashCode => Object.hash(style, brightness);

  @override
  String toString() =>
      'AppAppearance(${style.wireName}, ${brightness.wireName})';
}

/// The appearance read once during start-up (AppModuleContext
/// .resolveAppearance, overridden in BootstrapSuccess.overrides): NoteApp's
/// first frames use it while the settings snapshot is still loading, so a
/// non-default style does not flash the default one at every cold start.
/// Without an override: the defaults.
final initialAppearanceProvider = Provider<AppAppearance>(
  (ref) => const AppAppearance(),
  name: 'initialAppearanceProvider',
);

/// The appearance from the settings snapshot; [initialAppearanceProvider]
/// while the snapshot loads, when it failed, or without a store.
final appAppearanceProvider = Provider<AppAppearance>((ref) {
  final snapshot = ref.watch(settingsSnapshotProvider).value;
  if (snapshot == null) return ref.watch(initialAppearanceProvider);
  return AppAppearance.fromWire(
    snapshot.get(AppearanceKeys.style),
    snapshot.get(AppearanceKeys.brightness),
  );
}, name: 'appAppearanceProvider');
