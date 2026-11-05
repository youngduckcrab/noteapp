// lib/src/model/pen_style.dart — contract 00-overview 7.2.4 / CORE 4.2.1, 6.2.2.
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../common/json_read.dart';
import 'pressure_curve.dart';

const DeepCollectionEquality _deep = DeepCollectionEquality();

enum PenTool {
  ballpoint,
  fountain,
  highlighter,
  pencil,
  marker, // P0 (M1)
  brush,
  calligraphy,
  dashed,
  laser,
  tape; // P1 reserved (INK renders as ballpoint)

  bool get isP0 => index <= PenTool.marker.index;
  String get wireName => name; // == name

  /// Throws FormatException.
  static PenTool fromWireName(String name) {
    for (final t in PenTool.values) {
      if (t.name == name) return t;
    }
    throw FormatException('Unknown pen tool', name);
  }
}

@immutable
final class StrokeStyle {
  const StrokeStyle({
    required this.tool,
    required this.colorArgb,
    required this.width,
    this.opacity = 1.0,
    this.pressureSensitivity = 1.0,
    this.pressureCurve = PressureCurve.linear,
    this.smoothing = 0.5,
    this.extras = const {},
  });

  /// Default style per tool = default preset values (contract 7.2.4 table, CORE 6.2.2).
  factory StrokeStyle.defaultsFor(PenTool tool) => switch (tool) {
    PenTool.ballpoint => const StrokeStyle(
      tool: PenTool.ballpoint,
      colorArgb: 0xFF1A1A1A,
      width: 1.6,
    ),
    PenTool.fountain => const StrokeStyle(
      tool: PenTool.fountain,
      colorArgb: 0xFF1B2A6B,
      width: 2.2,
      smoothing: 0.55,
    ),
    PenTool.highlighter => const StrokeStyle(
      tool: PenTool.highlighter,
      colorArgb: 0xFFFFE600,
      width: 12.0,
      opacity: 0.35,
      smoothing: 0.3,
      extras: {'hlStraight': 'off'},
    ),
    PenTool.pencil => const StrokeStyle(
      tool: PenTool.pencil,
      colorArgb: 0xFF3C3C3C,
      width: 1.4,
      opacity: 0.9,
      smoothing: 0.4,
    ),
    PenTool.marker => const StrokeStyle(
      tool: PenTool.marker,
      colorArgb: 0xFF1A1A1A,
      width: 5.0,
    ),
    PenTool.brush => const StrokeStyle(
      tool: PenTool.brush,
      colorArgb: 0xFF1F1F1F,
      width: 2.0,
    ),
    PenTool.calligraphy => const StrokeStyle(
      tool: PenTool.calligraphy,
      colorArgb: 0xFF1F1F1F,
      width: 2.5,
      extras: {'nibAngleDeg': 45},
    ),
    PenTool.dashed => const StrokeStyle(
      tool: PenTool.dashed,
      colorArgb: 0xFF1F1F1F,
      width: 1.0,
      extras: {
        'dash': [4, 3],
      },
    ),
    PenTool.laser => const StrokeStyle(
      tool: PenTool.laser,
      colorArgb: 0xFFFF3B30,
      width: 3.0,
    ),
    PenTool.tape => const StrokeStyle(
      tool: PenTool.tape,
      colorArgb: 0xFF7E57C2,
      width: 14.0,
      smoothing: 0.3,
    ),
  };

  static const double minWidth = 0.1, maxWidth = 30.0; // pt
  static const double minOpacity = 0.05;

  final PenTool tool;
  // alpha forced to 0xFF by normalized(); transparency = opacity
  final int colorArgb;
  final double width; // pt, nominal diameter at width factor 1.0
  final double opacity; // [0.05, 1]
  final double pressureSensitivity; // [0, 1]; multiplies INK PenProfile.pressureGain (1 = full)
  // applied by INK at input time to real pressure only
  final PressureCurve pressureCurve;
  final double smoothing; // [0, 1]; INK 1-euro filter strength, input time
  // JSON-safe; keys owned by INK (InkStyleExtras)
  final Map<String, Object?> extras;

  /// == opacity once normalized
  double get effectiveAlpha => (colorArgb ~/ 0x1000000 % 256) / 255 * opacity;

  /// Clamps every range above, color alpha := 0xFF
  StrokeStyle normalized() => StrokeStyle(
    tool: tool,
    colorArgb: 0xFF000000 + colorArgb % 0x1000000,
    width: _clamp(width, minWidth, maxWidth, 1.6),
    opacity: _clamp(opacity, minOpacity, 1, 1),
    pressureSensitivity: _clamp(pressureSensitivity, 0, 1, 1),
    pressureCurve: PressureCurve(
      x1: _clamp(pressureCurve.x1, 0, 1, 0.25),
      y1: _clamp(pressureCurve.y1, 0, 1, 0.25),
      x2: _clamp(pressureCurve.x2, 0, 1, 0.75),
      y2: _clamp(pressureCurve.y2, 0, 1, 0.75),
    ),
    smoothing: _clamp(smoothing, 0, 1, 0.5),
    extras: extras,
  );

  static double _clamp(double v, double lo, double hi, double nanDefault) =>
      v.isNaN ? nanDefault : v.clamp(lo, hi).toDouble();

  StrokeStyle copyWith({
    PenTool? tool,
    int? colorArgb,
    double? width,
    double? opacity,
    double? pressureSensitivity,
    PressureCurve? pressureCurve,
    double? smoothing,
    Map<String, Object?>? extras,
  }) => StrokeStyle(
    tool: tool ?? this.tool,
    colorArgb: colorArgb ?? this.colorArgb,
    width: width ?? this.width,
    opacity: opacity ?? this.opacity,
    pressureSensitivity: pressureSensitivity ?? this.pressureSensitivity,
    pressureCurve: pressureCurve ?? this.pressureCurve,
    smoothing: smoothing ?? this.smoothing,
    extras: extras ?? this.extras,
  );

  Map<String, Object?> toJson() => {
    'tool': tool.wireName,
    'color': colorArgb,
    'width': width,
    'opacity': opacity,
    'pressureSensitivity': pressureSensitivity,
    'pressureCurve': pressureCurve.toJson(),
    'smoothing': smoothing,
    'extras': extras,
  };

  factory StrokeStyle.fromJson(Map<String, Object?> json) {
    final curve = json['pressureCurve'];
    return StrokeStyle(
      tool: PenTool.fromWireName(readString(json, 'tool')),
      colorArgb: readInt(json, 'color'),
      width: readDouble(json, 'width'),
      opacity: readDoubleOr(json, 'opacity', 1.0),
      pressureSensitivity: readDoubleOr(json, 'pressureSensitivity', 1.0),
      pressureCurve: curve == null
          ? PressureCurve.linear
          : PressureCurve.fromJson(asList(curve, 'pressureCurve')),
      smoothing: readDoubleOr(json, 'smoothing', 0.5),
      extras: readExtras(json, 'extras'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StrokeStyle &&
      other.tool == tool &&
      other.colorArgb == colorArgb &&
      other.width == width &&
      other.opacity == opacity &&
      other.pressureSensitivity == pressureSensitivity &&
      other.pressureCurve == pressureCurve &&
      other.smoothing == smoothing &&
      _deep.equals(other.extras, extras);

  @override
  int get hashCode => Object.hash(
    tool,
    colorArgb,
    width,
    opacity,
    pressureSensitivity,
    pressureCurve,
    smoothing,
    _deep.hash(extras),
  );

  @override
  String toString() =>
      'StrokeStyle(${tool.name}, 0x${colorArgb.toRadixString(16)}, '
      'width: $width, opacity: $opacity)';
}

/// Partial style change used by RestyleStrokes (lasso color/width change). CORE 4.2.
@immutable
final class StrokeStylePatch {
  const StrokeStylePatch({
    this.colorArgb,
    this.width,
    this.widthScale,
    this.opacity,
  });

  final int? colorArgb;
  final double? width; // absolute width; wins over widthScale
  final double? widthScale; // multiply current width
  final double? opacity;

  bool get isEmpty =>
      colorArgb == null &&
      width == null &&
      widthScale == null &&
      opacity == null;

  /// Result is normalized()
  StrokeStyle applyTo(StrokeStyle style) => style
      .copyWith(
        colorArgb: colorArgb,
        width: width ?? (widthScale == null ? null : style.width * widthScale!),
        opacity: opacity,
      )
      .normalized();

  @override
  bool operator ==(Object other) =>
      other is StrokeStylePatch &&
      other.colorArgb == colorArgb &&
      other.width == width &&
      other.widthScale == widthScale &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(colorArgb, width, widthScale, opacity);
}
