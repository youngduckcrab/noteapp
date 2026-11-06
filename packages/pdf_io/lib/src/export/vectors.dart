// lib/src/export/vectors.dart — renderer-neutral vectors (page pt, y down), 06-pdf 4.9,
// 6.11.5, 6.11.8; (2차) the page plan items of m5-7/06-pdf 4.1.3.
//
// Foundation step B4 (T0): types and plain getters; the path helpers and alpha255 are
// PDF T12. Web-safe numbers: ARGB channels with ~/ and %, no bit operations (7.4.3).
//
// 2차 foundation step R2-B4 (m5-7/06-pdf T20): the plan items (PdfPlanItem / PdfDrawItem
// families, PdfAffine, PdfPagePlan) and PdfInkVectorizer.planPage with their final
// signatures. PdfAffine (6.2.3 formulas), the value equality of the plan items and
// PdfPagePlan.isEmpty / hasReferences already work; resolving the *Ref items (6.2.4) and
// encoding image / text items (6.2.6) come with PDF T21–T26.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
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

/// Everything a page plan holds, in paint order (L-1, 6.2.1). PdfDrawItem = ready to encode;
/// the *Ref items are resolved by the export service (6.2.4) and never reach the encoder.
sealed class PdfPlanItem {
  const PdfPlanItem();
}

/// A plan item the encoder takes as it is (vector paths, image and text objects).
sealed class PdfDrawItem extends PdfPlanItem {
  const PdfDrawItem();
}

/// 1차 그대로 — path, colorArgb, opacity, blend, alpha255. (2차) now a PdfDrawItem.
sealed class PdfVectorItem extends PdfDrawItem {
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

// --- (2차, m5-7/06-pdf 4.1.3) page plan items -----------------------------------------------

/// 2D affine, PDF order: x' = a·x + c·y + e, y' = b·x + d·y + f (note pt unless stated).
@immutable
final class PdfAffine {
  const PdfAffine(this.a, this.b, this.c, this.d, this.e, this.f);
  static const PdfAffine identity = PdfAffine(1, 0, 0, 1, 0, 0);

  /// Frame-local pt (origin = unrotated rect top-left) → note pt, rotating about the center.
  ///
  /// 6.2.3: local (x, y) → c + R(θ)·((x, y) − (w/2, h/2)) with c the rect center and
  /// R(θ) = [[cos θ, −sin θ], [sin θ, cos θ]] (y down, so θ > 0 turns clockwise on screen —
  /// the same rule as core.ElementFrame.corners). Rotation 0 is the exact translation to the
  /// rect's top-left corner.
  factory PdfAffine.frame(core.ElementFrame frame) {
    final r = frame.rect;
    if (frame.rotation == 0) return PdfAffine(1, 0, 0, 1, r.left, r.top);
    final cos = math.cos(frame.rotation), sin = math.sin(frame.rotation);
    final cx = (r.left + r.right) / 2, cy = (r.top + r.bottom) / 2;
    final hw = (r.right - r.left) / 2, hh = (r.bottom - r.top) / 2;
    return PdfAffine(
      cos,
      sin,
      -sin,
      cos,
      cx - hw * cos + hh * sin,
      cy - hw * sin - hh * cos,
    );
  }

  final double a, b, c, d, e, f;

  /// outer ∘ this (apply this first)
  PdfAffine then(PdfAffine outer) => PdfAffine(
    outer.a * a + outer.c * b,
    outer.b * a + outer.d * b,
    outer.a * c + outer.c * d,
    outer.b * c + outer.d * d,
    outer.a * e + outer.c * f + outer.e,
    outer.b * e + outer.d * f + outer.f,
  );

  ui.Offset apply(ui.Offset p) =>
      ui.Offset(a * p.dx + c * p.dy + e, b * p.dx + d * p.dy + f);

  @override
  bool operator ==(Object other) =>
      other is PdfAffine &&
      other.a == a &&
      other.b == b &&
      other.c == c &&
      other.d == d &&
      other.e == e &&
      other.f == f;

  @override
  int get hashCode => Object.hash(a, b, c, d, e, f);

  @override
  String toString() => 'PdfAffine($a, $b, $c, $d, $e, $f)';
}

/// Image pixels as PDFium takes them.
///
/// The subtypes hold bytes and keep identity equality (like 1차 byte payloads).
sealed class PdfImageData {
  const PdfImageData({required this.width, required this.height});
  final int width, height;
  int get byteLength;
}

/// JPEG bytes as stored (M-3: baseline/progressive, EXIF orientation already baked — 6.12).
final class PdfJpegData extends PdfImageData {
  const PdfJpegData(this.bytes, {required super.width, required super.height});
  final Uint8List bytes;

  @override
  int get byteLength => bytes.length;

  @override
  String toString() => 'PdfJpegData(${width}x$height, ${bytes.length} B)';
}

/// Straight (not premultiplied) RGBA8888, top row first. Any alpha < 255 → the PDF image gets
/// an SMask (확인함 — 6.1 E3).
final class PdfRgbaData extends PdfImageData {
  const PdfRgbaData(
    this.rgba, {
    required super.width,
    required super.height,
    required this.hasAlpha,
  });
  final Uint8List rgba;
  final bool hasAlpha;

  @override
  int get byteLength => rgba.length;

  @override
  String toString() =>
      'PdfRgbaData(${width}x$height, ${rgba.length} B, hasAlpha: $hasAlpha)';
}

/// [matrix] maps the image's unit square (PDF image space: x right, y UP; (0, 1) = top-left
/// pixel) to note pt.
@immutable
final class PdfImageItem extends PdfDrawItem {
  const PdfImageItem({required this.image, required this.matrix});
  final PdfImageData image;
  final PdfAffine matrix;

  /// The same image (identity — it holds bytes) under an equal matrix.
  @override
  bool operator ==(Object other) =>
      other is PdfImageItem &&
      identical(other.image, image) &&
      other.matrix == matrix;

  @override
  int get hashCode => Object.hash(identityHashCode(image), matrix);

  @override
  String toString() => 'PdfImageItem($image, $matrix)';
}

/// One text line = one PDF text object. [matrix] maps text space (origin = baseline start,
/// x right, y UP, 1 unit = 1 pt) to note pt. [fontId]: PdfComposeOpcodes.fontRegular / fontBold.
@immutable
final class PdfTextItem extends PdfDrawItem {
  const PdfTextItem({
    required this.text,
    required this.fontId,
    required this.fontSize,
    required this.colorArgb,
    required this.matrix,
  });
  final String text;
  final int fontId;
  final double fontSize; // pt
  final int colorArgb; // alpha byte used as fill alpha
  final PdfAffine matrix;

  @override
  bool operator ==(Object other) =>
      other is PdfTextItem &&
      other.text == text &&
      other.fontId == fontId &&
      other.fontSize == fontSize &&
      other.colorArgb == colorArgb &&
      other.matrix == matrix;

  @override
  int get hashCode => Object.hash(text, fontId, fontSize, colorArgb, matrix);

  @override
  String toString() =>
      'PdfTextItem(${text.length} chars, font $fontId, $fontSize pt, $matrix)';
}

// --- references: resolved by the export service (6.2.4) ---

/// An image asset placed as an image object ([frame]) or as the page's image background ([fit]).
@immutable
final class PdfAssetImageRef extends PdfPlanItem {
  const PdfAssetImageRef.object({
    required this.assetId,
    required core.ElementFrame this.frame,
  }) : fit = null,
       pageSize = null;
  const PdfAssetImageRef.background({
    required this.assetId,
    required core.ImageFit this.fit,
    required ui.Size this.pageSize,
  }) : frame = null;
  final core.AssetId assetId;
  final core.ElementFrame? frame;
  final core.ImageFit? fit;
  final ui.Size? pageSize;

  @override
  bool operator ==(Object other) =>
      other is PdfAssetImageRef &&
      other.assetId == assetId &&
      other.frame == frame &&
      other.fit == fit &&
      other.pageSize == pageSize;

  @override
  int get hashCode => Object.hash(assetId, frame, fit, pageSize);

  @override
  String toString() => frame != null
      ? 'PdfAssetImageRef.object($assetId, $frame)'
      : 'PdfAssetImageRef.background($assetId, ${fit?.name}, $pageSize)';
}

/// INK's text lines (frame-local pt, laid out with NoteSans). Empty when NoteSans was not loaded
/// at export time (CP-INK-9) → the resolver rasterizes the box.
typedef PdfTextLine = ({String text, double x, double baselineY, double width});

@immutable
final class PdfTextBoxRef extends PdfPlanItem {
  const PdfTextBoxRef(this.object, this.lines);
  final core.TextBoxObject object;
  final List<PdfTextLine> lines;

  @override
  bool operator ==(Object other) =>
      other is PdfTextBoxRef &&
      other.object == object &&
      const ListEquality<PdfTextLine>().equals(other.lines, lines);

  @override
  int get hashCode =>
      Object.hash(object, const ListEquality<PdfTextLine>().hash(lines));

  @override
  String toString() => 'PdfTextBoxRef(${object.id}, ${lines.length} lines)';
}

@immutable
final class PdfMathRef extends PdfPlanItem {
  const PdfMathRef(this.object);
  final core.MathObject object;

  @override
  bool operator ==(Object other) =>
      other is PdfMathRef && other.object == object;

  @override
  int get hashCode => object.hashCode;

  @override
  String toString() => 'PdfMathRef(${object.id})';
}

/// Everything one output page draws, in paint order (6.2.1).
@immutable
final class PdfPagePlan {
  const PdfPagePlan(this.items);
  static const PdfPagePlan empty = PdfPagePlan([]);
  final List<PdfPlanItem> items; // paint order (6.2.1)

  /// No items at all.
  bool get isEmpty => items.isEmpty;

  /// any *Ref
  bool get hasReferences => items.any((item) => item is! PdfDrawItem);

  /// Same items in the same order (each item's own ==; vector items keep identity).
  @override
  bool operator ==(Object other) =>
      other is PdfPagePlan &&
      const ListEquality<PdfPlanItem>().equals(other.items, items);

  @override
  int get hashCode => const ListEquality<PdfPlanItem>().hash(items);

  @override
  String toString() => 'PdfPagePlan(${items.length} items)';
}

/// Port to INK's vector export (default InkEngineVectorizer in ink_adapter/). (2차) planPage
/// added.
abstract interface class PdfInkVectorizer {
  /// 1차 그대로 (strokes only).
  PdfPageVectors vectorize(
    core.Page page,
    List<core.Stroke> strokes, {
    required bool includeInk,
    required bool includeTemplate,
  });

  /// (2차) The whole page in L-1 order (6.2.1). includeInk false → background only (paper,
  /// template, image background). Objects of [content] are drawn; UnknownObject is skipped.
  PdfPagePlan planPage(
    core.PageContent content, {
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
