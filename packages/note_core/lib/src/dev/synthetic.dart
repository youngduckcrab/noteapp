// Internal: deterministic handwriting-like strokes (CORE 6.2.4 '합성 필기 생성기'). Shared
// by StrokeFixtures (testing.dart) and seedSyntheticNote (dev_tools.dart).
import 'dart:math' as math;

import '../common/ids.dart';
import '../model/pen_style.dart';
import '../model/stroke.dart';
import '../model/stroke_points.dart';

final class _Gauss {
  _Gauss(this.random);
  final math.Random random;
  double? _spare;

  /// N(0, sigma) by Box-Muller.
  double next(double sigma) {
    final spare = _spare;
    if (spare != null) {
      _spare = null;
      return spare * sigma;
    }
    var u = 0.0;
    while (u <= 1e-12) {
      u = random.nextDouble();
    }
    final v = random.nextDouble();
    final r = math.sqrt(-2 * math.log(u));
    _spare = r * math.sin(2 * math.pi * v);
    return r * math.cos(2 * math.pi * v) * sigma;
  }
}

double _uniform(math.Random r, double lo, double hi) =>
    lo + r.nextDouble() * (hi - lo);

/// Points of one synthetic stroke (seeded, reproducible on every platform).
StrokePoints syntheticPoints({
  required int seed,
  int pointCount = 100,
  double hz = 120,
  bool hasTilt = true,
}) {
  final random = math.Random(seed);
  final g = _Gauss(random);
  var x = _uniform(random, 50, 500);
  var y = _uniform(random, 50, 700);
  var heading = _uniform(random, 0, 2 * math.pi);
  var speed = _uniform(random, 30, 150); // pt/s
  var widthQ = _uniform(random, 0.2, 0.3);
  var tilt = _uniform(random, 0.3, 0.9);
  var azimuth = _uniform(random, -3, 3);
  var t = 0.0;
  final b = StrokePointsBuilder(
    hasTilt: hasTilt,
    hasAzimuth: hasTilt,
    initialCapacity: pointCount,
  );
  for (var i = 0; i < pointCount; i++) {
    b.add(x, y, widthQ: widthQ, tilt: tilt, azimuth: azimuth, t: t);
    final dt = math.max(0.1, 1000 / hz + g.next(0.3));
    heading += g.next(0.12);
    speed = math.max(10, speed + g.next(8));
    x += math.cos(heading) * speed * dt / 1000;
    y += math.sin(heading) * speed * dt / 1000;
    widthQ = (widthQ + g.next(0.003)).clamp(0.05, 1.0);
    tilt = (tilt + g.next(0.003)).clamp(0.0, math.pi / 2);
    azimuth += g.next(0.004);
    t += dt;
  }
  return b.build();
}

Stroke syntheticStroke({
  required PageId pageId,
  required IdGenerator ids,
  int seed = 0,
  int pointCount = 100,
  double hz = 120,
  PenTool tool = PenTool.ballpoint,
  EpochMillis createdAt = 0,
  bool hasTilt = true,
}) => Stroke(
  id: ids.newId(),
  pageId: pageId,
  style: StrokeStyle.defaultsFor(tool).normalized(),
  points: syntheticPoints(
    seed: seed,
    pointCount: pointCount,
    hz: hz,
    hasTilt: hasTilt,
  ),
  createdAt: createdAt,
);
