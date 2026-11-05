// T02 (03-ink 8, 4.1): InkPoints is a zero-copy, read-only view over
// core.StrokePoints.rawData (K-2).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:note_core/note_core.dart' as core;

core.StrokePoints _points(List<core.StrokePoint> list) =>
    core.StrokePoints.fromList(list, hasTilt: true, hasAzimuth: true);

void main() {
  final p = _points(const [
    core.StrokePoint(10, 20, widthQ: 0.2, tilt: 0.3, azimuth: 3.0, t: 0),
    core.StrokePoint(13, 24, widthQ: 0.4, tilt: 0.5, azimuth: -3.0, t: 8),
    core.StrokePoint(13, 30, widthQ: 0.6, tilt: 0.1, azimuth: 1.0, t: 16.5),
  ]);

  group('zero copy (K-2)', () {
    test('fromRaw wraps the buffer itself', () {
      final buf = Float32List.fromList([1, 2, 0.25, 0, 0, 0]);
      final v = InkPoints.fromRaw(buf);
      expect(identical(v.raw, buf), isTrue);
    });

    test('of(points) keeps the CORE view: no copy, no writes', () {
      final v = InkPoints.of(p);
      // Debug and test runs: CORE hands out an unmodifiable view of its own
      // buffer (a fresh view per rawData call, so identical() holds only in
      // release). A copy made by INK would be writable.
      expect(() => v.raw[0] = 99, throwsUnsupportedError);
      expect(v.raw, orderedEquals(p.rawData));
      expect(v.raw.lengthInBytes, p.rawData.lengthInBytes);
      // Reading every channel leaves the CORE values unchanged.
      final before = Float32List.fromList(p.rawData);
      for (var i = 0; i < v.length; i++) {
        v[i];
        v.lerpAt(i + 0.5);
      }
      v.arcLength();
      v.cumulativeLengths();
      expect(p.rawData, orderedEquals(before));
    });

    test('InkStroke keeps one InkPoints per stroke', () {
      final s = InkStroke.of(
        core.Stroke(
          id: 's1',
          pageId: 'p1',
          style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
          points: p,
          createdAt: 1,
        ),
      );
      expect(identical(s.points, s.points), isTrue);
      expect(identical(s.points.raw, s.points.raw), isTrue);
    });

    test('a length that is not a positive multiple of 6 is rejected', () {
      expect(() => InkPoints.fromRaw(Float32List(0)), throwsArgumentError);
      expect(() => InkPoints.fromRaw(Float32List(7)), throwsArgumentError);
    });
  });

  test('channel reads match CORE', () {
    final v = InkPoints.of(p);
    expect(InkPoints.stride, core.StrokePoints.stride);
    expect(v.length, p.length);
    expect(v.isEmpty, isFalse);
    for (var i = 0; i < p.length; i++) {
      expect(v.x(i), p.x(i));
      expect(v.y(i), p.y(i));
      expect(v.widthQ(i), p.widthQ(i));
      expect(v.tilt(i), p.tilt(i));
      expect(v.azimuth(i), p.azimuth(i));
      expect(v.t(i), p.t(i));
      expect(v.offsetAt(i), Offset(p.x(i), p.y(i)));
      expect(v[i], p[i]);
    }
  });

  group('lerpAt', () {
    final v = InkPoints.of(p);

    test('integer index = operator []', () {
      for (var i = 0; i < v.length; i++) {
        expect(v.lerpAt(i.toDouble()), v[i]);
      }
    });

    test('interpolates every channel linearly', () {
      final m = v.lerpAt(1.25);
      expect(m.x, closeTo(13, 1e-6));
      expect(m.y, closeTo(24 + 0.25 * 6, 1e-5));
      expect(m.widthQ, closeTo(0.4 + 0.25 * 0.2, 1e-6));
      expect(m.tilt, closeTo(0.5 - 0.25 * 0.4, 1e-6));
      expect(m.t, closeTo(8 + 0.25 * 8.5, 1e-5));
    });

    test('boundaries clamp to the first / last point', () {
      expect(v.lerpAt(-3), v[0]);
      expect(v.lerpAt(double.nan), v[0]);
      expect(v.lerpAt(2), v[2]);
      expect(v.lerpAt(9.5), v[2]);
      final single = InkPoints.of(
        _points(const [core.StrokePoint(1, 2, widthQ: 0.5)]),
      );
      expect(single.lerpAt(0), single[0]);
      expect(single.lerpAt(0.7), single[0]);
    });

    test('azimuth takes the shortest arc and stays in (-pi, pi]', () {
      // 3.0 → -3.0 crosses ±pi: the short way is +0.283 rad, not -6 rad.
      final a0 = v.azimuth(0), a1 = v.azimuth(1);
      final short = a1 - a0 + 2 * math.pi;
      final quarter = v.lerpAt(0.25).azimuth;
      expect(quarter, closeTo(a0 + 0.25 * short, 1e-5));
      for (var k = 0; k <= 20; k++) {
        final az = v.lerpAt(k / 20).azimuth;
        expect(az, greaterThan(-math.pi));
        expect(az, lessThanOrEqualTo(math.pi));
        // Never passes through 0 (the long way).
        expect(az.abs(), greaterThan(2.9));
      }
      // Normal case (no wrap): plain linear.
      final b = v.lerpAt(1.5).azimuth;
      final a2 = v.azimuth(2);
      var d = a2 - a1;
      if (d > math.pi) d -= 2 * math.pi;
      if (d < -math.pi) d += 2 * math.pi;
      var expected = a1 + 0.5 * d;
      if (expected <= -math.pi) expected += 2 * math.pi;
      expect(b, closeTo(expected, 1e-5));
    });
  });

  test('arcLength and cumulativeLengths', () {
    final v = InkPoints.of(
      _points(const [
        core.StrokePoint(0, 0),
        core.StrokePoint(3, 4),
        core.StrokePoint(3, 10),
        core.StrokePoint(3, 10),
      ]),
    );
    expect(v.arcLength(), closeTo(11, 1e-9));
    final c = v.cumulativeLengths();
    expect(c, isA<Float64List>());
    expect(c, hasLength(4));
    expect(c[0], 0);
    expect(c[1], closeTo(5, 1e-9));
    expect(c[2], closeTo(11, 1e-9));
    expect(c[3], closeTo(11, 1e-9));
    final one = InkPoints.of(_points(const [core.StrokePoint(5, 5)]));
    expect(one.arcLength(), 0);
    expect(one.cumulativeLengths(), [0]);
  });
}
