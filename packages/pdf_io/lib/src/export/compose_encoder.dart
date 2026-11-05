// lib/src/export/compose_encoder.dart — 06-pdf 4.9, 6.11.5 (PDF T12).
//
// One output page's vectors → the binary ops the compose backends interpret (6.11.5):
// verbs (Uint8), coords (Float32, note page pt, y down), paints (Float32, stride 10). Every
// item becomes one PDF path object: its path verbs (codes = ink.InkPathVerb indices), then
// endObject with one coordinate, the paint index. Equal paints share one index.
import 'dart:typed_data';

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
