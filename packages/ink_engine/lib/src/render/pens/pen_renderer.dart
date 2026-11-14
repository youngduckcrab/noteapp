// lib/src/render/pens/pen_renderer.dart — INTERNAL (v2.11, C211-01) per-pen rendering.
//
// FOUNDATION FILE (shared by the texture and decor tracks — change only with
// both in mind). Every ink-layer stroke is painted through the renderer of its
// tool ([penRendererOf]):
//   committed — paintFillStroke (stroke_painter.dart) → paintCommitted: page
//     chunk pictures, overrides / previews, the selection preview, thumbnails
//     (layer_painters.dart, page_composite.dart) and the pen preview;
//   live — the active stroke on the ink layer (ink_page_controller.dart) →
//     paintLive;
//   PDF — exportPage inkShapes (vector_export.dart) → vectorPieces: one or
//     more nonzero fill pieces per stroke, each with its own color / opacity
//     (pdf_io maps every piece to one PdfFillItem; no raster path).
// The base class is the original fill: one nonzero outline fill (pencil grain
// when the profile is textured), so a pen whose renderer is not written yet
// looks like a ballpoint everywhere and never crashes.
//
// Rules for every renderer (contract C211-01):
//   * static and deterministic: the same stroke gives the same pixels on the
//     screen, in thumbnails and in the PDF; randomness only from PenRandom
//     (pen_random.dart) seeded from the stroke (createdAt, points) — never
//     time, never String.hashCode, never dart:math Random;
//   * K-1: every pixel inside core.Stroke.bounds = point bounds inflated by
//     width · max(2 · maxWidthQ, 0.75). widthQ = factor / 4, so that is the
//     outline radius at the widest point (factor / 2 · width), but never less
//     than 0.75 · width — a pen of factor 1 (outline radius 0.5 · width) has
//     0.75 · width for its glow, dust or stars; bounds_invariant_test checks it;
//   * arithmetic only on numbers that reach pixels (7.4.3, web = VM);
//   * no per-frame allocation storms: committed strokes are recorded once into
//     chunk pictures, so paintCommitted may be a few ms for a long stroke, but
//     paintLive runs every frame (keep it O(points) with small constants).
import 'dart:ui';

import 'package:note_core/note_core.dart' as core;

import '../../geometry/stroke_outline.dart';
import '../../geometry/vector_path.dart';
import '../../model/ink_stroke.dart';
import '../../pen/pen_profile.dart';
import '../../pen/style_ink.dart';
import '../stroke_painter.dart';
import 'decor/glitter_pen.dart';
import 'decor/jelly_pen.dart';
import 'decor/neon_pen.dart';
import 'decor/rainbow_pen.dart';
import 'texture/brush_pen.dart';
import 'texture/chalk_pen.dart';
import 'texture/crayon_pen.dart';
import 'texture/pencil_pen.dart';
import 'texture/spray_pen.dart';
import 'texture/watercolor_pen.dart';

/// One PDF fill piece of a stroke: nonzero [path] (page pt, y down), opaque
/// [colorArgb] (alpha 0xFF, K-5), [opacity] in [0, 1]. Pieces paint in list order.
typedef PenVectorPiece = ({InkVectorPath path, int colorArgb, double opacity});

/// What the live (wet) stroke offers a renderer, every frame.
final class PenLiveFrame {
  const PenLiveFrame({
    required this.style,
    required this.paths,
    required this.centerline,
    required this.bounds,
    required this.opacity,
    required this.seed,
    this.grain,
  });

  final core.StrokeStyle style;
  PenProfile get profile => style.profile;

  /// [frozen chunks, open chunk + tail] outline paths (nonzero), as the base fill draws them
  final List<Path> paths;

  /// stable centerline positions + raw tail, page pt (unquantized)
  final List<Offset> centerline;

  /// live bounds inflated by the 1 px margin (saveLayer bounds)
  final Rect bounds;

  /// style.opacity × the pencil tilt factor
  final double opacity;

  /// the future stroke's createdAt (pen-down ms) — the committed stroke's
  /// source.createdAt, so seeds can match before and after pen-up
  final int seed;

  /// the pencil grain (null until ready, or when the profile is not textured)
  final Image? grain;
}

/// The rendering of one pen. Subclasses override what differs from the plain fill.
base class PenRenderer {
  const PenRenderer();

  /// The plain fill (ballpoint, fountain, marker, dashed, calligraphy, …).
  static const PenRenderer fill = PenRenderer();

  /// A committed stroke from its L1 [outline]. [colorArgb] is the color to use
  /// (the recolor preview replaces it; alpha ignored), [opacity] > 0 is
  /// strokeOpacity(stroke). [grain] = the pencil grain when the profile is textured.
  void paintCommitted(
    Canvas canvas,
    InkStroke stroke,
    StrokeOutline outline, {
    required int colorArgb,
    required double opacity,
    Image? grain,
  }) {
    canvas.drawPath(
      outline.toPath(),
      inkFillPaint(stroke.profile, inkColor(colorArgb, opacity), grain: grain),
    );
  }

  /// The live stroke (every frame while drawing).
  void paintLive(Canvas canvas, PenLiveFrame frame) {
    paintFillPaths(
      canvas,
      frame.paths,
      profile: frame.profile,
      colorArgb: frame.style.colorArgb,
      opacity: frame.opacity,
      bounds: frame.bounds,
      grain: frame.grain,
    );
  }

  /// The PDF pieces of a committed stroke. [opacity] > 0 is the export opacity
  /// (screen opacity × the pencil factor for textured profiles).
  List<PenVectorPiece> vectorPieces(
    InkStroke stroke,
    StrokeOutline outline, {
    required double opacity,
    required bool smooth,
  }) {
    final path = outline.toVectorPath(smooth: smooth);
    if (path.verbs.isEmpty) return const [];
    return [
      (
        path: path,
        colorArgb: opaqueArgb(stroke.style.colorArgb),
        opacity: opacity,
      ),
    ];
  }
}

/// Alpha 0xFF (K-5), color kept (arithmetic — web-safe).
int opaqueArgb(int argb) => 0xFF000000 + argb % 0x1000000;

/// The renderer of [tool] (C211-01 dispatch table). Tools without their own
/// renderer use [PenRenderer.fill].
PenRenderer penRendererOf(core.PenTool tool) => switch (tool) {
  core.PenTool.ballpoint ||
  core.PenTool.fountain ||
  core.PenTool.highlighter ||
  core.PenTool.marker ||
  core.PenTool.calligraphy ||
  core.PenTool.dashed ||
  core.PenTool.laser ||
  core.PenTool.tape => PenRenderer.fill,
  // texture track (render/pens/texture/)
  core.PenTool.pencil => pencilPen,
  core.PenTool.brush => brushPen,
  core.PenTool.crayon => crayonPen,
  core.PenTool.chalk => chalkPen,
  core.PenTool.watercolor => watercolorPen,
  core.PenTool.spray => sprayPen,
  // decor track (render/pens/decor/)
  core.PenTool.neon => neonPen,
  core.PenTool.jelly => jellyPen,
  core.PenTool.rainbow => rainbowPen,
  core.PenTool.glitter => glitterPen,
};
