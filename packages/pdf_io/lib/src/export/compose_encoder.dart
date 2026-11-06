// lib/src/export/compose_encoder.dart — 06-pdf 4.9, 6.11.5 (PDF T12).
//
// One output page's vectors → the binary ops the compose backends interpret (6.11.5):
// verbs (Uint8), coords (Float32, note page pt, y down), paints (Float32, stride 10). Every
// item becomes one PDF path object: its path verbs (codes = ink.InkPathVerb indices), then
// endObject with one coordinate, the paint index. Equal paints share one index.
//
// (2차, m5-7/06-pdf T21 — 4.1.4, 6.2.6) encodeItems: one page's draw items in paint order →
// parts (paths, `image` ops, `text` ops; fonts ride on the first part that uses them).
import 'dart:typed_data';

import '../tuning.dart';
import 'compose_plan.dart';
import 'vectors.dart';

abstract final class PdfComposeEncoder {
  /// underlay then ink; every item becomes one PDF path object (6.11.5).
  ///
  /// T12: items with an empty path are skipped (nothing to draw); a path that does not start
  /// with moveTo, or whose coords do not match its verbs, is an ArgumentError.
  static PdfComposePageOps encode({
    required int outputIndex,
    required PdfPageVectors vectors,
  }) {
    final items = [
      for (final item in vectors.underlay)
        if (!item.path.isEmpty) item,
      for (final item in vectors.ink)
        if (!item.path.isEmpty) item,
    ];
    var verbCount = 0, coordCount = 0;
    for (final item in items) {
      _check(item.path);
      verbCount += item.path.verbs.length + 1;
      coordCount += item.path.coords.length + 1;
    }
    final verbs = Uint8List(verbCount);
    final coords = Float32List(coordCount);
    final paintIndex = <String, int>{};
    final paints = <double>[];
    var v = 0, c = 0;
    for (final item in items) {
      verbs.setAll(v, item.path.verbs);
      coords.setAll(c, item.path.coords);
      v += item.path.verbs.length;
      c += item.path.coords.length;
      final paint = _paint(item);
      final key = paint.join(',');
      final index = paintIndex.putIfAbsent(key, () {
        paints.addAll(paint);
        return paintIndex.length;
      });
      verbs[v++] = PdfComposeOpcodes.endObject;
      coords[c++] = index.toDouble();
    }
    return PdfComposePageOps(
      outputIndex: outputIndex,
      verbs: verbs,
      coords: coords,
      paints: Float32List.fromList(paints),
    );
  }

  /// (2차) [items] in paint order → parts of ONE page, in order. A part holds at most
  /// PdfTuning.exportChunkMaxBytes, except a single image larger than that (alone in its part —
  /// 7.4.5 '이미지 객체 임시 16 MB'). Fonts in [fontBytes] whose id is not in [sentFonts] ride on
  /// the first part that uses them; [sentFonts] is updated. Empty paths are skipped (1차).
  ///
  /// T21: no drawable item → no part. A part is cut before the item that would take it past
  /// the limit (byteLength of 6.2.6: verbs, coords and paints as sent, image bytes, 2 B per
  /// text code unit, font bytes), so any single item larger than the limit sits alone. Paints
  /// are shared within a part only. A text item whose font is neither in [sentFonts] nor in
  /// [fontBytes] is an ArgumentError, as is a bad path (1차 rules).
  static List<PdfComposePageOps> encodeItems({
    required int outputIndex,
    required List<PdfDrawItem> items,
    required Map<int, Uint8List> fontBytes,
    required Set<int> sentFonts,
  }) {
    final parts = <PdfComposePageOps>[];
    final sent = {...sentFonts};
    var part = _PartBuilder(outputIndex);
    for (final item in items) {
      if (item is PdfVectorItem) {
        if (item.path.isEmpty) continue;
        _check(item.path);
      }
      Uint8List? font;
      if (item is PdfTextItem && !sent.contains(item.fontId)) {
        font = fontBytes[item.fontId];
        if (font == null) {
          throw ArgumentError.value(
            item.fontId,
            'fontId',
            'no font bytes for a font not sent yet',
          );
        }
      }
      if (!part.isEmpty &&
          part.byteLength + part.cost(item, font) >
              PdfTuning.exportChunkMaxBytes) {
        parts.add(part.build());
        part = _PartBuilder(outputIndex);
      }
      part.add(item, font);
      if (item is PdfTextItem) sent.add(item.fontId);
    }
    if (!part.isEmpty) parts.add(part.build());
    sentFonts.addAll(sent);
    return parts;
  }

  /// [type(0 fill, 1 stroke), r, g, b, a(0..255), width, cap, join, blend, fillMode].
  static List<double> _paint(PdfVectorItem item) {
    final argb = item.colorArgb;
    final blend = switch (item.blend) {
      PdfBlend.normal => 0.0,
      PdfBlend.multiply => 1.0,
    };
    final rgba = [
      argbChannel(argb, 2).toDouble(),
      argbChannel(argb, 1).toDouble(),
      argbChannel(argb, 0).toDouble(),
      item.alpha255.toDouble(),
    ];
    return switch (item) {
      PdfFillItem(:final fillRule) => [
        0,
        ...rgba,
        0,
        0,
        0,
        blend,
        switch (fillRule) {
          PdfFillRule.evenOdd => PdfComposeOpcodes.fillModeEvenOdd.toDouble(),
          PdfFillRule.nonZero => PdfComposeOpcodes.fillModeNonZero.toDouble(),
        },
      ],
      PdfStrokeItem(:final width, :final cap, :final join) => [
        1,
        ...rgba,
        width,
        switch (cap) {
          PdfLineCap.butt => 0,
          PdfLineCap.round => 1,
          PdfLineCap.square => 2,
        },
        switch (join) {
          PdfLineJoin.miter => 0,
          PdfLineJoin.round => 1,
          PdfLineJoin.bevel => 2,
        },
        blend,
        0,
      ],
    };
  }

  static void _check(PdfVectorPath path) {
    if (path.verbs.first != PdfComposeOpcodes.moveTo) {
      throw ArgumentError.value(path, 'path', 'must start with moveTo');
    }
    var expected = 0;
    for (final verb in path.verbs) {
      expected += switch (verb) {
        PdfComposeOpcodes.moveTo || PdfComposeOpcodes.lineTo => 2,
        PdfComposeOpcodes.cubicTo => 6,
        PdfComposeOpcodes.close => 0,
        _ => throw ArgumentError.value(verb, 'verb', 'unknown path verb'),
      };
    }
    if (expected != path.coords.length) {
      throw ArgumentError.value(
        path.coords.length,
        'coords',
        '$expected values expected for ${path.verbs.length} verbs',
      );
    }
  }
}

/// One part under construction (encodeItems).
final class _PartBuilder {
  _PartBuilder(this.outputIndex);

  final int outputIndex;
  final BytesBuilder _verbs = BytesBuilder(copy: false);
  final List<double> _coords = [];
  final List<double> _paints = [];
  final Map<String, int> _paintIndex = {};
  final List<PdfImageData> _images = [];
  final List<String> _texts = [];
  final Map<int, Uint8List> fonts = {};
  int byteLength = 0;

  bool get isEmpty => _verbs.isEmpty;

  /// Bytes [item] adds to this part ([font]: bytes it would carry, if any).
  int cost(PdfDrawItem item, Uint8List? font) => switch (item) {
    PdfVectorItem(:final path) =>
      path.verbs.length +
          1 +
          4 * (path.coords.length + 1) +
          (_paintIndex.containsKey(_paintKey(item))
              ? 0
              : 4 * PdfComposeOpcodes.paintStride),
    PdfImageItem(:final image) =>
      1 + 4 * PdfComposeOpcodes.imageArgs + image.byteLength,
    PdfTextItem(:final text) =>
      1 +
          4 * PdfComposeOpcodes.textArgs +
          2 * text.length +
          (font == null ? 0 : font.lengthInBytes),
  };

  void add(PdfDrawItem item, Uint8List? font) {
    byteLength += cost(item, font);
    switch (item) {
      case PdfVectorItem(:final path):
        _verbs.add(path.verbs);
        _coords.addAll(path.coords);
        final key = _paintKey(item);
        final index = _paintIndex.putIfAbsent(key, () {
          _paints.addAll(PdfComposeEncoder._paint(item));
          return _paintIndex.length;
        });
        _verbs.addByte(PdfComposeOpcodes.endObject);
        _coords.add(index.toDouble());
      case PdfImageItem(:final image, :final matrix):
        _verbs.addByte(PdfComposeOpcodes.image);
        _coords
          ..add(_images.length.toDouble())
          ..addAll(_matrix(matrix));
        _images.add(image);
      case PdfTextItem(
        :final text,
        :final fontId,
        :final fontSize,
        :final colorArgb,
        :final matrix,
      ):
        if (font != null) fonts[fontId] = font;
        _verbs.addByte(PdfComposeOpcodes.text);
        _coords
          ..add(_texts.length.toDouble())
          ..add(fontId.toDouble())
          ..add(fontSize)
          ..add(argbChannel(colorArgb, 2).toDouble())
          ..add(argbChannel(colorArgb, 1).toDouble())
          ..add(argbChannel(colorArgb, 0).toDouble())
          ..add(argbChannel(colorArgb, 3).toDouble())
          ..addAll(_matrix(matrix));
        _texts.add(text);
    }
  }

  PdfComposePageOps build() => PdfComposePageOps(
    outputIndex: outputIndex,
    verbs: _verbs.toBytes(),
    coords: Float32List.fromList(_coords),
    paints: Float32List.fromList(_paints),
    images: List.unmodifiable(_images),
    texts: List.unmodifiable(_texts),
    fonts: Map.unmodifiable(fonts),
  );

  static String _paintKey(PdfVectorItem item) =>
      PdfComposeEncoder._paint(item).join(',');

  static List<double> _matrix(PdfAffine m) => [m.a, m.b, m.c, m.d, m.e, m.f];
}
