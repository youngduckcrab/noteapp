// lib/src/render/pens/decor/rainbow_pen.dart — INTERNAL (v2.11, C211-01) 무지개.
//
// OWNED BY THE DECOR TRACK. The lock app's rainbow (EffectBrushes `rainbow`),
// frozen: the hue runs along the stroke's arc length through the lock app's
// palette (7 colors, the first repeated at the end so it wraps without a seam),
// one round of the palette every P = 12 · w, plus the lock app's two gloss
// lines (a faint white highlight near the center, a thin brighter specular
// line towards the light). No time animation: the lock app slides the
// gradient; here it stays where the pen color puts it — the palette starts at
// the color nearest to the pen color's hue (red by default; gray / black start
// at red), so the color button picks where the rainbow begins.
//
// The period does not depend on the stroke's length (the lock app's
// min(L, 36 · w) stretched the colors while the stroke grew, and every short
// jamo ran through the whole palette — handwriting looked like confetti): a
// 15 pt jamo shows two or three neighboring hues, a long line cycles.
//
// Body: the stroke's outline radius (pressure as the ballpoint) cut along its
// length into bands of P / nc (nc ≤ 72 per round, bands ≥ 0.3 pt). Band j has
// the palette color of step j mod nc; all bands of one step are one piece (≤ nc
// pieces per stroke + 2 gloss lines, whatever the length). A band is the
// polygon of its piece of the centerline offset by the radius on both sides
// (butt ends — neighbors share the cut exactly), with round wedges at sharp
// turns and half discs at the two ends of the stroke. On the screen and in an
// opaque PDF a band reaches ε past its end under the next band (no
// anti-aliasing seam); a translucent PDF gets the bands without ε, so no area
// is covered twice (the screen paints translucent bands opaque inside one
// layer).
//
// Live: the same bands from the live centerline, with a radius wider than the
// live outline and clipped to it (frame.paths), so the colors sit at the same
// arc lengths before and after the pen lift. Bands whose points settled are
// kept between frames (LiveSpineCache): a frame builds only the last bands.
//
// A dot is the lock app's rainbow bead (`rainbowTapGeom`): a disc cut by the
// rainbow bands running diagonally (down-right, slightly curved around a far
// center), a faint dark rim and the white gloss and specular ovals — the same
// on the live dot and the stored one (no color wheel: the lock app dropped it
// because it looked like a color picker / a spinner).
import 'dart:math' as math;
import 'dart:ui' as ui;

import '../../../geometry/stroke_outline.dart';
import '../../../model/ink_stroke.dart';
import '../pen_renderer.dart';
import 'decor_kit.dart';

const PenRenderer rainbowPen = _RainbowPen();

/// The lock app's RAINBOW palette (first = last).
const List<int> kRainbowPalette = [
  0xFFFF4D6D,
  0xFFFF8A3D,
  0xFFFFD23F,
  0xFF52D681,
  0xFF3BB8F5,
  0xFF7C6CF2,
  0xFFE36BEA,
  0xFFFF4D6D,
];

/// The palette color at [t] (wraps every 1).
int rainbowAt(double t) {
  final u = (t % 1 + 1) % 1 * (kRainbowPalette.length - 1);
  final i = u.floor().clamp(0, kRainbowPalette.length - 2);
  return mixArgb(kRainbowPalette[i], kRainbowPalette[i + 1], u - i);
}

final Map<int, double> _starts = {};

/// Where the palette starts for [colorArgb]: the palette position whose hue is
/// nearest to the color's hue; 0 (red) for grays and very dark colors.
double rainbowStart(int colorArgb) {
  final key = colorArgb % 0x1000000;
  final hit = _starts[key];
  if (hit != null) return hit;
  final (h, s, v) = hsvOf(colorArgb);
  var best = 0.0;
  if (s >= 0.25 && v >= 0.2) {
    var bestD = double.infinity;
    const steps = 168;
    for (var k = 0; k < steps; k++) {
      final t = k / steps;
      final (ph, _, _) = hsvOf(rainbowAt(t));
      final d0 = (ph - h).abs();
      final d = math.min(d0, 360 - d0);
      if (d < bestD - 1e-9) {
        bestD = d;
        best = t;
      }
    }
  }
  if (_starts.length >= 64) _starts.clear();
  return _starts[key] = best;
}

// sizes in multiples of the width
const double _periodOfWidth = 12;
const int _maxSteps = 72, _minSteps = 6;
const double _bandMinPt = 0.3;
const double _hlShift = 0.05, _hlRadius = 0.11, _hlAlpha = 0.22;
const double _specShift = 0.17, _specRadius = 0.055, _specAlpha = 0.5;
const double _glossTrim = 0.5;

/// The live band radius: the widest live outline (factor 1.2 → 0.6 · w) and
/// a hair for anti-aliasing; the clip to the outline gives the shape. Not
/// wider: where a stroke comes back near itself (an ㅇ closing on its start)
/// a wider band would spill its color onto the other part inside the clip.
const double _liveRadius = 0.62;

/// Wedges at turns sharper than this (cos of 12°).
const double _wedgeCos = 0.978;

/// The rainbow's period: one round of the palette (pt).
double rainbowPeriod(double w) => _periodOfWidth * w;

/// The palette steps of one round and the band length (pt).
(int, double) rainbowBands(double w) {
  final p = rainbowPeriod(w);
  final nc = (p / _bandMinPt).floor().clamp(_minSteps, _maxSteps);
  return (nc, p / nc);
}

/// The overlap of a band under the next one (screen, opaque PDF).
double _overlap(double band) => math.min(0.15, 0.25 * band);

double _specRadiusOf(double w, double reach) =>
    math.min(math.max(_specRadius * w, 0.12), reach - _specShift * w);

/// Appends band [t0, t1] of [sp] — radius [radius] of the widthQ — to [v]:
/// the offset polygon, round wedges at sharp turns, half discs at the stroke's
/// ends ([startCap], [endCap]).
void _band(
  VecBuilder v,
  DecorSpine sp,
  double t0,
  double t1,
  double Function(double q) radius, {
  required bool startCap,
  required bool endCap,
}) {
  final rows = sp.range(t0, t1);
  final m = rows.length ~/ 5;
  final xy = List<double>.filled(4 * m, 0);
  for (var k = 0; k < m; k++) {
    final o = 5 * k;
    final r = radius(rows[o + 4]);
    xy[2 * k] = rows[o] + rows[o + 2] * r;
    xy[2 * k + 1] = rows[o + 1] + rows[o + 3] * r;
    final b = 2 * (2 * m - 1 - k);
    xy[b] = rows[o] - rows[o + 2] * r;
    xy[b + 1] = rows[o + 1] - rows[o + 3] * r;
  }
  v.polygon(xy);
  // round wedges on the outer side of sharp turns (the polygon cuts them)
  if (sp.n >= 3) {
    final a = sp.segmentAt(t0), b = sp.segmentAt(t1);
    for (var i = math.max(1, a + 1); i <= math.min(b, sp.n - 2); i++) {
      if (!(sp.s[i] > t0 && sp.s[i] < t1)) continue;
      final ax = sp.xs[i] - sp.xs[i - 1], ay = sp.ys[i] - sp.ys[i - 1];
      final bx = sp.xs[i + 1] - sp.xs[i], by = sp.ys[i + 1] - sp.ys[i];
      final la = math.sqrt(ax * ax + ay * ay),
          lb = math.sqrt(bx * bx + by * by);
      final dot = (ax * bx + ay * by) / (la * lb);
      if (dot >= _wedgeCos) continue;
      final cross = (ax * by - ay * bx) / (la * lb);
      final theta = math.atan2(cross, dot);
      final sign = cross > 0 ? -1.0 : 1.0;
      final nx = -ay / la * sign, ny = ax / la * sign;
      final r = radius(sp.qs[i]);
      final steps = (theta.abs() / (math.pi / 9)).ceil().clamp(1, 9);
      final w = <double>[sp.xs[i], sp.ys[i]];
      for (var k = 0; k <= steps; k++) {
        final f = theta * k / steps;
        final c = math.cos(f), s = math.sin(f);
        w
          ..add(sp.xs[i] + r * (nx * c - ny * s))
          ..add(sp.ys[i] + r * (nx * s + ny * c));
      }
      v.polygon(w);
    }
  }
  void cap(int o, double along) {
    final cx = rows[o], cy = rows[o + 1], nx = rows[o + 2], ny = rows[o + 3];
    final tx = ny * along, ty = -nx * along;
    final r = radius(rows[o + 4]);
    final c = <double>[];
    const steps = 12;
    for (var k = 0; k <= steps; k++) {
      final f = math.pi * k / steps;
      final cs = math.cos(f), sn = math.sin(f);
      c
        ..add(cx + r * (nx * cs + tx * sn))
        ..add(cy + r * (ny * cs + ty * sn));
    }
    v.polygon(c);
  }

  if (startCap) cap(0, -1);
  if (endCap) cap(5 * (m - 1), 1);
}

/// The bands of [sp] from band [from] as one VecBuilder per palette step.
/// [upTo] (exclusive) stops at a band index; [overlap]: bands reach ε under
/// the next one.
void _bands(
  DecorSpine sp,
  double w,
  double Function(double q) radius,
  List<VecBuilder?> out, {
  int from = 0,
  int? upTo,
  required bool overlap,
}) {
  final (nc, band) = rainbowBands(w);
  final length = sp.length;
  final count = math.max(1, (length / band - 1e-9).ceil());
  final last = count - 1;
  final eps = overlap ? _overlap(band) : 0.0;
  for (var j = from; j < (upTo ?? count); j++) {
    final t0 = j * band;
    final t1 = j == last ? length : math.min(length, (j + 1) * band + eps);
    _band(
      out[j % nc] ??= VecBuilder(),
      sp,
      t0,
      t1,
      radius,
      startCap: j == 0,
      endCap: j == last,
    );
  }
}

// --- the bead (a dot) ----------------------------------------------------------

const double _beadR = 0.72; // × w (lock RAINBOW_TAP_R_BIG; K-1 caps it)
const double _beadPeriod = 0.32 * 7; // × w (lock RAINBOW_TAP_HUE · 7)
const double _beadFar = 3, _beadMid = 0.34; // lock RAINBOW_TAP_FAR / _MID
const int _beadSteps = 36; // palette steps per round on the bead
const double _beadRim = 0.07, _beadRimAlpha = 0.2;
const int _beadSamples = 48;

/// The bead of a dot at ([cx], [cy]) of width [w]: (palette offset, shape) per
/// band, then the rim, the gloss and the specular oval.
(List<(double, DecorShape)>, DecorShape, DecorShape, DecorShape) _bead(
  double cx,
  double cy,
  double w,
) {
  final rimHalf = 0.5 * _beadRim * w;
  final r = math.min(_beadR * w, minReach(w) - rimHalf);
  final period = _beadPeriod * w;
  // bands are rings around a far center up-left, so they run down-right and
  // bend a little around the bead
  const ux = 0.70710678, uy = 0.70710678;
  final far = period * (_beadFar + _beadMid);
  final fx = cx - ux * far, fy = cy - uy * far;
  final phiC = math.atan2(cy - fy, cx - fx);
  final alpha = math.asin(math.min(1.0, r / far));
  final step = period / _beadSteps;
  final out = <(double, DecorShape)>[];
  // the disc between ρ (distance from the far center) in [rho0, rho1]
  (double, double)? span(double delta) {
    final sn = math.sin(delta);
    final disc = r * r - far * far * sn * sn;
    if (disc < 0) return null;
    final c = far * math.cos(delta), q = math.sqrt(disc);
    return (c - q, c + q);
  }

  final j0 = ((far - r) / step).floor(), j1 = ((far + r) / step).ceil();
  for (var j = j0; j < j1; j++) {
    final ra = j * step, rb = (j + 1) * step;
    double gap(double delta) {
      final sp = span(delta);
      if (sp == null) return -1;
      return math.min(rb, sp.$2) - math.max(ra, sp.$1);
    }

    final lo = <double>[], hi = <double>[];
    void add(double delta) {
      final sp = span(delta) ?? (far * math.cos(delta), far * math.cos(delta));
      final a = math.max(ra, sp.$1), b = math.max(a, math.min(rb, sp.$2));
      final e = phiC + delta;
      final ex = math.cos(e), ey = math.sin(e);
      lo
        ..add(fx + ex * a)
        ..add(fy + ey * a);
      hi
        ..add(fx + ex * b)
        ..add(fy + ey * b);
    }

    double? prev;
    var prevOk = false;
    for (var k = 0; k <= _beadSamples; k++) {
      // denser near the two tangents (the disc's edge turns fast there)
      final delta =
          alpha *
          0.999999 *
          math.sin(-math.pi / 2 + math.pi * k / _beadSamples);
      final ok = gap(delta) > 0;
      if (prev != null && ok != prevOk) {
        // the band starts or ends between the two samples: find where
        var a = prev, b = delta;
        for (var it = 0; it < 14; it++) {
          final mid = (a + b) / 2;
          if ((gap(mid) > 0) == prevOk) {
            a = mid;
          } else {
            b = mid;
          }
        }
        add(ok ? b : a);
      }
      if (ok) add(delta);
      prev = delta;
      prevOk = ok;
    }
    if (lo.length < 4) continue;
    final xy = <double>[...lo];
    for (var i = hi.length - 2; i >= 0; i -= 2) {
      xy
        ..add(hi[i])
        ..add(hi[i + 1]);
    }
    final v = VecBuilder()..polygon(xy);
    if (v.isEmpty) continue;
    out.add(((j + 0.5) / _beadSteps, DecorShape.vector(v.build())));
  }
  final rim = VecBuilder()
    ..circle(cx, cy, r + rimHalf)
    ..circleReversed(cx, cy, r - rimHalf);
  final gloss = VecBuilder()
    ..ellipse(cx - 0.22 * r, cy - 0.36 * r, 0.9 * r, 0.45 * r, -35);
  final spec = VecBuilder()
    ..ellipse(cx - 0.42 * r, cy - 0.44 * r, 0.26 * r, 0.09 * r, -40);
  return (
    out,
    DecorShape.vector(rim.build()),
    DecorShape.vector(gloss.build()),
    DecorShape.vector(spec.build()),
  );
}

List<DecorLayer> _beadLayers(
  (List<(double, DecorShape)>, DecorShape, DecorShape, DecorShape) b,
  double start,
) => [
  for (final (t, shape) in b.$1)
    (shape: shape, argb: rainbowAt(start + t), alpha: 1.0),
  (shape: b.$2, argb: kBlack, alpha: _beadRimAlpha),
  (shape: b.$3, argb: kWhite, alpha: 0.18),
  (shape: b.$4, argb: kWhite, alpha: 0.5),
];

// --- committed -------------------------------------------------------------------

final class _Geom {
  _Geom.line(this.steps, this.highlight, this.specular) : bead = null;
  _Geom.dot(this.bead) : steps = const [], highlight = null, specular = null;

  /// one shape per palette step (null: no band of that step)
  final List<DecorShape?> steps;
  final DecorShape? highlight, specular;
  final (List<(double, DecorShape)>, DecorShape, DecorShape, DecorShape)? bead;

  int get bytes => shapesBytes([
    ...steps,
    highlight,
    specular,
    if (bead != null) ...[for (final b in bead!.$1) b.$2, bead!.$2, bead!.$3],
  ]);
}

List<DecorShape?> _stepShapes(InkStroke stroke, DecorSpine sp, bool overlap) {
  final w = stroke.style.width;
  final reach = reachOf(stroke);
  final (nc, _) = rainbowBands(w);
  final out = List<VecBuilder?>.filled(nc, null);
  _bands(sp, w, (q) => math.min(reach, 2 * w * q), out, overlap: overlap);
  return [for (final v in out) v == null ? null : DecorShape.vector(v.build())];
}

_Geom _build(InkStroke stroke) {
  final w = stroke.style.width;
  final sp = DecorSpine.of(stroke.points);
  if (sp.isDot) return _Geom.dot(_bead(sp.xs[0], sp.ys[0], w));
  final reach = reachOf(stroke);
  final side = sp.lightSide(w);
  final (g0, g1) = trimmed(sp.length, _glossTrim * w);
  final spec = _specRadiusOf(w, reach);
  return _Geom.line(
    _stepShapes(stroke, sp, true),
    DecorShape.outline(
      tubeOutline(
        sp,
        w,
        radius: (_) => _hlRadius * w,
        t0: g0,
        t1: g1,
        shift: side * _hlShift * w,
        within: reach,
      ),
    ),
    spec > 0
        ? DecorShape.outline(
            tubeOutline(
              sp,
              w,
              radius: (_) => spec,
              t0: g0,
              t1: g1,
              shift: side * _specShift * w,
              within: reach,
            ),
          )
        : null,
  );
}

_Geom _geom(InkStroke stroke) =>
    decorGeometry('rainbow', stroke, () => _build(stroke), (g) => g.bytes);

List<DecorLayer> _lineLayers(List<DecorShape?> steps, _Geom g, double start) {
  final nc = steps.length;
  return [
    for (var k = 0; k < nc; k++)
      if (steps[k] != null)
        (shape: steps[k]!, argb: rainbowAt(start + (k + 0.5) / nc), alpha: 1.0),
    if (g.highlight != null)
      (shape: g.highlight!, argb: kWhite, alpha: _hlAlpha),
    if (g.specular != null)
      (shape: g.specular!, argb: kWhite, alpha: _specAlpha),
  ];
}

// --- live ------------------------------------------------------------------------

final class _Live extends LiveSpineCache {
  _Live(super.key, int nc) : steps = List.generate(nc, (_) => ui.Path());

  /// the kept bands [0, next) by palette step
  final List<ui.Path> steps;
  int next = 0;
}

final LiveCaches<_Live> _lives = LiveCaches<_Live>();

final class _RainbowPen extends DecorPen {
  const _RainbowPen();

  @override
  List<DecorLayer> layers(
    InkStroke stroke,
    StrokeOutline outline,
    int colorArgb,
  ) {
    final g = _geom(stroke);
    final start = rainbowStart(colorArgb);
    final bead = g.bead;
    if (bead != null) return _beadLayers(bead, start);
    return _lineLayers(g.steps, g, start);
  }

  @override
  List<PenVectorPiece> vectorPieces(
    InkStroke stroke,
    StrokeOutline outline, {
    required double opacity,
    required bool smooth,
  }) {
    final g = _geom(stroke);
    if (opacity >= 1 || g.bead != null) {
      return super.vectorPieces(
        stroke,
        outline,
        opacity: opacity,
        smooth: smooth,
      );
    }
    // translucent: bands that only touch (no area under two fills)
    final steps = _stepShapes(stroke, DecorSpine.of(stroke.points), false);
    return [
      for (final l in _lineLayers(
        steps,
        g,
        rainbowStart(stroke.style.colorArgb),
      ))
        (
          path: l.shape.vectorPath(smooth: smooth),
          colorArgb: opaqueArgb(l.argb),
          opacity: (l.alpha * opacity).clamp(0.0, 1.0).toDouble(),
        ),
    ];
  }

  @override
  void paintCommitted(
    ui.Canvas canvas,
    InkStroke stroke,
    StrokeOutline outline, {
    required int colorArgb,
    required double opacity,
    ui.Image? grain,
  }) {
    if (opacity >= 1) {
      super.paintCommitted(
        canvas,
        stroke,
        outline,
        colorArgb: colorArgb,
        opacity: opacity,
      );
      return;
    }
    // translucent: the bands opaque inside one layer (no darker joints)
    canvas.saveLayer(stroke.bounds.inflate(1), fillPaint(0, opacity));
    super.paintCommitted(
      canvas,
      stroke,
      outline,
      colorArgb: colorArgb,
      opacity: 1,
    );
    canvas.restore();
  }

  @override
  void paintLive(ui.Canvas canvas, PenLiveFrame frame) {
    final w = frame.style.width;
    final o = frame.opacity;
    final start = rainbowStart(frame.style.colorArgb);
    final sp = DecorSpine.offsets(frame.centerline, 0.25);
    if (sp.isEmpty) return;
    final layered = o < 1;
    if (layered) canvas.saveLayer(frame.bounds, fillPaint(0, o));
    if (sp.isDot) {
      for (final l in _beadLayers(_bead(sp.xs[0], sp.ys[0], w), start)) {
        canvas.drawPath(l.shape.path, fillPaint(l.argb, l.alpha));
      }
    } else {
      _paintLiveLine(canvas, frame, sp, w, start);
    }
    if (layered) canvas.restore();
  }

  void _paintLiveLine(
    ui.Canvas canvas,
    PenLiveFrame frame,
    DecorSpine sp,
    double w,
    double start,
  ) {
    final (nc, band) = rainbowBands(w);
    final key = (frame.seed, w);
    var live = _lives.of(key, () => _Live(key, nc));
    var settled = 0;
    if (!live.update(sp, (c) => settled = c)) {
      final fresh = _Live(key, nc);
      _lives.reset(live, fresh);
      live = fresh..update(sp, (c) => settled = c);
    }
    double radius(double _) => _liveRadius * w;
    // bands whose points have settled (and that are not the last): keep them
    final safe = settledLength(sp, settled);
    final eps = _overlap(band);
    var upTo = live.next;
    while ((upTo + 1) * band + eps <= safe && (upTo + 1) * band < sp.length) {
      upTo++;
    }
    if (upTo > live.next) {
      final add = List<VecBuilder?>.filled(nc, null);
      _bands(sp, w, radius, add, from: live.next, upTo: upTo, overlap: true);
      for (var k = 0; k < nc; k++) {
        final v = add[k];
        if (v != null) {
          live.steps[k].addPath(v.build().toUiPath(), ui.Offset.zero);
        }
      }
      live
        ..next = upTo
        ..depends = settled;
    }
    final tail = List<VecBuilder?>.filled(nc, null);
    _bands(sp, w, radius, tail, from: live.next, overlap: true);
    final tailPaths = [for (final v in tail) v?.build().toUiPath()];
    final paints = [
      for (var k = 0; k < nc; k++)
        fillPaint(rainbowAt(start + (k + 0.5) / nc), 1),
    ];
    for (final p in frame.paths) {
      canvas
        ..save()
        ..clipPath(p);
      for (var k = 0; k < nc; k++) {
        if (k < live.steps.length) canvas.drawPath(live.steps[k], paints[k]);
        final t = tailPaths[k];
        if (t != null) canvas.drawPath(t, paints[k]);
      }
      canvas.restore();
    }
    final side = sp.lightSide(w);
    final (g0, g1) = trimmed(sp.length, _glossTrim * w);
    final spec = _specRadiusOf(w, minReach(w));
    canvas.drawPath(
      tubePolyline(sp, t0: g0, t1: g1, shift: side * _hlShift * w),
      tubePaint(_hlRadius * w, kWhite, _hlAlpha),
    );
    if (spec > 0) {
      canvas.drawPath(
        tubePolyline(sp, t0: g0, t1: g1, shift: side * _specShift * w),
        tubePaint(spec, kWhite, _specAlpha),
      );
    }
  }
}
