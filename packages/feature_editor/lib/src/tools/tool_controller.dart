// lib/src/tools/tool_controller.dart — 04-editor 6.6.1; stored forms 6.14.
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../state/debounced_writer.dart';
import '../state/settings/editor_setting_keys.dart';
import '../ui/pen/width_mapping.dart';
import 'tool_state.dart';

/// Debounce of the three tool keys (6.14: '변경 500ms 뒤').
const Duration _writeDelay = Duration(milliseconds: 500);

/// Global (shared by all notes). Defaults: core.StrokeStyle.defaultsFor(tool) for every
/// core.PenTool (contract 7.2.4 table — EDITOR has no default table of its own).
/// Loads / saves EditorSettingKeys.penStyles + eraser (synced) and toolSelection
/// (device) — 6.14. Every style is stored and handed to INK as style.normalized().
///
/// Like EditorSettingsNotifier: build() returns the defaults synchronously and
/// the stored values replace them after the load; a change made before the
/// load completes wins for its key; the synced keys follow settings.watch
/// (own echo ignored); invalid stored entries decode to defaults and are
/// reported once per load (library 'feature_editor'). eyedropperActive is
/// never stored.
class ToolController extends Notifier<ToolState> {
  late DebouncedSettingWriter _stylesWriter;
  late DebouncedSettingWriter _eraserWriter;
  late DebouncedSettingWriter _selectionWriter;
  final List<StreamSubscription<Map<String, Object?>>> _remote = [];
  bool _loaded = false;
  int _generation = 0;

  @override
  ToolState build() {
    final settings = ref.watch(core.settingsRepositoryProvider);
    final generation = ++_generation;
    _loaded = false;
    final writers = [
      _stylesWriter = DebouncedSettingWriter(
        settings: settings,
        key: EditorSettingKeys.penStyles,
        delay: _writeDelay,
      ),
      _eraserWriter = DebouncedSettingWriter(
        settings: settings,
        key: EditorSettingKeys.eraser,
        delay: _writeDelay,
      ),
      _selectionWriter = DebouncedSettingWriter(
        settings: settings,
        key: EditorSettingKeys.toolSelection,
        delay: _writeDelay,
      ),
    ];
    final remote = _remote;
    ref.onDispose(() {
      _generation++;
      for (final w in writers) {
        w.dispose();
      }
      for (final s in remote) {
        unawaited(s.cancel());
      }
      remote.clear();
    });
    unawaited(_load(settings, generation));
    return ToolState.defaults();
  }

  /// True after the stored values have been read (or found absent / undecodable).
  bool get isLoaded => _loaded;

  // ---- setters ----

  /// → eraser: previousTool = old tool. Leaving the eraser clears it.
  /// Also ends the eyedropper.
  void selectTool(EditorTool tool) {
    final s = state;
    if (tool == s.activeTool) {
      if (s.eyedropperActive) _update(s.copyWith(eyedropperActive: false));
      return;
    }
    _update(
      tool == EditorTool.eraser
          ? s.copyWith(
              activeTool: tool,
              previousTool: s.activeTool,
              eyedropperActive: false,
            )
          : s.copyWith(
              activeTool: tool,
              clearPreviousTool: true,
              eyedropperActive: false,
            ),
    );
  }

  /// Also activeTool = pen.
  void selectPenType(core.PenTool type) => _update(
    state.copyWith(
      penType: type,
      activeTool: EditorTool.pen,
      clearPreviousTool: true,
      eyedropperActive: false,
    ),
  );

  /// Alpha forced to 0xFF (normalized).
  void setColor(int argb) => _updateCurrent((s) => s.copyWith(colorArgb: argb));

  /// Clamp [StrokeStyle.minOpacity, 1], round 0.01.
  void setOpacity(double value) =>
      _updateCurrent((s) => s.copyWith(opacity: _round(value, 100)));

  /// WidthMapping.snap.
  void setWidth(double value) =>
      _updateCurrent((s) => s.copyWith(width: WidthMapping.snap(value)));

  /// 0..1, step 0.05.
  void setPressureSensitivity(double value) =>
      _updateCurrent((s) => s.copyWith(pressureSensitivity: _round(value, 20)));

  /// soft / linear / firm (6.9.3).
  void setPressureCurve(core.PressureCurve curve) =>
      _updateCurrent((s) => s.copyWith(pressureCurve: curve));

  /// 0..1, step 0.05.
  void setSmoothing(double value) =>
      _updateCurrent((s) => s.copyWith(smoothing: _round(value, 20)));

  /// Highlighter only (no-op for other tools): style.withHighlighterStraightening(value).
  void setHighlighterStraightening(ink.HighlighterStraightening value) {
    if (state.penType != core.PenTool.highlighter) return;
    _updateCurrent((s) => s.withHighlighterStraightening(value));
  }

  /// Edits the style of [tool] (settings > pen section edits non-active tools too).
  void updateStyleOf(
    core.PenTool tool,
    core.StrokeStyle Function(core.StrokeStyle) update,
  ) {
    final s = state;
    final next = update(s.penStyles[tool]!).copyWith(tool: tool).normalized();
    if (next == s.penStyles[tool]) return;
    _update(s.copyWith(penStyles: {...s.penStyles, tool: next}));
  }

  /// Preset: penType = style.tool, pen active.
  void applyStyle(core.StrokeStyle style) {
    final s = state;
    final normalized = style.normalized();
    _update(
      s.copyWith(
        penType: style.tool,
        activeTool: EditorTool.pen,
        clearPreviousTool: true,
        eyedropperActive: false,
        penStyles: {...s.penStyles, style.tool: normalized},
      ),
    );
  }

  void updateEraser(EraserSettings Function(EraserSettings) update) {
    final s = state;
    _update(s.copyWith(eraser: update(s.eraser).normalized()));
  }

  /// activeTool = previousTool ?? pen (only while the eraser is active).
  void returnFromEraser() {
    final s = state;
    if (s.activeTool != EditorTool.eraser) return;
    _update(
      s.copyWith(
        activeTool: s.previousTool ?? EditorTool.pen,
        clearPreviousTool: true,
      ),
    );
  }

  void setEyedropper(bool active) {
    if (state.eyedropperActive == active) return;
    // Not stored: _update compares the stored forms only.
    state = state.copyWith(eyedropperActive: active);
  }

  /// All tools → core.StrokeStyle.defaultsFor (settings > pen '펜 종류별 기본값으로 초기화').
  void resetPenDefaults() =>
      _update(state.copyWith(penStyles: ToolState.defaultPenStyles()));

  /// Writes pending debounced values now (EditorCommands.flushAll, 6.17).
  Future<void> flush() async {
    await Future.wait([
      _stylesWriter.flush(),
      _eraserWriter.flush(),
      _selectionWriter.flush(),
    ]);
  }

  // ---- internals ----

  static double _round(double value, int perUnit) =>
      value.isNaN ? value : (value * perUnit).round() / perUnit;

  void _updateCurrent(core.StrokeStyle Function(core.StrokeStyle) update) =>
      updateStyleOf(state.penType, update);

  void _update(ToolState next) {
    final previous = state;
    if (next == previous) return;
    state = next;
    // Snapshots are taken now: writers may run from onDispose, where provider
    // state must not be read.
    if (!_styles.equals(previous.penStyles, next.penStyles)) {
      final json = _ToolStateJson.penStylesToJson(next.penStyles);
      _stylesWriter.schedule(() => json);
    }
    if (previous.eraser != next.eraser) {
      final json = next.eraser.toJson();
      _eraserWriter.schedule(() => json);
    }
    if (previous.activeTool != next.activeTool ||
        previous.penType != next.penType ||
        previous.previousTool != next.previousTool) {
      final json = _ToolStateJson.selectionToJson(next);
      _selectionWriter.schedule(() => json);
    }
  }

  static const _styles = MapEquality<core.PenTool, core.StrokeStyle>();

  Future<void> _load(core.SettingsRepository settings, int generation) async {
    Map<String, Object?> styles = const {};
    Map<String, Object?> eraser = const {};
    Map<String, Object?> selection = const {};
    try {
      styles = await settings.get(EditorSettingKeys.penStyles);
      eraser = await settings.get(EditorSettingKeys.eraser);
      selection = await settings.get(EditorSettingKeys.toolSelection);
    } on Object catch (error, stack) {
      _report(error, stack, 'while loading the tool settings');
    }
    if (generation != _generation) return; // rebuilt or disposed meanwhile
    final invalid = <String>[];
    final loadedStyles = _ToolStateJson.penStylesFromJson(styles, invalid);
    final eraserInvalid = <String>[];
    final loadedEraser = EraserSettings.fromJson(
      eraser,
      invalidFields: eraserInvalid,
    );
    invalid.addAll([
      for (final f in eraserInvalid) '${EditorSettingKeys.eraser.name}.$f',
    ]);
    final loadedSelection = _ToolStateJson.selectionFromJson(
      selection,
      invalid,
    );
    if (invalid.isNotEmpty) {
      _report(
        FormatException(
          'Invalid tool settings replaced by defaults: ${invalid.join(', ')}',
        ),
        null,
        'while loading the tool settings',
      );
    }
    final current = state;
    state = current.copyWith(
      penStyles: _stylesWriter.isPending ? null : loadedStyles,
      eraser: _eraserWriter.isPending ? null : loadedEraser.normalized(),
      activeTool: _selectionWriter.isPending
          ? null
          : loadedSelection.activeTool,
      penType: _selectionWriter.isPending ? null : loadedSelection.penType,
      previousTool: _selectionWriter.isPending
          ? null
          : loadedSelection.previousTool,
      clearPreviousTool:
          !_selectionWriter.isPending && loadedSelection.previousTool == null,
    );
    _loaded = true;
    _remote
      ..add(
        settings
            .watch(EditorSettingKeys.penStyles)
            .listen(
              _onRemoteStyles,
              onError: (Object error, StackTrace stack) =>
                  _report(error, stack, 'while watching the pen styles'),
            ),
      )
      ..add(
        settings
            .watch(EditorSettingKeys.eraser)
            .listen(
              _onRemoteEraser,
              onError: (Object error, StackTrace stack) =>
                  _report(error, stack, 'while watching the eraser settings'),
            ),
      );
  }

  /// Another device's value (M4), or our own write coming back.
  void _onRemoteStyles(Map<String, Object?> json) {
    if (_stylesWriter.isOwnEcho(json) || _stylesWriter.isPending) return;
    final styles = _ToolStateJson.penStylesFromJson(json, null);
    if (_styles.equals(styles, state.penStyles)) return;
    state = state.copyWith(penStyles: styles);
  }

  void _onRemoteEraser(Map<String, Object?> json) {
    if (_eraserWriter.isOwnEcho(json) || _eraserWriter.isPending) return;
    final eraser = EraserSettings.fromJson(json).normalized();
    if (eraser == state.eraser) return;
    state = state.copyWith(eraser: eraser);
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

/// Stored forms of the pen styles and the tool selection (6.14).
abstract final class _ToolStateJson {
  /// {"v":1,"styles":{"ballpoint":{StrokeStyle.toJson()},...}} — key =
  /// PenTool.wireName, value = the normalized style.
  static Map<String, Object?> penStylesToJson(
    Map<core.PenTool, core.StrokeStyle> styles,
  ) => {
    'v': 1,
    'styles': {
      for (final t in core.PenTool.values)
        if (styles[t] case final style?) t.wireName: style.toJson(),
    },
  };

  /// Every core.PenTool gets a style: unknown tool names are skipped, missing
  /// tools take defaultsFor, entries that fail to decode (or name another
  /// tool) take defaultsFor and are added to [invalid].
  static Map<core.PenTool, core.StrokeStyle> penStylesFromJson(
    Map<String, Object?> json,
    List<String>? invalid,
  ) {
    final result = Map.of(ToolState.defaultPenStyles());
    final styles = json['styles'];
    if (styles == null) return Map.unmodifiable(result);
    if (styles is! Map) {
      invalid?.add('${EditorSettingKeys.penStyles.name}.styles');
      return Map.unmodifiable(result);
    }
    for (final MapEntry(:key, :value) in styles.entries) {
      final tool = core.PenTool.values.firstWhereOrNull(
        (t) => t.wireName == key,
      );
      if (tool == null) continue; // a newer tool: not an error
      try {
        if (value is! Map) throw const FormatException('not an object');
        final style = core.StrokeStyle.fromJson({
          for (final e in value.entries) '${e.key}': e.value,
        });
        if (style.tool != tool) throw const FormatException('another tool');
        result[tool] = style.normalized();
      } on Object {
        invalid?.add('${EditorSettingKeys.penStyles.name}.styles.$key');
      }
    }
    return Map.unmodifiable(result);
  }

  /// {"v":1,"activeTool":"pen","penType":"ballpoint","previousTool":null}
  static Map<String, Object?> selectionToJson(ToolState state) => {
    'v': 1,
    'activeTool': state.activeTool.name,
    'penType': state.penType.wireName,
    'previousTool': state.previousTool?.name,
  };

  static ({
    EditorTool activeTool,
    core.PenTool penType,
    EditorTool? previousTool,
  })
  selectionFromJson(Map<String, Object?> json, List<String>? invalid) {
    final name = EditorSettingKeys.toolSelection.name;
    EditorTool? tool(String field) {
      final v = json[field];
      if (v == null) return null;
      final t = EditorTool.values.firstWhereOrNull((t) => t.name == v);
      if (t == null) invalid?.add('$name.$field');
      return t;
    }

    final active = tool('activeTool') ?? EditorTool.pen;
    var previous = tool('previousTool');
    if (active != EditorTool.eraser) previous = null;
    var penType = core.PenTool.ballpoint;
    final rawPen = json['penType'];
    if (rawPen != null) {
      final t = core.PenTool.values.firstWhereOrNull(
        (t) => t.wireName == rawPen,
      );
      if (t == null) {
        invalid?.add('$name.penType');
      } else {
        penType = t;
      }
    }
    return (activeTool: active, penType: penType, previousTool: previous);
  }
}

final editorToolProvider = NotifierProvider<ToolController, ToolState>(
  ToolController.new,
  name: 'editorToolProvider',
);
