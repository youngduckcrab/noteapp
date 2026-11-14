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
// Both are pure functions of the stroke (geometry in TextureGeometryCache), so
// the screen, thumbnails, previews and the PDF agree and repaint identically.
// The flat alphas are calibrated so the flat look covers about as much as the
// textured one (texture_pens_test: PDF ÷ screen coverage within ±12 %); the
// PDF export does not apply the pencil grain factor to these pens.
import 'dart:ui';

import '../../../geometry/stroke_outline.dart';
import '../../../model/ink_stroke.dart';
import '../../stroke_painter.dart';
import '../pen_renderer.dart';
import 'texture_tiles.dart';

/// One flat layer: a nonzero outline in the pen color (or [argb] when set) at [alpha].
typedef FlatLayer = ({StrokeOutline outline, double alpha, int? argb});

abstract base class TexturePen extends PenRenderer {
  const TexturePen();

  /// The textured look (inside a saveLayer at the stroke opacity) in [argb].
  void paintTextured(
    Canvas canvas,
    InkStroke stroke,
    StrokeOutline outline,
    int argb,
    TextureTiles tiles,
  );

  /// The flat layers (PDF pieces and the screen before the tiles are ready)
  /// for the color [argb] (the recolor preview passes its own).
  List<FlatLayer> flatLayers(InkStroke stroke, StrokeOutline outline, int argb);

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
      paintTextured(canvas, stroke, outline, argb, tiles);
    } else {
      for (final l in flatLayers(stroke, outline, argb)) {
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
    final argb = opaqueArgb(paintColor(stroke.style.colorArgb));
    final out = <PenVectorPiece>[];
    for (final l in flatLayers(stroke, outline, stroke.style.colorArgb)) {
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

  /// Live: [paints] over the frame's outline paths at the frame opacity
  /// (textured when the grain is ready, else one flat [flatAlpha] layer). The
  /// live chunks overlap at their joints, so the paths are drawn once as an
  /// opaque mask and the paints fill the mask (srcIn) — no darker joint dots.
  void paintLiveWith(
    Canvas canvas,
    PenLiveFrame frame,
    List<Paint> Function(TextureTiles tiles, int argb) paints, {
    required double flatAlpha,
  }) {
    if (frame.opacity <= 0) return;
    final argb = paintColor(frame.style.colorArgb);
    final tiles = TextureTiles.of(frame.grain);
    final list = tiles == null
        ? [solidPaint(argb, flatAlpha)]
        : paints(tiles, argb);
    paintMasked(canvas, frame.paths, frame.bounds, frame.opacity, list);
  }
}

/// [paints] (each over the whole of [bounds]) inside the union of [paths], at
/// [opacity]: two layers, the paths drawn once as an opaque mask.
void paintMasked(
  Canvas canvas,
  List<Path> paths,
  Rect bounds,
  double opacity,
  List<Paint> paints,
) {
  canvas.saveLayer(bounds, Paint()..color = inkColor(0, opacity));
  final mask = Paint()
    ..isAntiAlias = true
    ..color = const Color(0xFFFFFFFF);
  for (final p in paths) {
    canvas.drawPath(p, mask);
  }
  canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.srcIn);
  for (final paint in paints) {
    canvas.drawRect(bounds, paint);
  }
  canvas
    ..restore()
    ..restore();
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
