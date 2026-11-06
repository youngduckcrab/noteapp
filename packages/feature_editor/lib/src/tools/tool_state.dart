// lib/src/tools/tool_state.dart — 04-editor 6.6.1; stored forms 6.14
// (editor.penStyles, editor.eraser, editor.toolSelection). (v2, E2-03)
// m5-7/04-editor 6.2.1: the shape and text tools, lastTool / lastPenType.
// (E2-19) 6.17: EraserSettings.eraseShapes.
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

/// (v2) Image insertion and math are actions of the insert menu, not modal
/// tools.
enum EditorTool { pen, eraser, lasso, shape, text }

@immutable
class EraserSettings {
  const EraserSettings({
    this.mode = ink.EraserMode.partial,
    this.diameter = 12.0,
    this.filter = core.StrokeFilter.all,
    this.returnToPreviousTool = false,
    this.eraseShapes = true,
  });
  static const double minDiameter = 1.0;
  static const double maxDiameter = 100.0;
  static const double diameterStep = 0.5;

  final ink.EraserMode mode;
  final double diameter; // pt (radius passed to INK = diameter / 2)
  final core.StrokeFilter filter;
  final bool returnToPreviousTool;

  /// (v2, m5-7/04-editor 6.17 — U22) a touched shape is removed whole, in
  /// both modes (INK EraserSpec.eraseShapes). Text, images and math are
  /// never erased.
  final bool eraseShapes;

  /// ink.EraserSpec(mode: mode, radius: diameter / 2, filter: filter,
  /// eraseShapes: eraseShapes)
  ink.EraserSpec toSpec() => ink.EraserSpec(
    mode: mode,
    radius: diameter / 2,
    filter: filter,
    eraseShapes: eraseShapes,
  );

  /// [diameter] clamped to [minDiameter, maxDiameter] on the 0.5 pt step.
  static double snapDiameter(double value) {
    if (value.isNaN) return const EraserSettings().diameter;
    final rounded = (value.clamp(minDiameter, maxDiameter) * 2).round() / 2;
    return rounded.clamp(minDiameter, maxDiameter);
  }

  /// The same settings with the diameter snapped ([snapDiameter]).
  EraserSettings normalized() {
    final d = snapDiameter(diameter);
    return d == diameter ? this : copyWith(diameter: d);
  }

  EraserSettings copyWith({
    ink.EraserMode? mode,
    double? diameter,
    core.StrokeFilter? filter,
    bool? returnToPreviousTool,
    bool? eraseShapes,
  }) => EraserSettings(
    mode: mode ?? this.mode,
    diameter: diameter ?? this.diameter,
    filter: filter ?? this.filter,
    returnToPreviousTool: returnToPreviousTool ?? this.returnToPreviousTool,
    eraseShapes: eraseShapes ?? this.eraseShapes,
  );

  /// {"v":1,"mode":"partial","diameter":12.0,"filter":"all","returnToPrevious":false,
  /// "eraseShapes":true} — (v2) "eraseShapes" added, "v" stays 1 (6.18).
  Map<String, Object?> toJson() => {
    'v': 1,
    'mode': mode.name,
    'diameter': diameter,
    'filter': filter.name,
    'returnToPrevious': returnToPreviousTool,
    'eraseShapes': eraseShapes,
  };

  /// Missing fields take the defaults; invalid ones too, and their names are
  /// added to [invalidFields] when given. "v" is not checked; integers are
  /// accepted for the diameter.
  factory EraserSettings.fromJson(
    Map<String, Object?> json, {
    List<String>? invalidFields,
  }) {
    const d = EraserSettings();
    T field<T>(String name, T fallback, T? Function(Object value) read) {
      if (!json.containsKey(name)) return fallback;
      final raw = json[name];
      final value = raw == null ? null : read(raw);
      if (value == null) {
        invalidFields?.add(name);
        return fallback;
      }
      return value;
    }

    return EraserSettings(
      mode: field(
        'mode',
        d.mode,
        (v) => ink.EraserMode.values.firstWhereOrNull((m) => m.name == v),
      ),
      diameter: field('diameter', d.diameter, (v) {
        if (v is! num || !v.isFinite) return null;
        final x = v.toDouble();
        return x >= minDiameter && x <= maxDiameter ? x : null;
      }),
      filter: field(
        'filter',
        d.filter,
        (v) => core.StrokeFilter.values.firstWhereOrNull((f) => f.name == v),
      ),
      returnToPreviousTool: field(
        'returnToPrevious',
        d.returnToPreviousTool,
        (v) => v is bool ? v : null,
      ),
      // (v2) missing (a 1st-round value) → true.
      eraseShapes: field(
        'eraseShapes',
        d.eraseShapes,
        (v) => v is bool ? v : null,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EraserSettings &&
      other.mode == mode &&
      other.diameter == diameter &&
      other.filter == filter &&
      other.returnToPreviousTool == returnToPreviousTool &&
      other.eraseShapes == eraseShapes;
  @override
  int get hashCode =>
      Object.hash(mode, diameter, filter, returnToPreviousTool, eraseShapes);

  @override
  String toString() =>
      'EraserSettings(${mode.name}, $diameter pt, ${filter.name}, '
      'returnToPrevious: $returnToPreviousTool, eraseShapes: $eraseShapes)';
}

@immutable
class ToolState {
  const ToolState({
    required this.activeTool,
    required this.penType,
    required this.penStyles,
    this.previousTool,
    this.lastTool,
    this.lastPenType,
    this.eraser = const EraserSettings(),
    this.eyedropperActive = false,
  });

  /// Pen active, ballpoint, every core.PenTool at core.StrokeStyle.defaultsFor
  /// (contract 7.2.4 table).
  factory ToolState.defaults() => ToolState(
    activeTool: EditorTool.pen,
    penType: core.PenTool.ballpoint,
    penStyles: defaultPenStyles(),
  );

  /// Unmodifiable: core.StrokeStyle.defaultsFor(tool).normalized() for every tool.
  static Map<core.PenTool, core.StrokeStyle> defaultPenStyles() =>
      Map.unmodifiable({
        for (final t in core.PenTool.values)
          t: core.StrokeStyle.defaultsFor(t).normalized(),
      });

  final EditorTool activeTool;
  final EditorTool? previousTool; // tool active before switching to eraser
  final core.PenTool penType;

  /// (v2) The tool and pen type that were active before the last switch (any
  /// tool) — EditorAction.previousTool swaps (activeTool, penType) with
  /// these. Persisted (device).
  final EditorTool? lastTool;
  final core.PenTool? lastPenType;

  /// Unmodifiable, one normalized style per core.PenTool value (P1 tools are kept
  /// so presets/sync with them round-trip; the selector shows only isP0).
  final Map<core.PenTool, core.StrokeStyle> penStyles;
  final EraserSettings eraser;
  final bool eyedropperActive; // transient, never persisted

  core.StrokeStyle get currentPen => penStyles[penType]!;

  ToolState copyWith({
    EditorTool? activeTool,
    EditorTool? previousTool,
    bool clearPreviousTool = false,
    core.PenTool? penType,
    Map<core.PenTool, core.StrokeStyle>? penStyles,
    EraserSettings? eraser,
    bool? eyedropperActive,
    EditorTool? lastTool,
    core.PenTool? lastPenType,
    // true: lastTool / lastPenType take the given values as they are (null
    // clears them).
    bool clearLast = false,
  }) => ToolState(
    activeTool: activeTool ?? this.activeTool,
    previousTool: clearPreviousTool ? null : previousTool ?? this.previousTool,
    penType: penType ?? this.penType,
    lastTool: clearLast ? lastTool : lastTool ?? this.lastTool,
    lastPenType: clearLast ? lastPenType : lastPenType ?? this.lastPenType,
    penStyles: penStyles == null ? this.penStyles : Map.unmodifiable(penStyles),
    eraser: eraser ?? this.eraser,
    eyedropperActive: eyedropperActive ?? this.eyedropperActive,
  );

  static const _styles = MapEquality<core.PenTool, core.StrokeStyle>();

  @override
  bool operator ==(Object other) =>
      other is ToolState &&
      other.activeTool == activeTool &&
      other.previousTool == previousTool &&
      other.penType == penType &&
      other.lastTool == lastTool &&
      other.lastPenType == lastPenType &&
      other.eraser == eraser &&
      other.eyedropperActive == eyedropperActive &&
      _styles.equals(other.penStyles, penStyles);

  @override
  int get hashCode => Object.hash(
    activeTool,
    previousTool,
    penType,
    lastTool,
    lastPenType,
    eraser,
    eyedropperActive,
    _styles.hash(penStyles),
  );

  @override
  String toString() =>
      'ToolState(${activeTool.name}, pen: ${penType.name}, '
      'previous: ${previousTool?.name}, last: ${lastTool?.name}/'
      '${lastPenType?.name}, eyedropper: $eyedropperActive)';
}
