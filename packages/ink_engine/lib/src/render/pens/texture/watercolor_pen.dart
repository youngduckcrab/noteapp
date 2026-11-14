// lib/src/render/pens/texture/watercolor_pen.dart — INTERNAL (v2.11, C211-01).
//
// OWNED BY THE TEXTURE TRACK. 수채 — the lock app's `watercolor`: a
// transparent wash (alpha 0.2, more for light colors so white does not turn
// into gray fog) with smooth edges that bloom softly outward along the paper
// fibres (wash flow channel), four load levels that are denser where more
// paint was on the brush, slow mottling and granulation in the paper pits, a
// darker rim where the pigment dried at the edge — wide where the brush
// pressed (the lock app: where it lingered), pooled paint at both ends, and
// self-overlap glazing (where the stroke crosses itself the paint is laid
// twice; screen only). Default opacity 1: the transparency is in the internal
// alphas; style.opacity multiplies on top. Flat look / PDF: bloom rings, body,
// load levels, rims and end pools as flat translucent pieces (rings are outer
// band + reversed inner band, nonzero — the same pieces on screen and in PDF).
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../geometry/stroke_outline.dart';
import '../../../model/ink_stroke.dart';
import '../pen_renderer.dart';
import 'texture_geometry.dart';
import 'texture_pen.dart';
import 'texture_tiles.dart';

const PenRenderer watercolorPen = _WatercolorPen();

/// bloom: (pt outside the edge, alpha)
const List<(double, double)> _bloom = [(1.3, 0.05), (0.85, 0.06), (0.4, 0.08)];
const double _wash = 0.2;
const int _loadLevels = 4;
const double _rimAlpha = 0.55;

final class _Geom {
  _Geom({
    required this.body,
    required this.blooms,
    required this.loads,
    required this.rims,
    required this.pooled,
  });
  final StrokeOutline? body;
  final List<StrokeOutline?> blooms;
  final List<StrokeOutline?> loads;
  final List<StrokeOutline?> rims;
  final StrokeOutline? pooled;
}

final Expando<_Geom> _cache = Expando<_Geom>('watercolor');

_Geom _geom(InkStroke stroke) => _cache[stroke] ??= _build(Spine.of(stroke));

_Geom _build(Spine sp) {
  final w = sp.width;
  final (rl, rr) = sp.ragged((i) => sp.r[i], edge: 0.1, freq: 0.3);
  final body = band(sp, rl, rr);
  if (body == null) {
    return _Geom(body: null, blooms: [], loads: [], rims: [], pooled: null);
  }
  final blooms = [
    for (final (d, _) in _bloom)
      () {
        final o = band(sp, plus(rl, d), plus(rr, d));
        return o == null ? null : ring(o, body);
      }(),
  ];
  double load(int i) =>
      (1 -
              0.5 * smoothstep(0, 25 * w, sp.s[i]) -
              0.25 * (1 - sp.p[i]) +
              0.15 * wobble(sp.s[i] / w * 0.12, sp.seed + 3))
          .clamp(0.0, 1.0);
  final loads = [
    for (var lv = 1; lv <= _loadLevels; lv++)
      levelShape(
        sp,
        rl,
        rr,
        load,
        level: lv / (_loadLevels + 1),
        soft: 0.15,
        salt: 61 * lv,
      ),
  ];
  // the rim where the pigment dried: wide and dark where the brush pressed
  final il = Float64List(sp.n), ir = Float64List(sp.n);
  for (var i = 0; i < sp.n; i++) {
    final p = sp.p[i];
    final pool =
        (0.9 * p * p + 0.6 * wobble(sp.s[i] / w * 0.22, sp.seed + 9) - 0.15)
            .clamp(0.0, 1.0);
    final inset = 0.35 + 1.7 * pool * math.min(1.0, w / 6);
    il[i] = math.max(0.3 * rl[i], rl[i] - inset);
    ir[i] = math.max(0.3 * rr[i], rr[i] - inset);
  }
  final il2 = Float64List(sp.n), ir2 = Float64List(sp.n);
  for (var i = 0; i < sp.n; i++) {
    il2[i] = rl[i] - (rl[i] - il[i]) * 0.45;
    ir2[i] = rr[i] - (rr[i] - ir[i]) * 0.45;
  }
  final rims = [
    for (final (a, b) in [(il, ir), (il2, ir2)])
      () {
        final inner = band(sp, a, b);
        return inner == null ? null : ring(body, inner);
      }(),
  ];
  double ends(int i) => math.max(
    smoothstep(1.5 * w, 0, sp.s[i]),
    smoothstep(1.5 * w, 0, sp.length - sp.s[i]),
  );
  final pooled = sp.isDot
      ? null
      : levelShape(sp, rl, rr, ends, level: 0.5, soft: 0.3, salt: 13);
  return _Geom(
    body: body,
    blooms: blooms,
    loads: loads,
    rims: rims,
    pooled: pooled,
  );
}

double _boost(int argb) => 1 + 0.8 * smoothstep(0.55, 0.95, luma(argb));

final class _WatercolorPen extends TexturePen {
  const _WatercolorPen();

  @override
  void paintTextured(
    Canvas canvas,
    InkStroke stroke,
    StrokeOutline outline,
    Spine sp,
    int argb,
    TextureTiles tiles,
  ) {
    final g = _geom(stroke);
    final body = g.body;
    if (body == null) return;
    final boost = _boost(argb);
    final wash = tiles.wash;
    for (var k = 0; k < _bloom.length; k++) {
      final b = g.blooms[k];
      if (b == null) continue;
      canvas.drawPath(
        b.toPath(),
        abovePaint(
          wash,
          argb,
          TileChannel.flow,
          0.25,
          0.75,
          amount: _bloom[k].$2 * 1.6 * boost,
        ),
      );
    }
    final bodyPath = body.toPath();
    canvas.drawPath(bodyPath, solidPaint(argb, _wash * boost));
    final layer = solidPaint(argb, 0.035 * boost);
    for (final l in g.loads) {
      if (l != null) canvas.drawPath(l.toPath(), layer);
    }
    // wide puddles (darker, lighter) and granulation in the paper pits
    canvas
      ..drawPath(
        bodyPath,
        abovePaint(
          wash,
          argb,
          TileChannel.mottle,
          0.4,
          0.6,
          amount: 0.13 * boost,
        ),
      )
      ..drawPath(
        bodyPath,
        belowPaint(wash, argb, TileChannel.mottle, 0.45, 0.45, amount: 0.22)
          ..blendMode = BlendMode.dstOut,
      )
      ..drawPath(
        bodyPath,
        belowPaint(
          tiles.tooth,
          argb,
          TileChannel.wax,
          0.4,
          0.55,
          amount: 0.1 * boost,
          angleDeg: 20,
        ),
      );
    for (var k = 0; k < g.rims.length; k++) {
      final rim = g.rims[k];
      if (rim == null) continue;
      final a = _rimAlpha * (k == 0 ? 0.3 : 0.4);
      canvas.drawPath(
        rim.toPath(),
        aroundPaint(wash, argb, TileChannel.flow, a, a * 0.7),
      );
    }
    final pooled = g.pooled;
    if (pooled != null) {
      canvas.drawPath(pooled.toPath(), solidPaint(argb, 0.08 * boost));
    }
    // glaze: where the stroke crosses itself (even winding) the paint is laid twice
    canvas
      ..saveLayer(stroke.bounds.inflate(1), Paint())
      ..drawPath(bodyPath, solidPaint(argb, 0.22 * boost))
      ..drawPath(
        Path.from(bodyPath)..fillType = PathFillType.evenOdd,
        solidPaint(argb, 1)..blendMode = BlendMode.dstOut,
      )
      ..restore();
  }

  @override
  List<FlatLayer> flatLayers(
    InkStroke stroke,
    StrokeOutline outline,
    Spine sp,
  ) {
    final g = _geom(stroke);
    final body = g.body;
    if (body == null) return const [];
    final boost = _boost(stroke.style.colorArgb);
    return [
      for (var k = 0; k < _bloom.length; k++)
        if (g.blooms[k] != null)
          (
            outline: g.blooms[k]!,
            alpha: 0.6 * _bloom[k].$2 * boost,
            argb: null,
          ),
      (outline: body, alpha: (_wash + 0.03) * boost, argb: null),
      for (final l in g.loads)
        if (l != null) (outline: l, alpha: 0.035 * boost, argb: null),
      for (var k = 0; k < g.rims.length; k++)
        if (g.rims[k] != null)
          (
            outline: g.rims[k]!,
            alpha: _rimAlpha * (k == 0 ? 0.3 : 0.4),
            argb: null,
          ),
      if (g.pooled != null)
        (outline: g.pooled!, alpha: 0.08 * boost, argb: null),
    ];
  }

  @override
  void paintLive(Canvas canvas, PenLiveFrame frame) {
    final boost = _boost(frame.style.colorArgb);
    paintLiveWith(
      canvas,
      frame,
      (tiles, argb) => [
        solidPaint(argb, (_wash + 0.07) * boost),
        abovePaint(
          tiles.wash,
          argb,
          TileChannel.mottle,
          0.4,
          0.6,
          amount: 0.13 * boost,
        ),
      ],
      flatAlpha: (_wash + 0.1) * boost,
    );
  }
}
