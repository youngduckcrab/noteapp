// Internal (not exported). Seeded synthetic pen points for test devices (4.11): built with
// CORE StrokePointsBuilder and encoded with StrokePointsCodec, so every value is already
// quantized like real input.
import 'dart:math';

import 'package:note_core/note_core.dart';

/// [count] points (1..StrokePoints.maxLength) of a wavy line; the same [seed] gives the
/// same points.
StrokePoints syntheticPoints({int seed = 0, int count = 100}) {
  if (count < 1 || count > StrokePoints.maxLength) {
    throw RangeError.range(count, 1, StrokePoints.maxLength, 'count');
  }
  final random = Random(seed);
  final b = StrokePointsBuilder(initialCapacity: count);
  var x = 40 + random.nextDouble() * 400;
  var y = 40 + random.nextDouble() * 700;
  var t = 0.0;
  for (var i = 0; i < count; i++) {
    b.add(x, y, widthQ: 0.3 + random.nextDouble() * 0.6, t: t);
    x += 0.5 + random.nextDouble() * 2.5;
    y += (random.nextDouble() - 0.5) * 3;
    t += 4 + random.nextDouble() * 6;
  }
  return b.build();
}

/// Base64 wire form of [syntheticPoints] (the stroke JSON `points` value, CORE 6.3).
String syntheticPointsBase64({int seed = 0, int count = 100}) =>
    StrokePointsCodec.encodeBase64(syntheticPoints(seed: seed, count: count));
