// Shared body (VM + Chrome) of the shape fitter cases — m5-7/05-library
// 6.17.1–6.17.3 (V9), 8.2 L2-06. unit/shape_fitter_test.dart runs it on the
// VM, web/recognition_browser_test.dart on dart2js (L2-20): the same
// generator and the same fitter must clear the same thresholds there.
//
// The generator is the E-L2 one (03-recognition 4.2 conditions — the 7.3
// prototype's bin/eval.dart): 7 kinds × 200 strokes, size 80–300 pt, closed
// outlines start anywhere with −6 %…+8 % overshoot / gap, any rotation, a
// low-frequency wobble (1.5 % of the size) and Gaussian jitter (0.6 %).
// Random calls in the prototype's order, so seed 20261105 gives the 6.17.3
// table.
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/shapes/shape_classifier.dart'
    show resamplePath;
import 'package:ink_recognition/testing.dart';
import 'package:note_core/note_core.dart' as core;

/// The true kind of a synthetic stroke.
enum ShapeTruth {
  line,
  circle,
  ellipse,
  triangle,
  rectangle,
  pentagon,
  scribble,
}

/// What a fit says, in the truth's terms: `'none'` (stays ink), `'line'`,
/// `'circle'` (an ellipse with a square, unrotated frame), `'ellipse'`,
/// `'triangle'`, `'rectangle'`, `'polygon'`.
String verdictOf(ink.InkShapeFit? fit) {
  if (fit == null) return 'none';
  if (fit.kind == core.ShapeKind.ellipse) {
    final f = fit.geometry.frame;
    final square =
        f.rotation == 0 && (f.rect.width - f.rect.height).abs() < 1e-9;
    return square ? 'circle' : 'ellipse';
  }
  return fit.kind.name;
}

const Map<ShapeTruth, String> kExpectedVerdict = {
  ShapeTruth.line: 'line',
  ShapeTruth.circle: 'circle',
  ShapeTruth.ellipse: 'ellipse',
  ShapeTruth.triangle: 'triangle',
  ShapeTruth.rectangle: 'rectangle',
  ShapeTruth.pentagon: 'polygon',
  ShapeTruth.scribble: 'none',
};

/// V9 (8.2 L2-06): the least share judged right per kind (the pentagon has
/// no own threshold — only the 'wrong' cap).
const Map<ShapeTruth, double> kV9MinRight = {
  ShapeTruth.line: 0.85,
  ShapeTruth.circle: 0.98,
  ShapeTruth.ellipse: 0.85,
  ShapeTruth.triangle: 0.80,
  ShapeTruth.rectangle: 0.85,
  ShapeTruth.scribble: 0.90,
};

/// V9: the largest share turned into a WRONG shape per kind.
const double kV9MaxWrong = 0.10;

/// The seeded generator (one Random for the whole run, like the prototype).
final class SyntheticShapeGenerator {
  SyntheticShapeGenerator(int seed) : _rng = math.Random(seed);

  final math.Random _rng;

  double _u(double a, double b) => a + _rng.nextDouble() * (b - a);

  double _gauss() {
    final u1 = math.max(1e-12, _rng.nextDouble()), u2 = _rng.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  List<Offset> _outline(ShapeTruth t, double s) {
    List<Offset> poly(List<Offset> v) => [...v, v.first];
    switch (t) {
      case ShapeTruth.line:
        final bow = _u(-0.02, 0.02) * s;
        return [
          for (var i = 0; i <= 40; i++)
            Offset(-s / 2 + s * i / 40, bow * math.sin(math.pi * i / 40)),
        ];
      case ShapeTruth.circle:
        return [
          for (var i = 0; i <= 120; i++)
            Offset(
              s / 2 * math.cos(2 * math.pi * i / 120),
              s / 2 * math.sin(2 * math.pi * i / 120),
            ),
        ];
      case ShapeTruth.ellipse:
        final r = _u(0.4, 0.65);
        return [
          for (var i = 0; i <= 120; i++)
            Offset(
              s / 2 * math.cos(2 * math.pi * i / 120),
              r * s / 2 * math.sin(2 * math.pi * i / 120),
            ),
        ];
      case ShapeTruth.triangle:
        return poly([
          for (final d in [90.0, 210 + _u(-12, 12), 330 + _u(-12, 12)])
            Offset(
              s / 2 * math.cos(d * math.pi / 180),
              s / 2 * math.sin(d * math.pi / 180),
            ),
        ]);
      case ShapeTruth.rectangle:
        final h = s * _u(0.45, 1.0);
        return poly([
          Offset(-s / 2, -h / 2),
          Offset(s / 2, -h / 2),
          Offset(s / 2, h / 2),
          Offset(-s / 2, h / 2),
        ]);
      case ShapeTruth.pentagon:
        return poly([
          for (var k = 0; k < 5; k++)
            Offset(
              s / 2 * math.cos(2 * math.pi * k / 5 + _u(-0.08, 0.08)),
              s / 2 * math.sin(2 * math.pi * k / 5 + _u(-0.08, 0.08)),
            ),
        ]);
      case ShapeTruth.scribble:
        return [
          for (var i = 0; i <= 60; i++)
            Offset(
              s / 2 * math.sin(i * 0.37) + _u(-s / 6, s / 6),
              s / 3 * math.cos(i * 0.21) + _u(-s / 6, s / 6),
            ),
        ];
    }
  }

  /// One hand-like stroke of [t] (page pt around (500, 500)).
  List<Offset> stroke(ShapeTruth t) {
    final s = _u(80, 300);
    final dense = resamplePath(_outline(t, s), 200);
    final closed = t != ShapeTruth.line && t != ShapeTruth.scribble;
    final List<Offset> path;
    if (closed) {
      final loop = dense.sublist(0, dense.length - 1);
      final start = _rng.nextInt(loop.length);
      final extra = (_u(-0.06, 0.08) * loop.length).round();
      path = [
        for (var i = 0; i < loop.length + extra; i++)
          loop[(start + i) % loop.length],
      ];
    } else {
      path = dense;
    }
    final rot = _u(0, 2 * math.pi), c = math.cos(rot), sn = math.sin(rot);
    final wobA = 0.015 * s, wobF = _u(1, 3), wobP = _u(0, 6.28);
    return [
      for (var i = 0; i < path.length; i++)
        () {
          final p = path[i];
          final w =
              wobA * math.sin(wobF * 2 * math.pi * i / path.length + wobP);
          final x = p.dx + w + _gauss() * 0.006 * s;
          final y = p.dy + w + _gauss() * 0.006 * s;
          return Offset(500 + x * c - y * sn, 500 + x * sn + y * c);
        }(),
    ];
  }
}

/// Verdict counts per true kind.
typedef ShapeTally = Map<ShapeTruth, Map<String, int>>;

/// [perKind] strokes of every kind in the prototype's order (kind by kind),
/// judged by [fitter] at viewScale 1.
ShapeTally runShapeV9({
  required int seed,
  int perKind = 200,
  GeometricShapeFitter fitter = const GeometricShapeFitter(),
}) {
  final gen = SyntheticShapeGenerator(seed);
  final tally = <ShapeTruth, Map<String, int>>{};
  for (final t in ShapeTruth.values) {
    for (var i = 0; i < perKind; i++) {
      final verdict = verdictOf(fitter.fit(gen.stroke(t), viewScale: 1));
      (tally[t] ??= {}).update(verdict, (v) => v + 1, ifAbsent: () => 1);
    }
  }
  return tally;
}

/// Share judged right / turned into a wrong shape (a scribble that became
/// any shape is wrong; 'none' is not wrong for the other kinds).
({double right, double wrong}) sharesOf(ShapeTally tally, ShapeTruth t) {
  final m = tally[t] ?? const {};
  final total = m.values.fold(0, (a, b) => a + b);
  final right = m[kExpectedVerdict[t]] ?? 0;
  final none = t == ShapeTruth.scribble ? 0 : (m['none'] ?? 0);
  return (right: right / total, wrong: (total - right - none) / total);
}

/// One line per kind (the test log / the progress record).
String describeTally(ShapeTally tally) =>
    [for (final t in ShapeTruth.values) _describe(tally, t)].join('\n');

String _describe(ShapeTally tally, ShapeTruth t) {
  final s = sharesOf(tally, t);
  final right = (100 * s.right).toStringAsFixed(1);
  final wrong = (100 * s.wrong).toStringAsFixed(1);
  return '${t.name}: right $right %, wrong $wrong % ${tally[t]}';
}

/// V9 on seeds 20261105, 7 and 42 (VM and Chrome).
void defineShapeCaseTests() {
  group('shape cases (6.17, V9)', () {
    for (final seed in [20261105, 7, 42]) {
      test('1,400 synthetic strokes (seed $seed): every kind over its V9 '
          'threshold, at most 10 % turned into a wrong shape', () {
        final tally = runShapeV9(seed: seed);
        // The 6.17.3 table in the test log.
        // ignore: avoid_print
        print('seed $seed\n${describeTally(tally)}');
        for (final t in ShapeTruth.values) {
          final s = sharesOf(tally, t);
          final min = kV9MinRight[t];
          if (min != null) {
            expect(s.right, greaterThanOrEqualTo(min), reason: '${t.name} $s');
          }
          expect(
            s.wrong,
            lessThanOrEqualTo(kV9MaxWrong),
            reason: '${t.name} $s',
          );
        }
      });
    }

    test('SyntheticShapes.rectanglePath → a rectangle within 1 pt', () {
      const rect = Rect.fromLTWH(100, 100, 240, 160);
      final fit = const GeometricShapeFitter().fit(
        SyntheticShapes.rectanglePath(rect),
        viewScale: 1,
      )!;
      expect(fit.kind, core.ShapeKind.rectangle);
      final r = fit.geometry.frame.rect;
      expect(r.left, closeTo(100, 1));
      expect(r.top, closeTo(100, 1));
      expect(r.right, closeTo(340, 1));
      expect(r.bottom, closeTo(260, 1));
    });
  });
}
