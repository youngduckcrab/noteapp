// lib/src/state/debounced_writer.dart — 04-editor 6.14.
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

/// Debounced core.SettingsRepository.set for one key.
///
/// [schedule] (re)starts the timer: a burst of changes writes once, [delay]
/// after the last one, with the snapshot taken at write time. The write
/// Future follows the CORE rule (contract 7.2.9 v1.2): it stays pending while
/// a failed commit is retried, so [flush] has no timeout. A write that fails
/// without retry (argument error) is reported, never thrown.
class DebouncedSettingWriter {
  DebouncedSettingWriter({
    required this.settings,
    required this.key,
    required this.delay,
  });

  final core.SettingsRepository settings;
  final core.SettingKey<Map<String, Object?>> key;
  final Duration delay;

  Timer? _timer;
  Map<String, Object?> Function()? _snapshot;
  Future<void> _inFlight = Future<void>.value();
  Map<String, Object?>? _lastWritten;
  bool _disposed = false;

  /// A write is scheduled and has not started yet.
  bool get isPending => _snapshot != null;

  /// [snapshot] is called when the write starts (also from [flush] and
  /// [dispose]); it must not read provider state.
  void schedule(Map<String, Object?> Function() snapshot) {
    if (_disposed) return;
    _snapshot = snapshot;
    _timer?.cancel();
    _timer = Timer(delay, _write);
  }

  Map<String, Object?>? get lastWritten =>
      _lastWritten; // to ignore our own echo from watch()

  /// True if [value] deep-equals the last value this writer wrote.
  bool isOwnEcho(Map<String, Object?> value) {
    final last = _lastWritten;
    return last != null && const DeepCollectionEquality().equals(last, value);
  }

  Future<void> flush() {
    // write immediately if scheduled
    if (_snapshot != null) _write();
    return _inFlight;
  }

  /// Drops a scheduled write (used before a reset of the key).
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _snapshot = null;
  }

  void dispose() {
    // flushes
    if (_disposed) return;
    unawaited(flush());
    _disposed = true;
    _timer?.cancel();
  }

  void _write() {
    _timer?.cancel();
    _timer = null;
    final snapshot = _snapshot;
    _snapshot = null;
    if (snapshot == null) return;
    final value = Map<String, Object?>.unmodifiable(snapshot());
    _lastWritten = value;
    final previous = _inFlight;
    _inFlight = () async {
      await previous;
      try {
        await settings.set(key, value);
      } on Object catch (error, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'feature_editor',
            context: ErrorDescription('while writing setting ${key.name}'),
          ),
        );
      }
    }();
  }
}
