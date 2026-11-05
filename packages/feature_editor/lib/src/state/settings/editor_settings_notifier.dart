// lib/src/state/settings/editor_settings_notifier.dart — contract 00-overview
// 7.2.17, 04-editor 4.8.
//
// Foundation step B5 (contract 7.6): memory only. The values are not read
// from or written to core.SettingsRepository yet; task E-06 adds the load,
// the 500 ms debounced writers, the remote watch and EditorSettingKeys.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;

import 'editor_settings.dart';

/// Global (not per note). build() returns defaults synchronously, then loads
/// EditorSettingKeys.deviceSettings and EditorSettingKeys.syncedSettings from
/// core.SettingsRepository and replaces the state. Every setter persists through
/// a 500 ms debounced writer (only the key whose fields changed).
///
/// ink.pressureModeProvider bridge (contract 7.3.3): after the load completes
/// (after an await — never inside build(), V4) and in setPressureMode(), calls
/// ref.read(ink.pressureModeProvider.notifier).set(state.pressureMode).
///
/// Remote updates (M4): listens to settings.watch(EditorSettingKeys.syncedSettings)
/// and applies values that differ from the last value this notifier wrote.
///
/// Foundation step B5: memory only — build() returns the defaults and nothing
/// is loaded or persisted until E-06. The INK bridge already runs in
/// setPressureMode() and resetToDefaults().
class EditorSettingsNotifier extends Notifier<EditorSettings> {
  @override
  EditorSettings build() => const EditorSettings();

  /// True after the stored values have been read (or found absent / undecodable).
  ///
  /// B5: always true — there is nothing to read yet.
  bool get isLoaded => true;

  void setInputMode(InputMode mode) {
    state = state.copyWith(inputMode: mode);
  }

  void setPalmRejection(PalmRejectionSettings value) {
    state = state.copyWith(palmRejection: value);
  }

  void setGestures(GestureSettings value) {
    state = state.copyWith(gestures: value);
  }

  void setPageFlipMode(PageFlipMode mode) {
    state = state.copyWith(pageFlipMode: mode);
  }

  void setPressureMode(ink.PressureMode mode) {
    state = state.copyWith(pressureMode: mode);
    _pushPressureMode();
  }

  void setShowDevOverlay(bool value) {
    state = state.copyWith(showDevOverlay: value);
  }

  void toggleDevOverlay() {
    state = state.copyWith(showDevOverlay: !state.showDevOverlay);
  }

  /// Called by the input router the first time a stylus is seen.
  void markStylusSeen() {
    if (state.stylusSeen) return;
    state = state.copyWith(stylusSeen: true);
  }

  /// Resets both keys (core.SettingsRepository.reset) and pushes PressureMode.auto to INK.
  ///
  /// B5: resets the in-memory state only.
  void resetToDefaults() {
    state = const EditorSettings();
    _pushPressureMode();
  }

  /// Writes pending debounced values now (EditorCommands.flushAll, 6.17).
  ///
  /// B5: nothing is pending, completes right away.
  Future<void> flush() => Future<void>.value();

  /// Contract 7.3.3: INK's pressure mode follows the editor setting. Called
  /// from setters only, never from build() (04-editor 6.13.1 #7).
  void _pushPressureMode() {
    ref.read(ink.pressureModeProvider.notifier).set(state.pressureMode);
  }
}

final editorSettingsProvider =
    NotifierProvider<EditorSettingsNotifier, EditorSettings>(
      EditorSettingsNotifier.new,
      name: 'editorSettingsProvider',
    );
