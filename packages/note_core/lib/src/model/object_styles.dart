// lib/src/model/object_styles.dart — (v2.0) 2nd-round contract 7.2.2 / 02-core 4.2, 4.3,
// 6.2.3: ShapeStyle, TextAlignKind, TextBoxStyle, MathStyle. Normalization table (the
// contract's 'single source'): 02-core 6.2.3.
import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../common/json_read.dart';
import 'object_rules.dart';
import 'shape_geometry.dart';

@immutable
final class ShapeStyle {
  const ShapeStyle({
    required this.strokeColorArgb,
    this.strokeWidth = 2.0,
    this.strokeOpacity = 1.0,
    this.dash = LineDash.solid,
    this.fillColorArgb,
    this.fillOpacity = 1.0,
    this.arrowHeads = ArrowHeads.none,
  });
  static const double minWidth = 0.1, maxWidth = 30.0; // = StrokeStyle range

  // alpha forced to 0xFF by normalized() (1차 K-5와 같음)
  final int strokeColorArgb;
  final double strokeWidth; // pt
  final double strokeOpacity; // [0.05, 1]
  final LineDash dash;
  final int? fillColorArgb; // null = no fill
  final double fillOpacity; // [0, 1]
  final ArrowHeads arrowHeads; // line / arrow only; others ignore it

  /// Arrowhead length in pt: max(6, 3 * strokeWidth). Part of the bounds rule below.
  double get arrowHeadLength => math.max(6, 3 * strokeWidth);

  /// (CORE 6.2.3) Colors alpha 0xFF (opacity lives in the *Opacity fields), strokeWidth
  /// [0.1, 30], strokeOpacity [0.05, 1], fillOpacity [0, 1]; NaN → the default.
  ShapeStyle normalized() => ShapeStyle(
    strokeColorArgb: opaqueArgb(strokeColorArgb),
    strokeWidth: clampOr(strokeWidth, minWidth, maxWidth, 2.0),
    strokeOpacity: clampOr(strokeOpacity, 0.05, 1, 1.0),
    dash: dash,
    fillColorArgb: fillColorArgb == null ? null : opaqueArgb(fillColorArgb!),
    fillOpacity: clampOr(fillOpacity, 0, 1, 1.0),
    arrowHeads: arrowHeads,
  );
  ShapeStyle copyWith({
    int? strokeColorArgb,
    double? strokeWidth,
    double? strokeOpacity,
    LineDash? dash,
    int? fillColorArgb,
    bool clearFill = false,
    double? fillOpacity,
    ArrowHeads? arrowHeads,
  }) => ShapeStyle(
    strokeColorArgb: strokeColorArgb ?? this.strokeColorArgb,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    strokeOpacity: strokeOpacity ?? this.strokeOpacity,
    dash: dash ?? this.dash,
    fillColorArgb: clearFill ? null : fillColorArgb ?? this.fillColorArgb,
    fillOpacity: fillOpacity ?? this.fillOpacity,
    arrowHeads: arrowHeads ?? this.arrowHeads,
  );

  /// Every key always (fillColorArgb null when unset — CORE 6.3).
  Map<String, Object?> toJson() => {
    'strokeColorArgb': strokeColorArgb,
    'strokeWidth': strokeWidth,
    'strokeOpacity': strokeOpacity,
    'dash': dash.name,
    'fillColorArgb': fillColorArgb,
    'fillOpacity': fillOpacity,
    'arrowHeads': arrowHeads.name,
  };

  /// strokeColorArgb required; absent keys take the constructor defaults; an unknown `dash` /
  /// `arrowHeads` name is an UnknownEnumNameException (PageObject.fromJson → UnknownObject).
  /// Never normalizes (CORE 6.2.3).
  factory ShapeStyle.fromJson(Map<String, Object?> json) => ShapeStyle(
    strokeColorArgb: readInt(json, 'strokeColorArgb'),
    strokeWidth: readDoubleOr(json, 'strokeWidth', 2.0),
    strokeOpacity: readDoubleOr(json, 'strokeOpacity', 1.0),
    dash: readEnumOr(json, 'dash', LineDash.values, LineDash.solid),
    fillColorArgb: readIntOrNull(json, 'fillColorArgb'),
    fillOpacity: readDoubleOr(json, 'fillOpacity', 1.0),
    arrowHeads: readEnumOr(
      json,
      'arrowHeads',
      ArrowHeads.values,
      ArrowHeads.none,
    ),
  );

  // CORE 4.3: ==, hashCode (1차 7.4.4)
  @override
  bool operator ==(Object other) =>
      other is ShapeStyle &&
      other.strokeColorArgb == strokeColorArgb &&
      other.strokeWidth == strokeWidth &&
      other.strokeOpacity == strokeOpacity &&
      other.dash == dash &&
      other.fillColorArgb == fillColorArgb &&
      other.fillOpacity == fillOpacity &&
      other.arrowHeads == arrowHeads;

  @override
  int get hashCode => Object.hash(
    strokeColorArgb,
    strokeWidth,
    strokeOpacity,
    dash,
    fillColorArgb,
    fillOpacity,
    arrowHeads,
  );

  @override
  String toString() =>
      'ShapeStyle(0x${strokeColorArgb.toRadixString(16)}, $strokeWidth pt, '
      '${dash.name}${fillColorArgb == null ? '' : ', filled'})';
}

// --- text boxes, images, math ---
enum TextAlignKind { start, center, end }

@immutable
final class TextBoxStyle {
  const TextBoxStyle({
    this.fontSizePt = 16,
    this.colorArgb = 0xFF1A1A1A,
    this.bold = false,
    this.align = TextAlignKind.start,
    this.lineHeight = 1.4,
    this.backgroundArgb,
  });
  static const double minFontSize = 6, maxFontSize = 144;
  final double fontSizePt;
  final int colorArgb; // alpha 0xFF
  final bool bold;
  final TextAlignKind align;
  final double lineHeight; // [1.0, 3.0], multiple of fontSizePt
  final int? backgroundArgb; // null = transparent
  /// (CORE 6.2.3) fontSizePt [6, 144], colorArgb alpha 0xFF, lineHeight [1.0, 3.0],
  /// backgroundArgb as is (a translucent background is allowed); NaN → the default.
  TextBoxStyle normalized() => TextBoxStyle(
    fontSizePt: clampOr(fontSizePt, minFontSize, maxFontSize, 16),
    colorArgb: opaqueArgb(colorArgb),
    bold: bold,
    align: align,
    lineHeight: clampOr(lineHeight, 1.0, 3.0, 1.4),
    backgroundArgb: backgroundArgb,
  );
  TextBoxStyle copyWith({
    double? fontSizePt,
    int? colorArgb,
    bool? bold,
    TextAlignKind? align,
    double? lineHeight,
    int? backgroundArgb,
    bool clearBackground = false,
  }) => TextBoxStyle(
    fontSizePt: fontSizePt ?? this.fontSizePt,
    colorArgb: colorArgb ?? this.colorArgb,
    bold: bold ?? this.bold,
    align: align ?? this.align,
    lineHeight: lineHeight ?? this.lineHeight,
    backgroundArgb: clearBackground
        ? null
        : backgroundArgb ?? this.backgroundArgb,
  );

  /// Every key always (backgroundArgb null when unset — CORE 6.3).
  Map<String, Object?> toJson() => {
    'fontSizePt': fontSizePt,
    'colorArgb': colorArgb,
    'bold': bold,
    'align': align.name,
    'lineHeight': lineHeight,
    'backgroundArgb': backgroundArgb,
  };

  /// Absent keys take the constructor defaults; an unknown `align` name is an
  /// UnknownEnumNameException. Never normalizes.
  factory TextBoxStyle.fromJson(Map<String, Object?> json) => TextBoxStyle(
    fontSizePt: readDoubleOr(json, 'fontSizePt', 16),
    colorArgb: readIntOrNull(json, 'colorArgb') ?? 0xFF1A1A1A,
    bold: readBoolOr(json, 'bold', false),
    align: readEnumOr(json, 'align', TextAlignKind.values, TextAlignKind.start),
    lineHeight: readDoubleOr(json, 'lineHeight', 1.4),
    backgroundArgb: readIntOrNull(json, 'backgroundArgb'),
  );

  // CORE 4.3: ==, hashCode (1차 7.4.4)
  @override
  bool operator ==(Object other) =>
      other is TextBoxStyle &&
      other.fontSizePt == fontSizePt &&
      other.colorArgb == colorArgb &&
      other.bold == bold &&
      other.align == align &&
      other.lineHeight == lineHeight &&
      other.backgroundArgb == backgroundArgb;

  @override
  int get hashCode => Object.hash(
    fontSizePt,
    colorArgb,
    bold,
    align,
    lineHeight,
    backgroundArgb,
  );

  @override
  String toString() =>
      'TextBoxStyle($fontSizePt pt, 0x${colorArgb.toRadixString(16)}'
      '${bold ? ', bold' : ''}, ${align.name})';
}

@immutable
final class MathStyle {
  const MathStyle({this.colorArgb = 0xFF1A1A1A, this.fontSizePt = 18});
  static const double minFontSize = 6, maxFontSize = 144; // (v2.1, CP-5)
  final int colorArgb;
  final double fontSizePt; // [6, 144]; scaled by TransformElements
  // (v2.1) alpha 0xFF, size clamped
  MathStyle normalized() => MathStyle(
    colorArgb: opaqueArgb(colorArgb),
    fontSizePt: clampOr(fontSizePt, minFontSize, maxFontSize, 18),
  );
  // (v2.1)
  MathStyle copyWith({int? colorArgb, double? fontSizePt}) => MathStyle(
    colorArgb: colorArgb ?? this.colorArgb,
    fontSizePt: fontSizePt ?? this.fontSizePt,
  );
  Map<String, Object?> toJson() => {
    'colorArgb': colorArgb,
    'fontSizePt': fontSizePt,
  };

  /// Absent keys take the constructor defaults. Never normalizes.
  factory MathStyle.fromJson(Map<String, Object?> json) => MathStyle(
    colorArgb: readIntOrNull(json, 'colorArgb') ?? 0xFF1A1A1A,
    fontSizePt: readDoubleOr(json, 'fontSizePt', 18),
  );

  // CORE 4.3: ==, hashCode (1차 7.4.4)
  @override
  bool operator ==(Object other) =>
      other is MathStyle &&
      other.colorArgb == colorArgb &&
      other.fontSizePt == fontSizePt;

  @override
  int get hashCode => Object.hash(colorArgb, fontSizePt);

  @override
  String toString() =>
      'MathStyle(0x${colorArgb.toRadixString(16)}, $fontSizePt pt)';
}
