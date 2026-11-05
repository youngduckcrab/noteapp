// lib/src/viewport/viewport_memory.dart — 04-editor 6.3.5, stored form 6.14:
// {"v":1,"entries":[{"noteId":..,"pageId":..,"dx":..,"dy":..,"zoom":..,"at":..}]}
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

import '../state/settings/editor_setting_keys.dart';
import 'viewport_controller.dart';

/// Debounce of `editor.viewport` (6.14: '상호작용이 끝나고 2초 뒤').
const Duration _saveDelay = Duration(seconds: 2);

/// Entries kept (LRU by `at`).
const int _maxEntries = 50;

/// Last viewed position per note, stored under EditorSettingKeys.viewport
/// (core.SettingScope.device — contract 7.4.6). Keeps the 50 most recent notes
/// (LRU by `at`).
///
/// A write reads the stored list first and merges this instance's saves into
/// it, so entries written meanwhile (another screen) are kept. Invalid stored
/// entries are dropped and reported once per read (library 'feature_editor').
/// The write Future follows the CORE rule (contract 7.2.9 v1.2): [flush] has no
/// timeout.
class ViewportMemory {
  ViewportMemory(this._settings, {required this._now});

  final core.SettingsRepository _settings;
  final core.EpochMillis Function() _now;

  /// Saved here and not written yet (noteId → entry).
  final Map<String, _Entry> _unsaved = {};

  /// Being written now (until that set completes).
  final Map<String, _Entry> _writing = {};
  Timer? _timer;
  Future<void> _inFlight = Future<void>.value();
  bool _disposed = false;

  Future<ViewportAnchor?> load(String noteId) async {
    final local = _unsaved[noteId] ?? _writing[noteId];
    if (local != null) return local.anchor;
    final stored = await _read();
    // A save that arrived while reading wins.
    return (_unsaved[noteId] ?? _writing[noteId] ?? stored[noteId])?.anchor;
  }

  /// Debounced 2 s.
  void save(String noteId, ViewportAnchor anchor) {
    if (_disposed) return;
    _unsaved[noteId] = _Entry(noteId: noteId, anchor: anchor, at: _now());
    _timer?.cancel();
    _timer = Timer(_saveDelay, _write);
  }

  Future<void> flush() {
    if (_unsaved.isNotEmpty) _write();
    return _inFlight;
  }

  void dispose() {
    if (_disposed) return;
    unawaited(flush());
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  void _write() {
    _timer?.cancel();
    _timer = null;
    if (_unsaved.isEmpty) return;
    final batch = Map<String, _Entry>.of(_unsaved);
    _unsaved.clear();
    _writing.addAll(batch);
    final previous = _inFlight;
    _inFlight = () async {
      await previous;
      try {
        final merged = await _read();
        merged.addAll(batch);
        final entries = merged.values.toList()
          ..sort((a, b) => b.at.compareTo(a.at));
        final kept = entries.take(_maxEntries);
        await _settings.set(EditorSettingKeys.viewport, {
          'v': 1,
          'entries': [for (final e in kept) e.toJson()],
        });
      } on Object catch (error, stack) {
        _report(
          error,
          stack,
          'while writing ${EditorSettingKeys.viewport.name}',
        );
      }
      for (final e in batch.values) {
        if (identical(_writing[e.noteId], e)) _writing.remove(e.noteId);
      }
    }();
  }

  /// The stored entries by note id (invalid ones dropped and reported).
  Future<Map<String, _Entry>> _read() async {
    final Map<String, Object?> json;
    try {
      json = await _settings.get(EditorSettingKeys.viewport);
    } on Object catch (error, stack) {
      _report(error, stack, 'while reading ${EditorSettingKeys.viewport.name}');
      return {};
    }
    final result = <String, _Entry>{};
    final list = json['entries'];
    if (list == null) return result;
    if (list is! List) {
      _report(
        FormatException('editor.viewport: "entries" is not a list', list),
        null,
        'while reading ${EditorSettingKeys.viewport.name}',
      );
      return result;
    }
    Object? firstError;
    for (final item in list) {
      try {
        final entry = _Entry.fromJson(item);
        final existing = result[entry.noteId];
        if (existing == null || existing.at < entry.at) {
          result[entry.noteId] = entry;
        }
      } on FormatException catch (error) {
        firstError ??= error;
      }
    }
    if (firstError != null) {
      _report(
        firstError,
        null,
        'while reading ${EditorSettingKeys.viewport.name}',
      );
    }
    return result;
  }

  static void _report(Object error, StackTrace? stack, String context) {
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

@immutable
final class _Entry {
  const _Entry({required this.noteId, required this.anchor, required this.at});

  factory _Entry.fromJson(Object? json) {
    if (json is! Map) {
      throw FormatException('editor.viewport: entry is not an object', json);
    }
    final map = <String, Object?>{
      for (final MapEntry(:key, :value) in json.entries) '$key': value,
    };
    final noteId = map['noteId'];
    if (noteId is! String || noteId.isEmpty) {
      throw FormatException('editor.viewport: invalid noteId', noteId);
    }
    final at = map['at'];
    if (at is! num || !at.isFinite) {
      throw FormatException('editor.viewport: invalid at', at);
    }
    return _Entry(
      noteId: noteId,
      anchor: ViewportAnchor.fromJson(map),
      at: at.round(),
    );
  }

  final String noteId;
  final ViewportAnchor anchor;
  final core.EpochMillis at;

  Map<String, Object?> toJson() => {
    'noteId': noteId,
    ...anchor.toJson(),
    'at': at,
  };
}
