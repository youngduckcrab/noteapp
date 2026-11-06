// lib/src/geometry/nib_outline.dart — INTERNAL (m5-7/03-ink 6.4, T28).
//
// The calligraphy pen (nibOutline): an elliptic nib E_i at every point p_i —
// major radius a_i = r_i = max(minRadiusPt, 2 · width · widthQ_i), minor radius
// b_i = k · a_i (k = style.nibAspect), the major axis at θ = nibAngleDeg · π / 180
// (clockwise on the screen, y down) — swept along the centerline (the Minkowski
// sum). Moving along the major axis gives the thin line (width 2b), across it the
// thick one (2a). The round-1 fill outline O1–O9 with O1, O4 and O6 changed:
//
//   N1 dot        one point or length < 1e-3 → the nib ellipse itself, a polygon
//                 of 2 × the O6 segment count, parameter-uniform
//   N2 direction  O2
//   N3 corners    O3 (dot < sharpCornerCos → two polygons)
//   N4 sides      the ellipse's support point for the side normal:
//                 M = R(θ) · diag(a, b), s(n) = M · Mᵀn / ‖Mᵀn‖,
//                 L_i = p_i + s_i(n_i), R_i = p_i − s_i(n_i); k = 1 → s = a · n (O4).
//                 The outer side of a bend gets the ellipse arc between the
//                 support points of the two segment normals (O4's round join)
//   N5 retrograde O5
//   N6 caps       half ellipses: the end cap from L_n through the forward side to
//                 R_n, the start cap from R_0 through the back to L_0, uniform in
//                 the ellipse parameter φ, clamp(⌈π · a / capChordPt⌉, 4, 16)
//   N7            O7 (positive orientation), O8 (RDP, tolerance ≤ b / 4)
//
// E(φ) = u · a cos φ + v · b sin φ (u = (cos θ, sin θ), v = (−sin θ, cos θ)); the
// support point of the normal n is E(φ(n)), φ(n) = atan2(b · v·n, a · u·n) — an
// increasing function of the angle of n, so an arc of normals is an arc of φ.
//
// K-1: every vertex lies on some E_i, and E_i ⊂ disk(p_i, a_i) (b_i ≤ a_i); the
// smooth path stays inside the vertices' convex hull, so the outline is inside
// ∪ disk(p_i, a_i) ⊆ pointBounds.inflate(max a_i) — the round-1 fill pen bound
// (contract: 'the calligraphy nib half length = 2 · width · widthQ').
part of 'outline_generator.dart';

/// The ellipse of one nib: the axis directions and the aspect (minor / major).
final class _Nib {
  _Nib(double angleDeg, double aspect)
    : k = aspect.isFinite ? aspect.clamp(0.1, 1.0).toDouble() : 0.25,
      ux = math.cos(_radians(angleDeg)),
      uy = math.sin(_radians(angleDeg));

  final double k;

  /// the major axis direction u; the minor axis v = (−uy, ux)
  final double ux, uy;
  double get vx => -uy;
  double get vy => ux;

  static double _radians(double deg) =>
      (deg.isFinite ? deg : 45) * math.pi / 180;

  /// φ of the support point for the normal (nx, ny) on the nib of major radius
  /// [a] (minor k · a).
  double phiOf(double nx, double ny, double a) =>
      math.atan2(k * a * (vx * nx + vy * ny), a * (ux * nx + uy * ny));

  /// E(φ) on the nib of major radius [a] (relative to its center).
  (double, double) pointAt(double a, double phi) {
    final c = math.cos(phi) * a, s = math.sin(phi) * k * a;
    return (ux * c + vx * s, uy * c + vy * s);
  }

  /// (cx, cy) + E(φ) appended to [out].
  void addPoint(_Coords out, double cx, double cy, double a, double phi) {
    final (x, y) = pointAt(a, phi);
    out.add(cx + x, cy + y);
  }

  /// The support point s(n) = M · Mᵀn / ‖Mᵀn‖ for the unit normal (nx, ny).
  (double, double) support(double nx, double ny, double a) {
    final b = k * a;
    final un = ux * nx + uy * ny, vn = vx * nx + vy * ny;
    final norm = math.sqrt(a * a * un * un + b * b * vn * vn);
    if (!(norm > 0)) return (0, 0);
    final pu = a * a * un / norm, pv = b * b * vn / norm;
    return (ux * pu + vx * pv, uy * pu + vy * pv);
  }
}

/// (T28, 6.4) The nib outline of [points] (see the file comment).
StrokeOutline _nibOutline(
  InkPoints points, {
  required double width,
  required double angleDeg,
  required double aspect,
  required OutlineOptions options,
}) {
  final n = points.length;
  if (n == 0) {
    return StrokeOutline(polygons: const [], bounds: ui.Rect.zero);
  }
  final nib = _Nib(angleDeg, aspect);
  double radius(int i) {
    final r = 2 * width * OutlineGenerator._finite(points.widthQ(i));
    return r > InkTuning.minRadiusPt ? r : InkTuning.minRadiusPt;
  }

  // Distinct consecutive points (a duplicate keeps the larger radius).
  final xs = Float64List(n), ys = Float64List(n), rs = Float64List(n);
  var m = 0;
  var length = 0.0;
  for (var i = 0; i < n; i++) {
    final x = OutlineGenerator._finite(points.x(i));
    final y = OutlineGenerator._finite(points.y(i));
    final r = radius(i);
    if (m > 0) {
      final ex = x - xs[m - 1], ey = y - ys[m - 1];
      final d = math.sqrt(ex * ex + ey * ey);
      if (d <= _duplicateEps) {
        if (r > rs[m - 1]) rs[m - 1] = r;
        continue;
      }
      length += d;
    }
    xs[m] = x;
    ys[m] = y;
    rs[m] = r;
    m++;
  }

  // N1: the nib ellipse
  if (m == 1 || length < _dotLength) {
    var a = 0.0;
    for (var i = 0; i < m; i++) {
      a = math.max(a, rs[i]);
    }
    final segments = 2 * _nibCapSegments(a, options);
    final out = _Coords(2 * segments);
    for (var j = 0; j < segments; j++) {
      nib.addPoint(out, xs[0], ys[0], a, 2 * math.pi * j / segments);
    }
    final poly = Float32List(out.length)..setRange(0, out.length, out.data);
    OutlineGenerator._orientPositive(poly);
    return StrokeOutline(polygons: [poly], bounds: _vertexBounds([poly]));
  }

  // N2 segment directions (every segment is longer than _duplicateEps)
  final dx = Float64List(m - 1), dy = Float64List(m - 1);
  for (var i = 0; i < m - 1; i++) {
    final ex = xs[i + 1] - xs[i], ey = ys[i + 1] - ys[i];
    final len = math.sqrt(ex * ex + ey * ey);
    dx[i] = ex / len;
    dy[i] = ey / len;
  }

  // N3 split at sharp corners
  final polygons = <Float32List>[];
  var start = 0;
  for (var i = 1; i < m; i++) {
    final last = i == m - 1;
    if (!last &&
        dx[i - 1] * dx[i] + dy[i - 1] * dy[i] >= options.sharpCornerCos) {
      continue;
    }
    polygons.add(_nibRunPolygon(nib, xs, ys, rs, dx, dy, start, i, options));
    start = i;
  }
  return StrokeOutline(polygons: polygons, bounds: _vertexBounds(polygons));
}

/// N6 / O6: clamp(⌈π · a / capChordPt⌉, 4, maxCapSegments).
int _nibCapSegments(double a, OutlineOptions options) =>
    (math.pi * a / options.capChordPt).ceil().clamp(
      _minCapSegments,
      math.max(_minCapSegments, options.maxCapSegments),
    );

ui.Rect _vertexBounds(List<Float32List> polygons) {
  var minX = double.infinity, minY = double.infinity;
  var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  for (final poly in polygons) {
    for (var i = 0; i + 1 < poly.length; i += 2) {
      final x = poly[i], y = poly[i + 1];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  if (minX > maxX) return ui.Rect.zero;
  return ui.Rect.fromLTRB(minX, minY, maxX, maxY);
}

/// One polygon for the points [a]..[b] (b > a): left side forward, end cap, right
/// side backward, start cap (N4–N7).
Float32List _nibRunPolygon(
  _Nib nib,
  Float64List xs,
  Float64List ys,
  Float64List rs,
  Float64List dx,
  Float64List dy,
  int a,
  int b,
  OutlineOptions options,
) {
  // N2 point tangents: the adjacent segment at the run ends, else the bisector.
  final count = b - a + 1;
  final tx = Float64List(count), ty = Float64List(count);
  for (var k = 0; k < count; k++) {
    final i = a + k;
    double x, y;
    if (k == 0) {
      x = dx[i];
      y = dy[i];
    } else if (k == count - 1) {
      x = dx[i - 1];
      y = dy[i - 1];
    } else {
      x = dx[i - 1] + dx[i];
      y = dy[i - 1] + dy[i];
      final len = math.sqrt(x * x + y * y);
      if (len > 1e-9) {
        x /= len;
        y /= len;
      } else {
        x = dx[i];
        y = dy[i];
      }
    }
    tx[k] = x;
    ty[k] = y;
  }

  final maxSteps = math.max(_minCapSegments, options.maxCapSegments);
  // |dφ / dα| ≤ a / b = 1 / k: the arc of a turn α is at most a · α / k long
  final reach = 1 / nib.k;

  // N4 + N5 for one side (sign +1 = left, −1 = right), in point order.
  _Coords side(double sign) {
    final v = _Coords(2 * count + 16);
    void add(int k, double x, double y) {
      if (k > 0 && k < count - 1) {
        final px = v.data[v.length - 2], py = v.data[v.length - 1];
        if ((x - px) * tx[k] + (y - py) * ty[k] < 0) return; // N5 = O5
      }
      v.add(x, y);
    }

    for (var k = 0; k < count; k++) {
      final i = a + k;
      final r = rs[i];
      if (k > 0 && k < count - 1) {
        // Outer side of a bend: the nib arc between the support points of the
        // normals of d_{i−1} and d_i when it is longer than capChordPt.
        final c = dx[i - 1] * dx[i] + dy[i - 1] * dy[i];
        final cross = dx[i - 1] * dy[i] - dy[i - 1] * dx[i];
        // the O4 Jordan bound, times the arc stretch 1 / k of the ellipse
        final small =
            c > 0 &&
            cross.abs() * (math.pi / 2) * r * reach <=
                0.999 * options.capChordPt;
        if ((cross > 0) == (sign < 0) && !small) {
          // sign · n(d) with n = (−dy, dx)
          final phi0 = nib.phiOf(-dy[i - 1] * sign, dx[i - 1] * sign, r);
          final phi1 = nib.phiOf(-dy[i] * sign, dx[i] * sign, r);
          var delta = phi1 - phi0;
          if (delta > math.pi) delta -= 2 * math.pi;
          if (delta <= -math.pi) delta += 2 * math.pi;
          final segments = (delta.abs() * r / options.capChordPt).ceil();
          if (segments > 1) {
            final steps = math.min(segments, maxSteps);
            for (var j = 0; j <= steps; j++) {
              final (ex, ey) = nib.pointAt(r, phi0 + delta * j / steps);
              add(k, xs[i] + ex, ys[i] + ey);
            }
            continue;
          }
        }
      }
      // n = (−τy, τx)
      final (sx, sy) = nib.support(-ty[k] * sign, tx[k] * sign, r);
      add(k, xs[i] + sx, ys[i] + sy);
    }
    return v;
  }

  final left = side(1);
  final right = side(-1);
  final capEnd = _nibCapSegments(rs[b], options);
  final capStart = _nibCapSegments(rs[a], options);
  final out = _Coords(left.length + right.length + 2 * (capEnd + capStart))
    ..addAll(left);
  // N6 end cap: L_b → the forward side → R_b, φ decreasing by π
  final phiEnd = nib.phiOf(-ty[count - 1], tx[count - 1], rs[b]);
  for (var j = 1; j < capEnd; j++) {
    nib.addPoint(out, xs[b], ys[b], rs[b], phiEnd - math.pi * j / capEnd);
  }
  for (var i = right.length - 2; i >= 0; i -= 2) {
    out.add(right.data[i], right.data[i + 1]);
  }
  // N6 start cap: R_a → the back → L_a, φ from φ(n) + π decreasing by π
  final phiStart = nib.phiOf(-ty[0], tx[0], rs[a]) + math.pi;
  for (var j = 1; j < capStart; j++) {
    nib.addPoint(out, xs[a], ys[a], rs[a], phiStart - math.pi * j / capStart);
  }

  final poly = Float32List(out.length)..setRange(0, out.length, out.data);
  OutlineGenerator._orientPositive(poly); // N7 = O7
  // O8 with the minor radii: the tolerance stays below b / 4
  final minor = Float64List(rs.length);
  for (var i = a; i <= b; i++) {
    minor[i] = rs[i] * nib.k;
  }
  return OutlineGenerator._simplify(poly, minor, a, b, options);
}
