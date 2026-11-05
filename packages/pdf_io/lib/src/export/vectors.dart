// lib/src/export/vectors.dart — renderer-neutral vectors (page pt, y down), 06-pdf 4.9,
// 6.11.5, 6.11.8.
//
// Foundation step B4 (T0): types and plain getters; the path helpers and alpha255 come
// with PDF T12.
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

enum PdfBlend { normal, multiply }

enum PdfFillRule { evenOdd, nonZero }

enum PdfLineCap { butt, round, square }

enum PdfLineJoin { miter, round, bevel }

/// Verb codes equal ink.InkPathVerb indices: 0 moveTo(2), 1 lineTo(2), 2 cubicTo(6), 3 close(0).
@immutable
final class PdfVectorPath {
  const PdfVectorPath(this.verbs, this.coords);
  factory PdfVectorPath.rect(ui.Rect rect) =>
      throw UnimplementedError('PdfVectorPath.rect (PDF T12)');

  /// Each circle = 4 cubic Béziers (k = 0.5523), one subpath per circle.
  factory PdfVectorPath.circles(List<(ui.Offset, double)> centersAndRadii) =>
      throw UnimplementedError('PdfVectorPath.circles (PDF T12)');

  /// Concatenates subpaths (each input must start with moveTo).
  factory PdfVectorPath.concat(List<PdfVectorPath> paths) =>
      throw UnimplementedError('PdfVectorPath.concat (PDF T12)');
  final Uint8List verbs;
  final Float32List coords;
  bool get isEmpty => verbs.isEmpty;
}

sealed class PdfVectorItem {
  const PdfVectorItem({
    required this.path,
    required this.colorArgb,
    required this.opacity,
    this.blend = PdfBlend.normal,
  });
  final PdfVectorPath path;
  final int colorArgb; // alpha byte multiplies opacity
  final double opacity; // 0..1
  final PdfBlend blend;

  /// round(255 * opacity * alpha(colorArgb) / 255), computed without bit ops.
  int get alpha255 =>
      throw UnimplementedError('PdfVectorItem.alpha255 (PDF T12)');
}

final class PdfFillItem extends PdfVectorItem {
  const PdfFillItem({
    required super.path,
    required super.colorArgb,
    super.opacity = 1,
    super.blend,
    this.fillRule = PdfFillRule.nonZero,
  });
  final PdfFillRule fillRule;
}

final class PdfStrokeItem extends PdfVectorItem {
  const PdfStrokeItem({
    required super.path,
    required super.colorArgb,
    super.opacity = 1,
    super.blend,
    required this.width,
    this.cap = PdfLineCap.round,
    this.join = PdfLineJoin.round,
  });
  final double width; // pt
  final PdfLineCap cap;
  final PdfLineJoin join;
}

@immutable
final class PdfPageVectors {
  const PdfPageVectors({this.underlay = const [], this.ink = const []});
  static const PdfPageVectors empty = PdfPageVectors();

  /// paper fill + template (blank/template pages only)
  final List<PdfVectorItem> underlay;

  /// highlighter strokes first, then fills in z-order
  final List<PdfVectorItem> ink;
  bool get isEmpty => underlay.isEmpty && ink.isEmpty;
}

/// Port to INK's vector export (default InkEngineVectorizer in ink_adapter/).
abstract interface class PdfInkVectorizer {
  PdfPageVectors vectorize(
    core.Page page,
    List<core.Stroke> strokes, {
    required bool includeInk,
    required bool includeTemplate,
  });
}
