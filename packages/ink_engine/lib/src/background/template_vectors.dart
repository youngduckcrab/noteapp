// lib/src/background/template_vectors.dart — TemplateVectorItem / TemplateLine /
// TemplateDot (INK 4.10), contract 7.2.16.
import 'dart:ui' show Offset, Rect, Size;

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

sealed class TemplateVectorItem {
  const TemplateVectorItem();
}

@immutable
final class TemplateLine extends TemplateVectorItem {
  const TemplateLine(
    this.p0,
    this.p1, {
    required this.width,
    required this.colorArgb,
  });
  final Offset p0;
  final Offset p1;
  final double width;
  final int colorArgb;

  @override
  bool operator ==(Object other) =>
      other is TemplateLine &&
      other.p0 == p0 &&
      other.p1 == p1 &&
      other.width == width &&
      other.colorArgb == colorArgb;

  @override
  int get hashCode => Object.hash(p0, p1, width, colorArgb);
}

@immutable
final class TemplateDot extends TemplateVectorItem {
  const TemplateDot(
    this.center, {
    required this.radius,
    required this.colorArgb,
  });
  final Offset center;
  final double radius;
  final int colorArgb;

  @override
  bool operator ==(Object other) =>
      other is TemplateDot &&
      other.center == center &&
      other.radius == radius &&
      other.colorArgb == colorArgb;

  @override
  int get hashCode => Object.hash(center, radius, colorArgb);
}

abstract final class TemplateVectors {
  /// Lines / dots (no paper fill) in page pt, y down. Used by the painter and PDF export.
  ///
  /// Foundation step B3 (03-ink 4.15): returns an empty list for every kind. The six
  /// templates with the 6.16 defaults come with INK T13 / T13b (signature unchanged).
  static List<TemplateVectorItem> build(
    core.PageTemplate template, {
    required Size pageSize,
    required int paperColorArgb,
    Rect? clip,
  }) => const [];
}
