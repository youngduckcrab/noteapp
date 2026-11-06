// lib/src/state/settings/pre_roll.dart — m5-7/04-editor 6.19 (review S-10),
// 6.18, contract R-5 (E2-03).
//
// editor.playback.preRollMs (synced, the one integer key): how far before
// the tapped stroke tap-to-seek starts playing. Default 1500, clamped to
// [0, 5000]; written 500 ms after a change (1st-round setter rule); a change
// made before the load wins; the key follows settings.watch (own echo
// ignored). Tap-to-seek (6.15.3) and the settings slider read only this.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart' as core;

import 'editor_setting_keys.dart';

class PreRollMsNotifier extends Notifier<int> {
  static const int defaultMs = 1500, minMs = 0, maxMs = 5000;
  static const Duration writeDelay = Duration(milliseconds: 500);

  late core.SettingsRepository _settings;
  Timer? _timer;
  int? _pending;
  int? _lastWritten;
  Future<void> _inFlight = Future<void>.value();
  StreamSubscription<int>? _remote;
  int _generation = 0;

  /// [ms] clamped to [minMs, maxMs].
  static int clampMs(int ms) => ms.clamp(minMs, maxMs);

  @override
  int build() {
    _settings = ref.watch(core.settingsRepositoryProvider);
    final generation = ++_generation;
    ref.onDispose(() {
      _generation++;
      unawaited(flush());
      _timer?.cancel();
      unawaited(_remote?.cancel());
      _remote = null;
    });
    unawaited(_load(generation));
    return defaultMs;
  }

  void set(int ms) {
    final value = clampMs(ms);
    if (value == state) return;
    state = value;
    _pending = value;
    _timer?.cancel();
    _timer = Timer(writeDelay, _write);
  }

  /// Writes a pending value now.
  Future<void> flush() {
    if (_pending != null) _write();
    return _inFlight;
  }

  void _write() {
    _timer?.cancel();
    _timer = null;
    final value = _pending;
    _pending = null;
    if (value == null) return;
    _lastWritten = value;
    final settings = _settings;
    final previous = _inFlight;
    _inFlight = () async {
      await previous;
      try {
        await settings.set(EditorSettingKeys.playbackPreRollMs, value);
      } on Object catch (error, stack) {
        _report(error, stack, 'while writing the pre-roll');
      }
    }();
  }

  Future<void> _load(int generation) async {
    int stored = defaultMs;
    try {
      stored = await _settings.get(EditorSettingKeys.playbackPreRollMs);
    } on Object catch (error, stack) {
      _report(error, stack, 'while loading the pre-roll');
    }
    if (generation != _generation) return;
    if (_pending == null && _lastWritten == null) state = clampMs(stored);
    _remote = _settings.watch(EditorSettingKeys.playbackPreRollMs).listen(
      (value) {
        if (_pending != null || value == _lastWritten) return;
        final next = clampMs(value);
        if (next != state) state = next;
      },
      onError: (Object error, StackTrace stack) =>
          _report(error, stack, 'while watching the pre-roll'),
    );
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

/// Global (all notes) — 6.19.
final editorPreRollMsProvider = NotifierProvider<PreRollMsNotifier, int>(
  PreRollMsNotifier.new,
  name: 'editorPreRollMsProvider',
);
