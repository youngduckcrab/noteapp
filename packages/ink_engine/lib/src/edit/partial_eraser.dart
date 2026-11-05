// lib/src/edit/partial_eraser.dart — INTERNAL (03-ink 6.20 P2–P6, INK T16).
//
// Vector split of strokes by the eraser capsules of one gesture:
//  P2 per segment, the minimum u* of the convex g(u) (6.18, golden section);
//     g(u*) > 0 → no cut;
//  P3 otherwise the zeros of g in [0, u*] and [u*, 1] by bisection
//     (InkTuning.bisectionIterations), taken on the OUTSIDE (g > 0) so a kept
//     point is never inside the eraser; a segment end already inside stays;
//  P4 the cuts as intervals of the fractional index s = i + u, accumulated
//     per original for the whole gesture and merged (ε 1e-6);
//  P5 the kept pieces = the complement in [0, n − 1]: lerpAt(a), the original
//     points a < k < b, lerpAt(b) — every channel interpolated;
//  P6 pieces shorter than max(0.3 pt, 0.25 · width) are dropped; a dot stroke
//     that is touched is erased whole.
// P7 / P8 (CORE fragments, the InkEdit) live in the eraser session.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

import '../model/ink_points.dart';
import '../model/ink_stroke.dart';
import '../tuning.dart';
import 'hit_test.dart';

/// A closed interval of the fractional point index s (s = i + u).
@internal
@immutable
final class ParamInterval {
  const ParamInterval(this.start, this.end);

  final double start;
  final double end;

  double get length => end - start;

  @override
  bool operator ==(Object other) =>
      other is ParamInterval && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'ParamInterval($start, $end)';
}

@internal
final class PartialEraser {
  PartialEraser(this.radius);

  /// Merge tolerance of P4 (fractional index).
  static const double mergeEpsilon = 1e-6;

  /// The eraser radius R (pt).
  final double radius;

  // insertion order = first touch
  final Map<String, List<ParamInterval>> _erased = {};
  final Map<String, InkStroke> _strokes = {};

  /// Ids of the originals cut so far (first touch first).
  Iterable<String> get touchedIds => _erased.keys;

  /// The merged erased intervals of [id] (empty if untouched).
  List<ParamInterval> erasedOf(String id) =>
      List.unmodifiable(_erased[id] ?? const <ParamInterval>[]);

  /// The original of [id] as it was when first touched.
  InkStroke? strokeOf(String id) => _strokes[id];

  void clear() {
    _erased.clear();
    _strokes.clear();
  }

  /// P2–P4 for the capsule a → b (a == b: a disc). True if the erased set of
  /// [s] grew.
  bool addCapsule(InkStroke s, Offset a, Offset b) {
    final found = cutsOf(s, a, b, radius);
    if (found.isEmpty) return false;
    final before = _erased[s.id];
    final merged = mergeIntervals([...?before, ...found]);
    if (before != null && _same(before, merged)) return false;
    _erased[s.id] = merged;
    _strokes.putIfAbsent(s.id, () => s);
    return true;
  }

  /// P5 + P6: the interleaved point data of the kept pieces of [id], in
  /// order along the stroke; empty if the stroke goes away entirely.
  List<Float32List> piecesOf(String id) {
    final s = _strokes[id];
    final erased = _erased[id];
    if (s == null || erased == null) return const [];
    final p = s.points;
    if (p.length == 0 || s.isDot) return const [];
    final minLength = minPieceLength(s.style);
    return [
      for (final keep in complement(erased, (p.length - 1).toDouble()))
        if (pieceData(p, keep) case final data
            when arcLengthOf(data) >= minLength)
          data,
    ];
  }

  /// P2 / P3: the parameter intervals of [s] inside the capsule a → b of
  /// [radius] (one per cut segment, not merged).
  static List<ParamInterval> cutsOf(
    InkStroke s,
    Offset a,
    Offset b,
    double radius,
  ) {
    final p = s.points;
    final n = p.length;
    if (n == 0 || !(radius >= 0) || !a.isFinite || !b.isFinite) {
      return const [];
    }
    if (s.isDot) {
      return InkHitTest.capsuleTouches(s, a, b, radius)
          ? [ParamInterval(0, (n - 1).toDouble())]
          : const [];
    }
    final left = math.min(a.dx, b.dx) - radius;
    final right = math.max(a.dx, b.dx) + radius;
    final top = math.min(a.dy, b.dy) - radius;
    final bottom = math.max(a.dy, b.dy) + radius;
    final out = <ParamInterval>[];
    // A first cut with the stroke's largest radius (T22 B5) — it never drops
    // a segment the per-segment test below would keep.
    final rMax = s.maxRadius;
    for (var i = 0; i + 1 < n; i++) {
      final x0 = p.x(i), y0 = p.y(i), x1 = p.x(i + 1), y1 = p.y(i + 1);
      if ((x0 < x1 ? x0 : x1) - rMax > right ||
          (x0 > x1 ? x0 : x1) + rMax < left ||
          (y0 < y1 ? y0 : y1) - rMax > bottom ||
          (y0 > y1 ? y0 : y1) + rMax < top) {
        continue;
      }
      final r0 = s.radiusAt(i), r1 = s.radiusAt(i + 1);
      final rm = math.max(r0, r1);
      if (math.min(x0, x1) - rm > right ||
          math.max(x0, x1) + rm < left ||
          math.min(y0, y1) - rm > bottom ||
          math.max(y0, y1) + rm < top) {
        continue;
      }
      double g(double u) =>
          InkHitTest.capsuleGapAt(u, x0, y0, r0, x1, y1, r1, a, b, radius);
      final m = InkHitTest.minimize(g);
      if (m.gap > 0) continue;
      final u0 = g(0) <= 0 ? 0.0 : _outsideZero(g, 0, m.u);
      final u1 = g(1) <= 0 ? 1.0 : _outsideZero(g, 1, m.u);
      out.add(ParamInterval(i + u0, i + u1));
    }
    return out;
  }

  /// Bisection between [outside] (g > 0) and [inside] (g ≤ 0); returns the
  /// last outside point (P3: precision = segment / 2^iterations).
  static double _outsideZero(
    double Function(double u) g,
    double outside,
    double inside,
  ) {
    var o = outside, i = inside;
    for (var k = 0; k < InkTuning.bisectionIterations; k++) {
      final mid = (o + i) / 2;
      if (g(mid) <= 0) {
        i = mid;
      } else {
        o = mid;
      }
    }
    return o;
  }

  /// P4: sorted union; intervals closer than [mergeEpsilon] join.
  static List<ParamInterval> mergeIntervals(List<ParamInterval> intervals) {
    if (intervals.isEmpty) return const [];
    final sorted = [...intervals]
      ..sort((x, y) {
        final c = x.start.compareTo(y.start);
        return c != 0 ? c : x.end.compareTo(y.end);
      });
    final out = <ParamInterval>[];
    var cur = sorted.first;
    for (final next in sorted.skip(1)) {
      if (next.start <= cur.end + mergeEpsilon) {
        if (next.end > cur.end) cur = ParamInterval(cur.start, next.end);
      } else {
        out.add(cur);
        cur = next;
      }
    }
    out.add(cur);
    return out;
  }

  /// P5: the parts of [0, last] outside the merged [erased] (empty parts
  /// left out).
  static List<ParamInterval> complement(
    List<ParamInterval> erased,
    double last,
  ) {
    final out = <ParamInterval>[];
    var from = 0.0;
    for (final e in erased) {
      final end = math.min(e.start, last);
      if (end > from) out.add(ParamInterval(from, end));
      if (e.end > from) from = e.end;
    }
    if (last > from) out.add(ParamInterval(from, last));
    return out;
  }

  /// P5: lerpAt(a), the original points with a < k < b, lerpAt(b) as
  /// interleaved core.StrokePoints data (stride 6).
  static Float32List pieceData(InkPoints p, ParamInterval keep) {
    const stride = InkPoints.stride;
    final a = keep.start, b = keep.end;
    final first = a.floor() + 1;
    var count = 0; // the original points k with a < k < b: first, first + 1, …
    for (var k = first; k < b; k++) {
      count++;
    }
    final data = Float32List((count + 2) * stride);
    void put(int slot, core.StrokePoint q) {
      final o = slot * stride;
      data[o] = q.x;
      data[o + 1] = q.y;
      data[o + 2] = q.widthQ;
      data[o + 3] = q.tilt;
      data[o + 4] = q.azimuth;
      data[o + 5] = q.t;
    }

    put(0, p.lerpAt(a));
    data.setRange(stride, (count + 1) * stride, p.raw, first * stride);
    put(count + 1, p.lerpAt(b));
    return data;
  }

  /// Centerline length of interleaved point data.
  static double arcLengthOf(Float32List data) {
    const stride = InkPoints.stride;
    var sum = 0.0;
    for (var o = stride; o + 1 < data.length; o += stride) {
      final dx = data[o] - data[o - stride];
      final dy = data[o + 1] - data[o + 1 - stride];
      sum += math.sqrt(dx * dx + dy * dy);
    }
    return sum;
  }

  /// P6: pieces shorter than this are dropped.
  static double minPieceLength(core.StrokeStyle style) => math.max(
    InkTuning.minPieceLengthPt,
    InkTuning.minPieceWidthRatio * style.width,
  );

  static bool _same(List<ParamInterval> x, List<ParamInterval> y) {
    if (x.length != y.length) return false;
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }
}
