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

  group('6.17.5 review fixes', () {
    /// An ellipse a × b turned by [rot], [n] samples over [laps], then a
    /// rest of [hold] samples drifting by [drift] with ±[tremor] pt.
    List<Offset> ellipse(
      double a,
      double b, {
      double rot = 0.4,
      int n = 240,
      double laps = 1.04,
      double Function(double t)? radius,
      int hold = 0,
      Offset drift = Offset.zero,
      double tremor = 0,
    }) {
      final c = math.cos(rot), s = math.sin(rot);
      final pts = <Offset>[
        for (var i = 0; i <= n; i++)
          () {
            final t = laps * i / n;
            final k = radius?.call(t) ?? 1;
            final x = a * k * math.cos(2 * math.pi * t);
            final y = b * k * math.sin(2 * math.pi * t);
            return Offset(400 + x * c - y * s, 400 + x * s + y * c);
          }(),
      ];
      return _rest(pts, hold, drift, tremor);
    }

    test('a sloppy circle (axis ratio 0.85) stays a circle; 0.75 is an '
        'ellipse (circleMinAxisRatio 0.82)', () {
      expect(verdictOf(fitter.fit(ellipse(120, 102), viewScale: 1)), 'circle');
      expect(verdictOf(fitter.fit(ellipse(120, 90), viewScale: 1)), 'ellipse');
    });

    test('a thin box (aspect 0.1–0.2, any turn) is a rectangle; a thin '
        'ellipse stays an ellipse', () {
      for (final (w, h, rot) in [
        (300.0, 30.0, 0.0),
        (300.0, 20.0, 0.0),
        (260.0, 40.0, 0.5),
        (320.0, 36.0, -0.3),
      ]) {
        final c = math.cos(rot), s = math.sin(rot);
        final v = [
          for (final p in [
            Offset(-w / 2, -h / 2),
            Offset(w / 2, -h / 2),
            Offset(w / 2, h / 2),
            Offset(-w / 2, h / 2),
          ])
            Offset(400 + p.dx * c - p.dy * s, 400 + p.dx * s + p.dy * c),
        ];
        // Start in the middle of the top edge, 30 samples per 100 pt.
        final pts = <Offset>[];
        final path = [(v[0] + v[1]) / 2, v[1], v[2], v[3], v[0]];
        path.add(path.first);
        for (var i = 1; i < path.length; i++) {
          final m = ((path[i] - path[i - 1]).distance * 0.3).ceil();
          for (var k = 0; k < m; k++) {
            pts.add(Offset.lerp(path[i - 1], path[i], k / m)!);
          }
        }
        pts.add(path.last);
        final fit = fitter.fit(pts, viewScale: 1);
        expect(fit?.kind, core.ShapeKind.rectangle, reason: '$w×$h@$rot');
        final q = (fit!.geometry as core.PolylineGeometry).points;
        final sides = [
          for (var i = 0; i < 4; i++)
            (Offset(q[i].x, q[i].y) -
                    Offset(q[(i + 1) % 4].x, q[(i + 1) % 4].y))
                .distance,
        ]..sort();
        expect(sides.last, closeTo(w, 3), reason: '$w×$h@$rot');
        expect(sides.first, closeTo(h, 3), reason: '$w×$h@$rot');
      }
      for (final r in [0.1, 0.15, 0.25]) {
        expect(
          verdictOf(fitter.fit(ellipse(150, 150 * r), viewScale: 1)),
          'ellipse',
          reason: 'ratio $r',
        );
      }
    });

    test('a loose rest (a 6 pt drift, ±1.5 pt tremor — inside the 8 px '
        'hold radius) does not stop small or large shapes', () {
      const tri = [Offset(400, 370), Offset(430, 420), Offset(370, 420)];
      List<Offset> closed(List<Offset> v, int per) => [
        for (var i = 0; i < v.length; i++)
          for (var k = 0; k < per; k++)
            Offset.lerp(v[i], v[(i + 1) % v.length], k / per)!,
        v.first,
      ];
      for (final d in [
        const Offset(6, 0),
        const Offset(-4, 4),
        const Offset(0, -6),
      ]) {
        expect(
          fitter.fit(_rest(closed(tri, 30), 120, d, 1.5), viewScale: 1)?.kind,
          core.ShapeKind.triangle,
          reason: 'small triangle, drift $d',
        );
        expect(
          verdictOf(
            fitter.fit(
              ellipse(18, 12, hold: 120, drift: d, tremor: 1.5),
              viewScale: 1,
            ),
          ),
          'ellipse',
          reason: 'small ellipse, drift $d',
        );
        expect(
          fitter
              .fit(
                _rest(
                  [for (var i = 0; i <= 200; i++) Offset(100 + i * 1.5, 300)],
                  120,
                  d,
                  1.5,
                ),
                viewScale: 1,
              )
              ?.kind,
          core.ShapeKind.line,
          reason: 'line, drift $d',
        );
      }
    });

    test('triangle corners stay under the pen (not ~4 % inside)', () {
      const v = [Offset(400, 150), Offset(560, 430), Offset(230, 410)];
      final pts = <Offset>[
        for (var i = 0; i < 3; i++)
          for (var k = 0; k < 80; k++)
            Offset.lerp(v[i], v[(i + 1) % 3], k / 80)! +
                Offset(math.sin(i * 80 + k) * 0.8, math.cos(k * 1.7) * 0.8),
        v.first,
      ];
      final fit = fitter.fit(pts, viewScale: 1)!;
      expect(fit.kind, core.ShapeKind.triangle);
      final corners = (fit.geometry as core.PolylineGeometry).points;
      for (final c in v) {
        final nearest = corners
            .map((p) => (Offset(p.x, p.y) - c).distance)
            .reduce(math.min);
        // Before: the first corner sat 14 pt inside.
        expect(nearest, lessThan(2.5), reason: '$c');
      }
    });

    test('an unsteady ring (radius off by ±5 % at 40 points) is a circle', () {
      final rng = math.Random(5);
      final j = [for (var k = 0; k < 40; k++) rng.nextDouble() * 0.1 - 0.05];
      double radius(double t) {
        final x = (t % 1) * 40, k = x.floor() % 40, f = x - x.floor();
        return 1 + j[k] * (1 - f) + j[(k + 1) % 40] * f;
      }

      expect(
        verdictOf(fitter.fit(ellipse(110, 110, radius: radius), viewScale: 1)),
        'circle',
      );
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

/// [pts] then [hold] samples resting at its end: a drift of [drift] over the
/// rest and a deterministic tremor of ±[tremor] pt.
List<Offset> _rest(List<Offset> pts, int hold, Offset drift, double tremor) {
  final end = pts.last;
  return [
    ...pts,
    for (var k = 1; k <= hold; k++)
      end +
          drift * (k / hold) +
          Offset(math.sin(k * 2.3) * tremor, math.cos(k * 1.9) * tremor),
  ];
}
