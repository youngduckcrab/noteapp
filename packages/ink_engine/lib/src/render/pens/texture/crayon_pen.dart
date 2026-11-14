// lib/src/render/pens/texture/crayon_pen.dart — INTERNAL (v2.11, C211-01).
//
// OWNED BY THE TEXTURE TRACK. 크레파스 — the lock app's `crayon`: wax on the
// paper's tooth peaks (wax channel, ridges slanted 20°, fixed to the page so
// overlapping strokes leave the same pits), a nearly full core, edges that
// break up and fade over ~0.8 pt, a faint wax film in the holes, a few grooves
// along the stroke and wax building up at the start, the end and bends.
// Coverage levels follow the pressure (the lock app used the hand speed).
// Six coverage levels on screen; flat look / PDF: the film plus three coverage
// bands with stepped alpha (× _flatGain, calibrated to the textured coverage)
// and the build-up band. See pen_renderer.dart for the rules.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../geometry/stroke_outline.dart';
import '../../../model/ink_stroke.dart';
import '../pen_renderer.dart';
import 'texture_geometry.dart';
import 'texture_pen.dart';
import 'texture_tiles.dart';

const PenRenderer crayonPen = _CrayonPen();

const double _angle = 20;
const List<double> _levels = [0.14, 0.34, 0.54, 0.72, 0.86, 0.95];
const List<double> _flatLevels = [0.34, 0.72, 0.95];

/// flat (PDF) alphas × this: the flat bands match the textured coverage
const double _flatGain = 1.15;
const double _film = 0.1;
const int _grooves = 4;

final class _Geom {
  _Geom(this.film, this.levels, this.flat, this.grooves, this.build);
  final StrokeOutline? film;
  final List<StrokeOutline?> levels;
  final List<StrokeOutline?> flat;
  final List<Float32List> grooves;
  final List<StrokeOutline?> build;
}

_Geom _geom(InkStroke stroke) => textureGeometry(
  stroke,
  _build,
  (g) =>
      outlineBytes(g.film) +
      outlinesBytes(g.levels) +
      polygonsBytes(g.grooves) +
      outlinesBytes(g.build),
);

_Geom _build(Spine sp) {
  final w = sp.width;
  final (rl, rr) = sp.ragged(
    (i) => sp.r[i],
    edge: 0.05,
    freq: 1.5,
    rough: 0.035,
  );
  double core(int i) => 0.9 + 0.08 * sp.p[i];
  double edge(int i) => 0.34 + 0.16 * sp.p[i];
  final rho0 = math.max(0.35, 1 - 2.5 / math.max(0.5, w / 2));
  StrokeOutline? level(double c, int j) {
    final b = coverageBand(
      sp,
      rl,
      rr,
      core: core,
      edge: edge,
      level: c,
      rho0: rho0,
      q: 1.6,
      fade: 0.8,
      jit: j > 0 ? 0.1 : 0,
      salt: 31 * j,
    );
    return b == null ? null : band(sp, b.$1, b.$2);
  }

  final film = band(sp, plus(rl, -0.3), plus(rr, -0.3));
  final levels = [
    for (var j = 0; j < _levels.length; j++) level(_levels[j], j),
  ];
  final flat = [for (final c in _flatLevels) levels[_levels.indexOf(c)]];
  // grooves: a few lines along the stroke with less wax
  final mid = Float64List(sp.n);
  for (var i = 0; i < sp.n; i++) {
    mid[i] = (rl[i] + rr[i]) / 2;
  }
  final grooves = <Float32List>[];
  if (!sp.isDot) {
    for (var g = 0; g < _grooves; g++) {
      final frac = (noise01(sp.seed, 41 * g) * 2 - 1) * 0.75;
      final px =
          (0.25 + 0.25 * noise01(sp.seed, 43 * g + 1)) * math.min(1.0, w / 3);
      final side = 0.6 + 0.8 * noise01(sp.seed, 59 * g + 2);
      final wl = Float64List(sp.n), wr = Float64List(sp.n);
      for (var i = 0; i < sp.n; i++) {
        wl[i] =
            px *
            (0.1 + 1.6 * wobble(sp.s[i] / w * 0.35, sp.seed + 53 * g)).clamp(
              0.0,
              1.0,
            );
        wr[i] = wl[i] * side;
      }
      grooves.addAll(
        offsetBands(sp, frac, mid, wl, wr, maxOffset: (i) => mid[i] * 0.95),
      );
    }
  }
  // build-up at the start, the end and bends
  final bend = sp.curvature();
  double build(int i) => math.max(
    math.max(
      smoothstep(1.4 * w, 0.2 * w, sp.s[i]),
      smoothstep(1.4 * w, 0.2 * w, sp.length - sp.s[i]),
    ),
    math.min(1.0, bend[i].abs() * w * 1.2),
  );
  final il = times(rl, 0.85), ir = times(rr, 0.85);
  final builds = [
    levelShape(sp, il, ir, build, level: 0.45, soft: 0.3, salt: 71),
  ];
  return _Geom(film, levels, flat, grooves, builds);
}

final class _CrayonPen extends TexturePen {
  const _CrayonPen();

  @override
  void paintTextured(
    Canvas canvas,
    InkStroke stroke,
    StrokeOutline outline,
    int argb,
    TextureTiles tiles,
  ) {
    final g = _geom(stroke);
    final t = tiles.tooth;
    final film = g.film;
    if (film != null) {
      canvas.drawPath(
        film.toPath(),
        aroundPaint(t, argb, TileChannel.wax, _film, 0.12, angleDeg: _angle),
      );
    }
    for (var j = 0; j < _levels.length; j++) {
      final b = g.levels[j];
      if (b == null) continue;
      canvas.drawPath(
        b.toPath(),
        abovePaint(
          t,
          argb,
          TileChannel.wax,
          1 - _levels[j],
          0.07,
          angleDeg: _angle,
        ),
      );
    }
    if (g.grooves.isNotEmpty) {
      final path = Path()..fillType = PathFillType.nonZero;
      for (final p in g.grooves) {
        path.addPolygon(_offsets(p), true);
      }
      canvas.drawPath(
        path,
        belowPaint(
          t,
          argb,
          TileChannel.wax,
          0.55,
          0.3,
          amount: 0.85,
          angleDeg: _angle,
          blendMode: BlendMode.dstOut,
        ),
      );
    }
    for (final b in g.build) {
      if (b == null) continue;
      final path = b.toPath();
      canvas
        ..drawPath(
          path,
          abovePaint(
            t,
            argb,
            TileChannel.wax,
            0.02,
            0.1,
            amount: 0.45,
            angleDeg: _angle,
          ),
        )
        ..drawPath(
          path,
          solidPaint(0xFF000000, 0.03)..blendMode = BlendMode.srcATop,
        );
    }
  }

  @override
  List<FlatLayer> flatLayers(
    InkStroke stroke,
    StrokeOutline outline,
    int argb,
  ) {
    final g = _geom(stroke);
    final alphas = stackedAlphas(_flatLevels, under: _film);
    return [
      if (g.film != null) (outline: g.film!, alpha: _film, argb: null),
      for (var j = 0; j < g.flat.length; j++)
        if (g.flat[j] != null && alphas[j] > 0)
          (outline: g.flat[j]!, alpha: alphas[j] * _flatGain, argb: null),
      for (final b in g.build)
        if (b != null) (outline: b, alpha: 0.25, argb: null),
    ];
  }

  @override
  void paintLive(Canvas canvas, PenLiveFrame frame) => paintLiveWith(
    canvas,
    frame,
    (tiles, argb) => [
      aroundPaint(
        tiles.tooth,
        argb,
        TileChannel.wax,
        _film,
        0.12,
        angleDeg: _angle,
      ),
      abovePaint(
        tiles.tooth,
        argb,
        TileChannel.wax,
        1 - 0.76,
        0.07,
        angleDeg: _angle,
      ),
    ],
    flatAlpha: 0.9,
  );
}

List<Offset> _offsets(Float32List p) => [
  for (var i = 0; i + 1 < p.length; i += 2) Offset(p[i], p[i + 1]),
];
