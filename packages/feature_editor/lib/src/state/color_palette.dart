// lib/src/state/color_palette.dart — 04-editor 6.9.5; stored form 6.14.
//
// Made with E-08 (the pen pushes its colour into the recent colours when a
// stroke commits); the picker UI and its completion tests are E-14.
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart' as core;

import 'debounced_writer.dart';
import 'settings/editor_setting_keys.dart';

/// Debounce of editor.colors (6.14: '변경 1000ms 뒤').
const Duration _writeDelay = Duration(milliseconds: 1000);

@immutable
class ColorPaletteState {
  const ColorPaletteState({
    this.recent = const <int>[],
    this.palette = const <int>[],
  });
  static const int maxRecent = 12;
  static const int maxPalette = 40;
  final List<int> recent; // ARGB, alpha 0xFF
  final List<int> palette;

  static const _list = ListEquality<int>();

  /// {"v":1,"recent":[ARGB...],"palette":[ARGB...]} (6.14).
  Map<String, Object?> toJson() => {
    'v': 1,
    'recent': List<int>.of(recent),
    'palette': List<int>.of(palette),
  };

  /// Unknown `v` reads the known fields. A missing list is empty; entries
  /// that are not ARGB integers are dropped and their field named in
  /// [invalidFields]; lists are made opaque, de-duplicated and cut to their
  /// maximum length.
  factory ColorPaletteState.fromJson(
    Map<String, Object?> json, {
    List<String>? invalidFields,
  }) {
    List<int> read(String name, int max) {
      final raw = json[name];
      if (raw == null) return const [];
      if (raw is! List) {
        invalidFields?.add(name);
        return const [];
      }
      final out = <int>[];
      var invalid = false;
      for (final v in raw) {
        if (v is int && v >= 0 && v <= 0xFFFFFFFF) {
          final c = opaque(v);
          if (!out.contains(c) && out.length < max) out.add(c);
        } else {
          invalid = true;
        }
      }
      if (invalid) invalidFields?.add(name);
      return List.unmodifiable(out);
    }

    return ColorPaletteState(
      recent: read('recent', maxRecent),
      palette: read('palette', maxPalette),
    );
  }

  /// 0xFF000000 | rgb, without bit operations (web-safe arithmetic, 7.4.3).
  static int opaque(int argb) => 0xFF000000 + argb % 0x1000000;

  @override
  bool operator ==(Object other) =>
      other is ColorPaletteState &&
      _list.equals(other.recent, recent) &&
      _list.equals(other.palette, palette);

  @override
  int get hashCode => Object.hash(_list.hash(recent), _list.hash(palette));

  @override
  String toString() => 'ColorPaletteState(recent: $recent, palette: $palette)';
}

/// Global. Persists EditorSettingKeys.colors (synced, 1000 ms debounce — 6.14).
///
/// Same load rules as the other EDITOR notifiers: build() returns the empty
/// state synchronously and the stored value replaces it after the load (a
/// change made before the load completes wins); settings.watch brings remote
/// values (own echo ignored); invalid stored entries are dropped and reported
/// once per load (library 'feature_editor').
class ColorPaletteNotifier extends Notifier<ColorPaletteState> {
  late DebouncedSettingWriter _writer;
  StreamSubscription<Map<String, Object?>>? _remote;
  int _generation = 0;

  @override
  ColorPaletteState build() {
    final settings = ref.watch(core.settingsRepositoryProvider);
    final generation = ++_generation;
    final writer = _writer = DebouncedSettingWriter(
      settings: settings,
      key: EditorSettingKeys.colors,
      delay: _writeDelay,
    );
    ref.onDispose(() {
      _generation++;
      writer.dispose();
      unawaited(_remote?.cancel());
      _remote = null;
    });
    unawaited(_load(settings, generation));
    return const ColorPaletteState();
  }

  /// Moves [argb] (made opaque) to the front of the recent colours (no
  /// duplicates, at most [ColorPaletteState.maxRecent]).
  void pushRecent(int argb) {
    final c = ColorPaletteState.opaque(argb);
    final s = state;
    if (s.recent.isNotEmpty && s.recent.first == c) return;
    final recent = [c, ...s.recent.where((r) => r != c)];
    _update(
      ColorPaletteState(
        recent: List.unmodifiable(
          recent.take(ColorPaletteState.maxRecent).toList(),
        ),
        palette: s.palette,
      ),
    );
  }

  /// false when full or duplicate.
  bool addToPalette(int argb) {
    final c = ColorPaletteState.opaque(argb);
    final s = state;
    if (s.palette.contains(c) ||
        s.palette.length >= ColorPaletteState.maxPalette) {
      return false;
    }
    _update(
      ColorPaletteState(
        recent: s.recent,
        palette: List.unmodifiable([...s.palette, c]),
      ),
    );
    return true;
  }

  void removeFromPalette(int index) {
    final s = state;
    if (index < 0 || index >= s.palette.length) return;
    _update(
      ColorPaletteState(
        recent: s.recent,
        palette: List.unmodifiable([...s.palette]..removeAt(index)),
      ),
    );
  }

  /// Writes a pending debounced value now (EditorCommands.flushAll, 6.17).
  Future<void> flush() => _writer.flush();

  void _update(ColorPaletteState next) {
    if (next == state) return;
    state = next;
    final json = next.toJson();
    _writer.schedule(() => json);
  }

  Future<void> _load(core.SettingsRepository settings, int generation) async {
    Map<String, Object?> json = const {};
    try {
      json = await settings.get(EditorSettingKeys.colors);
    } on Object catch (error, stack) {
      _report(error, stack, 'while loading the colour palette');
    }
    if (generation != _generation) return; // rebuilt or disposed meanwhile
    final invalid = <String>[];
    final loaded = ColorPaletteState.fromJson(json, invalidFields: invalid);
    if (invalid.isNotEmpty) {
      _report(
        FormatException(
          'Invalid colour palette entries dropped: '
          '${invalid.map((f) => '${EditorSettingKeys.colors.name}.$f').join(', ')}',
        ),
        null,
        'while loading the colour palette',
      );
    }
    if (!_writer.isPending) state = loaded;
    _remote = settings
        .watch(EditorSettingKeys.colors)
        .listen(
          _onRemote,
          onError: (Object error, StackTrace stack) =>
              _report(error, stack, 'while watching the colour palette'),
        );
  }

  void _onRemote(Map<String, Object?> json) {
    if (_writer.isOwnEcho(json) || _writer.isPending) return;
    final next = ColorPaletteState.fromJson(json);
    if (next != state) state = next;
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

final editorColorPaletteProvider =
    NotifierProvider<ColorPaletteNotifier, ColorPaletteState>(
      ColorPaletteNotifier.new,
      name: 'editorColorPaletteProvider',
    );
