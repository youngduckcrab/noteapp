// lib/src/render/pens/texture/spray_pen.dart — INTERNAL (v2.11, C211-01).
//
// OWNED BY THE TEXTURE TRACK. 스프레이 — the lock app's `spray` (airbrush): a
// gaussian mist built from stacked bands of decreasing width (each layer's
// alpha chosen so the stack is peak · exp(−x² / 2σ²) across the stroke; the
// widths follow the pressure because every layer is the stroke's own radius
// scaled, and each layer's edge wanders a little along the stroke so the
// steps read as mist, not as contour rings when zoomed in), plus round droplets with power-law sizes (many small, few
// large) scattered with a wider gaussian, more where the pen pressed and on the
// outside of bends. Droplet positions are hashed from arc-length cells and the
// stroke's createdAt. The mist ends at the K-1 reach (Spine.limit), so it never
// leaves core.Stroke.bounds. On screen (tiles ready) each mist layer is
// dithered with the fine dust channel — alpha a ± 0.8 a, mean a — so the layer
// edges break up into spray speckle instead of contour rings; the PDF (and the
// screen before the tiles) draws the same layers flat at the mean alpha.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../geometry/stroke_outline.dart';
import '../../../model/ink_stroke.dart';
import '../../../tuning.dart';
import '../../stroke_painter.dart';
import '../pen_renderer.dart';
import 'texture_geometry.dart';
import 'texture_pen.dart';
import 'texture_tiles.dart';

const PenRenderer sprayPen = _SprayPen();

/// mist layers: one per ~0.7 pt of reach, within these bounds (each layer is
/// a band to build, record and export — the wandering edges hide the steps)
const int _minSteps = 8;
const int _maxSteps = 16;

int _stepsFor(double reachPt) =>
    (reachPt / 0.7).ceil().clamp(_minSteps, _maxSteps);

/// how far a mist layer's edge wanders along the stroke (fraction of its radius)
const double _wander = 0.07;
const double _peak = 0.85;

/// the mist ends at this many standard deviations
const double _reach = 3.0;

/// droplets spread this many mist deviations
const double _spread = 1.5;

/// droplets: (diameter pt at width 10, alpha)
const List<(double, double)> _sizes = [
  (0.3, 0.85),
  (0.45, 0.75),
  (0.65, 0.65),
  (0.9, 0.6),
  (1.25, 0.55),
];

/// at most this many droplet candidates per stroke
const int _maxCandidates = 4000;

final Map<int, List<(double, double)>> _tables = {};

/// (half width as a fraction of the outermost layer, alpha) from the outside
/// in, [steps] layers: stacked, they make peak · exp(−x² / 2σ²).
List<(double, double)> _mist(int steps) => _tables[steps] ??= () {
  final out = <(double, double)>[];
  const sigma = 1 / _reach;
  var prev = 0.0;
  for (var j = 0; j < steps; j++) {
    final x = 1 - j / steps;
    final xc = x - 0.5 / steps;
    final target = _peak * math.exp(-xc * xc / (2 * sigma * sigma));
    out.add((x, 1 - (1 - target) / (1 - prev)));
    prev = target;
  }
  return out;
}();

/// Thresholds of the power-law size classes: v where the size
/// 0.6 · (1 − 0.985 v)^(−1 / 2.2) passes the midpoint of two neighbours.
final List<double> _classV = [
  for (var k = 0; k + 1 < _sizes.length; k++)
    () {
      final mid = (_sizes[k].$1 + _sizes[k + 1].$1) / 2 / 0.3 * 0.6;
      return (1 - math.pow(mid / 0.6, -2.2)) / 0.985;
    }(),
];

final class _Geom {
  _Geom(this.mist, this.drops, this.reach);

  /// the mist's K-1 reach (pt)
  final double reach;

  /// (outline, alpha), outermost first
  final List<(StrokeOutline, double)> mist;

  /// per size class
  final List<StrokeOutline?> drops;
}

_Geom _geom(InkStroke stroke) => textureGeometry(
  stroke,
  (sp) => _build(stroke, sp),
  (g) =>
      outlinesBytes([for (final (o, _) in g.mist) o]) + outlinesBytes(g.drops),
);

_Geom _build(InkStroke stroke, Spine sp) {
  final maxR = math.max(InkTuning.minRadiusPt, stroke.maxRadius);
  // the outermost layer: radius kMax · r(i), never beyond the K-1 reach
  final kMax = sp.limit / maxR;
  final mist = <(StrokeOutline, double)>[];
  final rl = Float64List(sp.n), rr = Float64List(sp.n);
  // a hairline spray (reach under 1 pt) is one solid band at the reach, not a
  // sub-pixel gaussian that would vanish
  if (sp.limit < 1) {
    for (var i = 0; i < sp.n; i++) {
      rl[i] = math.max(InkTuning.minRadiusPt, kMax * sp.r[i]);
    }
    final o = band(sp, rl, rl);
    return _Geom([if (o != null) (o, _peak)], _droplets(sp, kMax), sp.limit);
  }
  const floor = InkTuning.minRadiusPt;
  var j = 0;
  for (final (x, a) in _mist(_stepsFor(sp.limit))) {
    j++;
    if (a <= 0.002) continue;
    // the outermost layer keeps its edge (it is the K-1 reach)
    final wander = j == 1 ? 0.0 : _wander;
    for (var i = 0; i < sp.n; i++) {
      final k =
          kMax *
          x *
          (1 + wander * wobble(sp.s[i] / sp.width, sp.seed + 13 * j));
      rl[i] = math.min(sp.limit, math.max(floor, k * sp.r[i]));
      rr[i] = rl[i];
    }
    final o = band(sp, rl, rr);
    if (o != null) mist.add((o, a));
  }
  return _Geom(mist, _droplets(sp, kMax), sp.limit);
}

List<StrokeOutline?> _droplets(Spine sp, double kMax) {
  final w = sp.width;
  final k = math.sqrt((w / 10).clamp(0.25, 4.0));
  final polys = [for (final _ in _sizes) <Float32List>[]];
  final salt = sp.seed + 577;
  final bendAt = sp.curvature();
  // candidates: ~0.44 · w per pt of length (the lock app's density)
  var cell = 4 / (0.44 * w);
  if (sp.length / cell > _maxCandidates) cell = sp.length / _maxCandidates;
  final count = sp.isDot
      ? (0.44 * w * w / 4).ceil()
      : (sp.length / cell).ceil();
  for (var q = 0; q < count; q++) {
    final at = sp.isDot ? 0.0 : (q + noise01(salt, 9 * q)) * cell;
    final i = sp.isDot ? 0 : sp.sampleAt(math.min(at, sp.length));
    final hard = sp.p[i];
    if (noise01(salt, 9 * q + 5) > 0.55 + 0.45 * hard) continue;
    final bend = math.min(1.0, bendAt[i].abs() * w * 2);
    // a gaussian across the stroke (sum of four uniforms — arithmetic only)
    var g =
        (noise01(salt, 9 * q + 1) +
            noise01(salt, 9 * q + 2) +
            noise01(salt, 9 * q + 6) +
            noise01(salt, 9 * q + 7) -
            2) *
        math.sqrt(3);
    final outer = bendAt[i] > 0 ? -1.0 : 1.0;
    if (g * outer < 0 && noise01(salt, 9 * q + 8) < 0.6 * bend) g = -g;
    final here = sp.locate(math.min(at, sp.length));
    final sigma = kMax * Spine.lerp(sp.r, here.i, here.t) / _reach;
    final d0 = g * sigma * _spread * (1 + (g * outer > 0 ? 0.35 * bend : 0));
    // the center is the mist's
    if (d0.abs() < sigma * _spread * 0.55) continue;
    final v = noise01(salt, 9 * q + 3);
    var cls = 0;
    for (final t in _classV) {
      if (v > t) cls++;
    }
    final dr = _sizes[cls].$1 * k / 2;
    // beyond the K-1 reach: dropped (clamping would line them up at the edge)
    if (d0.abs() > sp.limit - dr) continue;
    final d = d0;
    if (sp.isDot) {
      final a = 2 * math.pi * noise01(salt, 9 * q + 4);
      polys[cls].add(
        circlePolygon(
          sp.x[0] + d * math.cos(a),
          sp.y[0] + d * math.sin(a),
          dr,
          segments: 8,
        ),
      );
    } else {
      polys[cls].add(
        circlePolygon(
          here.x + here.nx * d,
          here.y + here.ny * d,
          dr,
          segments: 8,
        ),
      );
    }
  }
  return [
    for (final list in polys)
      list.isEmpty
          ? null
          : StrokeOutline(polygons: list, bounds: _boundsOf(list)),
  ];
}

Rect _boundsOf(List<Float32List> polys) {
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
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

final class _SprayPen extends TexturePen {
  const _SprayPen();

  @override
  bool get layered => false;

  @override
  void paintTextured(
    Canvas canvas,
    InkStroke stroke,
    StrokeOutline outline,
    int argb,
    TextureTiles tiles,
  ) {
    final g = _geom(stroke);
    // hairline mist (under ~1 pt) stays flat: dithering a sub-pixel layer
    // would leave it empty
    final dither = g.reach >= 1;
    for (final (o, a) in g.mist) {
      canvas.drawPath(
        o.toPath(),
        dither
            ? aroundPaint(tiles.wash, argb, TileChannel.dust, a, 1.6 * a)
            : solidPaint(argb, a),
      );
    }
    for (var c = 0; c < _sizes.length; c++) {
      final d = g.drops[c];
      if (d != null) {
        canvas.drawPath(d.toPath(), solidPaint(argb, _sizes[c].$2));
      }
    }
  }

  @override
  List<FlatLayer> flatLayers(
    InkStroke stroke,
    StrokeOutline outline,
    int argb,
  ) {
    final g = _geom(stroke);
    return [
      for (final (o, a) in g.mist) (outline: o, alpha: a, argb: null),
      for (var c = 0; c < _sizes.length; c++)
        if (g.drops[c] != null)
          (outline: g.drops[c]!, alpha: _sizes[c].$2, argb: null),
    ];
  }

  @override
  void paintLive(Canvas canvas, PenLiveFrame frame) {
    // the mist on the live centerline (nominal width: the live frame carries no
    // pressure); the droplets appear with the committed stroke
    if (frame.opacity <= 0 || frame.centerline.isEmpty) return;
    final w = frame.style.width;
    final reach = 0.75 * w;
    canvas.saveLayer(
      frame.bounds.inflate(reach),
      Paint()..color = inkColor(0, frame.opacity),
    );
    final path = Path();
    final pts = frame.centerline;
    path.moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    if (pts.length == 1) path.lineTo(pts.first.dx + 0.01, pts.first.dy);
    final steps = _stepsFor(reach);
    for (final (x, a) in _mist(steps)) {
      if (a <= 0.002) continue;
      canvas.drawPath(
        path,
        Paint()
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 2 * reach * x
          ..color = inkColor(frame.style.colorArgb, a),
      );
    }
    canvas.restore();
  }
}
