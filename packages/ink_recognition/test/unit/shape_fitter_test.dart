// L2-06 (m5-7/05-library 8.2, 6.17.1, 6.17.3, 6.24): GeometricShapeFitter —
// V9 on 1,400 synthetic strokes for seeds 20261105, 7 and 42 (the shared
// body, also on Chrome), the guards (fewer than 4 points, a small stroke at
// its viewScale, NaN / infinity → null, never throws), score and minScore,
// and the time of one fit (6.24: ≤ 0.5 ms VM median — recorded, the assert
// is loose because six other agents share the machine).
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/testing.dart';
import 'package:material_ui/material_ui.dart' show Rect;
import 'package:note_core/note_core.dart' as core;

import '../shared/shape_cases.dart';

void main() {
  defineShapeCaseTests();

  const fitter = GeometricShapeFitter();
  final square = SyntheticShapes.rectanglePath(
    const Rect.fromLTWH(100, 100, 120, 120),
  );

  group('guards (6.17.1 step 1, 6.17.2 last line)', () {
    test('fewer than 4 points → null', () {
      expect(
        fitter.fit(const [
          Offset.zero,
          Offset(100, 0),
          Offset(200, 0),
        ], viewScale: 1),
        isNull,
      );
    });

    test('bounds diagonal × viewScale < 24 → null (dots, small letters); '
        'the same path at a larger viewScale fits', () {
      final small = SyntheticShapes.rectanglePath(
        const Rect.fromLTWH(0, 0, 48, 48),
      ); // diagonal 67.9 pt
      expect(fitter.fit(small, viewScale: 0.25), isNull); // 17 px
      expect(fitter.fit(small, viewScale: 0.35), isNull); // 23.8 px
      expect(fitter.fit(small, viewScale: 1)?.kind, core.ShapeKind.rectangle);
      final tick = [for (var i = 0; i < 10; i++) Offset(10.0 + i, 10.0 + i)];
      expect(fitter.fit(tick, viewScale: 1), isNull); // 12.7 pt
      expect(fitter.fit(tick, viewScale: 2)?.kind, core.ShapeKind.line);
    });

    test('NaN / infinite coordinates or viewScale → null, no exception', () {
      for (final bad in [double.nan, double.infinity, -double.infinity]) {
        final pts = [...square]..[5] = Offset(bad, 3);
        expect(fitter.fit(pts, viewScale: 1), isNull);
        expect(fitter.fit(square, viewScale: bad), isNull);
      }
      expect(fitter.fit(square, viewScale: 0), isNull);
      expect(fitter.fit(square, viewScale: -1), isNull);
    });

    test('degenerate input → null, no exception', () {
      final same = List.filled(50, const Offset(100, 100));
      expect(fitter.fit(same, viewScale: 1), isNull);
      final back = [
        for (var i = 0; i < 40; i++)
          Offset(100.0 + (i < 20 ? i : 40 - i) * 5, 100),
      ];
      expect(() => fitter.fit(back, viewScale: 1), returnsNormally);
    });
  });

  group('score and tuning', () {
    test('score = clamp(1 − error ÷ threshold, 0, 1) — in (0, 1] for an '
        'exact rectangle and a straight line', () {
      final rect = fitter.fit(square, viewScale: 1)!;
      expect(rect.score, greaterThan(0));
      expect(rect.score, lessThanOrEqualTo(1));
      final line = fitter.fit([
        for (var i = 0; i <= 20; i++) Offset(100.0 + 10 * i, 100),
      ], viewScale: 1)!;
      expect(line.score, closeTo(1, 1e-9)); // no deviation at all
    });

    test('minScore above every score → null', () {
      const strict = GeometricShapeFitter(
        tuning: ShapeFitTuning(minScore: 1.01),
      );
      expect(strict.fit(square, viewScale: 1), isNull);
    });

    test('a scribble stays ink', () {
      final gen = SyntheticShapeGenerator(3);
      var none = 0;
      for (var i = 0; i < 20; i++) {
        if (fitter.fit(gen.stroke(ShapeTruth.scribble), viewScale: 1) == null) {
          none++;
        }
      }
      expect(none, greaterThanOrEqualTo(16));
    });
  });

  group('6.17.5 (hand-drawn corpus findings)', () {
    /// [v] closed, 40 samples per edge, starting at v.first, then [hold]
    /// samples of tremor (±0.6 pt) round the last point.
    List<Offset> outline(List<Offset> v, {int hold = 0}) {
      final pts = <Offset>[
        for (var i = 0; i < v.length; i++)
          for (var k = 0; k < 40; k++)
            Offset.lerp(v[i], v[(i + 1) % v.length], k / 40)!,
        v.first,
      ];
      for (var k = 0; k < hold; k++) {
        pts.add(
          v.first + Offset(k.isEven ? 0.6 : -0.6, k % 3 == 0 ? 0.5 : -0.4),
        );
      }
      return pts;
    }

    const tri = [Offset(300, 100), Offset(420, 320), Offset(180, 320)];

    test('a triangle started at a corner (the closing turn counts) → a '
        'triangle, also with a 60-sample hold tail', () {
      expect(
        fitter.fit(outline(tri), viewScale: 1)?.kind,
        core.ShapeKind.triangle,
      );
      expect(
        fitter.fit(outline(tri, hold: 60), viewScale: 1)?.kind,
        core.ShapeKind.triangle,
      );
    });

    test('an ellipse of axis ratio 0.75 stays an ellipse (not a circle); a '
        'drawn-over close does not matter', () {
      final e = [
        for (var i = 0; i <= 140; i++)
          Offset(
            400 + 120 * math.cos(2 * math.pi * i / 120 + 0.3),
            400 + 90 * math.sin(2 * math.pi * i / 120 + 0.3),
          ),
      ];
      expect(verdictOf(fitter.fit(e, viewScale: 1)), 'ellipse');
    });

    test('two laps of a circle stay ink', () {
      final twice = [
        for (var i = 0; i <= 240; i++)
          Offset(
            400 + 100 * math.cos(2 * math.pi * i / 120),
            400 + 100 * math.sin(2 * math.pi * i / 120),
          ),
      ];
      expect(fitter.fit(twice, viewScale: 1), isNull);
    });
  });

  test('one fit ≤ 0.5 ms (6.24 — VM median, recorded)', () {
    final gen = SyntheticShapeGenerator(20261105);
    final strokes = [
      for (final t in ShapeTruth.values)
        for (var i = 0; i < 20; i++) gen.stroke(t),
    ];
    for (final s in strokes.take(40)) {
      fitter.fit(s, viewScale: 1); // warm up
    }
    final times = <int>[];
    final sw = Stopwatch();
    for (final s in strokes) {
      sw
        ..reset()
        ..start();
      fitter.fit(s, viewScale: 1);
      times.add(sw.elapsedMicroseconds);
    }
    times.sort();
    final median = times[times.length ~/ 2];
    // ignore: avoid_print
    print('fit median $median µs, max ${times.last} µs (${times.length})');
    expect(median, lessThan(1500)); // 3× the 0.5 ms target (shared machine)
  });
}
