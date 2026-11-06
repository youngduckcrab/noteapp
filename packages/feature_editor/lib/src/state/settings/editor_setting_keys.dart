// lib/src/state/settings/editor_setting_keys.dart — 04-editor 6.14;
// (v2) m5-7/04-editor 6.18: editor.deviceState (E2-01), editor.toolOptions
// and editor.playback.preRollMs (E2-03).
//
// Every CORE setting key of the editor: JSON objects whose first field is
// "v": 1, names with the 'editor.' prefix, scopes by contract 7.4.6 (values
// that differ per device are `device`, user taste is `synced`). (v2)
// editor.playback.preRollMs is the one integer key (contract R-5, 7.4.4
// (v2.1) — the exception to the jsonMap convention).
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

  /// (v2, E2-01) EDITOR-internal device state: web text input mode, the
  /// shape-sample toggle, the first Pencil squeeze / barrel-roll events
  /// (m5-7/04-editor 4.3.3 EditorDeviceState).
  static final deviceState = core.SettingKey.jsonMap(
    'editor.deviceState',
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

  /// (v2, E2-03) Shape and text tool defaults (6.2.4 ToolOptions.toJson).
  static final toolOptions = core.SettingKey.jsonMap(
    'editor.toolOptions',
    scope: core.SettingScope.synced,
  );

  /// (v2, E2-03) Tap-to-seek pre-roll in ms (R-5): default 1500, [0, 5000].
  static final playbackPreRollMs = core.SettingKey.integer(
    'editor.playback.preRollMs',
    1500,
    scope: core.SettingScope.synced,
  );

  /// (v2.1, review S-10) `SettingKey<Object?>` so the integer key fits too.
  static List<core.SettingKey<Object?>> get all => [
    deviceSettings,
    toolSelection,
    viewport,
    presetBar,
    deviceState,
    syncedSettings,
    penStyles,
    eraser,
    colors,
    toolOptions,
    playbackPreRollMs,
  ];
}
