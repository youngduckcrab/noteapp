/// '화면' settings: 홈 화면 스타일, 필기 화면 스타일 and brightness (01-infra
/// 14.3, contract 7.4.4 v2.14-ui).
///
/// All are device settings (SettingScope.device): how the screen looks is a
/// matter of the device (a dark tablet at night, a bright phone), and a
/// device key never syncs. NoteApp watches [appAppearanceProvider], so a
/// change applies at once, without a restart.
///
/// (v2.14-ui split) The home style themes the app (library, folders, trash,
/// search, settings and the dialogs opened from them); the editor style
/// themes the note-editor route (EditorStyleScope). Brightness stays one
/// app-wide setting.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart'
    show SettingKey, SettingScope, SettingsSnapshot, settingsSnapshotProvider;
import 'package:ui_kit/ui_kit.dart';

/// Setting keys of the '화면' group (prefix `app.` — contract 7.4.4). The
/// stored values are the wire names of [AppStyle] / [AppBrightnessMode].
abstract final class AppearanceKeys {
  /// 홈 화면 스타일 (default 크래프트).
  static final SettingKey<String> homeStyle = SettingKey.string(
    'app.appearance.homeStyle',
    AppStyle.fallback.wireName,
    scope: SettingScope.device,
  );

  /// 필기 화면 스타일 (default 크래프트).
  static final SettingKey<String> editorStyle = SettingKey.string(
    'app.appearance.editorStyle',
    AppStyle.fallback.wireName,
    scope: SettingScope.device,
  );

  /// The one '화면 스타일' of stage 1 (read only): while a new key is not
  /// stored, it takes this value, so the earlier choice is kept for both.
  static final SettingKey<String> legacyStyle = SettingKey.string(
    'app.appearance.style',
    AppStyle.fallback.wireName,
    scope: SettingScope.device,
  );

  /// (UI stage 2) '펜을 띄우면 이름 보기': a stylus (or mouse) held over an
  /// icon-only button shows its name (ui_kit HoverName). Default on.
  static final SettingKey<bool> hoverNames = SettingKey.boolean(
    'app.appearance.hoverNames',
    true,
    scope: SettingScope.device,
  );

  static final SettingKey<String> brightness = SettingKey.string(
    'app.appearance.brightness',
    AppBrightnessMode.fallback.wireName,
    scope: SettingScope.device,
  );

  /// [homeStyle] / [editorStyle] / [legacyStyle] read as null while not
  /// stored (or undecodable) — the migration needs to tell "not stored"
  /// from "stored craft".
  static SettingKey<String?> storedOrNull(SettingKey<String> key) =>
      SettingKey<String?>(
        key.name,
        defaultValue: null,
        encode: (value) => value,
        decode: (json) => json! as String,
        scope: key.scope,
      );
}

/// The chosen styles and brightness.
@immutable
final class AppAppearance {
  const AppAppearance({
    this.homeStyle = AppStyle.fallback,
    this.editorStyle = AppStyle.fallback,
    this.brightness = AppBrightnessMode.fallback,
    this.hoverNames = true,
  });

  /// From the stored wire names; unknown values → the defaults. A missing
  /// (null) [homeStyle] / [editorStyle] takes [legacyStyle] (stage 1's one
  /// style setting), then the default.
  factory AppAppearance.fromWire({
    String? homeStyle,
    String? editorStyle,
    String? legacyStyle,
    String? brightness,
    bool hoverNames = true,
  }) => AppAppearance(
    homeStyle: AppStyle.fromWire(homeStyle ?? legacyStyle),
    editorStyle: AppStyle.fromWire(editorStyle ?? legacyStyle),
    brightness: AppBrightnessMode.fromWire(brightness),
    hoverNames: hoverNames,
  );

  /// From a settings snapshot (see [AppAppearance.fromWire]).
  factory AppAppearance.fromSnapshot(SettingsSnapshot snapshot) =>
      AppAppearance.fromWire(
        homeStyle: snapshot.get(
          AppearanceKeys.storedOrNull(AppearanceKeys.homeStyle),
        ),
        editorStyle: snapshot.get(
          AppearanceKeys.storedOrNull(AppearanceKeys.editorStyle),
        ),
        legacyStyle: snapshot.get(
          AppearanceKeys.storedOrNull(AppearanceKeys.legacyStyle),
        ),
        brightness: snapshot.get(AppearanceKeys.brightness),
        hoverNames: snapshot.get(AppearanceKeys.hoverNames),
      );

  final AppStyle homeStyle;
  final AppStyle editorStyle;
  final AppBrightnessMode brightness;

  /// (UI stage 2) '펜을 띄우면 이름 보기' ([AppearanceKeys.hoverNames]).
  final bool hoverNames;

  /// MaterialApp.themeMode for [brightness].
  ThemeMode get themeMode => switch (brightness) {
    AppBrightnessMode.system => ThemeMode.system,
    AppBrightnessMode.light => ThemeMode.light,
    AppBrightnessMode.dark => ThemeMode.dark,
  };

  /// The brightness shown for [brightness] when the platform is
  /// [platform] — what MaterialApp resolves [themeMode] to.
  Brightness effectiveBrightness(Brightness platform) => switch (brightness) {
    AppBrightnessMode.system => platform,
    AppBrightnessMode.light => Brightness.light,
    AppBrightnessMode.dark => Brightness.dark,
  };

  @override
  bool operator ==(Object other) =>
      other is AppAppearance &&
      other.homeStyle == homeStyle &&
      other.editorStyle == editorStyle &&
      other.brightness == brightness &&
      other.hoverNames == hoverNames;

  @override
  int get hashCode =>
      Object.hash(homeStyle, editorStyle, brightness, hoverNames);

  @override
  String toString() =>
      'AppAppearance(home: ${homeStyle.wireName}, '
      'editor: ${editorStyle.wireName}, ${brightness.wireName}'
      '${hoverNames ? '' : ', no hover names'})';
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
  return AppAppearance.fromSnapshot(snapshot);
}, name: 'appAppearanceProvider');
