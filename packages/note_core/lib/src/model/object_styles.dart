// lib/src/model/object_styles.dart — (v2.0) 2nd-round contract 7.2.2 / 02-core 4.2, 4.3,
// 6.2.3: ShapeStyle, TextAlignKind, TextBoxStyle, MathStyle. Normalization table (the
// contract's 'single source'): 02-core 6.2.3.
import 'package:meta/meta.dart';

import '../common/pending.dart';
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
  double get arrowHeadLength => notYet('T20b', 'ShapeStyle.arrowHeadLength');
  ShapeStyle normalized() => notYet('T20b', 'ShapeStyle.normalized');
  ShapeStyle copyWith({
    int? strokeColorArgb,
    double? strokeWidth,
    double? strokeOpacity,
    LineDash? dash,
    int? fillColorArgb,
    bool clearFill = false,
    double? fillOpacity,
    ArrowHeads? arrowHeads,
  }) => notYet('T20b', 'ShapeStyle.copyWith');
  Map<String, Object?> toJson() => notYet('T20a', 'ShapeStyle.toJson');
  factory ShapeStyle.fromJson(Map<String, Object?> json) =>
      notYet('T20a', 'ShapeStyle.fromJson');

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
  TextBoxStyle normalized() => notYet('T20b', 'TextBoxStyle.normalized');
  TextBoxStyle copyWith({
    double? fontSizePt,
    int? colorArgb,
    bool? bold,
    TextAlignKind? align,
    double? lineHeight,
    int? backgroundArgb,
    bool clearBackground = false,
  }) => notYet('T20b', 'TextBoxStyle.copyWith');
  Map<String, Object?> toJson() => notYet('T20a', 'TextBoxStyle.toJson');
  factory TextBoxStyle.fromJson(Map<String, Object?> json) =>
      notYet('T20a', 'TextBoxStyle.fromJson');

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
  MathStyle normalized() => notYet('T20b', 'MathStyle.normalized');
  // (v2.1)
  MathStyle copyWith({int? colorArgb, double? fontSizePt}) =>
      notYet('T20b', 'MathStyle.copyWith');
  Map<String, Object?> toJson() => notYet('T20a', 'MathStyle.toJson');
  factory MathStyle.fromJson(Map<String, Object?> json) =>
      notYet('T20a', 'MathStyle.fromJson');

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
