// lib/src/export/raster_ports.dart — the formula and text raster ports of the object resolver
// (m5-7/06-pdf 6.2.4 · 6.2.5, PDF-M2 · M3). Internal (not in the barrel).
//
// The resolver takes formula and text rasters only through these ports: the defaults draw with
// INK (InkMathRenderer, InkTextLayout.rasterize — CP-PDF-7), the tests use solid RGBA fakes
// (test/support/fake_rasterizers.dart). The resolver lowers the pixel density with
// [cappedPixelsPerPt] before the call, so a fake gets the same request as INK. One raster is
// ≤ PdfTuning.maxRasterPixels (4 Mpx = 16 MiB RGBA). Web-safe.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../tuning.dart';
import 'vectors.dart';

abstract interface class PdfMathRasterizer {
  /// Laid-out size in pt at object.style.fontSizePt; null = invalid LaTeX.
  ui.Size? layoutSize(core.MathObject object);

  /// RGBA of the laid-out formula at [pixelsPerPt] (transparent background); null = failed /
  /// timed out. Implementations must not return more than PdfTuning.maxRasterPixels.
  Future<PdfRgbaData?> rasterize(
    core.MathObject object, {
    required double pixelsPerPt,
  });
}

abstract interface class PdfTextRasterizer {
  /// Frame-local (unrotated) RGBA of the box text, transparent background, no box background.
  Future<PdfRgbaData?> rasterize(
    core.TextBoxObject object, {
    required double pixelsPerPt,
  });
}

/// Default: ink.InkMathRenderer.layout / rasterize → toByteData(rawStraightRgba) → image.dispose().
final class InkMathRasterizer implements PdfMathRasterizer {
  const InkMathRasterizer();

  @override
  ui.Size? layoutSize(core.MathObject object) {
    try {
      return ink.InkMathRenderer.layout(
        object.latex,
        fontSizePt: object.style.fontSizePt,
      )?.sizePt;
    } on Object {
      return null; // a size INK refuses (ArgumentError) or a frame phase (StateError)
    }
  }

  @override
  Future<PdfRgbaData?> rasterize(
    core.MathObject object, {
    required double pixelsPerPt,
  }) async {
    final ui.Image? image;
    try {
      image = await ink.InkMathRenderer.rasterize(
        object.latex,
        colorArgb: object.style.colorArgb,
        fontSizePt: object.style.fontSizePt,
        pixelsPerPt: pixelsPerPt,
      );
    } on Object {
      return null;
    }
    return rgbaOfImage(image);
  }
}

/// Default: ink.InkTextLayout.rasterize (CP-PDF-7) → same.
final class InkTextRasterizer implements PdfTextRasterizer {
  const InkTextRasterizer();

  @override
  Future<PdfRgbaData?> rasterize(
    core.TextBoxObject object, {
    required double pixelsPerPt,
  }) async {
    final ui.Image? image;
    try {
      image = await ink.InkTextLayout.rasterize(
        object,
        pixelsPerPt: pixelsPerPt,
      );
    } on Object {
      return null;
    }
    return rgbaOfImage(image);
  }
}

/// min(want, sqrt(maxRasterPixels / (w·h)), maxRasterSidePx / max(w, h)) — the INK rule (03-ink 4.10),
/// applied by PDF before the call so a fake rasterizer gets the same request.
///
/// Like INK, the result is lowered a little further while ⌈w·k⌉ × ⌈h·k⌉ is still above
/// maxRasterPixels (rounding up) or a side is above maxRasterSidePx, so a raster of exactly
/// that size fits. A non-finite or non-positive [wantPixelsPerPt] → 0.
double cappedPixelsPerPt(double wantPixelsPerPt, ui.Size sizePt) {
  if (!(wantPixelsPerPt > 0) || !wantPixelsPerPt.isFinite) return 0;
  final w = sizePt.width, h = sizePt.height;
  var k = wantPixelsPerPt;
  final area = w * h;
  if (area > 0 && area.isFinite) {
    k = math.min(k, math.sqrt(PdfTuning.maxRasterPixels / area));
  }
  final side = math.max(w, h);
  if (side > 0 && side.isFinite) {
    k = math.min(k, PdfTuning.maxRasterSidePx / side);
  }
  bool over(double k) =>
      (w * k).ceil() * (h * k).ceil() > PdfTuning.maxRasterPixels ||
      (side * k).ceil() > PdfTuning.maxRasterSidePx;
  while (k > 0 && w.isFinite && h.isFinite && over(k)) {
    k *= 0.999;
  }
  return k;
}

/// The pixel size of a raster of [sizePt] at [pixelsPerPt]: ⌈w·k⌉ × ⌈h·k⌉ (the INK rule).
({int width, int height}) rasterPixelSize(ui.Size sizePt, double pixelsPerPt) =>
    (
      width: math.max(0, (sizePt.width * pixelsPerPt).ceil()),
      height: math.max(0, (sizePt.height * pixelsPerPt).ceil()),
    );

/// [image] → straight RGBA (alpha kept), then image.dispose(); null for a null image, a failed
/// read or an image over PdfTuning.maxRasterPixels.
Future<PdfRgbaData?> rgbaOfImage(ui.Image? image) async {
  if (image == null) return null;
  try {
    final width = image.width, height = image.height;
    if (width < 1 || height < 1 || width * height > PdfTuning.maxRasterPixels) {
      return null;
    }
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (data == null) return null;
    return PdfRgbaData(
      Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes),
      width: width,
      height: height,
      hasAlpha: true,
    );
  } on Object {
    return null;
  } finally {
    image.dispose();
  }
}
