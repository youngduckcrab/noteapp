// lib/src/state/settings/editor_setting_keys.dart — 04-editor 6.14.
//
// Every CORE setting key of the editor: JSON objects whose first field is
// "v": 1, names with the 'editor.' prefix, scopes by contract 7.4.6 (values
// that differ per device are `device`, user taste is `synced`).
import 'package:note_core/note_core.dart' as core;

abstract final class EditorSettingKeys {
  // device — values that differ per device (contract 7.4.6)
  static final deviceSettings = core.SettingKey.jsonMap(
    'editor.settings.device',
    scope: core.SettingScope.device,
  );
  static final toolSelection = core.SettingKey.jsonMap(
    'editor.toolSelection',
    scope: core.SettingScope.device,
  );
  static final viewport = core.SettingKey.jsonMap(
    'editor.viewport',
    scope: core.SettingScope.device,
  );
  static final presetBar = core.SettingKey.jsonMap(
    'editor.presetBar',
    scope: core.SettingScope.device,
  );
  // synced — user taste (contract 7.4.6)
  static final syncedSettings = core.SettingKey.jsonMap(
    'editor.settings.synced',
    scope: core.SettingScope.synced,
  );
  static final penStyles = core.SettingKey.jsonMap(
    'editor.penStyles',
    scope: core.SettingScope.synced,
  );
  static final eraser = core.SettingKey.jsonMap(
    'editor.eraser',
    scope: core.SettingScope.synced,
  );
  static final colors = core.SettingKey.jsonMap(
    'editor.colors',
    scope: core.SettingScope.synced,
  );

  static List<core.SettingKey<Map<String, Object?>>> get all => [
    deviceSettings,
    toolSelection,
    viewport,
    presetBar,
    syncedSettings,
    penStyles,
    eraser,
    colors,
  ];
}
