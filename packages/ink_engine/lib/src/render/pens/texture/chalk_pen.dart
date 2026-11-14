// lib/src/render/pens/texture/chalk_pen.dart — INTERNAL (v2.11, C211-01).
//
// OWNED BY THE TEXTURE TRACK. 분필 — the lock app's `chalk`: powder only on
// the peaks of a coarse tooth (chalk channel, slanted −18°), skipping a lot at
// light pressure, a half-transparent fine powder film underneath, a very faint
// smeared haze around the stroke, edges breaking up along the grain and soft
// dust specks just outside the stroke — more behind the motion and on the
// outside of bends. The specks sit at arc-length cells hashed from the stroke's
// createdAt (static, the same on screen and in the PDF). Everything stays
// within the K-1 reach (Spine.limit), so the haze and dust are narrow on thin
// chalk. Four coverage levels on screen; flat look / PDF: haze, film, two
// coverage bands (calibrated to the textured coverage), the same specks.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../geometry/stroke_outline.dart';
import '../../../model/ink_stroke.dart';
import '../pen_renderer.dart';
import 'texture_geometry.dart';
import 'texture_pen.dart';
import 'texture_tiles.dart';

const PenRenderer chalkPen = _ChalkPen();

const double _angle = -18;
const List<double> _levels = [0.12, 0.3, 0.5, 0.7];
const List<double> _flatLevels = [0.3, 0.7];
const double _powder = 0.22;

/// flat (PDF) alphas of the coverage bands × this: the flat bands match the
/// textured coverage
const double _flatGain = 1.25;

/// haze: (pt outside the edge, alpha)
const List<(double, double)> _halo = [(1.2, 0.05)];

/// dust specks: (diameter pt at width 4, alpha) — one disc each
const List<(double, double)> _dust = [(0.8, 0.3), (1.1, 0.22), (1.5, 0.15)];

/// at most this many speck candidates per stroke (longer strokes thin out)
const int _maxCandidates = 3000;

final class _Geom {
  _Geom(this.halo, this.powder, this.levels, this.flat, this.dust);
  final List<StrokeOutline?> halo;
  final StrokeOutline? powder;
  final List<StrokeOutline?> levels;
  final List<StrokeOutline?> flat;

  /// per size class
  final List<StrokeOutline?> dust;
}

_Geom _geom(InkStroke stroke) => textureGeometry(
  stroke,
  _build,
  (g) =>
      outlinesBytes(g.halo) +
      outlineBytes(g.powder) +
      outlinesBytes(g.levels) +
      outlinesBytes(g.dust),
);

_Geom _build(Spine sp) {
  final (rl, rr) = sp.ragged(
    (i) => sp.r[i],
    edge: 0.09,
    freq: 1.1,
    rough: 0.07,
  );
  final halo = [for (final (d, _) in _halo) band(sp, plus(rl, d), plus(rr, d))];
  final powder = band(sp, times(rl, 0.95), times(rr, 0.95));
  final levels = <StrokeOutline?>[];
  for (var j = 0; j < _levels.length; j++) {
    final b = coverageBand(
      sp,
      rl,
      rr,
      core: (i) => 0.55 + 0.25 * sp.p[i],
      edge: (i) => 0.2 + 0.1 * sp.p[i],
      level: _levels[j],
      rho0: 0.2,
      q: 1.2,
      fade: 1.1,
      jit: j > 0 ? 0.22 : 0,
      salt: 37 * j,
    );
    levels.add(b == null ? null : band(sp, b.$1, b.$2));
  }
  final flat = [for (final c in _flatLevels) levels[_levels.indexOf(c)]];
  return _Geom(halo, powder, levels, flat, _specks(sp, rl, rr));
}

List<StrokeOutline?> _specks(Spine sp, Float64List rl, Float64List rr) {
  final w = sp.width;
  final k = (w / 4).clamp(0.5, 1.5);
  final discs = [for (final _ in _dust) <Float32List>[]];
  if (!sp.isDot) {
    var cell = 0.5 * w;
    final cells = sp.length / cell;
    if (cells * 3 > _maxCandidates) cell = sp.length * 3 / _maxCandidates;
    final count = (sp.length / cell).floor();
    final bendAt = sp.curvature();
    final salt = sp.seed + 911;
    for (var c = 0; c < count; c++) {
      for (var m = 0; m < 3; m++) {
        final q = 3 * c + m;
        final at = (c + noise01(salt, 7 * q)) * cell;
        final i = sp.sampleAt(at);
        final bend = math.min(1.0, bendAt[i].abs() * w * 2.5);
        if (noise01(salt, 7 * q + 5) > 0.2 + 0.45 * bend) continue;
        final outer = bendAt[i] > 0 ? -1.0 : 1.0;
        final side = noise01(salt, 7 * q + 1) < 0.55 + 0.35 * bend
            ? outer
            : -outer;
        final v = noise01(salt, 7 * q + 3);
        final cls = v < 0.55 ? 0 : (v < 0.85 ? 1 : 2);
        final dr = _dust[cls].$1 * k / 2;
        // behind the moving chalk
        final back = (0.3 + 0.9 * noise01(salt, 7 * q + 4)) * w * 0.5;
        final at2 = sp.locate(math.max(0, at - back));
        final u = noise01(salt, 7 * q + 2);
        final rad = Spine.lerp(side > 0 ? rl : rr, at2.i, at2.t);
        final d = math.min(
          rad * (1 + (0.45 + 0.8 * bend) * u * u) + 0.55,
          sp.limit - dr,
        );
        if (d <= 0) continue;
        final x = at2.x + at2.nx * d * side;
        final y = at2.y + at2.ny * d * side;
        discs[cls].add(circlePolygon(x, y, dr, segments: 8));
      }
    }
  }
  StrokeOutline? of(List<Float32List> polys) {
    if (polys.isEmpty) return null;
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in polys) {
      for (var i = 0; i + 1 < p.length; i += 2) {
        minX = math.min(minX, p[i]);
        maxX = math.max(maxX, p[i]);
        minY = math.min(minY, p[i + 1]);
        maxY = math.max(maxY, p[i + 1]);
      }
    }
    return StrokeOutline(
      polygons: polys,
      bounds: Rect.fromLTRB(minX, minY, maxX, maxY),
    );
  }

  return [for (var c = 0; c < _dust.length; c++) of(discs[c])];
}

final class _ChalkPen extends TexturePen {
  const _ChalkPen();

  @override
  void paintTextured(
    Canvas canvas,
    InkStroke stroke,
    StrokeOutline outline,
    int argb,
    TextureTiles tiles,
  ) {
    final g = _geom(stroke);
    for (var h = 0; h < _halo.length; h++) {
      final b = g.halo[h];
      if (b == null) continue;
      final a = _halo[h].$2;
      canvas.drawPath(
        b.toPath(),
        aroundPaint(tiles.wash, argb, TileChannel.flow, a, a * 1.4),
      );
    }
    final powder = g.powder;
    if (powder != null) {
      canvas.drawPath(
        powder.toPath(),
        aroundPaint(tiles.wash, argb, TileChannel.dust, _powder, 0.3),
      );
    }
    for (var j = 0; j < _levels.length; j++) {
      final b = g.levels[j];
      if (b == null) continue;
      canvas.drawPath(
        b.toPath(),
        abovePaint(
          tiles.tooth,
          argb,
          TileChannel.chalk,
          1 - _levels[j],
          0.12,
          amount: 0.92,
          angleDeg: _angle,
        ),
      );
    }
    for (var c = 0; c < _dust.length; c++) {
      final d = g.dust[c];
      if (d != null) canvas.drawPath(d.toPath(), solidPaint(argb, _dust[c].$2));
    }
  }

  @override
  List<FlatLayer> flatLayers(
    InkStroke stroke,
    StrokeOutline outline,
    int argb,
  ) {
    final g = _geom(stroke);
    final alphas = stackedAlphas(_flatLevels, under: _powder);
    return [
      for (var h = 0; h < _halo.length; h++)
        if (g.halo[h] != null)
          (outline: g.halo[h]!, alpha: _halo[h].$2, argb: null),
      if (g.powder != null)
        (outline: g.powder!, alpha: _powder * 1.55, argb: null),
      for (var j = 0; j < g.flat.length; j++)
        if (g.flat[j] != null && alphas[j] > 0)
          (
            outline: g.flat[j]!,
            alpha: (alphas[j] * 0.92 * _flatGain).clamp(0.0, 1.0),
            argb: null,
          ),
      for (var c = 0; c < _dust.length; c++)
        if (g.dust[c] != null)
          (outline: g.dust[c]!, alpha: _dust[c].$2, argb: null),
    ];
  }

  @override
  void paintLive(Canvas canvas, PenLiveFrame frame) => paintLiveWith(
    canvas,
    frame,
    (tiles, argb) => [
      aroundPaint(tiles.wash, argb, TileChannel.dust, _powder, 0.3),
      abovePaint(
        tiles.tooth,
        argb,
        TileChannel.chalk,
        1 - 0.48,
        0.12,
        amount: 0.92,
        angleDeg: _angle,
      ),
    ],
    flatAlpha: 0.6,
  );
}
