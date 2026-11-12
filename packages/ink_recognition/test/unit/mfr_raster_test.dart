// The on-device math engine's input image (ondevice/mfr_raster.dart): black
// strokes on WHITE, a thin antialiased pen at the natural scale (median
// stroke extent ≈ 48 px), cropped to the ink + margin, STRETCHED to
// 384 × 384 with Pillow's bicubic resampling, NCHW pixel values. The parity
// case compares the resampling with the reference preprocessing (PIL
// `resize((384, 384), BICUBIC)` of a sample of the evaluation set —
// test/fixtures/mfr/parity_*.gray.gz).
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/src/model/handwriting_trace.dart';
import 'package:ink_recognition/src/ondevice/mfr_raster.dart';

import '../support/math_model_fakes.dart';

HandwritingTrace _trace(List<(double, double)> points) => HandwritingTrace(
  xs: Float32List.fromList([for (final p in points) p.$1]),
  ys: Float32List.fromList([for (final p in points) p.$2]),
  ts: Float64List.fromList([for (var i = 0; i < points.length; i++) i * 8.0]),
);

/// A '+' then a '1' at page pt, 10 pt high, starting at (100, 200).
List<HandwritingTrace> _plusOne() => [
  _trace([(100, 205), (110, 205)]),
  _trace([(105, 200), (105, 210)]),
  _trace([(120, 200), (120, 210)]),
];

void main() {
  test('natural scale: median stroke extent → 48 px, ink box + 16 px '
      'margin, white background, black ink', () {
    final image = rasterizeTraces(_plusOne())!;
    // ink box 20 × 10 pt, 10 pt per stroke → 4.8 px / pt
    expect(image.width, (20 * 4.8).ceil() + 32 + 1);
    expect(image.height, (10 * 4.8).ceil() + 32 + 1);
    // margins are pure white
    for (var x = 0; x < image.width; x++) {
      for (final y in [0, 1, 14, image.height - 1, image.height - 15]) {
        expect(image.at(x, y), 255, reason: '($x, $y)');
      }
    }
    for (var y = 0; y < image.height; y++) {
      expect(image.at(0, y), 255);
      expect(image.at(image.width - 1, y), 255);
    }
    // the '1' at x = 16 + 20 * 4.8 = 112: dark in the middle of its height
    final midY = 16 + 24;
    expect(image.at(112, midY), lessThan(64));
    // the pen is thin: ≈ 2 px of ink across the vertical stroke
    final across = [
      for (var x = 100; x < image.width; x++)
        if (image.at(x, midY) < 128) x,
    ];
    expect(across.length, inInclusiveRange(1, 3));
  });

  test('a long formula is drawn smaller to fit maxSidePx', () {
    final strokes = [
      for (var i = 0; i < 200; i++) _trace([(i * 15.0, 0), (i * 15.0, 10)]),
    ];
    final image = rasterizeTraces(
      strokes,
      config: const MfrRasterConfig(maxSidePx: 1000),
    )!;
    expect(image.width, lessThanOrEqualTo(1001));
    expect(image.height, greaterThan(16 * 2));
  });

  test('a dot (one point) is drawn; no point → null', () {
    final dot = rasterizeTraces([
      _trace([(5, 5)]),
    ])!;
    expect(dot.pixels.any((v) => v < 255), isTrue);
    expect(rasterizeTraces(const []), isNull);
    expect(rasterizeTraces([_trace(const [])]), isNull);
    expect(mfrPixelValues(const []), isNull);
  });

  test('stretch, not pad: a wide image fills the whole square', () {
    // left half black, right half white, 200 × 40
    final src = GrayImage.white(200, 40);
    for (var y = 0; y < 40; y++) {
      for (var x = 0; x < 100; x++) {
        src.pixels[y * 200 + x] = 0;
      }
    }
    final out = resizeBicubic(src, kMfrImageSize, kMfrImageSize);
    expect(out.width, kMfrImageSize);
    expect(out.height, kMfrImageSize);
    // top and bottom rows carry the content (no white padding bands)
    expect(out.at(10, 0), 0);
    expect(out.at(10, kMfrImageSize - 1), 0);
    expect(out.at(kMfrImageSize - 10, kMfrImageSize ~/ 2), 255);
  });

  test('pixel values: NCHW, three equal planes, white +1, black −1', () {
    final image = GrayImage.white(kMfrImageSize, kMfrImageSize);
    image.pixels[0] = 0;
    image.pixels[1] = 128;
    final values = pixelValuesOf(image);
    const plane = kMfrImageSize * kMfrImageSize;
    expect(values, hasLength(3 * plane));
    for (final c in [0, 1, 2]) {
      expect(values[c * plane], -1.0);
      expect(values[c * plane + 1], closeTo((128 / 255 - 0.5) / 0.5, 1e-6));
      expect(values[c * plane + 2], 1.0);
    }
    final full = mfrPixelValues(_plusOne())!;
    expect(full, hasLength(3 * plane));
    expect(full.reduce((a, b) => a > b ? a : b), 1.0);
    expect(full.reduce((a, b) => a < b ? a : b), lessThan(-0.5));
  });

  test('parity with the reference preprocessing (Pillow bicubic 384²)', () {
    final dir = mfrFixtures();
    final source = gzip.decode(
      File('$dir/parity_source.gray.gz').readAsBytesSync(),
    );
    final w = source[0] << 8 | source[1], h = source[2] << 8 | source[3];
    final src = GrayImage(w, h, Uint8List.fromList(source.sublist(4)));
    final expected = gzip.decode(
      File('$dir/parity_pil_384.gray.gz').readAsBytesSync(),
    );
    final out = resizeBicubic(src, kMfrImageSize, kMfrImageSize);
    var maxDiff = 0, sum = 0;
    for (var i = 0; i < expected.length; i++) {
      final d = (out.pixels[i] - expected[i]).abs();
      sum += d;
      if (d > maxDiff) maxDiff = d;
    }
    expect(maxDiff, lessThanOrEqualTo(1), reason: 'max |Δ|');
    expect(sum / expected.length, lessThan(0.01), reason: 'mean |Δ|');
  });
}
