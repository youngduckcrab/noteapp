// lib/src/render/pens/decor/glitter_pen.dart — INTERNAL (v2.11, C211-01) 반짝이.
//
// OWNED BY THE DECOR TRACK. The lock app's glitter (EffectBrushes `glitter`,
// `glitterGeom`, `glitterTones`, `sparkle`), frozen in one moment: a body in a
// deeper shade of the pen color, dense grains in four tones of the pen color,
// some grains caught bright (the lock app's twinkling share, here with a fixed
// brightness each), and white four-armed stars with a halo in the pen color at
// seeded places along the line. No time animation and no moving light band.
//
// Determinism: grain k sits at arc length (k + u) · Δ (Δ fixed by the width,
// ≥ 0.08 pt; every 2,500 grains the spacing doubles from there on) and star j
// follows star j − 1 by a seeded gap (≥ 3 pt; doubling every 160 places) —
// both from PenRandom(penSeed([createdAt, stream])) streams consumed in arc-
// length order and never moved once made (_Gen), so the live stroke (same
// createdAt = PenLiveFrame.seed) grows the same grains and stars as the stored
// one, and the screen, thumbnails and the PDF get the same ones. The cost per
// length is bounded at every width (a thin long stroke thins out at its end).
// Live: the grains and stars over settled points are kept between frames
// (LiveSpineCache) — a frame generates only the new end. A partial erase restarts the arc length of the pieces
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
// an octagon (a circle from 0.5 pt radius). Live: body as a round stroke,
// grains as round points, the same stars (kept between frames).
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../geometry/stroke_outline.dart';
import '../../../model/ink_stroke.dart';
import '../pen_random.dart';
import '../pen_renderer.dart';
import 'decor_kit.dart';

const PenRenderer glitterPen = _GlitterPen();

const double _unitOfWidth = 0.6;
const double _bodyR = 0.5; // × b
// × b of arc length per grain (lock app 0.05; a little sparser with grains
// 12 % larger — the same cover, a quarter fewer shapes in the PDF)
const double _grainSpacing = 0.065;
const double _grainMinStep = 0.08; // pt: thin pens get fewer, not more grains
const int _grainBlock = 2500; // grains per block (then half as dense)
const double _across = 0.88; // × body radius
const double _starGap = 3.4; // × b
const double _starShow = 0.5; // share of star places that shine
const double _starMinGap = 3; // pt
const int _starBlock = 160; // star places per block (then half as many)

/// grain radius (× b) and alpha of the four tones, then low / mid / high
const List<(double, double)> _grainLooks = [
  (0.084, 0.8),
  (0.084, 0.9),
  (0.0756, 0.9),
  (0.084, 0.9),
  (0.084, 0.9), // low: tint 1
  (0.106, 0.95), // mid: glint
  (0.14, 1.0), // high: white
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

/// two stars on a dot (the lock app's five made periods and i-dots read as
/// star clusters bigger than the letters)
const List<double> _tapStarA = [0.12, 0.62];

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
final class _Sink {
  final List<List<double>> g = List.generate(7, (_) => <double>[]);
  final List<double> st = [];

  void star(double x, double y, double size, double deg, double grow) =>
      st.addAll([x, y, size, deg, grow]);
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

/// 2^m (m ≥ 0) without dart:math pow.
double _pow2(int m) {
  var p = 1.0;
  for (var i = 0; i < m; i++) {
    p *= 2;
  }
  return p;
}

/// The grains and stars of a line, generated in arc-length order and only
/// ever appended: [run] adds every grain and star up to an arc length. The
/// live stroke keeps one generator for its settled part and runs a [copy]
/// for the rest of the frame.
///
/// Spacing: grain k of block m = k ~/ [_grainBlock] sits in block m's stretch
/// at (k mod block + u) · Δ · 2^m (Δ fixed by the width, at least
/// [_grainMinStep]); stars likewise with [_starBlock] places per block — so a
/// very long or very thin stroke thins out towards its end instead of moving
/// the grains it already has, and its cost stays bounded per length.
final class _Gen {
  _Gen(int seed, double w)
    : _b = _unitOfWidth * w,
      _reach = minReach(w),
      _step = math.max(_grainSpacing * _unitOfWidth * w, _grainMinStep),
      _gap = math.max(_starGap * _unitOfWidth * w, _starMinGap),
      _gr = PenRandom(penSeed([seed, 1])),
      _sr = PenRandom(penSeed([seed, 2])) {
    _nextStar = _gap * (0.3 + 0.4 * _sr.next());
    _pullGrain();
  }

  _Gen._copy(_Gen o)
    : _b = o._b,
      _reach = o._reach,
      _step = o._step,
      _gap = o._gap,
      _gr = o._gr.copy(),
      _sr = o._sr.copy(),
      _k = o._k,
      _gs = o._gs,
      _gu1 = o._gu1,
      _gu2 = o._gu2,
      _gu3 = o._gu3,
      _place = o._place,
      _nextStar = o._nextStar;

  final double _b, _reach, _step, _gap;
  final PenRandom _gr, _sr;

  /// the next grain: index, arc length and its other draws
  int _k = 0;
  double _gs = 0, _gu1 = 0, _gu2 = 0, _gu3 = 0;

  /// the next star place: index and arc length
  int _place = 0;
  double _nextStar = 0;

  _Gen copy() => _Gen._copy(this);

  void _pullGrain() {
    final u0 = _gr.next();
    _gu1 = _gr.next();
    _gu2 = _gr.next();
    _gu3 = _gr.next();
    final m = _k ~/ _grainBlock, i = _k - m * _grainBlock;
    final scale = _pow2(m);
    _gs = _step * _grainBlock * (scale - 1) + (i + u0) * _step * scale;
  }

  /// Adds the grains and stars at arc length ≤ [upTo] to [out].
  void run(DecorSpine sp, double upTo, _Sink out) {
    final row = Float64List(5);
    final rb = _bodyR * _b;
    while (_gs <= upTo) {
      sp.sampleInto(_gs, row, 0);
      final across = (2 * _gu1 - 1) * rb * _across;
      out.g[_classOf(_gu2, _gu3)]
        ..add(row[0] + row[2] * across)
        ..add(row[1] + row[3] * across);
      _k++;
      _pullGrain();
    }
    while (_nextStar <= upTo) {
      final uA = _sr.next(), uShow = _sr.next(), uSize = _sr.next();
      final uRot = _sr.next(), uGap = _sr.next();
      if (uShow < _starShow) {
        sp.sampleInto(_nextStar, row, 0);
        final across = (uA - 0.5) * 0.24 * _b;
        final room = (_reach - across.abs()) / _extent;
        final env = 0.5 + 0.5 * uSize;
        out.star(
          row[0] + row[2] * across,
          row[1] + row[3] * across,
          room * env,
          (uRot - 0.5) * 40,
          math.min(1, env * 1.6),
        );
      }
      _nextStar += _gap * _pow2(_place ~/ _starBlock) * (0.75 + 0.5 * uGap);
      _place++;
    }
  }
}

/// The grains and stars of a dot (the lock app's glitter tap).
void _dotSparkles(DecorSpine sp, double w, int seed, _Sink out) {
  final b = _unitOfWidth * w;
  final reach = minReach(w);
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
}

/// The grains of [xy] (from coordinate [from]) of radius [r].
VecBuilder _grainPath(List<double> xy, double r, [int from = 0]) {
  final v = VecBuilder();
  for (var i = from; i + 1 < xy.length; i += 2) {
    v.grain(xy[i], xy[i + 1], r);
  }
  return v;
}

/// Star paths from the star rows [from, …): halo layers, edge, stars, centers.
(List<VecBuilder>, VecBuilder, VecBuilder, VecBuilder) _starPaths(
  List<double> st, [
  int from = 0,
]) {
  final halos = [for (var k = 0; k < _haloK.length; k++) VecBuilder()];
  final edge = VecBuilder(), star = VecBuilder(), center = VecBuilder();
  for (var i = from; i + 4 < st.length; i += 5) {
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

  int get bytes =>
      shapesBytes([rim, body, ...grains, ...halos, edge, star, center]);
}

_Geom _build(InkStroke stroke) {
  final w = stroke.style.width;
  final b = _unitOfWidth * w;
  final sp = DecorSpine.of(stroke.points);
  final sparkles = _Sink();
  if (sp.isDot) {
    _dotSparkles(sp, w, stroke.source.createdAt, sparkles);
  } else {
    _Gen(stroke.source.createdAt, w).run(sp, sp.length, sparkles);
  }
  final rb = sp.isDot ? _tapR * b : _bodyR * b;
  final rim = 0.08 * b;
  final grains = [
    for (var c = 0; c < sparkles.g.length; c++)
      DecorShape.vector(
        _grainPath(sparkles.g[c], _grainLooks[c].$1 * b).build(),
      ),
  ];
  final (halos, edge, star, center) = _starPaths(sparkles.st);
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
  List<DecorLayer> layers(
    InkStroke stroke,
    StrokeOutline outline,
    int colorArgb,
  ) {
    final g = decorGeometry(
      'glitter',
      stroke,
      () => _build(stroke),
      (g) => g.bytes,
    );
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
    final key = (frame.seed, w);
    var live = _lives.of(key, () => _Live(key, frame.seed, w));
    var settled = 0;
    if (!live.update(sp, (c) => settled = c)) {
      final fresh = _Live(key, frame.seed, w);
      _lives.reset(live, fresh);
      live = fresh..update(sp, (c) => settled = c);
    }
    // the sparkles over settled points are final: keep them
    final safe = settledLength(sp, settled);
    if (safe > 0) {
      final before = live.sink.st.length;
      live.gen.run(sp, safe, live.sink);
      live.depends = settled;
      if (live.sink.st.length > before) {
        final (halos, edge, star, center) = _starPaths(live.sink.st, before);
        for (var k = 0; k < halos.length; k++) {
          live.halos[k].addPath(halos[k].build().toUiPath(), ui.Offset.zero);
        }
        live.edge.addPath(edge.build().toUiPath(), ui.Offset.zero);
        live.star.addPath(star.build().toUiPath(), ui.Offset.zero);
        live.center.addPath(center.build().toUiPath(), ui.Offset.zero);
      }
    }
    final tail = _Sink();
    live.gen.copy().run(sp, sp.length, tail);
    // grains as round points (the stored ones are octagons of the same
    // radius — the same at any zoom a grain is seen at; points keep a frame
    // cheap: a path of thousands of grains would be filled anew every frame)
    for (var c = 0; c < tail.g.length; c++) {
      final (r, alpha) = _grainLooks[c];
      final paint = ui.Paint()
        ..isAntiAlias = true
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = 2 * r * b
        ..color = fillPaint(t.grain(c), alpha * o).color;
      final kept = live.points(c);
      if (kept.isNotEmpty) {
        canvas.drawRawPoints(ui.PointMode.points, kept, paint);
      }
      final xy = tail.g[c];
      if (xy.isNotEmpty) {
        canvas.drawRawPoints(
          ui.PointMode.points,
          Float32List.fromList(xy),
          paint,
        );
      }
    }
    final (halos, edge, star, center) = _starPaths(tail.st);
    for (var k = 0; k < halos.length; k++) {
      final paint = fillPaint(t.halo, _haloA[k] * t.glowA * o);
      canvas.drawPath(live.halos[k], paint);
      if (!halos[k].isEmpty) {
        canvas.drawPath(halos[k].build().toUiPath(), paint);
      }
    }
    final edgePaint = fillPaint(darken(t.halo, 0.25), _edgeAlpha * o);
    final starPaint = fillPaint(kWhite, o);
    final centerPaint = fillPaint(kWhite, 0.9 * o);
    canvas
      ..drawPath(live.edge, edgePaint)
      ..drawPath(live.star, starPaint)
      ..drawPath(live.center, centerPaint);
    if (!star.isEmpty) {
      canvas
        ..drawPath(edge.build().toUiPath(), edgePaint)
        ..drawPath(star.build().toUiPath(), starPaint)
        ..drawPath(center.build().toUiPath(), centerPaint);
    }
  }
}

/// The kept part of a live glitter stroke.
final class _Live extends LiveSpineCache {
  _Live(super.key, int seed, double w) : gen = _Gen(seed, w);

  final _Gen gen;
  final _Sink sink = _Sink();
  final List<ui.Path> halos = [for (final _ in _haloK) ui.Path()];
  final ui.Path edge = ui.Path(), star = ui.Path(), center = ui.Path();
  final List<Float32List> _points = List.filled(7, Float32List(0));

  /// the kept grains of class [c] as raw points (rebuilt when they grow)
  Float32List points(int c) {
    final xy = sink.g[c];
    if (_points[c].length != xy.length) _points[c] = Float32List.fromList(xy);
    return _points[c];
  }
}

final LiveCaches<_Live> _lives = LiveCaches<_Live>();
