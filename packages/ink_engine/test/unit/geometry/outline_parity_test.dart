@TestOn('vm')
library;

// T07 (03-ink 8, 6.8 last paragraph): with constant pressure, no taper and no
// smoothing our outline fills the same area as perfect_freehand.getStroke
// (MIT, dev dependency only) within 3%. Both are rasterized into a 256×256
// alpha image (nonzero fill, anti-aliased) and the alpha sums compared.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart' as pf;

import '../../support/outline_helpers.dart';

const int _size = 256;

/// Alpha sum / 255 (≈ covered pixels) of [path] filled opaque.
Future<double> _coverage(ui.Path path) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawPath(
    path,
    ui.Paint()
      ..color = const ui.Color(0xFF000000)
      ..isAntiAlias = true,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(_size, _size);
  final bytes = (await image.toByteData())!;
  image.dispose();
  picture.dispose();
  var sum = 0;
  for (var i = 3; i < bytes.lengthInBytes; i += 4) {
    sum += bytes.getUint8(i);
  }
  return sum / 255;
}

ui.Path _polygonPath(List<ui.Offset> points) {
  final path = ui.Path()..fillType = ui.PathFillType.nonZero;
  if (points.isEmpty) return path;
  path.moveTo(points.first.dx, points.first.dy);
  for (final p in points.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  return path..close();
}

/// The 10 inputs: (name, centerline, radius).
List<(String, List<ui.Offset>, double)> _inputs() {
  const c = ui.Offset(128, 128);
  return [
    (
      'horizontal line',
      sampleCurve((u) => ui.Offset(30 + 196 * u, 128), length: 196),
      6,
    ),
    (
      'diagonal line',
      sampleCurve((u) => ui.Offset(30 + 190 * u, 40 + 170 * u), length: 255),
      3,
    ),
    (
      'sine wave',
      sampleCurve(
        (u) => ui.Offset(20 + 216 * u, 128 + 50 * math.sin(u * 3 * math.pi)),
        length: 400,
      ),
      5,
    ),
    (
      'arc 270°',
      sampleCurve(
        (u) =>
            c +
            ui.Offset(
              80 * math.cos(u * 1.5 * math.pi),
              80 * math.sin(u * 1.5 * math.pi),
            ),
        length: 80 * 1.5 * math.pi,
      ),
      4,
    ),
    (
      'spiral',
      sampleCurve((u) {
        final a = u * 4 * math.pi;
        final r = 20 + 80 * u;
        return c + ui.Offset(r * math.cos(a), r * math.sin(a));
      }, length: 4 * math.pi * 60),
      3,
    ),
    (
      'loop',
      [
        for (var i = 0; i <= 100; i++) ui.Offset(20.0 + i, 170),
        ...sampleCurve(
          (u) => ui.Offset(
            120 + 50 * math.sin(u * 2 * math.pi),
            120 + 50 * math.cos(u * 2 * math.pi),
          ),
          length: 100 * math.pi,
        ).skip(1),
        for (var i = 1; i <= 100; i++) ui.Offset(120.0 + i, 170),
      ],
      4,
    ),
    (
      'zigzag',
      [
        for (var k = 0; k < 6; k++)
          ...sampleCurve(
            (u) => ui.Offset(
              20 + 36 * (k + u),
              k.isEven ? 100 + 40 * u : 140 - 40 * u,
            ),
            length: 54,
          ).skip(k == 0 ? 0 : 1),
      ],
      3,
    ),
    (
      'right angle',
      [
        for (var i = 0; i <= 150; i++) ui.Offset(50.0 + i, 50),
        for (var i = 1; i <= 150; i++) ui.Offset(200, 50.0 + i),
      ],
      4,
    ),
    (
      'short stroke',
      sampleCurve((u) => ui.Offset(120 + 16 * u, 128), length: 16),
      5,
    ),
    (
      'circle',
      sampleCurve(
        (u) =>
            c +
            ui.Offset(
              70 * math.cos(u * 2 * math.pi),
              70 * math.sin(u * 2 * math.pi),
            ),
        length: 140 * math.pi,
      ),
      3,
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (name, xy, r) in _inputs()) {
    test('fill area within 3% of perfect_freehand: $name', () async {
      // r = 2 · width · widthQ with widthQ 0.25 → width = 2r
      final ours = outlineFor(xy, width: 2 * r).toPath();
      final theirs = pf.getStroke(
        [for (final p in xy) pf.PointVector(p.dx, p.dy, 0.5)],
        options: pf.StrokeOptions(
          size: 2 * r,
          thinning: 0,
          smoothing: 0,
          streamline: 0,
          simulatePressure: false,
          isComplete: true,
        ),
      );
      final a = await _coverage(ours);
      final b = await _coverage(_polygonPath(theirs));
      expect(b, greaterThan(100), reason: 'perfect_freehand drew nothing');
      expect((a - b).abs() / b, lessThan(0.03), reason: 'ours $a, pf $b');
    });
  }
}
