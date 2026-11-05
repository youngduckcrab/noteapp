// Pixel helpers for the render tests (T08): paint into an offscreen image and
// read RGBA values, and build CORE strokes from point lists.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ink_engine/src/interop/core_interop.dart' as interop;
import 'package:note_core/note_core.dart' as core;

/// RGBA8888 pixels of an offscreen image.
final class Pixels {
  Pixels(this.width, this.height, this.bytes);

  final int width;
  final int height;
  final ByteData bytes;

  /// [r, g, b, a] at (x, y).
  List<int> at(int x, int y) {
    final o = (y * width + x) * 4;
    return [
      bytes.getUint8(o),
      bytes.getUint8(o + 1),
      bytes.getUint8(o + 2),
      bytes.getUint8(o + 3),
    ];
  }
}

/// Paints with [paint] into a [width] × [height] image (1 px = 1 unit) and
/// returns its pixels. Call from a real async zone (a plain `test`, or
/// `tester.runAsync`).
Future<Pixels> renderPixels(
  int width,
  int height,
  void Function(ui.Canvas canvas) paint,
) async {
  final recorder = ui.PictureRecorder();
  paint(ui.Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final bytes = (await image.toByteData())!;
    return Pixels(width, height, bytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// Fills the whole canvas with [argb] (the paper).
void paintPaper(ui.Canvas canvas, int argb, {double size = 4096}) =>
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, size, size),
      ui.Paint()..color = ui.Color(argb),
    );

var _strokeIds = 0;

/// A CORE stroke through [points] with one widthQ (t 10 ms apart).
core.Stroke strokeThrough(
  List<ui.Offset> points,
  core.StrokeStyle style, {
  double widthQ = core.kNominalWidthQ,
  double tilt = 0,
  String? id,
  int createdAt = 1000,
}) {
  const stride = core.StrokePoints.stride;
  final data = Float32List(points.length * stride);
  for (var i = 0; i < points.length; i++) {
    data[i * stride] = points[i].dx;
    data[i * stride + 1] = points[i].dy;
    data[i * stride + 2] = widthQ;
    data[i * stride + 3] = tilt;
    data[i * stride + 5] = i * 10.0;
  }
  _strokeIds++;
  return interop.strokeFromData(
    data,
    id: id ?? 'st-$_strokeIds',
    pageId: 'p1',
    style: style,
    createdAt: createdAt + _strokeIds,
    hasTilt: tilt != 0,
    hasAzimuth: false,
  );
}

/// Points every [step] along the segment a → b (both ends included).
List<ui.Offset> segment(ui.Offset a, ui.Offset b, {double step = 2}) {
  final n = ((b - a).distance / step).ceil().clamp(1, 100000);
  return [for (var i = 0; i <= n; i++) ui.Offset.lerp(a, b, i / n)!];
}

/// Channel-wise |a − b| ≤ [tol].
bool samePixel(List<int> a, List<int> b, {int tol = 1}) {
  for (var i = 0; i < 4; i++) {
    if ((a[i] - b[i]).abs() > tol) return false;
  }
  return true;
}
