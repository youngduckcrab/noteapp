// lib/src/render/pens/texture/texture_pen.dart — INTERNAL (v2.11, C211-01)
// the common frame of the texture pens. OWNED BY THE TEXTURE TRACK.
//
// A texture pen has two looks of one geometry (texture_geometry.dart):
//   textured — the lock app's look: bands painted with tile threshold paints
//     (texture_tiles.dart) inside one saveLayer(stroke bounds, opacity), when
//     the renderer received the grain (⇒ the tiles are ready);
//   flat — translucent flat layers of the same bands (coverage levels as
//     inset bands with stepped alpha, dots as circles): the PDF pieces, and
//     the screen until the grain is ready (the controllers then re-record).
// Both are pure functions of the stroke (geometry cached per stroke), so the
// screen, thumbnails, previews and the PDF agree and repaint identically.
import 'dart:ui';

import '../../../geometry/stroke_outline.dart';
import '../../../model/ink_stroke.dart';
import '../../stroke_painter.dart';
import '../pen_renderer.dart';
import 'texture_geometry.dart';
import 'texture_tiles.dart';

/// One flat layer: a nonzero outline in the pen color (or [argb] when set) at [alpha].
typedef FlatLayer = ({StrokeOutline outline, double alpha, int? argb});

abstract base class TexturePen extends PenRenderer {
  const TexturePen();

  /// The textured look (inside a saveLayer at the stroke opacity).
  void paintTextured(
    Canvas canvas,
    InkStroke stroke,
    StrokeOutline outline,
    Spine sp,
    int argb,
    TextureTiles tiles,
  );

  /// The flat layers (PDF pieces and the screen before the tiles are ready).
  List<FlatLayer> flatLayers(InkStroke stroke, StrokeOutline outline, Spine sp);

  /// The color the pen actually paints with (pencil: graphite tint).
  int paintColor(int argb) => argb;

  /// Whether the committed look needs its own layer at opacity 1 (blend
  /// modes inside the stroke, overlapping translucent layers).
  bool get layered => true;

  @override
  void paintCommitted(
    Canvas canvas,
    InkStroke stroke,
    StrokeOutline outline, {
    required int colorArgb,
    required double opacity,
    Image? grain,
  }) {
    final sp = Spine.of(stroke);
    final argb = paintColor(colorArgb);
    final tiles = TextureTiles.of(grain);
    final layer = layered || opacity < 1;
    if (layer) {
      canvas.saveLayer(
        stroke.bounds.inflate(1),
        Paint()..color = inkColor(0, opacity),
      );
    }
    if (tiles != null) {
      paintTextured(canvas, stroke, outline, sp, argb, tiles);
    } else {
      for (final l in flatLayers(stroke, outline, sp)) {
        canvas.drawPath(
          l.outline.toPath(),
          Paint()
            ..isAntiAlias = true
            ..color = inkColor(l.argb ?? argb, l.alpha),
        );
      }
    }
    if (layer) canvas.restore();
  }

  @override
  List<PenVectorPiece> vectorPieces(
    InkStroke stroke,
    StrokeOutline outline, {
    required double opacity,
    required bool smooth,
  }) {
    final sp = Spine.of(stroke);
    final argb = opaqueArgb(paintColor(stroke.style.colorArgb));
    final out = <PenVectorPiece>[];
    for (final l in flatLayers(stroke, outline, sp)) {
      final path = l.outline.toVectorPath(smooth: smooth);
      if (path.verbs.isEmpty) continue;
      out.add((
        path: path,
        colorArgb: l.argb == null ? argb : opaqueArgb(l.argb!),
        opacity: (l.alpha * opacity).clamp(0.0, 1.0),
      ));
    }
    return out;
  }

  /// Live: [paints] on the frame's outline paths inside one layer at the
  /// frame opacity (textured when the grain is ready, else [flatAlpha]).
  void paintLiveWith(
    Canvas canvas,
    PenLiveFrame frame,
    List<Paint> Function(TextureTiles tiles, int argb) paints, {
    required double flatAlpha,
  }) {
    if (frame.opacity <= 0) return;
    canvas.saveLayer(frame.bounds, Paint()..color = inkColor(0, frame.opacity));
    final argb = paintColor(frame.style.colorArgb);
    final tiles = TextureTiles.of(frame.grain);
    final list = tiles == null
        ? [
            Paint()
              ..isAntiAlias = true
              ..color = inkColor(argb, flatAlpha),
          ]
        : paints(tiles, argb);
    for (final paint in list) {
      for (final p in frame.paths) {
        canvas.drawPath(p, paint);
      }
    }
    canvas.restore();
  }
}

/// A solid paint of [argb] at [alpha].
Paint solidPaint(int argb, double alpha) => Paint()
  ..isAntiAlias = true
  ..color = inkColor(argb, alpha);

/// Alphas of flat layers stacked inside each other so that the coverage
/// inside layer j is [coverage][j] over a base of [under].
List<double> stackedAlphas(List<double> coverage, {double under = 0}) {
  final out = <double>[];
  var prev = under;
  for (final c in coverage) {
    out.add(c <= prev ? 0 : 1 - (1 - c) / (1 - prev));
    if (c > prev) prev = c;
  }
  return out;
}
