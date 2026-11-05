// T04 (03-ink 8, 6.5, 6.6): velocity-based simulated pressure and real
// pressure smoothing.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/input/simulated_pressure.dart';

/// Feeds a trajectory x(tMs) (screen px / viewScale = pt) sampled at [hz] for
/// [durationMs]; returns (timeMs, pressure) pairs.
List<(double, double)> _run(
  Offset Function(double tMs) at, {
  required double hz,
  double durationMs = 1000,
  double viewScale = 1,
}) {
  final sim = SimulatedPressure(viewScale: viewScale);
  final out = <(double, double)>[];
  final n = (durationMs * hz / 1000).round();
  for (var i = 0; i <= n; i++) {
    final tMs = i * 1000 / hz;
    out.add((tMs, sim.add(at(tMs), (tMs * 1000).round())));
  }
  return out;
}

/// Linear interpolation of a sampled series at [tMs].
double _valueAt(List<(double, double)> s, double tMs) {
  for (var i = 1; i < s.length; i++) {
    if (s[i].$1 >= tMs) {
      final (t0, v0) = s[i - 1];
      final (t1, v1) = s[i];
      return v0 + (v1 - v0) * (tMs - t0) / (t1 - t0);
    }
  }
  return s.last.$2;
}

void main() {
  test('smoothstep', () {
    expect(smoothstep(0, 1, -1), 0);
    expect(smoothstep(0, 1, 0.5), 0.5);
    expect(smoothstep(0, 1, 2), 1);
    expect(smoothstep(0.08, 1.6, 0.08), 0);
    expect(smoothstep(0.08, 1.6, 1.6), 1);
  });

  test('starts at 0.5', () {
    final sim = SimulatedPressure(viewScale: 1);
    expect(sim.value, 0.5);
    expect(sim.add(const Offset(10, 10), 0), 0.5);
    expect(sim.smoothedSpeed, isNull);
  });

  test('held still → converges to 0.68', () {
    final s = _run((_) => const Offset(100, 100), hz: 120);
    expect(s.last.$2, closeTo(0.5 + InkTuning.simAmplitude, 1e-3));
    expect(s.last.$2, closeTo(0.68, 1e-3));
  });

  test('fast (2 px/ms) → converges to 0.32', () {
    final s = _run((t) => Offset(2 * t, 0), hz: 120);
    expect(s.last.$2, closeTo(0.32, 1e-3));
    // Every value stays in [0.32, 0.68].
    for (final (_, p) in s) {
      expect(p, inInclusiveRange(0.32 - 1e-9, 0.68 + 1e-9));
    }
  });

  test('faster → thinner (monotone in speed at steady state)', () {
    double steady(double pxPerMs) =>
        _run((t) => Offset(pxPerMs * t, 0), hz: 120).last.$2;
    final speeds = [0.0, 0.1, 0.3, 0.6, 1.0, 1.4, 2.0];
    final values = speeds.map(steady).toList();
    for (var i = 1; i < values.length; i++) {
      expect(values[i], lessThanOrEqualTo(values[i - 1] + 1e-12));
    }
  });

  test('the same trajectory at 60 / 120 / 240 Hz differs by ≤ 0.03', () {
    // Slow → fast → slow: speed 0.05 → 2.0 → 0.05 px/ms over 1.2 s.
    Offset at(double tMs) {
      final u = tMs / 1200;
      // x(t) = ∫ speed; speed = 0.05 + 1.95 · sin²(π u)
      final x =
          0.05 * tMs +
          1.95 * (tMs / 2 - 1200 / (4 * math.pi) * math.sin(2 * math.pi * u));
      return Offset(x, 0.3 * x);
    }

    final a = _run(at, hz: 60, durationMs: 1200);
    final b = _run(at, hz: 120, durationMs: 1200);
    final c = _run(at, hz: 240, durationMs: 1200);
    var maxDiff = 0.0;
    for (var t = 50.0; t <= 1200; t += 10) {
      final va = _valueAt(a, t), vb = _valueAt(b, t), vc = _valueAt(c, t);
      maxDiff = math.max(
        maxDiff,
        math.max((va - vb).abs(), math.max((vb - vc).abs(), (va - vc).abs())),
      );
    }
    expect(maxDiff, lessThanOrEqualTo(0.03));
  });

  test('viewScale 2 with the same screen speed gives the same result', () {
    final screen = _run((t) => Offset(0.7 * t, 0.2 * t), hz: 120);
    final zoomed = _run(
      (t) => Offset(0.7 * t / 2, 0.2 * t / 2),
      hz: 120,
      viewScale: 2,
    );
    for (var i = 0; i < screen.length; i++) {
      expect(zoomed[i].$2, closeTo(screen[i].$2, 1e-12));
    }
  });

  test('Δt = 0 is treated as 1 ms (no division by zero)', () {
    final sim = SimulatedPressure(viewScale: 1)..add(Offset.zero, 1000);
    final p = sim.add(const Offset(1, 0), 1000);
    expect(p.isFinite, isTrue);
    expect(sim.smoothedSpeed, closeTo(1, 1e-12)); // 1 px over 1 ms
  });

  group('RealPressureSmoother', () {
    test('first value passes, then an 8 ms exponential follows', () {
      final r = RealPressureSmoother();
      expect(r.value, isNull);
      expect(r.add(0.2, 0), 0.2);
      final p = r.add(0.8, 8000);
      expect(p, closeTo(0.2 + 0.6 * (1 - math.exp(-1)), 1e-12));
      // Held: converges to the raw value.
      var last = p;
      for (var i = 2; i < 200; i++) {
        last = r.add(0.8, i * 8000);
      }
      expect(last, closeTo(0.8, 1e-9));
    });

    test('rate independent: one 16 ms step = two 8 ms steps', () {
      final a = RealPressureSmoother()..add(0.1, 0);
      final one = a.add(0.9, 16000);
      final b = RealPressureSmoother()
        ..add(0.1, 0)
        ..add(0.9, 8000);
      final two = b.add(0.9, 16000);
      expect(two, closeTo(one, 1e-12));
    });
  });
}
