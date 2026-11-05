// T04 (03-ink 8, 6.6): the One Euro position filter.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/src/input/one_euro_filter.dart';

/// MINSTD in [0, 1): deterministic noise without bit operations.
final class _Noise {
  _Noise(this._s);
  int _s;
  double next() {
    _s = (_s * 48271) % 2147483647;
    return _s / 2147483647;
  }
}

double _std(List<double> v) {
  final mean = v.reduce((a, b) => a + b) / v.length;
  var sum = 0.0;
  for (final x in v) {
    sum += (x - mean) * (x - mean);
  }
  return math.sqrt(sum / v.length);
}

void main() {
  test('parameters follow s (6.6 table)', () {
    final f = OneEuroFilter(smoothing: 0.5, viewScale: 1);
    expect(f.minCutoff, closeTo(10 * math.pow(0.1, 0.5), 1e-12)); // 3.16 Hz
    expect(f.minCutoff, closeTo(3.162, 1e-3));
    expect(f.beta, closeTo(0.06, 1e-12));
    final hard = OneEuroFilter(smoothing: 1, viewScale: 1);
    expect(hard.minCutoff, closeTo(1, 1e-12));
    expect(hard.beta, closeTo(0.03, 1e-12));
    expect(OneEuroFilter(smoothing: 7, viewScale: 1).smoothing, 1);
    expect(OneEuroFilter(smoothing: double.nan, viewScale: 1).smoothing, 0.5);
  });

  test(
    'held still with ±0.3 pt noise: output std / input std < 0.4 (s = 0.5)',
    () {
      final f = OneEuroFilter(smoothing: 0.5, viewScale: 1);
      final noise = _Noise(12345);
      final inX = <double>[], inY = <double>[];
      final outX = <double>[], outY = <double>[];
      for (var i = 0; i < 1200; i++) {
        final raw = Offset(
          100 + (noise.next() * 2 - 1) * 0.3,
          200 + (noise.next() * 2 - 1) * 0.3,
        );
        final out = f.filter(raw, (i * 1000000 / 120).round());
        if (i >= 120) {
          inX.add(raw.dx);
          inY.add(raw.dy);
          outX.add(out.dx);
          outY.add(out.dy);
        }
      }
      expect(_std(outX) / _std(inX), lessThan(0.4));
      expect(_std(outY) / _std(inY), lessThan(0.4));
    },
  );

  test('constant 500 px/s: steady-state lag ≤ 6 ms', () {
    for (final hz in [60.0, 120.0, 240.0]) {
      final f = OneEuroFilter(smoothing: 0.5, viewScale: 1);
      late Offset out;
      late double xRaw;
      final n = (hz * 2).round(); // 2 s
      for (var i = 0; i <= n; i++) {
        final tMs = i * 1000 / hz;
        xRaw = 0.5 * tMs; // 500 pt/s at viewScale 1 = 500 px/s
        out = f.filter(Offset(xRaw, 0), (tMs * 1000).round());
      }
      final lagMs = (xRaw - out.dx) / 0.5;
      expect(lagMs, greaterThan(0));
      expect(lagMs, lessThanOrEqualTo(6), reason: '$hz Hz');
    }
  });

  test(
    'viewScale enters the cutoff: zoomed in, the same pt speed is faster',
    () {
      double lag(double viewScale) {
        final f = OneEuroFilter(smoothing: 0.5, viewScale: viewScale);
        late Offset out;
        late double x;
        for (var i = 0; i <= 240; i++) {
          final tMs = i * 1000 / 120;
          x = 0.1 * tMs;
          out = f.filter(Offset(x, 0), (tMs * 1000).round());
        }
        return x - out.dx;
      }

      expect(lag(4), lessThan(lag(1)));
    },
  );

  test('s = 0 → identity', () {
    final f = OneEuroFilter(smoothing: 0, viewScale: 1);
    expect(f.isBypass, isTrue);
    final noise = _Noise(7);
    for (var i = 0; i < 100; i++) {
      final raw = Offset(noise.next() * 500, noise.next() * 500);
      expect(f.filter(raw, i * 8333), raw);
    }
  });

  test('first sample passes unchanged', () {
    final f = OneEuroFilter(smoothing: 0.8, viewScale: 1);
    expect(f.value, isNull);
    expect(f.filter(const Offset(3, 4), 0), const Offset(3, 4));
    expect(f.value, const Offset(3, 4));
  });

  test('causal: earlier outputs do not depend on later samples', () {
    final noise = _Noise(99);
    final samples = [
      for (var i = 0; i < 300; i++)
        (
          Offset(i * 2 + noise.next(), 50 * math.sin(i / 20) + noise.next()),
          (i * 1000000 / 120).round(),
        ),
    ];
    final full = OneEuroFilter(smoothing: 0.5, viewScale: 1.5);
    final fullOut = [for (final (p, t) in samples) full.filter(p, t)];
    for (final cut in [1, 10, 150, 299]) {
      final part = OneEuroFilter(smoothing: 0.5, viewScale: 1.5);
      for (var i = 0; i < cut; i++) {
        expect(part.filter(samples[i].$1, samples[i].$2), fullOut[i]);
      }
    }
  });

  test('Δt = 0 does not produce NaN', () {
    final f = OneEuroFilter(smoothing: 0.5, viewScale: 1)
      ..filter(Offset.zero, 1000);
    final out = f.filter(const Offset(5, 5), 1000);
    expect(out.dx.isFinite && out.dy.isFinite, isTrue);
  });
}
