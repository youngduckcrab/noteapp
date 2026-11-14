// lib/src/render/pens/texture/pencil_pen.dart — INTERNAL (v2.11, C211-01).
//
// OWNED BY THE TEXTURE TRACK. 연필 — the round-1 look (the pencil grain fill,
// 6.11: one outline, the grain shader, the tilt opacity loss) with only the
// lock app's `pencilColour` taken over: dark colors move slightly toward a cool
// graphite gray. The lock app's banded graphite (edge band, body, pressure
// core) was tried and dropped in review: it was paler than the round-1 pencil,
// lost small dots, showed a ghost edge when zoomed in and cost 20× more to
// record — not "clearly better". The PDF is one piece in the same graphite
// color (× the export pencil factor, as before), so screen and PDF keep the
// round-1 match.
import 'dart:ui';

import '../../../geometry/stroke_outline.dart';
import '../../../model/ink_stroke.dart';
import '../../stroke_painter.dart';
import '../pen_renderer.dart';
import 'texture_geometry.dart';

const PenRenderer pencilPen = _PencilPen();

/// cool graphite gray the dark colors move toward
const int _cool = 0xFF4A525E;

/// Dark colors move slightly toward graphite gray (the lock app's pencilColour).
int pencilColour(int argb) {
  final lu = luma(argb);
  if (lu >= 0.3) return argb;
  return mixArgb(argb, _cool, 0.35 * (1 - lu / 0.3));
}

final class _PencilPen extends PenRenderer {
  const _PencilPen();

  @override
  void paintCommitted(
    Canvas canvas,
    InkStroke stroke,
    StrokeOutline outline, {
    required int colorArgb,
    required double opacity,
    Image? grain,
  }) => super.paintCommitted(
    canvas,
    stroke,
    outline,
    colorArgb: pencilColour(colorArgb),
    opacity: opacity,
    grain: grain,
  );

  @override
  void paintLive(Canvas canvas, PenLiveFrame frame) => paintFillPaths(
    canvas,
    frame.paths,
    profile: frame.profile,
    colorArgb: pencilColour(frame.style.colorArgb),
    opacity: frame.opacity,
    bounds: frame.bounds,
    grain: frame.grain,
  );

  @override
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
        colorArgb: opaqueArgb(pencilColour(stroke.style.colorArgb)),
        opacity: opacity,
      ),
    ];
  }
}
