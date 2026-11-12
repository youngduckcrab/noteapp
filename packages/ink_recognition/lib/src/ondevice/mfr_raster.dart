// lib/src/ondevice/mfr_raster.dart — (internal) the on-device math engine's
// input image, pure Dart (no dart:ui — it runs in a background isolate and
// in VM tests).
//
// The recipe the PC evaluation settled on (thick strokes or a padded square
// lose most of the accuracy):
// 1. strokes black on WHITE (never transparent → black), a thin antialiased
//    round pen ([MfrRasterConfig.penWidthPx] ≈ 2 px) at a natural scale where
//    one character is ≈ [MfrRasterConfig.charHeightPx] px high (40–60 px):
//    the character size is the median stroke extent;
// 2. cropped to the ink's bounding box + [MfrRasterConfig.marginPx];
// 3. STRETCHED to 384 × 384 (no aspect kept, like the model's
//    DeiTImageProcessor) with Pillow's bicubic resampling — [resizeBicubic]
//    is Pillow's ImagingResample for 8-bit images (support × scale when
//    shrinking, a = −0.5, 22-bit fixed-point coefficients, horizontal pass
//    then vertical, each rounded to 8 bits), so the tensor matches the
//    reference preprocessing (test/unit/mfr_raster_test parity case);
// 4. pixel_values = (v / 255 − 0.5) / 0.5, RGB, NCHW [1, 3, 384, 384]
//    (white = +1).
import 'dart:math' as math;
import 'dart:typed_data';

import '../model/handwriting_trace.dart';

/// The model's input side (DeiT encoder, 384 × 384).
const int kMfrImageSize = 384;

final class MfrRasterConfig {
  const MfrRasterConfig({
    this.penWidthPx = 2,
    this.charHeightPx = 48,
    this.marginPx = 16,
    this.maxSidePx = 2400,
  });

  /// Pen diameter at the natural scale.
  final double penWidthPx;

  /// The median stroke extent (≈ one character) at the natural scale.
  final double charHeightPx;

  /// White border around the ink's bounding box.
  final int marginPx;

  /// The natural image's longest side at most (a long formula is drawn
  /// smaller).
  final int maxSidePx;
}

/// An 8-bit grayscale image, row-major (0 = black, 255 = white).
final class GrayImage {
  GrayImage(this.width, this.height, this.pixels)
    : assert(pixels.length == width * height);

  GrayImage.white(this.width, this.height)
    : pixels = Uint8List(width * height)..fillRange(0, width * height, 255);

  final int width, height;
  final Uint8List pixels;

  int at(int x, int y) => pixels[y * width + x];
}

/// The natural-scale image of [traces] (steps 1–2); null when there is no
/// point at all.
GrayImage? rasterizeTraces(
  List<HandwritingTrace> traces, {
  MfrRasterConfig config = const MfrRasterConfig(),
}) {
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  final extents = <double>[];
  for (final t in traces) {
    if (t.xs.isEmpty) continue;
    var sMinX = double.infinity, sMinY = double.infinity;
    var sMaxX = -double.infinity, sMaxY = -double.infinity;
    for (var i = 0; i < t.xs.length; i++) {
      final x = t.xs[i], y = t.ys[i];
      if (!x.isFinite || !y.isFinite) continue;
      sMinX = math.min(sMinX, x);
      sMaxX = math.max(sMaxX, x);
      sMinY = math.min(sMinY, y);
      sMaxY = math.max(sMaxY, y);
    }
    if (!sMinX.isFinite) continue;
    minX = math.min(minX, sMinX);
    maxX = math.max(maxX, sMaxX);
    minY = math.min(minY, sMinY);
    maxY = math.max(maxY, sMaxY);
    final extent = math.max(sMaxX - sMinX, sMaxY - sMinY);
    if (extent > 0) extents.add(extent);
  }
  if (!minX.isFinite) return null;
  final inkW = maxX - minX, inkH = maxY - minY;
  final charPt = extents.isEmpty
      ? math.max(math.max(inkW, inkH), 1.0)
      : _median(extents);
  var scale = config.charHeightPx / charPt;
  final margin = config.marginPx;
  final longest = math.max(inkW, inkH) * scale + 2 * margin;
  if (longest > config.maxSidePx) {
    scale *= (config.maxSidePx - 2 * margin) / (longest - 2 * margin);
  }
  final width = math.max(1, (inkW * scale).ceil() + 2 * margin + 1);
  final height = math.max(1, (inkH * scale).ceil() + 2 * margin + 1);
  final coverage = Float32List(width * height);
  final radius = config.penWidthPx / 2;
  for (final t in traces) {
    final n = t.xs.length;
    if (n == 0) continue;
    double px(int i) => (t.xs[i] - minX) * scale + margin;
    double py(int i) => (t.ys[i] - minY) * scale + margin;
    if (n == 1) {
      _capsule(coverage, width, height, px(0), py(0), px(0), py(0), radius);
      continue;
    }
    for (var i = 1; i < n; i++) {
      _capsule(
        coverage,
        width,
        height,
        px(i - 1),
        py(i - 1),
        px(i),
        py(i),
        radius,
      );
    }
  }
  final pixels = Uint8List(width * height);
  for (var i = 0; i < pixels.length; i++) {
    pixels[i] = (255 * (1 - coverage[i])).round();
  }
  return GrayImage(width, height, pixels);
}

double _median(List<double> values) {
  final sorted = List<double>.of(values)..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Antialiased round-capped segment: coverage = clamp(r − d + 0.5, 0, 1)
/// at each pixel centre (d = distance to the segment), the union by max.
void _capsule(
  Float32List cov,
  int width,
  int height,
  double ax,
  double ay,
  double bx,
  double by,
  double r,
) {
  final pad = r + 1;
  final x0 = math.max(0, (math.min(ax, bx) - pad).floor());
  final x1 = math.min(width - 1, (math.max(ax, bx) + pad).ceil());
  final y0 = math.max(0, (math.min(ay, by) - pad).floor());
  final y1 = math.min(height - 1, (math.max(ay, by) + pad).ceil());
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  for (var y = y0; y <= y1; y++) {
    final cy = y + 0.5;
    for (var x = x0; x <= x1; x++) {
      final cx = x + 0.5;
      var t = len2 == 0 ? 0.0 : ((cx - ax) * dx + (cy - ay) * dy) / len2;
      if (t < 0) t = 0;
      if (t > 1) t = 1;
      final ex = cx - (ax + t * dx), ey = cy - (ay + t * dy);
      final d = math.sqrt(ex * ex + ey * ey);
      final c = r - d + 0.5;
      if (c <= 0) continue;
      final v = c >= 1 ? 1.0 : c;
      final k = y * width + x;
      if (v > cov[k]) cov[k] = v;
    }
  }
}

// --- Pillow's bicubic resampling (ImagingResample, 8 bits per channel) ------

const int _precisionBits = 32 - 8 - 2;

double _bicubic(double x) {
  const a = -0.5;
  if (x < 0) x = -x;
  if (x < 1) return ((a + 2) * x - (a + 3)) * x * x + 1;
  if (x < 2) return (((x - 5) * x + 8) * x - 4) * a;
  return 0;
}

/// (bounds: [xmin, count] per output pixel; kernel: ksize ints per pixel)
({Int32List bounds, Int32List kernel, int ksize}) _coefficients(
  int inSize,
  int outSize,
) {
  final scale = inSize / outSize;
  final filterScale = scale < 1 ? 1.0 : scale;
  final support = 2 * filterScale;
  final ksize = support.ceil() * 2 + 1;
  final bounds = Int32List(outSize * 2);
  final kernel = Int32List(outSize * ksize);
  final k = Float64List(ksize);
  for (var xx = 0; xx < outSize; xx++) {
    final center = (xx + 0.5) * scale;
    final ss = 1 / filterScale;
    var xmin = (center - support + 0.5).truncate();
    if (xmin < 0) xmin = 0;
    var xmax = (center + support + 0.5).truncate();
    if (xmax > inSize) xmax = inSize;
    xmax -= xmin;
    var ww = 0.0;
    for (var x = 0; x < xmax; x++) {
      final w = _bicubic((x + xmin - center + 0.5) * ss);
      k[x] = w;
      ww += w;
    }
    for (var x = 0; x < xmax; x++) {
      final w = ww == 0 ? k[x] : k[x] / ww;
      kernel[xx * ksize + x] = w < 0
          ? (-0.5 + w * (1 << _precisionBits)).truncate()
          : (0.5 + w * (1 << _precisionBits)).truncate();
    }
    bounds[xx * 2] = xmin;
    bounds[xx * 2 + 1] = xmax;
  }
  return (bounds: bounds, kernel: kernel, ksize: ksize);
}

int _clip8(int ss) {
  final v = ss >> _precisionBits;
  return v < 0 ? 0 : (v > 255 ? 255 : v);
}

/// [src] resized to [width] × [height] (stretched — no aspect kept) as
/// Pillow's `Image.resize(size, Image.BICUBIC)` does for an 'L' image.
GrayImage resizeBicubic(GrayImage src, int width, int height) {
  var image = src;
  if (width != image.width) {
    final c = _coefficients(image.width, width);
    final out = Uint8List(width * image.height);
    for (var y = 0; y < image.height; y++) {
      final row = y * image.width;
      for (var xx = 0; xx < width; xx++) {
        final xmin = c.bounds[xx * 2], count = c.bounds[xx * 2 + 1];
        var ss = 1 << (_precisionBits - 1);
        final kk = xx * c.ksize;
        for (var x = 0; x < count; x++) {
          ss += image.pixels[row + x + xmin] * c.kernel[kk + x];
        }
        out[y * width + xx] = _clip8(ss);
      }
    }
    image = GrayImage(width, image.height, out);
  }
  if (height != image.height) {
    final c = _coefficients(image.height, height);
    final out = Uint8List(image.width * height);
    for (var yy = 0; yy < height; yy++) {
      final ymin = c.bounds[yy * 2], count = c.bounds[yy * 2 + 1];
      final kk = yy * c.ksize;
      for (var x = 0; x < image.width; x++) {
        var ss = 1 << (_precisionBits - 1);
        for (var y = 0; y < count; y++) {
          ss += image.pixels[(y + ymin) * image.width + x] * c.kernel[kk + y];
        }
        out[yy * image.width + x] = _clip8(ss);
      }
    }
    image = GrayImage(image.width, height, out);
  }
  return identical(image, src)
      ? GrayImage(src.width, src.height, Uint8List.fromList(src.pixels))
      : image;
}

/// The encoder's pixel_values of a [kMfrImageSize]² gray image: RGB (the
/// gray value three times), NCHW, (v / 255 − 0.5) / 0.5.
Float32List pixelValuesOf(GrayImage image) {
  final plane = image.width * image.height;
  final out = Float32List(plane * 3);
  for (var i = 0; i < plane; i++) {
    final v = (image.pixels[i] / 255.0 - 0.5) / 0.5;
    out[i] = v;
    out[plane + i] = v;
    out[2 * plane + i] = v;
  }
  return out;
}

/// Steps 1–4 for [traces]; null when there is no point. Runs anywhere (a
/// background isolate in the app — top-level and argument-only).
Float32List? mfrPixelValues(
  List<HandwritingTrace> traces, {
  MfrRasterConfig config = const MfrRasterConfig(),
}) {
  final natural = rasterizeTraces(traces, config: config);
  if (natural == null) return null;
  return pixelValuesOf(resizeBicubic(natural, kMfrImageSize, kMfrImageSize));
}
