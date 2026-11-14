// lib/src/render/pens/decor/glitter_pen.dart — INTERNAL (v2.11, C211-01) 반짝이.
//
// OWNED BY THE DECOR TRACK. The lock app's glitter (EffectBrushes `glitter`,
// `glitterGeom`, `glitterTones`, `sparkle`), frozen in one moment: a body in a
// deeper shade of the pen color, dense grains in four tones of the pen color,
// some grains caught bright (the lock app's twinkling share, here with a fixed
// brightness each), and white four-armed stars with a halo in the pen color at
// seeded places along the line. No time animation and no moving light band.
//
// Determinism: grain k sits at arc length (k + u) · Δ (Δ fixed by the width;
// widened only past 1,500 grains) and star j follows star j − 1 by a seeded
// gap — both from PenRandom(penSeed([createdAt, stream])) streams consumed in
// order, so the live stroke (same createdAt = PenLiveFrame.seed) grows the same
// grains and stars as the stored one, and the screen, thumbnails and the PDF
// get the same ones. A partial erase restarts the arc length of the pieces
// (the glitter of the remaining pieces reshuffles — accepted).
//
// Size: the profile has no pressure response (an even gel line). The unit is
// b = 0.6 · w with the body radius 0.5 · b = 0.3 · w (thinner than the outline,
// which stays the hit area) so the stars can reach out to the K-1 limit 0.75 · w
// (decor_kit.dart): a star's halo fits in 0.75 · w − its distance from the
// centerline. The lock app's stars grew larger than that; here every star is
// sized to the room it has.
//
// Committed / PDF: rim (light inks), body, 4 grain tones, 3 bright grain
// classes, 4 halo layers, stars, star centers — at most 14 pieces, every grain
// a circle. Live: body as a round stroke, grains as round points, the same stars.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../model/ink_stroke.dart';
import '../pen_random.dart';
import '../pen_renderer.dart';
import 'decor_kit.dart';

const PenRenderer glitterPen = _GlitterPen();

const double _unitOfWidth = 0.6;
const double _bodyR = 0.5; // × b
const double _grainSpacing = 0.05; // × b of arc length per grain
const int _maxGrains = 1500;
const double _across = 0.88; // × body radius
const double _starGap = 3.4; // × b
const double _starShow = 0.5; // share of star places that shine

/// grain radius (× b) and alpha of the four tones, then low / mid / high
const List<(double, double)> _grainLooks = [
  (0.075, 0.8),
  (0.075, 0.9),
  (0.0675, 0.9),
  (0.075, 0.9),
  (0.075, 0.9), // low: tint 1
  (0.095, 0.95), // mid: glint
  (0.125, 1.0), // high: white
];

/// halo layers (lock GLINT_GLOW_K / GLINT_GLOW_A)
const List<double> _haloK = [1.95, 1.65, 1.4, 1.18];
const List<double> _haloA = [0.1, 0.15, 0.22, 0.32];
const double _starLen = 1.35, _starWaist = 0.16, _haloWaist = 0.3;

/// A slightly larger, darker star under the white one: the white arms that
/// reach past the body would vanish on white paper without it.
const double _edgeWaist = 0.26, _edgeAlpha = 0.45;

/// halo extent of a star of size 1 (the widest halo sparkle)
const double _extent = 1.95 * 0.8;

// the dot (lock app glitterTapGeom)
const double _tapR = 0.55; // × b (lock 0.72 — smaller, so its stars fit K-1)
const int _tapSpill = 7;
const List<double> _tapStarA = [0.12, 0.52, 0.92, 0.32, 0.72];

/// Pen-color tones (lock app `glitterTones`): body, four grain tints, glint.
final class _Tones {
  _Tones(int c) : this._(c, luma(c));
  _Tones._(int c, double lum)
    : deep = lum > 0.82
          ? 0xFFE2E3EA
          : lum < 0.12
          ? 0xFF1C1C22
          : darken(c, 0.14),
      tints = lum > 0.82
          ? const [kWhite, 0xFFB4B8C8, 0xFFFFC2DA, 0xFFB2D0FF]
          : lum < 0.12
          ? const [0xFF4A4A54, 0xFF6E6E7A, 0xFF9C9CAA, 0xFF5A5468]
          : [
              darken(c, 0.3),
              lighten(c, 0.22),
              lighten(c, 0.5),
              lighten(hueShift(c, 35), 0.4),
            ],
      glint = lum > 0.82
          ? kWhite
          : lum < 0.12
          ? 0xFFE6E6F0
          : lighten(c, 0.75),
      halo = lum > 0.82
          ? 0xFFA9BCFF
          : lum < 0.12
          ? 0xFF2C2838
          : c,
      glowA = lum < 0.15 ? 0.6 : 1.0;

  final int deep, glint, halo;
  final List<int> tints;
  final double glowA;

  /// the color of grain class k (0–3 tones, 4 low, 5 mid, 6 high)
  int grain(int k) => switch (k) {
    < 4 => tints[k],
    4 => tints[1],
    5 => glint,
    _ => kWhite,
  };
}

/// Grains (x, y per class) and stars (x, y, size, degrees, grow) of one stroke.
final class _Sparkles {
  _Sparkles(this.grains, this.stars);
  final List<Float64List> grains; // 7 classes
  final Float64List stars; // rows of 5
}

final class _Builder {
  final List<List<double>> g = List.generate(7, (_) => <double>[]);
  final List<double> st = [];

  void star(double x, double y, double size, double deg, double grow) =>
      st.addAll([x, y, size, deg, grow]);

  _Sparkles done() => _Sparkles([
    for (final l in g) Float64List.fromList(l),
  ], Float64List.fromList(st));
}

/// The class of a grain from u: 84 % in the four tones (lock app shares
/// 0.42 / 0.66 / 0.8 / 1 after the 16 % twinkling ones), the twinkling 16 %
/// frozen as low / mid / high.
int _classOf(double u, double v) {
  if (u < 0.16) return v < 0.5 ? 4 : (v < 0.8 ? 5 : 6);
  if (u < 0.42) return 0;
  if (u < 0.66) return 1;
  if (u < 0.8) return 2;
  return 3;
}

_Sparkles _sparkles(DecorSpine sp, double w, int seed) {
  final b = _unitOfWidth * w;
  final reach = minReach(w);
  final out = _Builder();
  final row = Float64List(5);
  if (sp.isDot) {
    final cx = sp.xs[0], cy = sp.ys[0];
    final r = _tapR * b;
    final gr = PenRandom(penSeed([seed, 11]));
    final n = math.max(8, (math.pi * r * r / (b * b * 0.044)).floor());
    for (var k = 0; k < n + _tapSpill; k++) {
      final spill = k >= n;
      final u0 = gr.next(), u1 = gr.next(), u2 = gr.next(), u3 = gr.next();
      final d = spill
          ? math.min(r * (1.1 + 0.6 * u0), reach - _grainLooks[6].$1 * b)
          : r * _across * math.sqrt(u0);
      final a = 2 * math.pi * u1;
      final cls = spill ? (u3 < 0.5 ? 5 : 6) : _classOf(u2, u3);
      out.g[cls]
        ..add(cx + math.cos(a) * d)
        ..add(cy + math.sin(a) * d);
    }
    final sr = PenRandom(penSeed([seed, 12]));
    final turn = sr.next();
    for (final a0 in _tapStarA) {
      final a = 2 * math.pi * (turn + a0 + (sr.next() - 0.5) * 0.1);
      final d = r * 1.2;
      final room = (reach - d) / _extent;
      final size = math.min(0.45 * 1.25 * b * (0.85 + 0.4 * sr.next()), room);
      out.star(
        cx + math.cos(a) * d,
        cy + math.sin(a) * d,
        size,
        (sr.next() - 0.5) * 30,
        1,
      );
    }
    return out.done();
  }
  final length = sp.length;
  final rb = _bodyR * b;
  // grains
  var step = _grainSpacing * b;
  if (length / step > _maxGrains) step = length / _maxGrains;
  final gr = PenRandom(penSeed([seed, 1]));
  for (var k = 0; ; k++) {
    final u0 = gr.next(), u1 = gr.next(), u2 = gr.next(), u3 = gr.next();
    final s = (k + u0) * step;
    if (s > length) break;
    sp.sampleInto(s, row, 0);
    final across = (2 * u1 - 1) * rb * _across;
    out.g[_classOf(u2, u3)]
      ..add(row[0] + row[2] * across)
      ..add(row[1] + row[3] * across);
  }
  // stars
  final gap = _starGap * b;
  final sr = PenRandom(penSeed([seed, 2]));
  var s = gap * (0.3 + 0.4 * sr.next());
  while (s < length) {
    final uA = sr.next(), uShow = sr.next(), uSize = sr.next();
    final uRot = sr.next(), uGap = sr.next();
    if (uShow < _starShow) {
      sp.sampleInto(s, row, 0);
      final across = (uA - 0.5) * 0.24 * b;
      final room = (reach - across.abs()) / _extent;
      final env = 0.5 + 0.5 * uSize;
      out.star(
        row[0] + row[2] * across,
        row[1] + row[3] * across,
        room * env,
        (uRot - 0.5) * 40,
        math.min(1, env * 1.6),
      );
    }
    s += gap * (0.75 + 0.5 * uGap);
  }
  return out.done();
}

final class _Geom {
  _Geom(
    this.rim,
    this.body,
    this.grains,
    this.halos,
    this.edge,
    this.star,
    this.center,
  );
  final DecorShape rim, body;
  final List<DecorShape> grains, halos;
  final DecorShape edge, star, center;
}

/// Star paths from the star rows: halo layers, white stars, white centers.
(List<VecBuilder>, VecBuilder, VecBuilder, VecBuilder) _starPaths(
  Float64List st,
) {
  final halos = [for (var k = 0; k < _haloK.length; k++) VecBuilder()];
  final edge = VecBuilder(), star = VecBuilder(), center = VecBuilder();
  for (var i = 0; i + 4 < st.length; i += 5) {
    final x = st[i], y = st[i + 1], size = st[i + 2];
    final deg = st[i + 3], grow = st[i + 4];
    star.sparkle(x, y, size * _starLen, deg, _starWaist, slim: true);
    edge.sparkle(x, y, size * _starLen * 1.12, deg, _edgeWaist, slim: true);
    for (var k = 0; k < _haloK.length; k++) {
      halos[k]
        ..sparkle(x, y, size * _haloK[k] * 0.8, deg, _haloWaist)
        ..circle(x, y, size * 0.29 * _haloK[k] * grow);
    }
    center.circle(x, y, size * 0.14 * grow);
  }
  return (halos, edge, star, center);
}

final Expando<_Geom> _geometry = Expando<_Geom>('glitter');

_Geom _build(InkStroke stroke) {
  final w = stroke.style.width;
  final b = _unitOfWidth * w;
  final sp = DecorSpine.of(stroke.points);
  final sparkles = _sparkles(sp, w, stroke.source.createdAt);
  final rb = sp.isDot ? _tapR * b : _bodyR * b;
  final rim = 0.08 * b;
  final grains = <DecorShape>[];
  for (var c = 0; c < sparkles.grains.length; c++) {
    final v = VecBuilder();
    final r = _grainLooks[c].$1 * b;
    final xy = sparkles.grains[c];
    for (var i = 0; i + 1 < xy.length; i += 2) {
      v.circle(xy[i], xy[i + 1], r);
    }
    grains.add(DecorShape.vector(v.build()));
  }
  final (halos, edge, star, center) = _starPaths(sparkles.stars);
  DecorShape tube(double radius) => sp.isDot
      ? DecorShape.vector(
          (VecBuilder()..circle(sp.xs[0], sp.ys[0], radius)).build(),
        )
      : DecorShape.outline(tubeOutline(sp, w, radius: (_) => radius));
  return _Geom(
    tube(rb + rim),
    tube(rb),
    grains,
    [for (final h in halos) DecorShape.vector(h.build())],
    DecorShape.vector(edge.build()),
    DecorShape.vector(star.build()),
    DecorShape.vector(center.build()),
  );
}

final class _GlitterPen extends DecorPen {
  const _GlitterPen();

  @override
  List<DecorLayer> layers(InkStroke stroke, int colorArgb) {
    final g = _geometry[stroke] ??= _build(stroke);
    final t = _Tones(colorArgb);
    final pale = lightInk(colorArgb);
    return [
      if (pale > 0.01) (shape: g.rim, argb: kRimArgb, alpha: 0.55 * pale),
      (shape: g.body, argb: t.deep, alpha: 1.0),
      for (var c = 0; c < g.grains.length; c++)
        (shape: g.grains[c], argb: t.grain(c), alpha: _grainLooks[c].$2),
      for (var k = 0; k < g.halos.length; k++)
        (shape: g.halos[k], argb: t.halo, alpha: _haloA[k] * t.glowA),
      (shape: g.edge, argb: darken(t.halo, 0.25), alpha: _edgeAlpha),
      (shape: g.star, argb: kWhite, alpha: 1.0),
      (shape: g.center, argb: kWhite, alpha: 0.9),
    ];
  }

  @override
  void paintLive(ui.Canvas canvas, PenLiveFrame frame) {
    final w = frame.style.width;
    final b = _unitOfWidth * w;
    final o = frame.opacity;
    final sp = DecorSpine.offsets(frame.centerline, 0.25);
    if (sp.isEmpty) return;
    final t = _Tones(frame.style.colorArgb);
    final pale = lightInk(frame.style.colorArgb);
    final rb = _bodyR * b;
    // body (and rim): a round stroke of the centerline; the drop look of a dot
    // comes with the pen lift
    final line = tubePolyline(sp);
    if (pale > 0.01) {
      canvas.drawPath(
        line,
        tubePaint(rb + 0.08 * b, kRimArgb, 0.55 * pale * o),
      );
    }
    canvas.drawPath(line, tubePaint(rb, t.deep, o));
    if (sp.isDot) return;
    final sparkles = _sparkles(sp, w, frame.seed);
    for (var c = 0; c < sparkles.grains.length; c++) {
      final xy = sparkles.grains[c];
      if (xy.isEmpty) continue;
      final (r, alpha) = _grainLooks[c];
      canvas.drawRawPoints(
        ui.PointMode.points,
        Float32List.fromList(xy),
        ui.Paint()
          ..isAntiAlias = true
          ..strokeCap = ui.StrokeCap.round
          ..strokeWidth = 2 * r * b
          ..color = fillPaint(t.grain(c), alpha * o).color,
      );
    }
    final (halos, edge, star, center) = _starPaths(sparkles.stars);
    for (var k = 0; k < halos.length; k++) {
      if (halos[k].isEmpty) continue;
      canvas.drawPath(
        halos[k].build().toUiPath(),
        fillPaint(t.halo, _haloA[k] * t.glowA * o),
      );
    }
    if (!star.isEmpty) {
      canvas
        ..drawPath(
          edge.build().toUiPath(),
          fillPaint(darken(t.halo, 0.25), _edgeAlpha * o),
        )
        ..drawPath(star.build().toUiPath(), fillPaint(kWhite, o))
        ..drawPath(center.build().toUiPath(), fillPaint(kWhite, 0.9 * o));
    }
  }
}
