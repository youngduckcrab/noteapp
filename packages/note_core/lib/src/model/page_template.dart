// lib/src/model/page_template.dart, paper_colors.dart — contract 00-overview 7.2.5 / CORE 4.2.3.
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../common/json_read.dart';

const DeepCollectionEquality _deep = DeepCollectionEquality();

// INK draws all six
enum PageTemplateKind { lined, grid, dotted, cornell, music, planner }

@immutable
final class PageTemplate {
  const PageTemplate({
    required this.kind,
    this.spacing,
    this.lineColorArgb,
    this.lineWidth,
    this.extras = const {},
  });

  /// All parameters null → INK defaults (03-ink 6.16 is the single source of default values).
  factory PageTemplate.defaults(PageTemplateKind kind) =>
      PageTemplate(kind: kind);

  final PageTemplateKind kind;
  final double? spacing; // pt; null = INK default
  final int? lineColorArgb; // null = INK picks by paper luminance (dark paper → light lines)
  final double? lineWidth; // pt; null = INK default
  final Map<String, Object?> extras; // keys: TemplateExtrasKeys

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'spacing': spacing,
    'lineColor': lineColorArgb,
    'lineWidth': lineWidth,
    'extras': extras,
  };

  factory PageTemplate.fromJson(Map<String, Object?> json) {
    final kindName = readString(json, 'kind');
    final kind = PageTemplateKind.values.firstWhere(
      (k) => k.name == kindName,
      orElse: () => throw FormatException('Unknown template kind', kindName),
    );
    return PageTemplate(
      kind: kind,
      spacing: readDoubleOrNull(json, 'spacing'),
      lineColorArgb: readIntOrNull(json, 'lineColor'),
      lineWidth: readDoubleOrNull(json, 'lineWidth'),
      extras: readExtras(json, 'extras'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PageTemplate &&
      other.kind == kind &&
      other.spacing == spacing &&
      other.lineColorArgb == lineColorArgb &&
      other.lineWidth == lineWidth &&
      _deep.equals(other.extras, extras);

  @override
  int get hashCode =>
      Object.hash(kind, spacing, lineColorArgb, lineWidth, _deep.hash(extras));

  @override
  String toString() => 'PageTemplate(${kind.name})';
}

abstract final class TemplateExtrasKeys {
  static const String marginTop = 'marginTop', marginLeft = 'marginLeft';
  static const String showMarginLine = 'showMarginLine';
  static const String headerHeight = 'headerHeight',
      cueColumnWidth = 'cueColumnWidth';
  static const String summaryHeight = 'summaryHeight'; // cornell
  static const String staffGap = 'staffGap'; // music
  static const String plannerLayout = 'layout'; // planner: 'weekly'
}

abstract final class PaperColors {
  static const int white = 0xFFFFFFFF;
  static const int ivory = 0xFFFBF7EC; // 미색
  static const int gray = 0xFFF1F3F4;
  static const int black = 0xFF202124;
  static const List<int> all = [white, ivory, gray, black];

  /// WCAG relative luminance, no bit ops
  static double luminance(int argb) {
    final r = (argb ~/ 65536) % 256;
    final g = (argb ~/ 256) % 256;
    final b = argb % 256;
    return 0.2126 * _linear(r) + 0.7152 * _linear(g) + 0.0722 * _linear(b);
  }

  static double _linear(int channel) {
    final c = channel / 255;
    return c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  /// luminance < 0.5
  static bool isDark(int argb) => luminance(argb) < 0.5;
}
