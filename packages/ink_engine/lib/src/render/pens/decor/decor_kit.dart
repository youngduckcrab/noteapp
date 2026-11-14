// lib/src/render/pens/decor/decor_kit.dart — INTERNAL (v2.11, C211-01) shared
// parts of the decoration pens (neon, jelly, rainbow, glitter).
//
// OWNED BY THE DECOR TRACK. A decoration pen is a short list of layers
// (DecorLayer: one nonzero shape, one opaque color, one alpha) painted in
// order. The same list is the screen (paintCommitted: chunk pictures,
// thumbnails, previews) and the PDF (vectorPieces: one piece per layer), so
// both show the same picture; the live stroke redraws the same layers from
// the live centerline (strokes of the polyline instead of outlines — the
// shapes agree, see each pen).
//
// K-1 (C211-01): core.Stroke.bounds = point bounds inflated by
// width · max(2 · maxWidthQ, 0.75). Every layer stays within [reachOf] of the
// centerline. Note the factor: widthQ = f / 4, so the reach is the outline
// radius at the widest point (f / 2 · width) but never below 0.75 · width —
// for a pen of constant factor 1 (outline radius 0.5 · width) a glow may
// reach 1.5× the outline radius. Neon and glitter therefore draw their
// visible tube thinner than the outline (the outline stays the hit area).
//
// Arithmetic only (7.4.3): colors are split with ~/ and %, never bit ops.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../geometry/outline_generator.dart';
import '../../../geometry/stroke_outline.dart';
import '../../../geometry/vector_path.dart';
import '../../../model/ink_points.dart';
import '../../../model/ink_stroke.dart';
import '../../../pen/pen_profile.dart';
import '../../stroke_painter.dart';
import '../pen_renderer.dart';

// --- colors ------------------------------------------------------------------

const int kWhite = 0xFFFFFFFF;
const int kBlack = 0xFF000000;

int _r(int c) => c ~/ 0x10000 % 256;
int _g(int c) => c ~/ 0x100 % 256;
int _b(int c) => c % 256;

int _rgb(double r, double g, double b) =>
    0xFF000000 +
    r.round().clamp(0, 255) * 0x10000 +
    g.round().clamp(0, 255) * 0x100 +
    b.round().clamp(0, 255);

/// a + (b − a) · t per channel, opaque.
int mixArgb(int a, int b, double t) => _rgb(
  _r(a) + (_r(b) - _r(a)) * t,
  _g(a) + (_g(b) - _g(a)) * t,
  _b(a) + (_b(b) - _b(a)) * t,
);

int lighten(int c, double k) => mixArgb(c, kWhite, k);
int darken(int c, double k) => mixArgb(c, kBlack, k);

/// Relative luminance 0..1 (Rec. 709 weights, like the lock app).
double luma(int c) => (0.2126 * _r(c) + 0.7152 * _g(c) + 0.0722 * _b(c)) / 255;

/// HSV of [c]: hue in degrees [0, 360), saturation and value in [0, 1].
(double, double, double) hsvOf(int c) {
  final r = _r(c) / 255, g = _g(c) / 255, b = _b(c) / 255;
  final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
  final d = mx - mn;
  var h = 0.0;
  if (d > 1e-9) {
    if (mx == r) {
      h = 60 * (((g - b) / d) % 6);
    } else if (mx == g) {
      h = 60 * ((b - r) / d + 2);
    } else {
      h = 60 * ((r - g) / d + 4);
    }
  }
  if (h < 0) h += 360;
  return (h, mx <= 0 ? 0 : d / mx, mx);
}

int hsvArgb(double h, double s, double v) {
  final hh = (h % 360 + 360) % 360 / 60;
  final c = v * s;
  final x = c * (1 - (hh % 2 - 1).abs());
  final m = v - c;
  final (r, g, b) = switch (hh.floor()) {
    0 => (c, x, 0.0),
    1 => (x, c, 0.0),
    2 => (0.0, c, x),
    3 => (0.0, x, c),
    4 => (x, 0.0, c),
    _ => (c, 0.0, x),
  };
  return _rgb((r + m) * 255, (g + m) * 255, (b + m) * 255);
}

/// The hue of [c] turned by [degrees].
int hueShift(int c, double degrees) {
  final (h, s, v) = hsvOf(c);
  return hsvArgb(h + degrees, s, v);
}

/// 0..1: how much a light ink needs a dark rim to show on light paper (lock
/// app `lightInk`: smoothstep(0.62, 0.9, luma)).
double lightInk(int c) => smoothstep01(0.62, 0.9, luma(c));

double smoothstep01(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// The rim color of light inks (lock app RIM).
const int kRimArgb = 0xFF8C8698;

// --- reach (K-1) ---------------------------------------------------------------

/// The K-1 reach of [stroke]: no painted point may be farther than this from
/// the centerline (core.Stroke.bounds = point bounds inflated by it). A hair
/// less than the exact value so float rounding never crosses the bound.
double reachOf(InkStroke stroke) =>
    stroke.style.width *
    math.max(2 * stroke.source.points.maxWidthQ, 0.75) *
    0.995;

/// The reach every stroke of width [w] has at least (factor ≤ 1.5): 0.75 · w.
double minReach(double w) => 0.75 * w * 0.995;

// --- centerline ----------------------------------------------------------------

/// A centerline: positions, widthQ, cumulative arc length and unit normals
/// (n = (−τy, τx), τ = mean of the adjacent segment directions).
/// Consecutive points closer than 1e-6 pt are one point.
final class DecorSpine {
  DecorSpine._(this.xs, this.ys, this.qs, this.s, this.nx, this.ny);

  factory DecorSpine.of(InkPoints p) {
    final n = p.length;
    final xs = <double>[], ys = <double>[], qs = <double>[];
    for (var i = 0; i < n; i++) {
      final x = p.x(i), y = p.y(i), q = p.widthQ(i);
      if (!x.isFinite || !y.isFinite) continue;
      if (xs.isNotEmpty) {
        final dx = x - xs.last, dy = y - ys.last;
        if (dx * dx + dy * dy <= 1e-12) {
          if (q > qs.last) qs[qs.length - 1] = q;
          continue;
        }
      }
      xs.add(x);
      ys.add(y);
      qs.add(q.isFinite ? q : 0.25);
    }
    return _build(xs, ys, qs);
  }

  /// The live centerline (no widthQ: every point gets [q]).
  factory DecorSpine.offsets(List<ui.Offset> c, double q) {
    final xs = <double>[], ys = <double>[], qs = <double>[];
    for (final o in c) {
      if (!o.dx.isFinite || !o.dy.isFinite) continue;
      if (xs.isNotEmpty) {
        final dx = o.dx - xs.last, dy = o.dy - ys.last;
        if (dx * dx + dy * dy <= 1e-12) continue;
      }
      xs.add(o.dx);
      ys.add(o.dy);
      qs.add(q);
    }
    return _build(xs, ys, qs);
  }

  static DecorSpine _build(List<double> x, List<double> y, List<double> q) {
    final n = x.length;
    final xs = Float64List.fromList(x), ys = Float64List.fromList(y);
    final qs = Float64List.fromList(q);
    final s = Float64List(n);
    final dx = Float64List(math.max(0, n - 1)), dy = Float64List(dx.length);
    for (var i = 0; i + 1 < n; i++) {
      final ex = xs[i + 1] - xs[i], ey = ys[i + 1] - ys[i];
      final d = math.sqrt(ex * ex + ey * ey);
      s[i + 1] = s[i] + d;
      dx[i] = ex / d;
      dy[i] = ey / d;
    }
    final nx = Float64List(n), ny = Float64List(n);
    for (var i = 0; i < n; i++) {
      double tx, ty;
      if (n == 1) {
        tx = 1;
        ty = 0;
      } else if (i == 0) {
        tx = dx[0];
        ty = dy[0];
      } else if (i == n - 1) {
        tx = dx[i - 1];
        ty = dy[i - 1];
      } else {
        tx = dx[i - 1] + dx[i];
        ty = dy[i - 1] + dy[i];
        final l = math.sqrt(tx * tx + ty * ty);
        if (l > 1e-9) {
          tx /= l;
          ty /= l;
        } else {
          tx = dx[i];
          ty = dy[i];
        }
      }
      nx[i] = -ty;
      ny[i] = tx;
    }
    return DecorSpine._(xs, ys, qs, s, nx, ny);
  }

  final Float64List xs, ys, qs, s, nx, ny;

  int get n => xs.length;
  bool get isEmpty => xs.isEmpty;
  double get length => xs.isEmpty ? 0 : s[n - 1];

  /// True for a dot (one point, or shorter than 1e-3 pt — OutlineGenerator O1).
  bool get isDot => n <= 1 || length < 1e-3;

  /// The largest i ≤ n − 2 with s[i] ≤ t (n ≥ 2).
  int segmentAt(double t) {
    var lo = 0, hi = n - 2;
    if (t >= s[hi]) return hi;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (s[mid] <= t) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Writes x, y, nx, ny, q at arc length [t] (clamped) into [out] at [o].
  void sampleInto(double t, Float64List out, int o) {
    if (n == 1) {
      out
        ..[o] = xs[0]
        ..[o + 1] = ys[0]
        ..[o + 2] = nx[0]
        ..[o + 3] = ny[0]
        ..[o + 4] = qs[0];
      return;
    }
    final tt = t.clamp(0.0, length);
    final i = segmentAt(tt);
    final seg = s[i + 1] - s[i];
    final f = seg > 0 ? (tt - s[i]) / seg : 0.0;
    var mx = nx[i] + (nx[i + 1] - nx[i]) * f;
    var my = ny[i] + (ny[i + 1] - ny[i]) * f;
    final l = math.sqrt(mx * mx + my * my);
    if (l > 1e-9) {
      mx /= l;
      my /= l;
    } else {
      mx = nx[i];
      my = ny[i];
    }
    out
      ..[o] = xs[i] + (xs[i + 1] - xs[i]) * f
      ..[o + 1] = ys[i] + (ys[i + 1] - ys[i]) * f
      ..[o + 2] = mx
      ..[o + 3] = my
      ..[o + 4] = qs[i] + (qs[i + 1] - qs[i]) * f;
  }

  /// The part [t0, t1] as rows of 5 (x, y, nx, ny, q): the interpolated ends and
  /// every point strictly between them.
  Float64List range(double t0, double t1) {
    if (n == 1 || t1 <= t0) {
      final out = Float64List(5);
      sampleInto(t0, out, 0);
      return out;
    }
    final a = segmentAt(t0), b = segmentAt(t1);
    final inner = <int>[
      for (var i = a + 1; i <= b; i++)
        if (s[i] > t0 + 1e-9 && s[i] < t1 - 1e-9) i,
    ];
    final out = Float64List(5 * (inner.length + 2));
    sampleInto(t0, out, 0);
    var o = 5;
    for (final i in inner) {
      out
        ..[o] = xs[i]
        ..[o + 1] = ys[i]
        ..[o + 2] = nx[i]
        ..[o + 3] = ny[i]
        ..[o + 4] = qs[i];
      o += 5;
    }
    sampleInto(t1, out, o);
    return out;
  }

  /// +1 or −1: the side of the stroke that faces the light (up, a little to
  /// the left on the screen), chosen once from the stroke's first 2 · [w] of
  /// length so the live stroke settles on the same side as the stored one.
  double lightSide(double w) {
    if (n < 2) return 1;
    var k = n - 1;
    for (var i = 1; i < n; i++) {
      if (s[i] >= 2 * w) {
        k = i;
        break;
      }
    }
    final dx = xs[k] - xs[0], dy = ys[k] - ys[0];
    // n = (−dy, dx) · (−0.45, −0.89)
    return (dy * 0.45 - dx * 0.89) >= 0 ? 1 : -1;
  }
}

// --- tubes ---------------------------------------------------------------------

const OutlineSpec _roundSpec = OutlineSpec(
  method: InkRenderMethod.filledOutline,
  cap: InkCap.round,
);

/// The outline of the centerline part [t0, t1] (whole line when null) shifted
/// by [shift] along the normal, radius [radius](q) at every point (round caps,
/// OutlineGenerator O1–O8).
StrokeOutline tubeOutline(
  DecorSpine sp,
  double width, {
  required double Function(double q) radius,
  double t0 = 0,
  double? t1,
  double shift = 0,
}) {
  if (sp.isEmpty) {
    return StrokeOutline(polygons: const [], bounds: ui.Rect.zero);
  }
  final rows = sp.range(t0, t1 ?? sp.length);
  final m = rows.length ~/ 5;
  const stride = InkPoints.stride;
  final raw = Float32List(m * stride);
  for (var k = 0; k < m; k++) {
    final o = 5 * k;
    raw[k * stride] = rows[o] + rows[o + 2] * shift;
    raw[k * stride + 1] = rows[o + 1] + rows[o + 3] * shift;
    raw[k * stride + 2] = radius(rows[o + 4]) / (2 * width);
  }
  return OutlineGenerator.outlineFor(
    InkPoints.fromRaw(raw),
    width: width,
    spec: _roundSpec,
  );
}

/// The same part as a polyline path (the live stroke draws it with a round
/// stroke of width 2 · radius — the shape of [tubeOutline] of a constant radius).
ui.Path tubePolyline(
  DecorSpine sp, {
  double t0 = 0,
  double? t1,
  double shift = 0,
}) {
  final path = ui.Path();
  if (sp.isEmpty) return path;
  final rows = sp.range(t0, t1 ?? sp.length);
  final m = rows.length ~/ 5;
  path.moveTo(rows[0] + rows[2] * shift, rows[1] + rows[3] * shift);
  if (m == 1) {
    // a zero-length line still gets its round caps
    path.lineTo(rows[0] + rows[2] * shift, rows[1] + rows[3] * shift);
  }
  for (var k = 1; k < m; k++) {
    final o = 5 * k;
    path.lineTo(
      rows[o] + rows[o + 2] * shift,
      rows[o + 1] + rows[o + 3] * shift,
    );
  }
  return path;
}

/// Round-capped, round-joined stroke paint of [radius] (live tubes).
ui.Paint tubePaint(double radius, int argb, double alpha) => ui.Paint()
  ..isAntiAlias = true
  ..style = ui.PaintingStyle.stroke
  ..strokeWidth = 2 * radius
  ..strokeCap = ui.StrokeCap.round
  ..strokeJoin = ui.StrokeJoin.round
  ..color = inkColor(argb, alpha);

ui.Paint fillPaint(int argb, double alpha) => ui.Paint()
  ..isAntiAlias = true
  ..style = ui.PaintingStyle.fill
  ..color = inkColor(argb, alpha);

/// A trimmed gloss range: [a, L − a], or the middle third of a short line.
(double, double) trimmed(double length, double a) {
  if (length > 2 * a + 1e-3) return (a, length - a);
  return (length / 3, length * 2 / 3);
}

// --- vector shapes ---------------------------------------------------------------

/// Builds an InkVectorPath (moveTo / lineTo / cubicTo / close; page pt, y down).
/// Circles and stars turn the same way (angle increasing — clockwise on the
/// screen), so overlapping ones in one path add up under nonzero.
final class VecBuilder {
  final List<int> _verbs = [];
  final List<double> _coords = [];
  double _x = 0, _y = 0;

  bool get isEmpty => _verbs.isEmpty;

  void moveTo(double x, double y) {
    _verbs.add(InkPathVerb.moveTo.index);
    _coords
      ..add(x)
      ..add(y);
    _x = x;
    _y = y;
  }

  void lineTo(double x, double y) {
    _verbs.add(InkPathVerb.lineTo.index);
    _coords
      ..add(x)
      ..add(y);
    _x = x;
    _y = y;
  }

  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) {
    _verbs.add(InkPathVerb.cubicTo.index);
    _coords.addAll([x1, y1, x2, y2, x3, y3]);
    _x = x3;
    _y = y3;
  }

  /// A quadratic as the equal cubic.
  void quadTo(double cx, double cy, double x, double y) => cubicTo(
    _x + 2 / 3 * (cx - _x),
    _y + 2 / 3 * (cy - _y),
    x + 2 / 3 * (cx - x),
    y + 2 / 3 * (cy - y),
    x,
    y,
  );

  void close() => _verbs.add(InkPathVerb.close.index);

  /// A circle (4 cubics, k = 0.5523).
  void circle(double cx, double cy, double r) {
    if (!(r > 0)) return;
    final k = 0.5523 * r;
    moveTo(cx + r, cy);
    cubicTo(cx + r, cy + k, cx + k, cy + r, cx, cy + r);
    cubicTo(cx - k, cy + r, cx - r, cy + k, cx - r, cy);
    cubicTo(cx - r, cy - k, cx - k, cy - r, cx, cy - r);
    cubicTo(cx + k, cy - r, cx + r, cy - k, cx + r, cy);
    close();
  }

  /// The lock app's four-armed sparkle (`sparkle`): a cross with a thin waist
  /// and a smaller diagonal cross on top. Arm tips at [size] (the diagonal at
  /// 0.48 · size); [slim]: both control points at the waist (thin arms).
  void sparkle(
    double x,
    double y,
    double size,
    double degrees,
    double waist, {
    bool slim = false,
  }) {
    if (!(size > 0)) return;
    final rad = degrees * math.pi / 180;
    final cs = math.cos(rad), sn = math.sin(rad);
    for (var layer = 0; layer < 2; layer++) {
      final len = layer == 0 ? size : size * 0.48;
      final w = layer == 0 ? size * waist : size * waist * 0.6;
      final a0 = layer == 0 ? 0.0 : math.pi / 4;
      double px(double ax, double ay) => x + ax * cs - ay * sn;
      double py(double ax, double ay) => y + ax * sn + ay * cs;
      final sx = math.cos(a0) * len, sy = math.sin(a0) * len;
      moveTo(px(sx, sy), py(sx, sy));
      for (var k = 0; k < 4; k++) {
        final b = a0 + k * math.pi / 2 + math.pi / 4;
        final wx = math.cos(b) * w, wy = math.sin(b) * w;
        final a = a0 + (k + 1) % 4 * math.pi / 2;
        final ex = math.cos(a) * len, ey = math.sin(a) * len;
        final cx = px(wx, wy), cy = py(wx, wy);
        if (slim) {
          cubicTo(cx, cy, cx, cy, px(ex, ey), py(ex, ey));
        } else {
          quadTo(cx, cy, px(ex, ey), py(ex, ey));
        }
      }
      close();
    }
  }

  InkVectorPath build() =>
      InkVectorPath(Uint8List.fromList(_verbs), Float32List.fromList(_coords));
}

/// One fill shape of a layer: an outline (screen = its smooth path, PDF = its
/// vector path) or a ready vector path (screen = the same path).
final class DecorShape {
  DecorShape.outline(StrokeOutline this._outline) : _vector = null;
  DecorShape.vector(InkVectorPath this._vector) : _outline = null;

  final StrokeOutline? _outline;
  final InkVectorPath? _vector;
  ui.Path? _path;

  bool get isEmpty {
    final o = _outline;
    if (o != null) return o.polygons.isEmpty && !o.isDot && o.dots.isEmpty;
    return _vector!.verbs.isEmpty;
  }

  ui.Path get path {
    final o = _outline;
    if (o != null) return o.toPath();
    return _path ??= _vector!.toUiPath();
  }

  InkVectorPath vectorPath({required bool smooth}) =>
      _outline?.toVectorPath(smooth: smooth) ?? _vector!;
}

/// One layer: [shape] filled with [argb] (opaque) at [alpha] × the stroke opacity.
typedef DecorLayer = ({DecorShape shape, int argb, double alpha});

/// A decoration pen: its committed picture and its PDF pieces are the same
/// [layers], in order.
abstract base class DecorPen extends PenRenderer {
  const DecorPen();

  /// The layers of [stroke] drawn in [colorArgb] (the recolor preview passes
  /// another color than the style's).
  List<DecorLayer> layers(InkStroke stroke, int colorArgb);

  @override
  void paintCommitted(
    ui.Canvas canvas,
    InkStroke stroke,
    StrokeOutline outline, {
    required int colorArgb,
    required double opacity,
    ui.Image? grain,
  }) {
    for (final l in layers(stroke, colorArgb)) {
      if (l.alpha <= 0 || l.shape.isEmpty) continue;
      canvas.drawPath(l.shape.path, fillPaint(l.argb, l.alpha * opacity));
    }
  }

  @override
  List<PenVectorPiece> vectorPieces(
    InkStroke stroke,
    StrokeOutline outline, {
    required double opacity,
    required bool smooth,
  }) => [
    for (final l in layers(stroke, stroke.style.colorArgb))
      if (l.alpha > 0 && !l.shape.isEmpty)
        (
          path: l.shape.vectorPath(smooth: smooth),
          colorArgb: opaqueArgb(l.argb),
          opacity: (l.alpha * opacity).clamp(0.0, 1.0).toDouble(),
        ),
  ];
}
