// lib/src/state/settings/editor_device_state.dart — m5-7/04-editor 4.3.3,
// 6.11.6, 6.18, 6.20 (E2-01).
//
// EDITOR-internal per-device values, NOT exported: the web text input mode
// (developer menu), the shape-sample toggle (developer menu, P-B) and whether
// this device has seen a Pencil squeeze / barrel roll (the settings rows show
// only after that — contract 7.2.10 (v2.1), CD2-24). Stored under the device
// key editor.deviceState, written 500 ms after a change like
// EditorSettingsNotifier.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart' as core;

import '../debounced_writer.dart';
import 'editor_setting_keys.dart';

/// 6.11.6. Native is always inline; textarea is the P-C fallback B (E2-11).
enum WebTextInputMode { inline, sheet, textarea }

@immutable
class EditorDeviceState {
  const EditorDeviceState({
    this.webTextInput = WebTextInputMode.inline,
    this.collectShapeSamples = false,
    this.seenSqueeze = false,
    this.seenBarrelRoll = false,
  });

  /// Developer menu, web only (6.11.6).
  final WebTextInputMode webTextInput;

  /// Developer toggle '도형 표본 모으기' (6.20, U18) — default off.
  final bool collectShapeSamples;

  /// A squeeze / barrel roll event arrived on this device (6.5.1, CD2-24).
  final bool seenSqueeze, seenBarrelRoll;

  EditorDeviceState copyWith({
    WebTextInputMode? webTextInput,
    bool? collectShapeSamples,
    bool? seenSqueeze,
    bool? seenBarrelRoll,
  }) => EditorDeviceState(
    webTextInput: webTextInput ?? this.webTextInput,
    collectShapeSamples: collectShapeSamples ?? this.collectShapeSamples,
    seenSqueeze: seenSqueeze ?? this.seenSqueeze,
    seenBarrelRoll: seenBarrelRoll ?? this.seenBarrelRoll,
  );

  /// {"v":1,"webTextInput":"inline","collectShapeSamples":false,
  ///  "seenSqueeze":false,"seenBarrelRoll":false}
  Map<String, Object?> toJson() => {
    'v': 1,
    'webTextInput': webTextInput.name,
    'collectShapeSamples': collectShapeSamples,
    'seenSqueeze': seenSqueeze,
    'seenBarrelRoll': seenBarrelRoll,
  };

  /// Unknown / wrong-typed values → defaults, no report (values a newer app
  /// wrote, 1st-round rule).
  factory EditorDeviceState.fromJson(Map<String, Object?> json) {
    const d = EditorDeviceState();
    bool flag(String key, bool fallback) => switch (json[key]) {
      final bool b => b,
      _ => fallback,
    };
    final mode = json['webTextInput'];
    return EditorDeviceState(
      webTextInput: WebTextInputMode.values.firstWhere(
        (m) => m.name == mode,
        orElse: () => d.webTextInput,
      ),
      collectShapeSamples: flag('collectShapeSamples', d.collectShapeSamples),
      seenSqueeze: flag('seenSqueeze', d.seenSqueeze),
      seenBarrelRoll: flag('seenBarrelRoll', d.seenBarrelRoll),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EditorDeviceState &&
          other.webTextInput == webTextInput &&
          other.collectShapeSamples == collectShapeSamples &&
          other.seenSqueeze == seenSqueeze &&
          other.seenBarrelRoll == seenBarrelRoll;

  @override
  int get hashCode => Object.hash(
    webTextInput,
    collectShapeSamples,
    seenSqueeze,
    seenBarrelRoll,
  );

  @override
  String toString() =>
      'EditorDeviceState(${webTextInput.name}, samples: $collectShapeSamples, '
      'squeeze: $seenSqueeze, roll: $seenBarrelRoll)';
}

/// Debounce of editor.deviceState (same as the settings keys — 6.18).
const Duration _writeDelay = Duration(milliseconds: 500);

/// Root (all notes). build() returns the defaults synchronously, then loads
/// the stored value; a setter that runs before the load completes wins.
class EditorDeviceStateNotifier extends Notifier<EditorDeviceState> {
  late DebouncedSettingWriter _writer;
  int _generation = 0;
  bool _loaded = false;

  @override
  EditorDeviceState build() {
    final settings = ref.watch(core.settingsRepositoryProvider);
    final generation = ++_generation;
    _loaded = false;
    final writer = _writer = DebouncedSettingWriter(
      settings: settings,
      key: EditorSettingKeys.deviceState,
      delay: _writeDelay,
    );
    ref.onDispose(() {
      _generation++;
      writer.dispose();
    });
    unawaited(_load(settings, generation));
    return const EditorDeviceState();
  }

  /// True after the stored value has been read (or found absent).
  bool get isLoaded => _loaded;

  Future<void> _load(core.SettingsRepository settings, int generation) async {
    Map<String, Object?> json = const {};
    try {
      json = await settings.get(EditorSettingKeys.deviceState);
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'feature_editor',
          context: ErrorDescription('while loading the editor device state'),
        ),
      );
    }
    if (generation != _generation) return;
    _loaded = true;
    if (_writer.isPending) return; // a local change wins
    state = EditorDeviceState.fromJson(json);
  }

  void _update(EditorDeviceState next) {
    if (next == state) return;
    state = next;
    final json = next.toJson();
    _writer.schedule(() => json);
  }

  void setWebTextInput(WebTextInputMode mode) =>
      _update(state.copyWith(webTextInput: mode));

  void setCollectShapeSamples(bool on) =>
      _update(state.copyWith(collectShapeSamples: on));

  /// The first squeeze on this device (6.5.1): later ones change nothing.
  void markSeenSqueeze() => _update(state.copyWith(seenSqueeze: true));

  /// The first barrel roll on this device (6.5.1).
  void markSeenBarrelRoll() => _update(state.copyWith(seenBarrelRoll: true));

  /// Writes a pending change now (tests, leaving the screen).
  Future<void> flush() => _writer.flush();
}

final editorDeviceStateProvider =
    NotifierProvider<EditorDeviceStateNotifier, EditorDeviceState>(
      EditorDeviceStateNotifier.new,
      name: 'editorDeviceStateProvider',
    );
