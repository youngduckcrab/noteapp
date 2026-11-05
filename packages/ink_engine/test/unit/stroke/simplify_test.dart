// T05 (03-ink 8, 6.7 F7): finish simplification (RDP 0.03 pt + widthQ rule,
// retries above core.StrokePoints.maxLength).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/stroke/simplify.dart';
import 'package:note_core/note_core.dart' as core;

const _stride = core.StrokePoints.stride;

/// Interleaved data from (x, y, widthQ) triples; tilt 0, azimuth 0, t = i ms.
Float32List _data(List<(double, double, double)> pts) {
  final d = Float32List(pts.length * _stride);
  for (var i = 0; i < pts.length; i++) {
    final (x, y, q) = pts[i];
    d
      ..[i * _stride] = x
      ..[i * _stride + 1] = y
      ..[i * _stride + 2] = q
      ..[i * _stride + 5] = i.toDouble();
  }
  return d;
}

int _count(Float32List d) => d.length ~/ _stride;

/// The output rows are rows of the input, in order (by t = index).
void _expectSubset(Float32List out, Float32List input) {
  var prev = -1.0;
  for (var o = 0; o < out.length; o += _stride) {
    final i = out[o + 5].toInt();
    expect(out[o + 5], greaterThan(prev));
    prev = out[o + 5];
    for (var c = 0; c < _stride; c++) {
      expect(out[o + c], input[i * _stride + c]);
    }
  }
}

void main() {
  test('a straight line of 100 points → its 2 ends', () {
    final input = _data([
      for (var i = 0; i < 100; i++) (10 + i * 0.7, 20 + i * 0.3, 0.25),
    ]);
    final out = simplifyStrokeData(input);
    expect(_count(out), 2);
    _expectSubset(out, input);
    expect(out[5], 0);
    expect(out[_stride + 5], 99);
  });

  test('wiggles under 0.03 pt go, over 0.03 pt stay', () {
    final small = _data([
      for (var i = 0; i < 100; i++) (i * 0.5, (i.isEven ? 0.01 : -0.01), 0.25),
    ]);
    expect(_count(simplifyStrokeData(small)), 2);
    final big = _data([
      for (var i = 0; i < 100; i++) (i * 0.5, (i.isEven ? 0.05 : -0.05), 0.25),
    ]);
    expect(_count(simplifyStrokeData(big)), 100);
  });

  test('points where widthQ changes are kept', () {
    // straight line, widthQ steps from 0.25 to 0.30 at point 50
    final input = _data([
      for (var i = 0; i < 100; i++) (i * 0.5, 0, i < 50 ? 0.25 : 0.30),
    ]);
    final out = simplifyStrokeData(input);
    expect(_count(out), inInclusiveRange(4, 6));
    _expectSubset(out, input);
    // the step itself survives: 49 (0.25) and 50 (0.30) are both there
    final kept = {
      for (var o = 0; o < out.length; o += _stride) out[o + 5].toInt(),
    };
    expect(kept, containsAll(<int>[0, 49, 50, 99]));
    // reconstructing widthQ from the kept points stays within 0.004
    final ks = kept.toList()..sort();
    for (var k = 1; k < ks.length; k++) {
      final a = ks[k - 1], b = ks[k];
      for (var i = a; i <= b; i++) {
        final u = (i - a) / (b - a);
        final qa = input[a * _stride + 2], qb = input[b * _stride + 2];
        final q = input[i * _stride + 2];
        expect((q - (qa + (qb - qa) * u)).abs(), lessThanOrEqualTo(0.004));
      }
    }
  });

  test(
    'a linear widthQ ramp (a taper) needs only the ends; noise < 0.004 goes',
    () {
      final ramp = _data([
        for (var i = 0; i < 100; i++) (i * 0.5, 0, 0.05 + i * 0.002),
      ]);
      expect(_count(simplifyStrokeData(ramp)), 2);
      final noisy = _data([
        for (var i = 0; i < 100; i++)
          (i * 0.5, 0, 0.25 + (i.isEven ? 0.0015 : -0.0015)),
      ]);
      expect(_count(simplifyStrokeData(noisy)), 2);
      final bumpy = _data([
        for (var i = 0; i < 100; i++)
          (i * 0.5, 0, 0.25 + (i.isEven ? 0.004 : -0.004)),
      ]);
      expect(_count(simplifyStrokeData(bumpy)), 100);
    },
  );

  test('ends are always kept; tiny inputs come back as they are', () {
    final one = _data([(1, 2, 0.25)]);
    expect(identical(simplifyStrokeData(one), one), isTrue);
    final two = _data([(1, 2, 0.25), (1, 2, 0.25)]);
    expect(identical(simplifyStrokeData(two), two), isTrue);
    final closed = _data([
      for (var i = 0; i <= 64; i++)
        (
          10 * math.cos(i * math.pi / 32),
          10 * math.sin(i * math.pi / 32),
          0.25,
        ),
    ]);
    final out = simplifyStrokeData(closed);
    // a closed loop (first == last) keeps its shape
    expect(_count(out), greaterThan(8));
    expect(out[0], closeTo(10, 1e-6));
    expect(out[out.length - _stride], closeTo(10, 1e-6));
  });

  test(
    'more than 100 000 points → simplified again with a larger tolerance',
    () {
      // 120 000 points: teeth 0.04…0.055 pt high every 0.1 pt. At 0.03 pt
      // almost every tooth stays (> maxLength); the first retry (0.06 pt)
      // flattens them.
      final rnd = math.Random(7);
      const n = 120000;
      final input = Float32List(n * _stride);
      for (var i = 0; i < n; i++) {
        input
          ..[i * _stride] = i * 0.1
          ..[i * _stride + 1] = i.isEven ? 0 : 0.04 + rnd.nextDouble() * 0.015
          ..[i * _stride + 2] = 0.25
          ..[i * _stride + 5] = i.toDouble();
      }
      expect(
        _count(
          simplifyOnce(
            input,
            tolerance: InkTuning.finishSimplifyPt,
            widthQTolerance: InkTuning.finishSimplifyWidthQ,
          ),
        ),
        greaterThan(core.StrokePoints.maxLength),
      );
      final out = simplifyStrokeData(input);
      expect(_count(out), lessThanOrEqualTo(core.StrokePoints.maxLength));
      expect(_count(out), lessThan(1000));
      expect(out[5], 0);
      expect(out[out.length - 1], n - 1);
      // CORE accepts it
      expect(core.StrokePoints.fromInterleaved(out).length, _count(out));
    },
  );

  test('still too many after 4 retries → the first maxPoints points', () {
    // teeth of 1 pt survive every tolerance up to 0.03 · 2⁴ = 0.48 pt
    final input = _data([
      for (var i = 0; i < 3000; i++) (i * 0.5, i.isEven ? 0 : 1, 0.25),
    ]);
    final out = simplifyStrokeData(input, maxPoints: 1000);
    expect(_count(out), 1000);
    _expectSubset(out, input);
    expect(out[out.length - 1], 999);
  });
}
