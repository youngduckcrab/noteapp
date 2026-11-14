// lib/src/render/pens/texture/pencil_pen.dart — INTERNAL (v2.11, C211-01).
//
// OWNED BY THE TEXTURE TRACK. 연필 — refined with the lock app's `pencil`
// where it is clearly better than the round-1 grain fill (6.11):
//   * dark colors shift toward a cool graphite gray (pencilColour);
//   * graphite on the fine, slightly stretched graph grain (35°) instead of the
//     isotropic pencil grain: a soft edge band where only the grain peaks take
//     graphite, a low-contrast body (≈ 70–85 % covered) and an inner core that
//     widens and darkens with pressure.
// The outline (hit testing, K-1, the tilt opacity loss 6.11) is unchanged.
// Every layer's alpha stays below 1 before clamping, so the stroke opacity is
// folded into the paints exactly and no saveLayer is needed (pencil strokes
// are the most numerous texture strokes on a page). Without the grain (not
// ready yet) and in the PDF: one piece, the outline in the graphite color.
import 'dart:math' as math;
import 'dart:ui';

import '../../../geometry/stroke_outline.dart';
import '../../../model/ink_stroke.dart';
import '../../stroke_painter.dart';
import '../pen_renderer.dart';
import 'texture_geometry.dart';
import 'texture_tiles.dart';

const PenRenderer pencilPen = _PencilPen();

const double _angle = 35;
const double _tone = 0.66;
const double _press = 0.16;
const double _var = 0.22;

/// cool graphite gray the dark colors move toward
const int _cool = 0xFF4A525E;

/// Dark colors move slightly toward graphite gray (the lock app's pencilColour).
int pencilColour(int argb) {
  final lu = luma(argb);
  if (lu >= 0.3) return argb;
  return mixArgb(argb, _cool, 0.35 * (1 - lu / 0.3));
}

final class _Geom {
  _Geom(this.edge, this.body, this.core);
  final StrokeOutline? edge;
  final StrokeOutline? body;
  final StrokeOutline? core;
}

final Expando<_Geom> _cache = Expando<_Geom>('pencil');

_Geom _geom(InkStroke stroke) => _cache[stroke] ??= _build(Spine.of(stroke));

_Geom _build(Spine sp) {
  // the fixed edge / inset widths shrink on very thin pencils (lock: PE_THIN)
  final ratio = math.min(1.0, sp.width / 2 / 0.72);
  final thin = ratio * ratio;
  final (rl, rr) = sp.ragged(
    (i) => sp.r[i],
    edge: 0.05,
    freq: 1.6,
    rough: 0.02,
  );
  return _Geom(
    band(sp, plus(rl, 0.3 * thin), plus(rr, 0.3 * thin)),
    band(sp, plus(rl, -0.25 * thin), plus(rr, -0.25 * thin)),
    band(
      sp,
      timesAt(rl, (i) => 0.75 * sp.p[i]),
      timesAt(rr, (i) => 0.75 * sp.p[i]),
    ),
  );
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
  }) {
    final argb = pencilColour(colorArgb);
    final tiles = TextureTiles.of(grain);
    if (tiles == null) {
      // the round-1 look (grain shader, or flat until the grain is ready)
      canvas.drawPath(
        outline.toPath(),
        inkFillPaint(stroke.profile, inkColor(argb, opacity), grain: grain),
      );
      return;
    }
    final g = _geom(stroke);
    for (final (o, paint) in [
      (g.edge, _edgePaint(tiles, argb, opacity)),
      (g.body, _bodyPaint(tiles, argb, opacity)),
      (g.core, _corePaint(tiles, argb, opacity)),
    ]) {
      if (o != null) canvas.drawPath(o.toPath(), paint);
    }
  }

  @override
  void paintLive(Canvas canvas, PenLiveFrame frame) {
    final tiles = TextureTiles.of(frame.grain);
    final argb = pencilColour(frame.style.colorArgb);
    if (tiles == null || frame.opacity <= 0) {
      paintFillPaths(
        canvas,
        frame.paths,
        profile: frame.profile,
        colorArgb: argb,
        opacity: frame.opacity,
        bounds: frame.bounds,
        grain: frame.grain,
      );
      return;
    }
    // the live chunks overlap: one layer at the stroke opacity
    canvas.saveLayer(frame.bounds, Paint()..color = inkColor(0, frame.opacity));
    final body = _bodyPaint(tiles, argb, 1, mean: _tone + 0.1);
    for (final p in frame.paths) {
      canvas.drawPath(p, body);
    }
    canvas.restore();
  }

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

// Every alpha below stays < 1 before clamping, so × opacity is exact.

Paint _edgePaint(TextureTiles t, int argb, double o) {
  // above(graph, 0.45, soft 0.5, amount 0.55): alpha = 1.1 · (v − 0.45) ≤ 0.61
  const k = 0.55 / 0.5;
  return tilePaint(
    t.tooth,
    argb,
    TileChannel.graph,
    k * o,
    -k * 0.45 * o,
    angleDeg: _angle,
  );
}

Paint _bodyPaint(TextureTiles t, int argb, double o, {double mean = _tone}) {
  const contrast = _tone * _var * 2;
  return tilePaint(
    t.tooth,
    argb,
    TileChannel.graph,
    contrast * o,
    (mean - 0.5 * contrast) * o,
    angleDeg: _angle,
  );
}

Paint _corePaint(TextureTiles t, int argb, double o) {
  const mean = _press * 1.6, contrast = _press * 1.2;
  return tilePaint(
    t.tooth,
    argb,
    TileChannel.graph,
    contrast * o,
    (mean - 0.5 * contrast) * o,
    angleDeg: _angle,
  );
}
