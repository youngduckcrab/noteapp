// lib/src/export/vectors.dart — renderer-neutral vectors (page pt, y down), 06-pdf 4.9,
// 6.11.5, 6.11.8.
//
// Foundation step B4 (T0): types and plain getters; the path helpers and alpha255 are
// PDF T12. Web-safe numbers: ARGB channels with ~/ and %, no bit operations (7.4.3).
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

  /// T12: one closed subpath, corners clockwise from the top left (y down).
  factory PdfVectorPath.rect(ui.Rect rect) => PdfVectorPath(
    Uint8List.fromList(const [_moveTo, _lineTo, _lineTo, _lineTo, _close]),
    Float32List.fromList([
      rect.left,
      rect.top,
      rect.right,
      rect.top,
      rect.right,
      rect.bottom,
      rect.left,
      rect.bottom,
    ]),
  );

  /// Each circle = 4 cubic Béziers (k = 0.5523), one subpath per circle.
  ///
  /// T12: a subpath starts at (cx + r, cy), goes through (cx, cy + r), (cx − r, cy),
  /// (cx, cy − r) and closes.
  factory PdfVectorPath.circles(List<(ui.Offset, double)> centersAndRadii) {
    final verbs = Uint8List(centersAndRadii.length * 6);
    final coords = Float32List(centersAndRadii.length * 26);
    var v = 0, c = 0;
    void put(double x, double y) {
      coords[c++] = x;
      coords[c++] = y;
    }

    for (final (center, r) in centersAndRadii) {
      final x = center.dx, y = center.dy, k = _kappa * r;
      verbs[v++] = _moveTo;
      put(x + r, y);
      verbs[v++] = _cubicTo;
      put(x + r, y + k);
      put(x + k, y + r);
      put(x, y + r);
      verbs[v++] = _cubicTo;
      put(x - k, y + r);
      put(x - r, y + k);
      put(x - r, y);
      verbs[v++] = _cubicTo;
      put(x - r, y - k);
      put(x - k, y - r);
      put(x, y - r);
      verbs[v++] = _cubicTo;
      put(x + k, y - r);
      put(x + r, y - k);
      put(x + r, y);
      verbs[v++] = _close;
    }
    return PdfVectorPath(verbs, coords);
  }

  /// Concatenates subpaths (each input must start with moveTo).
  ///
  /// T12: empty inputs are skipped; a non-empty input that does not start with moveTo is an
  /// ArgumentError.
  factory PdfVectorPath.concat(List<PdfVectorPath> paths) {
    var verbCount = 0, coordCount = 0;
    for (final path in paths) {
      if (path.isEmpty) continue;
      if (path.verbs.first != _moveTo) {
        throw ArgumentError.value(
          path,
          'paths',
          'a subpath must start with moveTo',
        );
      }
      verbCount += path.verbs.length;
      coordCount += path.coords.length;
    }
    final verbs = Uint8List(verbCount);
    final coords = Float32List(coordCount);
    var v = 0, c = 0;
    for (final path in paths) {
      if (path.isEmpty) continue;
      verbs.setAll(v, path.verbs);
      coords.setAll(c, path.coords);
      v += path.verbs.length;
      c += path.coords.length;
    }
    return PdfVectorPath(verbs, coords);
  }

  static const int _moveTo = 0, _lineTo = 1, _cubicTo = 2, _close = 3;
  static const double _kappa = 0.5523;

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
  ///
  /// T12: opacity is clamped to 0..1 first.
  int get alpha255 {
    final o = opacity.isNaN ? 0.0 : opacity.clamp(0.0, 1.0);
    return (255 * o * argbChannel(colorArgb, 3) / 255).round();
  }
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

/// Internal (not exported): channel [index] of an ARGB value — 3 alpha, 2 red, 1 green,
/// 0 blue — with ~/ and % only (web-safe, contract 7.4.3).
int argbChannel(int argb, int index) {
  var v = argb;
  for (var i = 0; i < index; i++) {
    v = v ~/ 256;
  }
  return v % 256;
}
