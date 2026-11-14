// lib/src/render/pens/texture/texture_geometry.dart — INTERNAL (v2.11, C211-01)
// shared geometry of the texture pens. OWNED BY THE TEXTURE TRACK.
//
// Ported from the lock-screen app (TextureBrushes.kt "선의 뼈대" / ragged /
// coverageRadii / levelShape / offsetBand), adapted to the note app:
//   * the spine is the stored centerline resampled by arc length (spacing a
//     fraction of the width), each sample with its outline radius
//     r = max(minRadiusPt, 2 · width · widthQ) — pressure and taper are already
//     in widthQ — and a pressure value p ∈ [0, 1] from the profile's factor
//     range (the lock app used the hand speed for that);
//   * a band with left / right radii (rl, rr) is built by the stroke outline
//     generator itself: the centerline shifted by (rl − rr) / 2 along the normal
//     with radius (rl + rr) / 2 — so corners, caps and the PDF path come from
//     the same code as every other pen (one nonzero StrokeOutline per band);
//   * K-1: every radius is clamped to Spine.limit = the reach of
//     core.Stroke.bounds (width · max(2 · maxWidthQ, 0.75)) minus a margin, and
//     every vertex is within its radius of a spine point (a point on the stored
//     polyline), so every band lies inside the stroke bounds;
//   * randomness: noise01 / wobble hash integers with MINSTD squaring rounds —
//     arithmetic only, the same on the VM and the web; seeds come from the
//     stroke's createdAt and arc lengths (never time).
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../geometry/outline_generator.dart';
import '../../../geometry/stroke_outline.dart';
import '../../../model/ink_points.dart';
import '../../../model/ink_stroke.dart';
import '../../../pen/pen_profile.dart';
import '../../../tuning.dart';

const int _m = 2147483647; // 2^31 - 1

/// a · b mod (2³¹ − 1) for 0 ≤ a, b < 2³¹, exact in doubles (b split in 16 bits).
int _mulMod(int a, int b) {
  final b1 = b ~/ 65536, b0 = b - b1 * 65536;
  return ((a * b1) % _m * 65536 + a * b0) % _m;
}

int _mix(int v) {
  var x = (v % _m + _m) % _m;
  x = (x * 48271 + 11) % _m;
  x = _mulMod(x + 1, x + 7);
  x = (x * 48271) % _m;
  x = _mulMod(x + 3, x + 5);
  return (x * 48271) % _m;
}

/// Two tables of uniform values (MINSTD streams) with coprime sizes: a noise
/// value is the fractional sum of one entry of each — cheap enough to call per
/// spine sample many times over (the hash [_mix] runs once per stroke).
const int _t1Size = 4096, _t2Size = 4093;
final Float64List _t1 = _table(_t1Size, 7331);
final Float64List _t2 = _table(_t2Size, 90217);

Float64List _table(int size, int seed) {
  final out = Float64List(size);
  var s = seed;
  for (var i = 0; i < 16; i++) {
    s = (s * 48271) % _m;
  }
  for (var i = 0; i < size; i++) {
    s = (s * 48271) % _m;
    out[i] = s / _m;
  }
  return out;
}

/// A hash of ([salt], [k]) in [0, 1). Deterministic, platform independent
/// (integer arithmetic below 2⁵³ and one double addition).
double noise01(int salt, int k) {
  final v =
      _t1[(salt + k) % _t1Size] + _t2[(salt ~/ _t1Size + 3 * k) % _t2Size];
  return v >= 1 ? v - 1 : v;
}

/// The lock app's 1-D value noise: smooth in [0, 1].
double valueNoise(double x, int salt) {
  final i = x.floor();
  var t = x - i;
  t = t * t * (3 - 2 * t);
  final a = noise01(salt, i), b = noise01(salt, i + 1);
  return a + (b - a) * t;
}

/// Smooth noise in [−1, 1] (two octaves), the lock app's `wobble`.
double wobble(double x, int salt) =>
    (valueNoise(x, salt) * 0.65 + valueNoise(x * 2.7, salt + 5003) * 0.35) * 2 -
    1;

double smoothstep(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// A seed in [0, 2³¹ − 1) from a stroke's createdAt (ms).
int strokeSalt(int createdAt) => _mix(createdAt % _m);

/// Relative luminance-ish (0 black … 1 white) of [argb]'s RGB.
double luma(int argb) {
  final r = (argb ~/ 0x10000) % 256, g = (argb ~/ 0x100) % 256, b = argb % 256;
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255;
}

/// [a] mixed toward [b] by [t] (RGB, alpha 0xFF).
int mixArgb(int a, int b, double t) {
  int ch(int v, int d) => (v ~/ d) % 256;
  int lerp(int x, int y) => (x + (y - x) * t).round().clamp(0, 255);
  return 0xFF000000 +
      lerp(ch(a, 0x10000), ch(b, 0x10000)) * 0x10000 +
      lerp(ch(a, 0x100), ch(b, 0x100)) * 0x100 +
      lerp(a % 256, b % 256);
}

/// The texture pens' geometry cache: one entry per stroke (identity), least
/// recently used out first once the entries pass
/// InkTuning.textureGeometryBudgetBytes — the shapes of a page that is open
/// stay, a long session does not pile them up (the chunk pictures keep what is
/// on screen).
abstract final class TextureGeometryCache {
  static final LinkedHashMap<InkStroke, (Object, int)> _entries =
      LinkedHashMap<InkStroke, (Object, int)>.identity();
  static int _bytes = 0;

  /// Bytes held now.
  static int get bytes => _bytes;

  /// Entries held now.
  static int get length => _entries.length;

  /// Drops everything (tests).
  static void clear() {
    _entries.clear();
    _bytes = 0;
  }

  static T _of<T extends Object>(
    InkStroke stroke,
    T Function(Spine sp) build,
    int Function(T g) bytesOf,
    double spacing,
  ) {
    final hit = _entries.remove(stroke);
    if (hit != null && hit.$1 is T) {
      _entries[stroke] = hit; // most recently used
      return hit.$1 as T;
    }
    if (hit != null) _bytes -= hit.$2;
    final g = build(Spine.of(stroke, spacing: spacing));
    final size = 64 + bytesOf(g);
    _entries[stroke] = (g, size);
    _bytes += size;
    while (_bytes > InkTuning.textureGeometryBudgetBytes &&
        _entries.length > 1) {
      final first = _entries.keys.first;
      _bytes -= _entries.remove(first)!.$2;
    }
    return g;
  }
}

/// The geometry of [stroke] for one pen: [build] runs on a cache miss (with a
/// fresh spine, samples [spacing] × the usual spacing apart), [bytesOf] tells
/// the cache what the result holds.
T textureGeometry<T extends Object>(
  InkStroke stroke,
  T Function(Spine sp) build,
  int Function(T g) bytesOf, {
  double spacing = 1,
}) => TextureGeometryCache._of(stroke, build, bytesOf, spacing);

/// Bytes of an optional outline.
int outlineBytes(StrokeOutline? o) => o == null ? 0 : o.approximateBytes;

/// Bytes of outlines.
int outlinesBytes(Iterable<StrokeOutline?> list) {
  var n = 0;
  for (final o in list) {
    n += outlineBytes(o);
  }
  return n;
}

/// Bytes of polygons.
int polygonsBytes(Iterable<Float32List> list) {
  var n = 0;
  for (final p in list) {
    n += 32 + p.lengthInBytes;
  }
  return n;
}

/// The resampled centerline of a committed stroke. Not cached itself: a pen
/// builds it once per stroke inside [textureGeometry] and keeps only the
/// shapes it needs.
final class Spine {
  Spine._({
    required this.n,
    required this.x,
    required this.y,
    required this.s,
    required this.nx,
    required this.ny,
    required this.r,
    required this.p,
    required this.length,
    required this.width,
    required this.limit,
    required this.seed,
  });

  /// The spine of [stroke] (built on every call — see [textureGeometry]),
  /// samples [spacing] × [spacingFor] apart.
  factory Spine.of(InkStroke stroke, {double spacing = 1}) =>
      Spine._build(stroke, spacing);

  final int n;
  final Float64List x, y, s, nx, ny;

  /// outline radius at the sample (pt)
  final Float64List r;

  /// pressure 0 (light) … 1 (hard), from the profile's factor range
  final Float64List p;

  /// centerline length (pt)
  final double length;

  /// style.width (pt)
  final double width;

  /// K-1 reach: no painted point farther than this from a spine sample
  final double limit;

  /// strokeSalt(createdAt)
  final int seed;

  bool get isDot => n == 1;

  /// Spacing of the samples (pt): about 0.4 width, never finer than 0.6 pt
  /// (thin strokes do not get several samples per input point).
  static double spacingFor(double width) => (0.4 * width).clamp(0.6, 2.5);

  /// At most this many samples per stroke (longer strokes get a wider spacing).
  static const int maxSamples = 1200;

  /// The sample count for [m] input points over [total] pt: the spacing above,
  /// but at most two samples per input point unless that leaves less than one
  /// sample per width (sparse fast strokes keep their ragged edges).
  static int samplesFor(
    int m,
    double total,
    double width, {
    double spacing = 1,
  }) {
    var n = (total / (spacing * spacingFor(width))).ceil() + 1;
    final cap = math.max(2 * m + 2, (total / math.max(width, 0.6)).ceil() + 2);
    if (n > cap) n = cap;
    return math.min(n, maxSamples);
  }

  static Spine _build(InkStroke stroke, double spacing) {
    final pts = stroke.points;
    final w = stroke.style.width;
    final profile = stroke.profile;
    final limit = math.max(
      InkTuning.minRadiusPt,
      w * math.max(2 * stroke.source.points.maxWidthQ, 0.75) - 0.02,
    );
    final seed = strokeSalt(stroke.source.createdAt);
    final m = pts.length;
    final cum = m > 0 ? pts.cumulativeLengths() : Float64List(1);
    final total = m > 0 ? cum[m - 1] : 0.0;
    double radius(double wq) =>
        math.min(limit, math.max(InkTuning.minRadiusPt, 2 * w * wq));
    double pressure(double wq) => _pressure(profile, wq);
    if (m <= 1 || total < 1e-3) {
      final wq = m == 0 ? 0.25 : pts.widthQ(0);
      return Spine._(
        n: 1,
        x: Float64List.fromList([m == 0 ? 0 : pts.x(0)]),
        y: Float64List.fromList([m == 0 ? 0 : pts.y(0)]),
        s: Float64List(1),
        nx: Float64List.fromList([0]),
        ny: Float64List.fromList([-1]),
        r: Float64List.fromList([radius(wq)]),
        p: Float64List.fromList([pressure(wq)]),
        length: 0,
        width: w,
        limit: limit,
        seed: seed,
      );
    }
    final n = samplesFor(m, total, w, spacing: spacing);
    final h = total / (n - 1);
    final x = Float64List(n), y = Float64List(n), s = Float64List(n);
    final r = Float64List(n), p = Float64List(n);
    var k = 0;
    for (var j = 0; j < n; j++) {
      final sj = j == n - 1 ? total : j * h;
      while (k < m - 2 && cum[k + 1] < sj) {
        k++;
      }
      final seg = cum[k + 1] - cum[k];
      final t = seg > 1e-9 ? ((sj - cum[k]) / seg).clamp(0.0, 1.0) : 0.0;
      x[j] = pts.x(k) + (pts.x(k + 1) - pts.x(k)) * t;
      y[j] = pts.y(k) + (pts.y(k + 1) - pts.y(k)) * t;
      final wq = pts.widthQ(k) + (pts.widthQ(k + 1) - pts.widthQ(k)) * t;
      s[j] = sj;
      r[j] = radius(wq);
      p[j] = pressure(wq);
    }
    final nx = Float64List(n), ny = Float64List(n);
    for (var j = 0; j < n; j++) {
      final a = j == 0 ? 0 : j - 1, b = j == n - 1 ? n - 1 : j + 1;
      var dx = x[b] - x[a], dy = y[b] - y[a];
      final d = math.sqrt(dx * dx + dy * dy);
      if (d > 1e-9) {
        dx /= d;
        dy /= d;
      } else {
        dx = 1;
        dy = 0;
      }
      // left normal in y-down coordinates
      nx[j] = dy;
      ny[j] = -dx;
    }
    return Spine._(
      n: n,
      x: x,
      y: y,
      s: s,
      nx: nx,
      ny: ny,
      r: r,
      p: p,
      length: total,
      width: w,
      limit: limit,
      seed: seed,
    );
  }

  static double _pressure(PenProfile profile, double wq) {
    final f = 4 * wq;
    final span = profile.maxFactor - profile.minFactor;
    if (span <= 1e-6) return 0.5;
    return ((f - profile.minFactor) / span).clamp(0.0, 1.0);
  }

  /// Unit tangent (dx, dy) of sample [i] (from the normal).
  double dx(int i) => -ny[i];
  double dy(int i) => nx[i];

  /// Signed curvature (1/pt), positive when bending toward the normal side.
  Float64List curvature() {
    final out = Float64List(n);
    for (var i = 0; i < n; i++) {
      final a = math.max(0, i - 2), b = math.min(n - 1, i + 2);
      final ds = s[b] - s[a];
      if (ds > 1e-3) {
        out[i] = (dx(a) * dy(b) - dy(a) * dx(b)) / ds;
      }
    }
    return out;
  }

  /// The first sample whose arc length is ≥ [at].
  int sampleAt(double at) {
    var lo = 0, hi = n - 1;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (s[mid] < at) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// The spine between samples at arc length [at] (clamped to the stroke):
  /// the position on the chord of the two samples around it (inside the convex
  /// hull of the stored points, so K-1 reasoning holds), the normal of the
  /// nearer sample, and [values] interpolated — so specks and droplets do not
  /// line up on the samples of a sparse, wide stroke.
  ({double x, double y, double nx, double ny, int i, double t}) locate(
    double at,
  ) {
    if (n == 1) return (x: x[0], y: y[0], nx: nx[0], ny: ny[0], i: 0, t: 0);
    final c = at.clamp(0.0, length);
    var j = sampleAt(c);
    if (j == 0) j = 1;
    final i = j - 1;
    final ds = s[j] - s[i];
    final t = ds > 1e-9 ? ((c - s[i]) / ds).clamp(0.0, 1.0) : 0.0;
    final k = t < 0.5 ? i : j;
    return (
      x: x[i] + (x[j] - x[i]) * t,
      y: y[i] + (y[j] - y[i]) * t,
      nx: nx[k],
      ny: ny[k],
      i: i,
      t: t,
    );
  }

  /// [a] (one value per sample) at the place [locate] returned.
  static double lerp(Float64List a, int i, double t) =>
      i + 1 < a.length ? a[i] + (a[i + 1] - a[i]) * t : a[i];

  /// Left / right radii: [radius] wobbled independently on each side — the
  /// lock app's `ragged` ([edge]: slow wobble amount, [freq]: wobbles per
  /// width of length, [rough]: fine jitter at 4.3 × freq).
  (Float64List, Float64List) ragged(
    double Function(int i) radius, {
    required double edge,
    required double freq,
    double rough = 0,
    int salt = 0,
  }) {
    final left = Float64List(n), right = Float64List(n);
    final sl = seed + salt;
    for (var i = 0; i < n; i++) {
      final rad = radius(i);
      final u = s[i] / width * freq;
      final a = 1 + edge * wobble(u, sl) + rough * wobble(u * 4.3, sl + 57);
      final b =
          1 + edge * wobble(u, sl + 101) + rough * wobble(u * 4.3, sl + 158);
      left[i] = math.min(limit, math.max(0.0, rad * a));
      right[i] = math.min(limit, math.max(0.0, rad * b));
    }
    return (left, right);
  }
}

/// Every radius + [d] (≥ 0).
Float64List plus(Float64List a, double d) {
  final out = Float64List(a.length);
  for (var i = 0; i < a.length; i++) {
    out[i] = math.max(0, a[i] + d);
  }
  return out;
}

/// Every radius × [k].
Float64List times(Float64List a, double k) {
  final out = Float64List(a.length);
  for (var i = 0; i < a.length; i++) {
    out[i] = a[i] * k;
  }
  return out;
}

/// Every radius × k(i).
Float64List timesAt(Float64List a, double Function(int i) k) {
  final out = Float64List(a.length);
  for (var i = 0; i < a.length; i++) {
    out[i] = a[i] * k(i);
  }
  return out;
}

const OutlineSpec _bandSpec = OutlineSpec(
  method: InkRenderMethod.filledOutline,
  cap: InkCap.round,
);

/// Outline options of the bands: no RDP (two thirds of the outline time on
/// band-sized polygons) — [decimate] thins the polygons in one pass instead —
/// and coarser caps (a band is one of several translucent layers).
const OutlineOptions _bandOptions = OutlineOptions(
  simplifyTolerance: 0,
  capChordPt: 1.2,
);

/// Vertices closer than this to the chord of their neighbours are dropped (pt).
const double _decimatePt = 0.1;

/// No kept edge longer than this (pt): the smooth path stays close to the band.
const double _maxEdgePt = 3;

/// [poly] (x, y pairs, closed) without the vertices that lie within
/// [_decimatePt] of the chord from the last kept vertex to the next one — one
/// linear pass (RDP is O(n log n) and was most of the band time). The kept
/// vertices are a subset, so the bounds only shrink (K-1 holds).
Float32List decimate(Float32List poly) {
  final m = poly.length ~/ 2;
  if (m < 8) return poly;
  final keep = Float32List(poly.length);
  var o = 0;
  var lx = poly[0], ly = poly[1];
  keep[o++] = lx;
  keep[o++] = ly;
  const tol2 = _decimatePt * _decimatePt;
  const max2 = _maxEdgePt * _maxEdgePt;
  for (var k = 1; k < m; k++) {
    final px = poly[2 * k], py = poly[2 * k + 1];
    final j = k + 1 == m ? 0 : k + 1;
    final nx = poly[2 * j], ny = poly[2 * j + 1];
    final dx = nx - lx, dy = ny - ly;
    final len2 = dx * dx + dy * dy;
    var drop = len2 <= max2;
    if (drop) {
      var u = len2 > 0 ? ((px - lx) * dx + (py - ly) * dy) / len2 : 0.0;
      if (u < 0) u = 0;
      if (u > 1) u = 1;
      final ex = px - (lx + u * dx), ey = py - (ly + u * dy);
      drop = ex * ex + ey * ey <= tol2;
    }
    if (drop) continue;
    keep[o++] = px;
    keep[o++] = py;
    lx = px;
    ly = py;
  }
  if (o < 6) return poly;
  return keep.sublist(0, o);
}

/// Radii below this are "no band".
const double _minBand = 0.03;

/// The band of the spine with left radii [rl] and right radii [rr] (clamped to
/// [0, sp.limit]): one nonzero StrokeOutline (polygons positive), or null when
/// every radius is ~0. Runs of zero radius split the band into pieces.
StrokeOutline? band(Spine sp, Float64List rl, Float64List rr) {
  final polys = <Float32List>[];
  var bounds = ui.Rect.zero;
  var any = false;
  void add(StrokeOutline o) {
    for (final p in o.polygons) {
      polys.add(decimate(p));
    }
    final c = o.dotCenter;
    if (c != null) polys.add(circlePolygon(c.dx, c.dy, o.dotRadius));
    bounds = any ? bounds.expandToInclude(o.bounds) : o.bounds;
    any = true;
  }

  double left(int i) => rl[i].clamp(0.0, sp.limit);
  double right(int i) => rr[i].clamp(0.0, sp.limit);
  var i = 0;
  while (i < sp.n) {
    if ((left(i) + right(i)) / 2 <= _minBand) {
      i++;
      continue;
    }
    var j = i;
    while (j + 1 < sp.n && (left(j + 1) + right(j + 1)) / 2 > _minBand) {
      j++;
    }
    final count = j - i + 1;
    if (count == 1) {
      final a = left(i), b = right(i);
      final off = (a - b) / 2;
      final cx = sp.x[i] + sp.nx[i] * off, cy = sp.y[i] + sp.ny[i] * off;
      final rad = (a + b) / 2;
      polys.add(circlePolygon(cx, cy, rad));
      final rect = ui.Rect.fromCircle(center: ui.Offset(cx, cy), radius: rad);
      bounds = any ? bounds.expandToInclude(rect) : rect;
      any = true;
    } else {
      final raw = Float32List(count * 6);
      for (var k = 0; k < count; k++) {
        final q = i + k;
        final a = left(q), b = right(q);
        final off = (a - b) / 2;
        raw[6 * k] = sp.x[q] + sp.nx[q] * off;
        raw[6 * k + 1] = sp.y[q] + sp.ny[q] * off;
        raw[6 * k + 2] = (a + b) / 4;
      }
      add(
        OutlineGenerator.outlineFor(
          InkPoints.fromRaw(raw),
          width: 1,
          spec: _bandSpec,
          options: _bandOptions,
        ),
      );
    }
    i = j + 1;
  }
  if (!any || polys.isEmpty) return null;
  return StrokeOutline(polygons: polys, bounds: bounds);
}

/// A circle as a positive polygon of [segments] vertices.
Float32List circlePolygon(double cx, double cy, double r, {int segments = 0}) {
  final k = segments > 0 ? segments : (r * 6).ceil().clamp(10, 32);
  final out = Float32List(2 * k);
  for (var i = 0; i < k; i++) {
    final a = 2 * math.pi * i / k;
    out[2 * i] = cx + r * math.cos(a);
    out[2 * i + 1] = cy + r * math.sin(a);
  }
  return out;
}

/// [outer] minus [inner] under nonzero: the inner polygons reversed.
StrokeOutline ring(StrokeOutline outer, StrokeOutline inner) => StrokeOutline(
  polygons: [...outer.polygons, for (final p in inner.polygons) reversed(p)],
  bounds: outer.bounds,
);

/// [a] with the polygons of [holes] cut out (reversed, nonzero).
StrokeOutline withHoles(StrokeOutline a, List<Float32List> holes) =>
    StrokeOutline(
      polygons: [...a.polygons, ...holes],
      bounds: a.bounds,
      dotCenter: a.dotCenter,
      dotRadius: a.dotRadius,
      dots: a.dots,
    );

/// The polygon in the opposite orientation.
Float32List reversed(Float32List p) {
  final m = p.length ~/ 2;
  final out = Float32List(p.length);
  for (var i = 0; i < m; i++) {
    out[2 * i] = p[2 * (m - 1 - i)];
    out[2 * i + 1] = p[2 * (m - 1 - i) + 1];
  }
  return out;
}

/// The polygon with a negative shoelace area (a hole under nonzero).
Float32List negative(Float32List p) => _area(p) > 0 ? reversed(p) : p;

double _area(Float32List p) {
  final m = p.length ~/ 2;
  var a = 0.0;
  for (var i = 0; i < m; i++) {
    final j = i + 1 == m ? 0 : i + 1;
    a += p[2 * i] * p[2 * j + 1] - p[2 * j] * p[2 * i + 1];
  }
  return a / 2;
}

/// Thin bands along the spine at the offset [frac] × [mid] from the center,
/// [wl] / [wr] wide on each side — the lock app's `offsetBand` (grooves,
/// dry-brush streaks). One polygon per run of nonzero width; offsets clamped
/// to ± [maxOffset](i) (inside the body).
List<Float32List> offsetBands(
  Spine sp,
  double frac,
  Float64List mid,
  Float64List wl,
  Float64List wr, {
  required double Function(int i) maxOffset,
}) {
  final out = <Float32List>[];
  final last = sp.n - 1;
  var i = 0;
  while (i <= last) {
    if (wl[i] + wr[i] <= 0) {
      i++;
      continue;
    }
    final from = math.max(0, i - 1);
    var to = i;
    while (to < last && wl[to + 1] + wr[to + 1] > 0) {
      to++;
    }
    to = math.min(last, to + 1);
    final count = to - from + 1;
    if (count >= 2) {
      final poly = Float32List(4 * count);
      var o = 0;
      for (var j = from; j <= to; j++) {
        final lim = maxOffset(j);
        final c = (frac * mid[j] + wl[j]).clamp(-lim, lim);
        poly[o++] = sp.x[j] + sp.nx[j] * c;
        poly[o++] = sp.y[j] + sp.ny[j] * c;
      }
      for (var j = to; j >= from; j--) {
        final lim = maxOffset(j);
        final c = (frac * mid[j] - wr[j]).clamp(-lim, lim);
        poly[o++] = sp.x[j] + sp.nx[j] * c;
        poly[o++] = sp.y[j] + sp.ny[j] * c;
      }
      out.add(poly);
    }
    i = to + 1;
  }
  return out;
}

/// The lock app's `coverageRadii`: the band where the coverage is ≥ [level].
/// Coverage at the relative distance ρ from the center = core − (core − edge) ·
/// ((ρ − ρ0) / (1 − ρ0))^q up to the nominal edge ρ = 1, then falling to 0
/// over [fade] pt outside. [jit] wobbles the boundary along the length.
(Float64List, Float64List)? coverageBand(
  Spine sp,
  Float64List left,
  Float64List right, {
  required double Function(int i) core,
  required double Function(int i) edge,
  required double level,
  required double rho0,
  required double q,
  required double fade,
  required double jit,
  required int salt,
}) {
  final outL = Float64List(sp.n), outR = Float64List(sp.n);
  var any = false;
  final invQ = 1 / q;
  for (var i = 0; i < sp.n; i++) {
    final c = core(i), e = edge(i);
    if (level >= c) continue;
    final w = jit != 0
        ? 1 + jit * wobble(sp.s[i] / sp.width * 1.7, sp.seed + salt)
        : 1.0;
    if (level <= e) {
      final extra = fade * (1 - level / e) * w;
      outL[i] = left[i] + extra;
      outR[i] = right[i] + extra;
    } else {
      final x = (c - level) / (c - e);
      final rho = math.min(
        1.0,
        (rho0 + (1 - rho0) * math.pow(x, invQ).toDouble()) * w,
      );
      outL[i] = left[i] * rho;
      outR[i] = right[i] * rho;
    }
    any = true;
  }
  return any ? (outL, outR) : null;
}

/// The lock app's `levelShape` width factor: 0 → 1 as [value] passes [level]
/// ± [soft], wobbled along the length.
double levelK(
  Spine sp,
  int i,
  double value,
  double level,
  double soft,
  int salt,
) => math.min(
  1.0,
  smoothstep(level - soft, level + soft, value) *
      (1 + 0.45 * wobble(sp.s[i] / sp.width * 0.7, sp.seed + salt)),
);

/// The band where [value](i) exceeds [level] (soft edges along the length).
StrokeOutline? levelShape(
  Spine sp,
  Float64List left,
  Float64List right,
  double Function(int i) value, {
  required double level,
  required double soft,
  required int salt,
}) {
  final ks = Float64List(sp.n);
  var widest = 0.0;
  for (var i = 0; i < sp.n; i++) {
    ks[i] = levelK(sp, i, value(i), level, soft, salt);
    if (ks[i] > widest) widest = ks[i];
  }
  if (widest <= 0) return null;
  return band(sp, timesAt(left, (i) => ks[i]), timesAt(right, (i) => ks[i]));
}
