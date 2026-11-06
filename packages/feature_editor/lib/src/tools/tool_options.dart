// lib/src/tools/tool_options.dart — m5-7/04-editor 6.2.4, 6.2.2, 6.18
// (E2-03): the shape and text tool defaults.
//
// Global (all notes), key editor.toolOptions (synced), written 500 ms after a
// change — like ToolController: build() gives the defaults at once and the
// stored value replaces them after the load (a change made before the load
// wins), the key follows settings.watch (own echo ignored). Reading follows
// the 6.2.2 forward-compatible rule: an unknown ShapeKind name → rectangle,
// unknown enum names inside the styles → that style's default, none of them
// reported; a value of the wrong type is reported once and takes its default.
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart' as core;

import '../state/debounced_writer.dart';
import '../state/settings/editor_setting_keys.dart';

@immutable
class ToolOptions {
  const ToolOptions({
    this.shapeKind = core.ShapeKind.rectangle,
    this.shapeStyle = const core.ShapeStyle(strokeColorArgb: 0xFF1A1A1A),
    this.polygonSides = 5,
    this.starPoints = 5,
    this.textStyle = const core.TextBoxStyle(),
  });

  /// ShapeGeometry.regularPolygon sides.
  static const int minPolygonSides = 3, maxPolygonSides = 12;

  /// Star points (2 · points ≤ PageObjectLimits.maxPolylinePoints).
  static const int minStarPoints = 4, maxStarPoints = 16;

  final core.ShapeKind shapeKind;

  /// normalized; arrowHeads used by line / arrow only.
  final core.ShapeStyle shapeStyle;

  /// 3..12 (ShapeGeometry.regularPolygon).
  final int polygonSides;

  /// 4..16 (2·points ≤ PageObjectLimits.maxPolylinePoints).
  final int starPoints;

  /// normalized; the style of a new text box.
  final core.TextBoxStyle textStyle;

  /// Styles normalized, sides / points clamped, and the arrow rule (6.2.4):
  /// an arrow whose arrowHeads is none gets `end` (a line keeps its heads).
  ToolOptions normalized() {
    var style = shapeStyle.normalized();
    if (shapeKind == core.ShapeKind.arrow &&
        style.arrowHeads == core.ArrowHeads.none) {
      style = style.copyWith(arrowHeads: core.ArrowHeads.end);
    }
    return ToolOptions(
      shapeKind: shapeKind,
      shapeStyle: style,
      polygonSides: polygonSides.clamp(minPolygonSides, maxPolygonSides),
      starPoints: starPoints.clamp(minStarPoints, maxStarPoints),
      textStyle: textStyle.normalized(),
    );
  }

  ToolOptions copyWith({
    core.ShapeKind? shapeKind,
    core.ShapeStyle? shapeStyle,
    int? polygonSides,
    int? starPoints,
    core.TextBoxStyle? textStyle,
  }) => ToolOptions(
    shapeKind: shapeKind ?? this.shapeKind,
    shapeStyle: shapeStyle ?? this.shapeStyle,
    polygonSides: polygonSides ?? this.polygonSides,
    starPoints: starPoints ?? this.starPoints,
    textStyle: textStyle ?? this.textStyle,
  );

  /// {"v":1,"shape":{"kind":…,"style":ShapeStyle.toJson(),"sides":5,
  ///  "points":5},"text":TextBoxStyle.toJson()}
  Map<String, Object?> toJson() => {
    'v': 1,
    'shape': {
      'kind': shapeKind.name,
      'style': shapeStyle.toJson(),
      'sides': polygonSides,
      'points': starPoints,
    },
    'text': textStyle.toJson(),
  };

  /// Missing or invalid fields → defaults (6.2.2 rule — see the file
  /// comment); wrong-typed field paths are added to [invalidFields]. The
  /// result is normalized.
  factory ToolOptions.fromJson(
    Map<String, Object?> json, {
    List<String>? invalidFields,
  }) {
    const d = ToolOptions();
    void bad(String path) => invalidFields?.add(path);
    Map<String, Object?>? object(Object? v, String path) {
      if (v == null) return null;
      if (v is Map) return {for (final e in v.entries) '${e.key}': e.value};
      bad(path);
      return null;
    }

    final shape = object(json['shape'], 'shape') ?? const {};
    var kind = d.shapeKind;
    switch (shape['kind']) {
      case null:
        break;
      case final String name:
        kind =
            core.ShapeKind.values.firstWhereOrNull((k) => k.name == name) ??
            d.shapeKind;
      default:
        bad('shape.kind');
    }
    int count(String field, int fallback) => switch (shape[field]) {
      null => fallback,
      final num n when n.isFinite && n == n.roundToDouble() => n.toInt(),
      _ => () {
        bad('shape.$field');
        return fallback;
      }(),
    };

    var shapeStyle = d.shapeStyle;
    final rawStyle = object(shape['style'], 'shape.style');
    if (rawStyle != null) {
      try {
        shapeStyle = core.ShapeStyle.fromJson(
          _withoutUnknownNames(rawStyle, {
            'dash': core.LineDash.values,
            'arrowHeads': core.ArrowHeads.values,
          }),
        );
      } on Object {
        bad('shape.style');
      }
    }
    var textStyle = d.textStyle;
    final rawText = object(json['text'], 'text');
    if (rawText != null) {
      try {
        textStyle = core.TextBoxStyle.fromJson(
          _withoutUnknownNames(rawText, {'align': core.TextAlignKind.values}),
        );
      } on Object {
        bad('text');
      }
    }
    return ToolOptions(
      shapeKind: kind,
      shapeStyle: shapeStyle,
      polygonSides: count('sides', d.polygonSides),
      starPoints: count('points', d.starPoints),
      textStyle: textStyle,
    ).normalized();
  }

  /// [json] without the enum fields whose string is not a known name (a
  /// newer app's value — that field then takes its default, unreported).
  static Map<String, Object?> _withoutUnknownNames(
    Map<String, Object?> json,
    Map<String, List<Enum>> enums,
  ) => {
    for (final MapEntry(:key, :value) in json.entries)
      if (!(value is String &&
          enums[key] != null &&
          !enums[key]!.any((e) => e.name == value)))
        key: value,
  };

  @override
  bool operator ==(Object other) =>
      other is ToolOptions &&
      other.shapeKind == shapeKind &&
      other.shapeStyle == shapeStyle &&
      other.polygonSides == polygonSides &&
      other.starPoints == starPoints &&
      other.textStyle == textStyle;

  @override
  int get hashCode =>
      Object.hash(shapeKind, shapeStyle, polygonSides, starPoints, textStyle);

  @override
  String toString() =>
      'ToolOptions(${shapeKind.name}, sides: $polygonSides, points: '
      '$starPoints)';
}

/// Global ToolOptions (all notes), editor.toolOptions (synced), 500 ms
/// debounce. Every value is stored normalized.
class ToolOptionsNotifier extends Notifier<ToolOptions> {
  late DebouncedSettingWriter _writer;
  StreamSubscription<Map<String, Object?>>? _remote;
  int _generation = 0;
  bool _loaded = false;

  static const Duration writeDelay = Duration(milliseconds: 500);

  @override
  ToolOptions build() {
    final settings = ref.watch(core.settingsRepositoryProvider);
    final generation = ++_generation;
    _loaded = false;
    final writer = _writer = DebouncedSettingWriter(
      settings: settings,
      key: EditorSettingKeys.toolOptions,
      delay: writeDelay,
    );
    ref.onDispose(() {
      _generation++;
      writer.dispose();
      unawaited(_remote?.cancel());
      _remote = null;
    });
    unawaited(_load(settings, generation));
    return const ToolOptions();
  }

  /// True after the stored value has been read (or found absent).
  bool get isLoaded => _loaded;

  /// (6.2.4) Choosing the arrow turns arrowHeads none into end.
  void setShapeKind(core.ShapeKind kind) =>
      _update(state.copyWith(shapeKind: kind));

  void setShapeStyle(core.ShapeStyle style) =>
      _update(state.copyWith(shapeStyle: style));

  /// Clamped to 3..12.
  void setPolygonSides(int sides) =>
      _update(state.copyWith(polygonSides: sides));

  /// Clamped to 4..16.
  void setStarPoints(int points) => _update(state.copyWith(starPoints: points));

  /// The style of the next text box (also set by the format bar — 6.11.4).
  void setTextStyle(core.TextBoxStyle style) =>
      _update(state.copyWith(textStyle: style));

  /// Writes a pending value now (EditorCommands.flushAll).
  Future<void> flush() => _writer.flush();

  void _update(ToolOptions next) {
    final normalized = next.normalized();
    if (normalized == state) return;
    state = normalized;
    final json = normalized.toJson();
    _writer.schedule(() => json);
  }

  Future<void> _load(core.SettingsRepository settings, int generation) async {
    Map<String, Object?> json = const {};
    try {
      json = await settings.get(EditorSettingKeys.toolOptions);
    } on Object catch (error, stack) {
      _report(error, stack, 'while loading the tool options');
    }
    if (generation != _generation) return;
    final invalid = <String>[];
    final loaded = ToolOptions.fromJson(json, invalidFields: invalid);
    if (invalid.isNotEmpty) {
      _report(
        FormatException(
          'Invalid tool options replaced by defaults: '
          '${invalid.map((f) => '${EditorSettingKeys.toolOptions.name}.$f').join(', ')}',
        ),
        null,
        'while loading the tool options',
      );
    }
    if (!_writer.isPending) state = loaded;
    _loaded = true;
    _remote = settings
        .watch(EditorSettingKeys.toolOptions)
        .listen(
          _onRemote,
          onError: (Object error, StackTrace stack) =>
              _report(error, stack, 'while watching the tool options'),
        );
  }

  void _onRemote(Map<String, Object?> json) {
    if (_writer.isOwnEcho(json) || _writer.isPending) return;
    final next = ToolOptions.fromJson(json);
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

final editorToolOptionsProvider =
    NotifierProvider<ToolOptionsNotifier, ToolOptions>(
      ToolOptionsNotifier.new,
      name: 'editorToolOptionsProvider',
    );
