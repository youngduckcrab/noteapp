// lib/src/render/pens/decor/rainbow_pen.dart — INTERNAL (v2.11, C211-01) 무지개.
//
// OWNED BY THE DECOR TRACK. The lock app's rainbow (EffectBrushes `rainbow`),
// frozen: the hue runs along the stroke's arc length through the lock app's
// palette (7 colors, the first repeated at the end so it wraps without a seam),
// one round of the palette every P = max(4 · w, min(L, 36 · w)) — a short
// stroke still shows the whole rainbow — plus the lock app's two gloss lines
// (a faint white highlight near the center, a thin brighter specular line
// towards the light). No time animation: the lock app slides the gradient; here
// it stays where the pen color puts it — the palette starts at the color
// nearest to the pen color's hue (red by default; gray / black start at red),
// so the color button picks where the rainbow begins.
//
// Body: the stroke's outline (pressure as the ballpoint) cut along its length
// into bands of about P / 72 (≥ 0.12 · w, ≥ 0.3 pt; at most 600 per stroke),
// each band the round-cap outline of its piece of the centerline in its
// palette color, painted in order (a band's start cap covers the previous
// band's end, so there is no seam). Screen = PDF: the same band outlines.
// Opacity < 1: the screen paints the bands opaque inside one saveLayer (no
// darker overlaps); the PDF pieces overlap at the band joints (they are
// separate fills) — a known, small difference of translucent rainbows only.
//
// Every band's color is the palette at its start minus its radius (where it
// starts to show past the previous band's end), so the hue sits at the same
// arc length as in the live stroke: there the bands are wide butt-ended
// strokes of the live centerline (overlapping 0.5 pt, round discs at the two
// ends) clipped to the live outline paths (frozen + tail), at most 200 bands,
// and the same gloss lines. A dot is a little color wheel.
import 'dart:math' as math;
import 'dart:typed_data';
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
const double _bandMin = 0.12, _bandMinPt = 0.3;
const int _bandsPerRound = 72, _maxBands = 600, _maxLiveBands = 200;
const double _hlShift = 0.05, _hlRadius = 0.11, _hlAlpha = 0.22;
const double _specShift = 0.17, _specRadius = 0.055, _specAlpha = 0.5;
const double _glossTrim = 0.5;

/// The live band stroke radius: wider than the widest body (factor 1.2 →
/// 0.6 · w), the clip to the outline gives the shape.
const double _liveBandRadius = 0.7;

/// Live bands are butt-ended and overlap the next one by this (pt): no seam,
/// and the color changes where the band starts (as the stored bands' colors).
const double _liveOverlap = 0.5;

double _period(double w, double length) =>
    math.max(4 * w, math.min(length, 36 * w));

int _bandCount(double w, double length, int cap) {
  final p = _period(w, length);
  final band = math.max(p / _bandsPerRound, math.max(_bandMin * w, _bandMinPt));
  return (length / band).ceil().clamp(1, cap);
}

double _specRadiusOf(double w) => math.max(_specRadius * w, 0.12);

final class _Geom {
  _Geom(this.bands, this.mids, this.period, this.highlight, this.specular);
  final List<DecorShape> bands;

  /// arc length at the middle of each band (its color); for a dot: the wedge
  /// index / wedge count
  final List<double> mids;

  /// P; 0 for a dot (mids are palette offsets then)
  final double period;
  final DecorShape? highlight, specular;
}

final Expando<_Geom> _geometry = Expando<_Geom>('rainbow');

const int _wedges = 21;

_Geom _build(InkStroke stroke) {
  final w = stroke.style.width;
  final sp = DecorSpine.of(stroke.points);
  if (sp.isDot) {
    // a color wheel: wedges overlapping the next one by 2° (no seams)
    final c = ui.Offset(sp.xs[0], sp.ys[0]);
    // the cubic arcs' control points lie up to 0.7 % outside the circle
    final r = math.min(reachOf(stroke) * 0.99, 2 * w * sp.qs[0]);
    final step = 2 * math.pi / _wedges;
    final bands = <DecorShape>[];
    for (var k = 0; k < _wedges; k++) {
      final b = VecBuilder()..moveTo(c.dx, c.dy);
      final a0 = -math.pi / 2 + k * step;
      final sweep = step + 2 * math.pi / 180;
      b.lineTo(c.dx + r * math.cos(a0), c.dy + r * math.sin(a0));
      // one cubic arc: k = 4/3 · tan(θ / 4)
      final kk = 4 / 3 * math.tan(sweep / 4) * r;
      final a1 = a0 + sweep;
      b
        ..cubicTo(
          c.dx + r * math.cos(a0) - kk * math.sin(a0),
          c.dy + r * math.sin(a0) + kk * math.cos(a0),
          c.dx + r * math.cos(a1) + kk * math.sin(a1),
          c.dy + r * math.sin(a1) - kk * math.cos(a1),
          c.dx + r * math.cos(a1),
          c.dy + r * math.sin(a1),
        )
        ..close();
      bands.add(DecorShape.vector(b.build()));
    }
    final hl = VecBuilder()..circle(c.dx - 0.3 * r, c.dy - 0.35 * r, 0.2 * r);
    return _Geom(
      bands,
      [for (var k = 0; k < _wedges; k++) k / _wedges],
      0,
      DecorShape.vector(hl.build()),
      null,
    );
  }
  final length = sp.length;
  final n = _bandCount(w, length, _maxBands);
  final band = length / n;
  final reach = reachOf(stroke);
  final bands = <DecorShape>[];
  final mids = <double>[];
  final row = Float64List(5);
  for (var k = 0; k < n; k++) {
    bands.add(
      DecorShape.outline(
        tubeOutline(
          sp,
          w,
          radius: (q) => math.min(reach, 2 * w * q),
          t0: k * band,
          t1: k == n - 1 ? length : (k + 1) * band,
        ),
      ),
    );
    // a band's start cap covers its radius of the previous band, so the band
    // shows from about r before its start: its color is taken r earlier, and
    // the hue at every arc length is the palette's there
    sp.sampleInto(k * band, row, 0);
    mids.add((k + 0.5) * band - math.min(reach, 2 * w * row[4]));
  }
  final side = sp.lightSide(w);
  final (g0, g1) = trimmed(length, _glossTrim * w);
  return _Geom(
    bands,
    mids,
    _period(w, length),
    DecorShape.outline(
      tubeOutline(
        sp,
        w,
        radius: (_) => _hlRadius * w,
        t0: g0,
        t1: g1,
        shift: side * _hlShift * w,
      ),
    ),
    DecorShape.outline(
      tubeOutline(
        sp,
        w,
        radius: (_) => _specRadiusOf(w),
        t0: g0,
        t1: g1,
        shift: side * _specShift * w,
      ),
    ),
  );
}

final class _RainbowPen extends DecorPen {
  const _RainbowPen();

  @override
  List<DecorLayer> layers(InkStroke stroke, int colorArgb) {
    final g = _geometry[stroke] ??= _build(stroke);
    final start = rainbowStart(colorArgb);
    return [
      for (var k = 0; k < g.bands.length; k++)
        (
          shape: g.bands[k],
          argb: rainbowAt(
            start + (g.period > 0 ? g.mids[k] / g.period : g.mids[k]),
          ),
          alpha: 1.0,
        ),
      if (g.highlight != null)
        (shape: g.highlight!, argb: kWhite, alpha: _hlAlpha),
      if (g.specular != null)
        (shape: g.specular!, argb: kWhite, alpha: _specAlpha),
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
      final paint = fillPaint(rainbowAt(start), 1);
      for (final p in frame.paths) {
        canvas.drawPath(p, paint);
      }
    } else {
      final length = sp.length;
      final period = _period(w, length);
      final n = _bandCount(w, length, _maxLiveBands);
      final band = length / n;
      final bands = <(ui.Path, ui.Paint)>[];
      for (var k = 0; k < n; k++) {
        final paint = tubePaint(
          _liveBandRadius * w,
          rainbowAt(start + (k + 0.5) * band / period),
          1,
        )..strokeCap = ui.StrokeCap.butt;
        final t0 = k * band;
        final t1 = k == n - 1 ? length : (k + 1) * band + _liveOverlap;
        bands.add((tubePolyline(sp, t0: t0, t1: t1), paint));
      }
      // the round ends of the outline (under the butt-ended bands): discs in
      // the end bands' colors
      final ends = [
        (ui.Offset(sp.xs[0], sp.ys[0]), bands.first.$2.color),
        (ui.Offset(sp.xs[sp.n - 1], sp.ys[sp.n - 1]), bands.last.$2.color),
      ];
      for (final p in frame.paths) {
        canvas
          ..save()
          ..clipPath(p);
        for (final (c, color) in ends) {
          canvas.drawCircle(c, _liveBandRadius * w, ui.Paint()..color = color);
        }
        for (final (path, paint) in bands) {
          canvas.drawPath(path, paint);
        }
        canvas.restore();
      }
      final side = sp.lightSide(w);
      final (g0, g1) = trimmed(length, _glossTrim * w);
      canvas
        ..drawPath(
          tubePolyline(sp, t0: g0, t1: g1, shift: side * _hlShift * w),
          tubePaint(_hlRadius * w, kWhite, _hlAlpha),
        )
        ..drawPath(
          tubePolyline(sp, t0: g0, t1: g1, shift: side * _specShift * w),
          tubePaint(_specRadiusOf(w), kWhite, _specAlpha),
        );
    }
    if (layered) canvas.restore();
  }
}
