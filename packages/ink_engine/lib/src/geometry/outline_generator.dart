// lib/src/geometry/outline_generator.dart — INTERNAL (03-ink 4.5, 6.8).
//
// Fill outline of one stroke, perfect-freehand style but with the pressure and
// taper already baked into the points (6.7): the outline only uses the radius
// r_i = max(InkTuning.minRadiusPt, 2 · width · widthQ_i).
//
//   O1 dot        one point or length < 1e-3 → circle (dotCenter, dotRadius);
//                 (m5-7 T27) a filled pen with square caps (tape) → an
//                 axis-aligned square of side 2r (corners r · √2 away)
//   O2 direction  d_i = unit(p_{i+1} − p_i), τ_i = unit(d_{i−1} + d_i), n_i ⟂ τ_i
//   O3 corners    dot(d_{i−1}, d_i) < sharpCornerCos → split into two polygons
//   O4 sides      L_i = p_i + n_i · r_i, R_i = p_i − n_i · r_i
//   O5 retrograde a side point that goes backwards along τ_i is skipped
//   O6 caps       half circles, clamp(⌈π · r / capChordPt⌉, 4, maxCapSegments)
//   O7 direction  every polygon gets a positive shoelace area (y down)
//   O8 simplify   RDP (simplifyTolerance) on each polygon
//   O9 polyline   highlighter: the centerline, stroked by the painter
//
// Every vertex is exactly r_i away from some p_i (side points, round caps), or
// r_i · √2 for the square caps of the highlighter (r = width / 2), and the
// smooth path stays inside the vertices' convex hull — the basis of K-1
// (6.7, contract 7.3.2): the outline is inside core.Stroke.bounds.
//
// (m5-7/03-ink T27) OutlineSpec picks the generator by render method: the
// filled outline above for filledOutline (and the highlighter's
// strokedPolyline outline); nibOutline and transientTrail use the filled
// outline too until T28 (nib) and T30 (laser trail) give them their own.
//
// (T29, 6.5 D1–D5) dashedPolyline: the stored centerline split by the dash
// pattern (style.dashPattern × width, phase 0 at the stroke start —
// dash.dart dashedStrokePieces), every capsule piece the round-cap outline
// above (O1–O8), every short piece a dot of radius r: all of them ONE outline
// (one nonZero path of many contours). Every vertex is on some disk(p, r) of a
// centerline point (a piece point lies on the centerline), so K-1 holds as
// for the filled pens. A dot stroke (O1) stays the one round dot.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:meta/meta.dart';

import '../model/ink_layer.dart';
import '../model/ink_points.dart';
import '../model/ink_stroke.dart';
import '../pen/pen_profile.dart';
import '../pen/style_ink.dart';
import '../tuning.dart';
import 'dash.dart';
import 'stroke_outline.dart';

@immutable
final class OutlineOptions {
  const OutlineOptions({
    this.sharpCornerCos = InkTuning.sharpCornerCos,
    this.capChordPt = InkTuning.capChordPt,
    this.maxCapSegments = InkTuning.maxCapSegments,
    this.simplifyTolerance = InkTuning.outlineSimplifyPt,
  });
  final double sharpCornerCos, capChordPt, simplifyTolerance;
  final int maxCapSegments;

  @override
  bool operator ==(Object other) =>
      other is OutlineOptions &&
      other.sharpCornerCos == sharpCornerCos &&
      other.capChordPt == capChordPt &&
      other.simplifyTolerance == simplifyTolerance &&
      other.maxCapSegments == maxCapSegments;

  @override
  int get hashCode => Object.hash(
    sharpCornerCos,
    capChordPt,
    simplifyTolerance,
    maxCapSegments,
  );
}

/// Lower bound of the cap segment count (6.8 O6).
const int _minCapSegments = 4;

/// Consecutive points closer than this are one point (pt).
const double _duplicateEps = 1e-6;

/// O1: a centerline shorter than this is a dot (pt).
const double _dotLength = 1e-3;

/// What the outline generator makes for one stroke (m5-7/03-ink T27): the
/// render method and cap of its profile, and the radius rule.
@immutable
final class OutlineSpec {
  const OutlineSpec({
    required this.method,
    required this.cap,
    this.constantRadius = false,
    this.dashPattern = defaultDashPattern,
  });

  /// The spec of [profile]: its render method and cap; the highlighter has a
  /// constant radius width / 2 (widthQ ignored). [dashPattern]: the stroke's
  /// style.dashPattern (dashedPolyline only).
  factory OutlineSpec.of(
    PenProfile profile, {
    List<double> dashPattern = defaultDashPattern,
  }) => OutlineSpec(
    method: profile.renderMethod,
    cap: profile.cap,
    constantRadius: profile.layer == InkLayer.highlighter,
    dashPattern: profile.renderMethod == InkRenderMethod.dashedPolyline
        ? dashPattern
        : defaultDashPattern,
  );

  /// The default of style.dashPattern (m5-7/03-ink 4.10).
  static const List<double> defaultDashPattern = [4, 3];

  final InkRenderMethod method;
  final InkCap cap;

  /// r = width / 2 for every point (highlighter); otherwise from widthQ.
  final bool constantRadius;

  /// dashedPolyline: on, off, … in multiples of the width (style.dashPattern).
  final List<double> dashPattern;

  /// O1 of a filled pen with square caps (tape): a square, not a circle. The
  /// highlighter (strokedPolyline) keeps the round-1 circle.
  bool get squareDot =>
      cap == InkCap.square && method == InkRenderMethod.filledOutline;

  @override
  bool operator ==(Object other) =>
      other is OutlineSpec &&
      other.method == method &&
      other.cap == cap &&
      other.constantRadius == constantRadius &&
      _sameList(other.dashPattern, dashPattern);

  @override
  int get hashCode =>
      Object.hash(method, cap, constantRadius, Object.hashAll(dashPattern));

  static bool _sameList(List<double> a, List<double> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The round-cap filled outline of one dash piece.
const OutlineSpec _dashPieceSpec = OutlineSpec(
  method: InkRenderMethod.filledOutline,
  cap: InkCap.round,
);

abstract final class OutlineGenerator {
  static StrokeOutline outline(
    InkStroke stroke, {
    OutlineOptions options = const OutlineOptions(),
  }) => outlineOf(
    stroke.points,
    width: stroke.style.width,
    profile: stroke.profile,
    dashPattern: stroke.style.dashPattern,
    options: options,
  );

  /// Same from raw parts (live builder, previews of transformed copies).
  /// [dashPattern]: style.dashPattern (dashedPolyline only).
  static StrokeOutline outlineOf(
    InkPoints points, {
    required double width,
    required PenProfile profile,
    List<double> dashPattern = OutlineSpec.defaultDashPattern,
    OutlineOptions options = const OutlineOptions(),
  }) => outlineFor(
    points,
    width: width,
    spec: OutlineSpec.of(profile, dashPattern: dashPattern),
    options: options,
  );

  /// The outline of [spec]'s render method (see the file comment).
  static StrokeOutline outlineFor(
    InkPoints points, {
    required double width,
    required OutlineSpec spec,
    OutlineOptions options = const OutlineOptions(),
  }) => switch (spec.method) {
    InkRenderMethod.dashedPolyline => dashed(
      points,
      width: width,
      pattern: spec.dashPattern,
      options: options,
    ),
    InkRenderMethod.filledOutline ||
    InkRenderMethod.strokedPolyline ||
    InkRenderMethod.nibOutline ||
    InkRenderMethod.transientTrail => _filled(
      points,
      width: width,
      spec: spec,
      options: options,
    ),
  };

  /// (T29) The outline of one dash piece (dash.dart dashedStrokePieces): the round-cap
  /// outline of its centerline, or the dot of a one-point piece (live dashes).
  static StrokeOutline dashPiece(
    InkPoints piece, {
    required double width,
    OutlineOptions options = const OutlineOptions(),
  }) => _filled(piece, width: width, spec: _dashPieceSpec, options: options);

  /// (T29, 6.5) The dashed outline of [points]: [pattern] (multiples of [width]) from
  /// phase 0 — or, live, from [lead] pt on (dash.dart dashIntervalsAfter) — split into
  /// round-cap pieces and dots of radius r = max(minRadiusPt, 2 · width · max widthQ).
  /// A stroke that is one point or shorter than 1e-3 pt is the O1 dot (from phase 0).
  static StrokeOutline dashed(
    InkPoints points, {
    required double width,
    required List<double> pattern,
    double lead = 0,
    int maxSegments = InkTuning.dashMaxSegments,
    OutlineOptions options = const OutlineOptions(),
  }) {
    final n = points.length;
    if (n == 0) {
      return StrokeOutline(polygons: const [], bounds: ui.Rect.zero);
    }
    if (!(lead > 0) && (n == 1 || points.arcLength() < _dotLength)) {
      return _filled(
        points,
        width: width,
        spec: _dashPieceSpec,
        options: options,
      );
    }
    var maxQ = 0.0;
    for (var i = 0; i < n; i++) {
      final q = _finite(points.widthQ(i));
      if (q > maxQ) maxQ = q;
    }
    final r = math.max(InkTuning.minRadiusPt, 2 * width * maxQ);
    final polygons = <Float32List>[];
    final dots = <ui.Offset>[];
    ui.Rect? bounds;
    for (final piece in dashedStrokePieces(
      points,
      [for (final v in pattern) v * width],
      radius: r,
      lead: lead,
      maxSegments: maxSegments,
    )) {
      final o = _filled(
        piece,
        width: width,
        spec: _dashPieceSpec,
        options: options,
      );
      final c = o.dotCenter;
      ui.Rect b;
      if (c != null) {
        dots.add(c);
        b = ui.Rect.fromCircle(center: c, radius: r);
      } else {
        polygons.addAll(o.polygons);
        b = o.bounds;
      }
      bounds = bounds == null ? b : bounds.expandToInclude(b);
    }
    return StrokeOutline(
      polygons: polygons,
      bounds: bounds ?? ui.Rect.zero,
      dots: dots,
      dotRadius: dots.isEmpty ? 0 : r,
    );
  }

  /// The round-1 fill outline (O1–O8) with [spec]'s cap and radius rule.
  static StrokeOutline _filled(
    InkPoints points, {
    required double width,
    required OutlineSpec spec,
    required OutlineOptions options,
  }) {
    final n = points.length;
    if (n == 0) {
      return StrokeOutline(polygons: const [], bounds: ui.Rect.zero);
    }
    final constantRadius = spec.constantRadius;
    double radius(int i) {
      final r = constantRadius
          ? width / 2
          : 2 * width * _finite(points.widthQ(i));
      return r > InkTuning.minRadiusPt ? r : InkTuning.minRadiusPt;
    }

    // Distinct consecutive points (a duplicate keeps the larger radius).
    final xs = Float64List(n), ys = Float64List(n), rs = Float64List(n);
    var m = 0;
    var length = 0.0;
    for (var i = 0; i < n; i++) {
      final x = _finite(points.x(i)), y = _finite(points.y(i));
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

    // O1
    if (m == 1 || length < _dotLength) {
      var r = 0.0;
      for (var i = 0; i < m; i++) {
        r = math.max(r, rs[i]);
      }
      final c = ui.Offset(xs[0], ys[0]);
      if (spec.squareDot) return _squareDot(c, r);
      return StrokeOutline(
        polygons: const [],
        bounds: ui.Rect.fromCircle(center: c, radius: r),
        dotCenter: c,
        dotRadius: r,
      );
    }

    // O2 segment directions (every segment is longer than _duplicateEps)
    final dx = Float64List(m - 1), dy = Float64List(m - 1);
    for (var i = 0; i < m - 1; i++) {
      final ex = xs[i + 1] - xs[i], ey = ys[i + 1] - ys[i];
      final len = math.sqrt(ex * ex + ey * ey);
      dx[i] = ex / len;
      dy[i] = ey / len;
    }

    // O3 split at sharp corners
    final polygons = <Float32List>[];
    final squareEnds = spec.cap == InkCap.square;
    var start = 0;
    for (var i = 1; i < m; i++) {
      final last = i == m - 1;
      if (!last &&
          dx[i - 1] * dx[i] + dy[i - 1] * dy[i] >= options.sharpCornerCos) {
        continue;
      }
      polygons.add(
        _runPolygon(
          xs,
          ys,
          rs,
          dx,
          dy,
          start,
          i,
          squareStart: squareEnds && start == 0,
          squareEnd: squareEnds && last,
          options: options,
        ),
      );
      start = i;
    }

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
    return StrokeOutline(
      polygons: polygons,
      bounds: ui.Rect.fromLTRB(minX, minY, maxX, maxY),
    );
  }

  /// O1 square dot: corners (c ± r, c ± r), each listed twice so the smooth
  /// path (quadratic through the edge midpoints) keeps the sharp corners —
  /// the midpoint of a repeated vertex is the vertex itself.
  static StrokeOutline _squareDot(ui.Offset c, double r) {
    final l = c.dx - r, t = c.dy - r, rt = c.dx + r, b = c.dy + r;
    final poly = Float32List.fromList([
      l, t, l, t, //
      rt, t, rt, t, //
      rt, b, rt, b, //
      l, b, l, b, //
    ]);
    _orientPositive(poly);
    return StrokeOutline(
      polygons: [poly],
      bounds: ui.Rect.fromLTRB(l, t, rt, b),
    );
  }

  /// Centerline x,y pairs for strokedPolyline pens (highlighter).
  static Float32List polyline(InkPoints points) {
    final out = Float32List(points.length * 2);
    for (var i = 0; i < points.length; i++) {
      out[2 * i] = points.x(i);
      out[2 * i + 1] = points.y(i);
    }
    return out;
  }

  /// Shoelace area of x,y pairs (implicitly closed); positive = the 6.8 O7
  /// orientation in y-down coordinates.
  @visibleForTesting
  static double signedArea(Float32List poly) {
    var area = 0.0;
    final m = poly.length ~/ 2;
    for (var i = 0; i < m; i++) {
      final j = i + 1 == m ? 0 : i + 1;
      area += poly[2 * i] * poly[2 * j + 1] - poly[2 * j] * poly[2 * i + 1];
    }
    return area / 2;
  }

  /// One polygon for the points [a]..[b] (b > a): left side forward, end cap,
  /// right side backward, start cap (O4–O8).
  static Float32List _runPolygon(
    Float64List xs,
    Float64List ys,
    Float64List rs,
    Float64List dx,
    Float64List dy,
    int a,
    int b, {
    required bool squareStart,
    required bool squareEnd,
    required OutlineOptions options,
  }) {
    // O2 point tangents: the adjacent segment at the run ends.
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
        // > 0 unless sharpCornerCos <= −1 kept a full reversal in the run
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

    // O4 + O5 for one side (sign +1 = left, −1 = right), in point order.
    // (T22 B1: typed buffers instead of List<double>, and atan2 only on the
    // outer side of a bend that may need a round join — the same vertices.)
    _Coords side(double sign) {
      final v = _Coords(2 * count + 16);
      void add(int k, double x, double y) {
        if (k > 0 && k < count - 1) {
          final px = v.data[v.length - 2], py = v.data[v.length - 1];
          if ((x - px) * tx[k] + (y - py) * ty[k] < 0) return; // O5
        }
        v.add(x, y);
      }

      for (var k = 0; k < count; k++) {
        final i = a + k;
        final r = rs[i];
        if (k > 0 && k < count - 1) {
          // Outer side of a bend: a round join (points on the circle from the
          // normal of d_{i−1} to the normal of d_i) instead of the single
          // bisector point when the chord would be longer than capChordPt.
          final c = dx[i - 1] * dx[i] + dy[i - 1] * dy[i];
          final cross = dx[i - 1] * dy[i] - dy[i - 1] * dx[i];
          // |θ| ≤ π/2 · |sin θ| when cos θ > 0 (Jordan): a turn this small
          // gives segments ≤ 1 (the bisector point) without atan2.
          final small =
              c > 0 &&
              cross.abs() * (math.pi / 2) * r <= 0.999 * options.capChordPt;
          if ((cross > 0) == (sign < 0) && !small) {
            final theta = math.atan2(cross, c); // signed turn
            final segments = (theta.abs() * r / options.capChordPt).ceil();
            if (segments > 1) {
              final steps = math.min(
                segments,
                math.max(_minCapSegments, options.maxCapSegments),
              );
              // u0 = sign · n(d_{i−1}), rotated by theta · j / steps
              final ux = -dy[i - 1] * sign, uy = dx[i - 1] * sign;
              for (var j = 0; j <= steps; j++) {
                final phi = theta * j / steps;
                final cs = math.cos(phi), sn = math.sin(phi);
                add(
                  k,
                  xs[i] + (ux * cs - uy * sn) * r,
                  ys[i] + (ux * sn + uy * cs) * r,
                );
              }
              continue;
            }
          }
        }
        // n = (−τy, τx)
        add(k, xs[i] - ty[k] * r * sign, ys[i] + tx[k] * r * sign);
      }
      return v;
    }

    final left = side(1);
    final right = side(-1);
    final out = _Coords(left.length + right.length + 4 * _maxCapPoints(options))
      ..addAll(left);
    // O6 end cap: L_b → p_b + τ·r → R_b
    _cap(
      out,
      xs[b],
      ys[b],
      rs[b],
      tx[count - 1],
      ty[count - 1],
      forward: true,
      square: squareEnd,
      options: options,
    );
    for (var i = right.length - 2; i >= 0; i -= 2) {
      out.add(right.data[i], right.data[i + 1]);
    }
    // O6 start cap: R_a → p_a − τ·r → L_a
    _cap(
      out,
      xs[a],
      ys[a],
      rs[a],
      tx[0],
      ty[0],
      forward: false,
      square: squareStart,
      options: options,
    );

    final poly = Float32List(out.length)..setRange(0, out.length, out.data);
    _orientPositive(poly); // O7
    return _simplify(poly, rs, a, b, options); // O8
  }

  /// The cap vertices strictly between the two side points around (cx, cy).
  /// [forward]: the end cap (from L through +τ to R); otherwise the start cap
  /// (from R through −τ to L). [square]: the two corners at r · √2.
  static int _maxCapPoints(OutlineOptions options) =>
      math.max(_minCapSegments, options.maxCapSegments);

  static void _cap(
    _Coords out,
    double cx,
    double cy,
    double r,
    double tx,
    double ty, {
    required bool forward,
    required bool square,
    required OutlineOptions options,
  }) {
    // from (nx, ny) towards (fx, fy): forward +n → +τ, backward −n → −τ
    final s = forward ? 1.0 : -1.0;
    final nx = -ty * s, ny = tx * s;
    final fx = tx * s, fy = ty * s;
    if (square) {
      out
        ..add(cx + (nx + fx) * r, cy + (ny + fy) * r)
        ..add(cx + (fx - nx) * r, cy + (fy - ny) * r);
      return;
    }
    final segments = (math.pi * r / options.capChordPt).ceil().clamp(
      _minCapSegments,
      math.max(_minCapSegments, options.maxCapSegments),
    );
    for (var k = 1; k < segments; k++) {
      final phi = math.pi * k / segments;
      final c = math.cos(phi), sn = math.sin(phi);
      out.add(cx + (nx * c + fx * sn) * r, cy + (ny * c + fy * sn) * r);
    }
  }

  /// O8: RDP over the closed polygon. The tolerance never exceeds a quarter of
  /// the smallest radius of the run, so the thinnest strokes keep their shape;
  /// a result with fewer than 3 vertices keeps the polygon as it is. The kept
  /// vertices are a subset, so the bounds can only shrink (K-1 still holds).
  static Float32List _simplify(
    Float32List poly,
    Float64List rs,
    int a,
    int b,
    OutlineOptions options,
  ) {
    var minR = double.infinity;
    for (var i = a; i <= b; i++) {
      minR = math.min(minR, rs[i]);
    }
    final tol = math.min(options.simplifyTolerance, 0.25 * minR);
    final count = poly.length ~/ 2;
    if (!(tol > 0) || count < 4) return poly;
    final keep = List<bool>.filled(count, false);
    // rdpMark with the error segmentDistance(…) / tol, inlined (T22 B1: the
    // closure call was most of the outline time); the same arithmetic.
    keep[0] = true;
    keep[count - 1] = true;
    final belowTol2 = tol * tol * (1 - 1e-9);
    final stack = <int>[0, count - 1];
    while (stack.isNotEmpty) {
      final j = stack.removeLast();
      final i = stack.removeLast();
      if (j - i < 2) continue;
      final ax = poly[2 * i], ay = poly[2 * i + 1];
      final bx = poly[2 * j], by = poly[2 * j + 1];
      final dx = bx - ax, dy = by - ay;
      final len2 = dx * dx + dy * dy;
      var worst = 1.0;
      var at = -1;
      // sqrt and the division are monotonic: a squared distance not above
      // the best one so far (or below the tolerance with a margin) cannot
      // give a larger error, so only new maxima take sqrt.
      var best2 = belowTol2;
      for (var k = i + 1; k < j; k++) {
        final px = poly[2 * k], py = poly[2 * k + 1];
        var u = 0.0;
        if (len2 > 0) {
          u = ((px - ax) * dx + (py - ay) * dy) / len2;
          if (u < 0) u = 0;
          if (u > 1) u = 1;
        }
        final ex = px - (ax + u * dx), ey = py - (ay + u * dy);
        final d2 = ex * ex + ey * ey;
        if (d2 <= best2) continue;
        final e = math.sqrt(d2) / tol;
        if (e > worst) {
          worst = e;
          at = k;
          best2 = d2;
        }
      }
      if (at < 0) continue;
      keep[at] = true;
      stack
        ..add(i)
        ..add(at)
        ..add(at)
        ..add(j);
    }
    var kept = 0;
    for (final k in keep) {
      if (k) kept++;
    }
    if (kept == count || kept < 3) return poly;
    final out = Float32List(kept * 2);
    var o = 0;
    for (var i = 0; i < count; i++) {
      if (!keep[i]) continue;
      out[o++] = poly[2 * i];
      out[o++] = poly[2 * i + 1];
    }
    return out;
  }

  static void _orientPositive(Float32List poly) {
    if (signedArea(poly) >= 0) return;
    final m = poly.length ~/ 2;
    for (var i = 0, j = m - 1; i < j; i++, j--) {
      final x = poly[2 * i], y = poly[2 * i + 1];
      poly[2 * i] = poly[2 * j];
      poly[2 * i + 1] = poly[2 * j + 1];
      poly[2 * j] = x;
      poly[2 * j + 1] = y;
    }
  }

  static double _finite(double v) => v.isFinite ? v : 0;
}

/// A growable x,y buffer of doubles (no boxing).
final class _Coords {
  _Coords(int capacity) : data = Float64List(capacity < 8 ? 8 : capacity);

  Float64List data;
  int length = 0;

  void add(double x, double y) {
    if (length + 2 > data.length) _grow(length + 2);
    data[length++] = x;
    data[length++] = y;
  }

  void addAll(_Coords other) {
    if (length + other.length > data.length) _grow(length + other.length);
    data.setRange(length, length + other.length, other.data);
    length += other.length;
  }

  void _grow(int need) {
    var n = data.length * 2;
    while (n < need) {
      n *= 2;
    }
    data = Float64List(n)..setRange(0, length, data);
  }
}
