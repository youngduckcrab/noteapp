// lib/src/state/settings/editor_settings_notifier.dart — contract 00-overview
// 7.2.17, 04-editor 4.8; stored form 6.14.
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../debounced_writer.dart';
import 'editor_setting_keys.dart';
import 'editor_settings.dart';

/// Debounce of the two settings keys (04-editor 6.14: '변경 500ms 뒤').
const Duration _writeDelay = Duration(milliseconds: 500);

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
/// A setter that runs before the load completes wins for its key: the loaded
/// value of a key with a pending write is not applied. Stored fields with
/// invalid values decode to their defaults and are reported once per load
/// (FlutterError.reportError, library 'feature_editor').
class EditorSettingsNotifier extends Notifier<EditorSettings> {
  late DebouncedSettingWriter _deviceWriter;
  late DebouncedSettingWriter _syncedWriter;
  StreamSubscription<Map<String, Object?>>? _remote;
  final List<Future<void>> _resets = [];
  bool _loaded = false;
  int _generation = 0;

  @override
  EditorSettings build() {
    final settings = ref.watch(core.settingsRepositoryProvider);
    final generation = ++_generation;
    _loaded = false;
    final deviceWriter = _deviceWriter = DebouncedSettingWriter(
      settings: settings,
      key: EditorSettingKeys.deviceSettings,
      delay: _writeDelay,
    );
    final syncedWriter = _syncedWriter = DebouncedSettingWriter(
      settings: settings,
      key: EditorSettingKeys.syncedSettings,
      delay: _writeDelay,
    );
    ref.onDispose(() {
      _generation++;
      deviceWriter.dispose();
      syncedWriter.dispose();
      unawaited(_remote?.cancel());
      _remote = null;
    });
    unawaited(_load(settings, generation));
    return const EditorSettings();
  }

  /// True after the stored values have been read (or found absent / undecodable).
  bool get isLoaded => _loaded;

  Future<void> _load(core.SettingsRepository settings, int generation) async {
    Map<String, Object?> device = const {};
    Map<String, Object?> synced = const {};
    try {
      device = await settings.get(EditorSettingKeys.deviceSettings);
      synced = await settings.get(EditorSettingKeys.syncedSettings);
    } on Object catch (error, stack) {
      _report(error, stack, 'while loading the editor settings');
    }
    if (generation != _generation) return; // rebuilt or disposed meanwhile
    _reportInvalidFields(device, core.SettingScope.device);
    _reportInvalidFields(synced, core.SettingScope.synced);
    final loaded = EditorSettings.fromJson(device: device, synced: synced);
    final current = state;
    state = EditorSettings.fromJson(
      device: (_deviceWriter.isPending ? current : loaded).toJson(
        core.SettingScope.device,
      ),
      synced: (_syncedWriter.isPending ? current : loaded).toJson(
        core.SettingScope.synced,
      ),
    );
    _loaded = true;
    _pushPressureMode();
    _remote = settings
        .watch(EditorSettingKeys.syncedSettings)
        .listen(
          _onRemoteSynced,
          onError: (Object error, StackTrace stack) =>
              _report(error, stack, 'while watching the synced settings'),
        );
  }

  /// Another device's value (M4), or our own write coming back.
  void _onRemoteSynced(Map<String, Object?> json) {
    if (_syncedWriter.isOwnEcho(json)) return;
    // A local change waiting to be written wins over the stored value.
    if (_syncedWriter.isPending) return;
    final current = state;
    final next = EditorSettings.fromJson(
      device: current.toJson(core.SettingScope.device),
      synced: json,
    );
    if (next != current) state = next;
  }

  void _update(EditorSettings next) {
    final previous = state;
    if (next == previous) return;
    state = next;
    // The snapshot is taken now: writers may run from onDispose, where
    // provider state must not be read.
    final device = next.toJson(core.SettingScope.device);
    final synced = next.toJson(core.SettingScope.synced);
    if (!_sameJson(previous.toJson(core.SettingScope.device), device)) {
      _deviceWriter.schedule(() => device);
    }
    if (!_sameJson(previous.toJson(core.SettingScope.synced), synced)) {
      _syncedWriter.schedule(() => synced);
    }
  }

  static bool _sameJson(Map<String, Object?> a, Map<String, Object?> b) =>
      const DeepCollectionEquality().equals(a, b);

  void setInputMode(InputMode mode) => _update(state.copyWith(inputMode: mode));

  void setPalmRejection(PalmRejectionSettings value) =>
      _update(state.copyWith(palmRejection: value));

  void setGestures(GestureSettings value) =>
      _update(state.copyWith(gestures: value));

  void setPageFlipMode(PageFlipMode mode) =>
      _update(state.copyWith(pageFlipMode: mode));

  void setPressureMode(ink.PressureMode mode) {
    _update(state.copyWith(pressureMode: mode));
    _pushPressureMode();
  }

  void setShowDevOverlay(bool value) =>
      _update(state.copyWith(showDevOverlay: value));

  void toggleDevOverlay() =>
      _update(state.copyWith(showDevOverlay: !state.showDevOverlay));

  /// Called by the input router the first time a stylus is seen.
  void markStylusSeen() {
    if (state.stylusSeen) return;
    _update(state.copyWith(stylusSeen: true));
  }

  /// Resets both keys (core.SettingsRepository.reset) and pushes PressureMode.auto to INK.
  void resetToDefaults() {
    _deviceWriter.cancel();
    _syncedWriter.cancel();
    state = const EditorSettings();
    final settings = ref.read(core.settingsRepositoryProvider);
    _resets.add(_reset(settings, EditorSettingKeys.deviceSettings));
    _resets.add(_reset(settings, EditorSettingKeys.syncedSettings));
    _pushPressureMode();
  }

  Future<void> _reset(
    core.SettingsRepository settings,
    core.SettingKey<Map<String, Object?>> key,
  ) async {
    try {
      await settings.reset(key);
    } on Object catch (error, stack) {
      _report(error, stack, 'while resetting ${key.name}');
    }
  }

  /// Writes pending debounced values now (EditorCommands.flushAll, 6.17).
  Future<void> flush() async {
    final resets = List.of(_resets);
    _resets.clear();
    await Future.wait([
      _deviceWriter.flush(),
      _syncedWriter.flush(),
      ...resets,
    ]);
  }

  /// Contract 7.3.3: INK's pressure mode follows the editor setting. Called
  /// after the load and from setters, never from build() (04-editor 6.13.1 #7).
  void _pushPressureMode() {
    ref.read(ink.pressureModeProvider.notifier).set(state.pressureMode);
  }

  void _reportInvalidFields(
    Map<String, Object?> stored,
    core.SettingScope scope,
  ) {
    final device = scope == core.SettingScope.device;
    final decoded = EditorSettings.fromJson(
      device: device ? stored : const {},
      synced: device ? const {} : stored,
    ).toJson(scope);
    final invalid = <String>[];
    _collectInvalid(stored, decoded, '', invalid);
    if (invalid.isEmpty) return;
    final key = device
        ? EditorSettingKeys.deviceSettings
        : EditorSettingKeys.syncedSettings;
    _report(
      FormatException(
        'Invalid values in ${key.name} replaced by defaults: '
        '${invalid.join(', ')}',
      ),
      null,
      'while loading the editor settings',
    );
  }

  /// Paths of known fields whose stored value did not survive decoding.
  /// Unknown fields, "v" and the draft pressure names are not errors.
  static void _collectInvalid(
    Map<String, Object?> stored,
    Map<String, Object?> decoded,
    String prefix,
    List<String> out,
  ) {
    for (final MapEntry(:key, :value) in stored.entries) {
      if (key == 'v' || !decoded.containsKey(key)) continue;
      final path = '$prefix$key';
      final expected = decoded[key];
      if (path == 'pressure' && (value == 'always' || value == 'never')) {
        continue;
      }
      if (value is Map && expected is Map<String, Object?>) {
        _collectInvalid(
          {
            for (final e in value.entries)
              if (e.key case final String k) k: e.value,
          },
          expected,
          '$path.',
          out,
        );
      } else if (value is num && expected is num) {
        if ((value - expected).abs() > 0.5) out.add(path);
      } else if (value is bool && expected is bool) {
        // Every bool field takes both values. A v1.4 gesture bool can decode
        // differently when "actions" has that gesture (m5-7/04-editor 4.3.2
        // '옛 앱과 섞일 때') — that is not an invalid value.
      } else if (value != expected) {
        out.add(path);
      }
    }
  }

  void _report(Object error, StackTrace? stack, String context) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'feature_editor',
        context: ErrorDescription(context),
      ),
    );
  }
}

final editorSettingsProvider =
    NotifierProvider<EditorSettingsNotifier, EditorSettings>(
      EditorSettingsNotifier.new,
      name: 'editorSettingsProvider',
    );
