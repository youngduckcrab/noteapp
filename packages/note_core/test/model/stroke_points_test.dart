import 'dart:math' as math;
import 'dart:typed_data';

import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

void main() {
  test('constants', () {
    expect(kMaxWidthFactor, 4.0);
    expect(kNominalWidthQ, 0.25);
    expect(StrokePoints.stride, 6);
    expect(StrokePoints.maxLength, 100000);
  });

  test('values are quantized on build (memory == decoded)', () {
    final p = StrokePoints.fromList(
      const [
        StrokePoint(
          1.23456,
          -2.34567,
          widthQ: 0.12345,
          tilt: 0.45678,
          azimuth: 1.23456,
          t: 3.14159,
        ),
      ],
      hasTilt: true,
      hasAzimuth: true,
    );
    expect(p.x(0), closeTo(1.23, 1e-6));
    expect(p.y(0), closeTo(-2.35, 1e-6));
    expect(p.widthQ(0), closeTo(0.123, 1e-6));
    expect(p.tilt(0), closeTo(0.457, 1e-6));
    expect(p.azimuth(0), closeTo(1.235, 1e-6));
    expect(p.t(0), closeTo(3.1, 1e-5));
    final again = StrokePointsCodec.decode(StrokePointsCodec.encode(p));
    expect(again.contentEquals(p), isTrue);
  });

  test('values are clamped', () {
    final p = StrokePoints.fromList(
      const [
        StrokePoint(99999, -99999, widthQ: 7, tilt: 9, azimuth: 4, t: 1e9),
      ],
      hasTilt: true,
      hasAzimuth: true,
    );
    expect(p.x(0), 32000);
    expect(p.y(0), -32000);
    expect(p.widthQ(0), 1);
    expect(p.tilt(0), closeTo(1.571, 1e-6));
    expect(p.azimuth(0), closeTo(4 - 2 * math.pi, 1e-3));
    expect(p.t(0), 500000);
  });

  test('without tilt / azimuth flags those channels are 0', () {
    final p = StrokePoints.fromList(const [
      StrokePoint(1, 1, tilt: 1, azimuth: 1),
    ]);
    expect(p.hasTilt, isFalse);
    expect(p.tilt(0), 0);
    expect(p.azimuth(0), 0);
    expect(p[0], const StrokePoint(1, 1));
  });

  test('fromList / fromInterleaved argument errors', () {
    expect(() => StrokePoints.fromList(const []), throwsArgumentError);
    expect(
      () => StrokePoints.fromInterleaved(Float32List(0)),
      throwsArgumentError,
    );
    expect(
      () => StrokePoints.fromInterleaved(Float32List(7)),
      throwsArgumentError,
    );
    expect(
      () => StrokePoints.fromInterleaved(
        Float32List((StrokePoints.maxLength + 1) * 6),
      ),
      throwsArgumentError,
    );
  });

  test('fromInterleaved copies and quantizes; rawData is read-only', () {
    final data = Float32List.fromList([
      1.001,
      2.004,
      0.3333,
      0.2,
      0.1,
      5.55,
      3,
      4,
      0.5,
      0,
      0,
      8.33,
    ]);
    final p = StrokePoints.fromInterleaved(data);
    expect(p.length, 2);
    expect(p.x(0), closeTo(1.0, 1e-6));
    expect(p.widthQ(0), closeTo(0.333, 1e-6));
    expect(p.tilt(0), 0, reason: 'hasTilt false');
    data[0] = 77;
    expect(p.x(0), closeTo(1.0, 1e-6), reason: 'input is copied');
    expect(p.rawData.length, 12);
    expect(() => p.rawData[0] = 5, throwsUnsupportedError);
  });

  test('pointBounds and maxWidthQ', () {
    final p = StrokePoints.fromList(const [
      StrokePoint(1, 5, widthQ: 0.2),
      StrokePoint(-3, 2, widthQ: 0.7),
      StrokePoint(4, 9, widthQ: 0.1),
    ]);
    expect(p.pointBounds, const PageRect(-3, 2, 4, 9));
    expect(p.maxWidthQ, closeTo(0.7, 1e-6));
    expect(p.points.length, 3);
  });

  test('sublist keeps flags and values', () {
    final p = StrokePoints.fromList([
      for (var i = 0; i < 10; i++) StrokePoint(i.toDouble(), 0, t: i * 10.0),
    ]);
    final s = p.sublist(3, 6);
    expect(s.length, 3);
    expect(s.x(0), 3);
    expect(s.t(0), 30, reason: 'fragments keep t');
    expect(p.sublist(8).length, 2);
    expect(() => p.sublist(4, 4), throwsArgumentError);
    expect(() => p.sublist(4, 20), throwsRangeError);
  });

  test('transformed moves points and rotates azimuth', () {
    final p = StrokePoints.fromList(
      const [StrokePoint(1, 0, widthQ: 0.4, tilt: 0.3, azimuth: 3.0, t: 7)],
      hasTilt: true,
      hasAzimuth: true,
    );
    final r = p.transformed(Affine2.rotation(math.pi / 2));
    expect(r.x(0), closeTo(0, 1e-6));
    expect(r.y(0), closeTo(1, 1e-6));
    expect(r.widthQ(0), p.widthQ(0));
    expect(r.tilt(0), p.tilt(0));
    expect(r.t(0), p.t(0));
    // 3.0 + pi/2 wraps into (-pi, pi]
    expect(r.azimuth(0), closeTo(3.0 + math.pi / 2 - 2 * math.pi, 1e-3));
    final noAz = StrokePoints.fromList(const [StrokePoint(1, 1)]);
    expect(noAz.transformed(Affine2.rotation(1)).azimuth(0), 0);
  });

  test('contentEquals and ==', () {
    final a = StrokePoints.fromList(const [
      StrokePoint(1, 2),
      StrokePoint(3, 4),
    ]);
    final b = StrokePoints.fromList(const [
      StrokePoint(1, 2),
      StrokePoint(3, 4),
    ]);
    final c = StrokePoints.fromList(const [
      StrokePoint(1, 2),
      StrokePoint(3, 5),
    ]);
    expect(a.contentEquals(b), isTrue);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a.contentEquals(c), isFalse);
    expect(
      a.contentEquals(
        StrokePoints.fromList(const [
          StrokePoint(1, 2),
          StrokePoint(3, 4),
        ], hasTilt: true),
      ),
      isFalse,
    );
  });

  group('StrokePointsBuilder', () {
    test('add, removeLast, build', () {
      final b = StrokePointsBuilder(hasTilt: true, initialCapacity: 1);
      for (var i = 0; i < 300; i++) {
        b.add(i.toDouble(), 0, tilt: 0.5, t: i.toDouble());
      }
      expect(b.length, 300);
      b.removeLast(100);
      expect(b.length, 200);
      final p = b.build();
      expect(p.length, 200);
      expect(p.hasTilt, isTrue);
      expect(p.tilt(199), 0.5);
      b.addPoint(const StrokePoint(9, 9, t: 1));
      expect(b.length, 201);
    });

    test('build of an empty builder throws StateError', () {
      expect(() => StrokePointsBuilder().build(), throwsStateError);
    });

    test('points beyond maxLength are ignored and isFull becomes true', () {
      final b = StrokePointsBuilder(initialCapacity: StrokePoints.maxLength);
      for (var i = 0; i < StrokePoints.maxLength + 5; i++) {
        b.add(0, 0, t: 0);
      }
      expect(b.length, StrokePoints.maxLength);
      expect(b.isFull, isTrue);
    });
  });
}
