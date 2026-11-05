// T05 (03-ink 8, 6.3, 6.7 F2): duplicate merge and centripetal Catmull-Rom
// subdivision of the centerline.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/stroke/centerline.dart';

/// MINSTD in [0, 1): deterministic, no bit operations.
final class _Noise {
  _Noise(this._s);
  int _s;
  double next() {
    _s = (_s * 48271) % 2147483647;
    return _s / 2147483647;
  }
}

double _maxGap(List<CenterPoint> pts) {
  var worst = 0.0;
  for (var i = 1; i < pts.length; i++) {
    worst = math.max(worst, (pts[i].position - pts[i - 1].position).distance);
  }
  return worst;
}

/// Every point of [original] appears in [out], the same object, in order.
void _expectPassesThrough(List<CenterPoint> out, List<CenterPoint> original) {
  var j = 0;
  for (final p in out) {
    if (j < original.length && identical(p, original[j])) j++;
  }
  expect(j, original.length, reason: 'all original samples kept in order');
}

InkSample _sample(double x, double y, int us) => InkSample(
  position: Offset(x, y),
  timeUs: us,
  kind: InkPointerKind.stylus,
  pressure: 0.5,
);

void main() {
  group('6.3 rule 2: duplicate merge', () {
    test('closer than 0.15 screen px and within 4 ms → duplicate', () {
      final a = _sample(10, 10, 0);
      expect(isDuplicateSample(a, _sample(10.1, 10, 3000), 1), isTrue);
      // 4 ms or later → a real sample even at the same spot
      expect(isDuplicateSample(a, _sample(10.1, 10, 4000), 1), isFalse);
      // far enough
      expect(isDuplicateSample(a, _sample(10.2, 10, 1000), 1), isFalse);
    });

    test('the distance is in screen px: viewScale 2 halves it in pt', () {
      final a = _sample(10, 10, 0);
      // 0.1 pt × 2 = 0.2 px ≥ 0.15
      expect(isDuplicateSample(a, _sample(10.1, 10, 1000), 2), isFalse);
      // 0.07 pt × 2 = 0.14 px < 0.15
      expect(isDuplicateSample(a, _sample(10.07, 10, 1000), 2), isTrue);
    });
  });

  test('maxSeg = clamp(0.5 · width, 0.75, 3.0)', () {
    expect(maxSegmentFor(1.6), closeTo(0.8, 1e-12));
    expect(maxSegmentFor(0.5), InkTuning.subdivideMinPt);
    expect(maxSegmentFor(12), InkTuning.subdivideMaxPt);
    expect(maxSegmentFor(30), 3.0);
  });

  test('random polylines: every gap ≤ maxSeg + 1e-6, samples kept', () {
    final noise = _Noise(1234);
    for (var trial = 0; trial < 200; trial++) {
      final n = 2 + (noise.next() * 30).floor();
      final pts = <CenterPoint>[];
      var x = 100.0, y = 100.0;
      for (var i = 0; i < n; i++) {
        pts.add(
          CenterPoint(
            x,
            y,
            factor: 0.5 + noise.next(),
            tilt: noise.next(),
            azimuth: (noise.next() * 2 - 1) * math.pi,
            t: i * 8.0,
          ),
        );
        // steps of 0 … 20 pt in any direction (sharp turns included)
        final step = noise.next() * 20;
        final a = noise.next() * 2 * math.pi;
        x += step * math.cos(a);
        y += step * math.sin(a);
      }
      final maxSeg = maxSegmentFor(0.1 + noise.next() * 8);
      final out = subdivide(pts, maxSeg);
      expect(_maxGap(out), lessThanOrEqualTo(maxSeg + 1e-6));
      _expectPassesThrough(out, pts);
      for (final p in out) {
        expect(p.x.isFinite && p.y.isFinite && p.factor.isFinite, isTrue);
      }
    }
  });

  test('inserted points interpolate every channel linearly', () {
    final a = CenterPoint(0, 0, factor: 1, tilt: 0.2, azimuth: 3, t: 0);
    final b = CenterPoint(10, 0, factor: 2, tilt: 0.6, azimuth: -3, t: 40);
    final out = subdivide([a, b], 1);
    expect(out.length, 11);
    for (var k = 1; k < out.length - 1; k++) {
      final p = out[k];
      // two points → reflected control points → a straight line
      expect(p.y, closeTo(0, 1e-9));
      final u = p.x / 10;
      expect(p.factor, closeTo(1 + u, 1e-9));
      expect(p.tilt, closeTo(0.2 + 0.4 * u, 1e-9));
      expect(p.t, closeTo(40 * u, 1e-9));
      // azimuth on the shortest arc through ±π, not through 0
      expect(p.azimuth.abs(), greaterThan(2.9));
      expect(out[k].t, greaterThan(out[k - 1].t));
    }
  });

  test('a curve is followed: inserted points lie near the circle', () {
    // samples every 30° on a circle of radius 20
    final pts = [
      for (var i = 0; i <= 12; i++)
        CenterPoint(
          20 * math.cos(i * math.pi / 6),
          20 * math.sin(i * math.pi / 6),
          t: i * 10.0,
        ),
    ];
    final out = subdivide(pts, 1);
    expect(_maxGap(out), lessThanOrEqualTo(1 + 1e-6));
    for (final p in out) {
      final deg = math.atan2(p.y, p.x) * 180 / math.pi;
      final r = p.position.distance;
      if (deg.abs() > 30) {
        // the chord midpoints would be at 19.32; Catmull-Rom stays close to 20
        expect(r, closeTo(20, 0.05), reason: 'at $deg°');
      } else {
        // first / last segment: reflected control point (no end curvature),
        // between the chord and the circle
        expect(r, inInclusiveRange(19.3, 20.05), reason: 'at $deg°');
      }
    }
  });

  test('coincident points and short gaps: no NaN, nothing inserted', () {
    final pts = [
      CenterPoint(0, 0),
      CenterPoint(0, 0),
      CenterPoint(0.5, 0),
      CenterPoint(0.5, 0),
      CenterPoint(8, 0),
      CenterPoint(8, 0),
    ];
    final out = subdivide(pts, 0.75);
    expect(_maxGap(out), lessThanOrEqualTo(0.75 + 1e-6));
    for (final p in out) {
      expect(p.x.isNaN || p.y.isNaN, isFalse);
    }
    expect(subdivide([CenterPoint(1, 1)], 1).length, 1);
    expect(subdivide(const [], 1), isEmpty);
    final near = [CenterPoint(0, 0), CenterPoint(0.5, 0)];
    expect(subdivide(near, 0.75).length, 2);
  });
}
