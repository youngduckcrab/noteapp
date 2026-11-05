// lib/src/input/simulated_pressure.dart — INTERNAL (not exported): 03-ink 6.5, 6.6.
//
// SimulatedPressure: velocity-based pressure when the pointer reports none
// (6.5). Fast → thin, slow → thick. Time based (exponential decay), so the same
// trajectory gives the same values at 60, 120 or 240 Hz. Speed is measured in
// screen px (pt × viewScale) on the RAW samples, so zooming does not change
// how the hand speed feels.
//
// RealPressureSmoother: light smoothing of real pressure (6.6,
// p += (raw − p) · (1 − exp(−Δt / 8 ms))).
import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../tuning.dart';

/// t²(3 − 2t) with t = clamp((x − e0) / (e1 − e0), 0, 1).
double smoothstep(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0).toDouble();
  return t * t * (3 - 2 * t);
}

/// Δt in ms between two sample times; 0 or negative → 1 ms (6.3 rule 3).
double sampleDtMs(int fromUs, int toUs) {
  final dt = (toUs - fromUs) / 1000;
  return dt > 0 ? dt : 1.0;
}

final class SimulatedPressure {
  SimulatedPressure({required this.viewScale});

  /// Logical px per page pt (no devicePixelRatio, contract 7.2.15 v1.1).
  final double viewScale;

  Offset? _last;
  int _lastUs = 0;
  double? _vf; // smoothed screen speed, px/ms
  double _p = 0.5;

  /// The pressure of the last sample (0.5 before any movement).
  double get value => _p;

  /// Smoothed screen speed in px/ms (null before the second sample).
  double? get smoothedSpeed => _vf;

  /// Feeds one raw sample and returns its simulated pressure in [0.32, 0.68].
  double add(Offset position, int timeUs) {
    final last = _last;
    _last = position;
    if (last == null) {
      _lastUs = timeUs;
      return _p;
    }
    final dt = sampleDtMs(_lastUs, timeUs);
    _lastUs = timeUs;
    final v = (position - last).distance * viewScale / dt;
    final vf = _vf;
    _vf = vf == null
        ? v
        : vf + (v - vf) * (1 - math.exp(-dt / InkTuning.simSpeedTauMs));
    final target =
        0.5 +
        InkTuning.simAmplitude *
            (1 - 2 * smoothstep(InkTuning.simV0, InkTuning.simV1, _vf!));
    _p += (target - _p) * (1 - math.exp(-dt / InkTuning.simPressureTauMs));
    return _p;
  }
}

final class RealPressureSmoother {
  double? _p;
  int _lastUs = 0;

  /// The smoothed pressure of the last sample (null before the first).
  double? get value => _p;

  /// Feeds one normalized pressure in [0, 1]; the first value passes as is.
  double add(double pressure, int timeUs) {
    final p = _p;
    if (p == null) {
      _lastUs = timeUs;
      return _p = pressure;
    }
    final dt = sampleDtMs(_lastUs, timeUs);
    _lastUs = timeUs;
    return _p =
        p + (pressure - p) * (1 - math.exp(-dt / InkTuning.realPressureTauMs));
  }
}
