// lib/src/input/one_euro_filter.dart — INTERNAL (not exported): 03-ink 6.6.
//
// One Euro filter on positions: strong when slow (removes jitter), weak when
// fast (little lag). Causal: an output never changes once given, so the
// stable prefix of a live stroke can be frozen (6.12). s = style.smoothing:
//   minCutoff = 10 · 0.1^s Hz, beta = 0.12 · 0.25^s (Hz per px/s), dCutoff 1 Hz
//   alpha(fc, dt) = 1 / (1 + 1 / (2π · fc · dt)), dt in seconds
//   dx  = (x − x_prevRaw) / dt                    (pt/s, 2D)
//   dxh = lerp(dxh_prev, dx, alpha(dCutoff, dt))
//   fc  = minCutoff + beta · |dxh| · viewScale     (speed in screen px/s)
//   xh  = lerp(xh_prev, x, alpha(fc, dt))
// s = 0 bypasses the filter (raw positions).
import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../tuning.dart';
import 'simulated_pressure.dart' show sampleDtMs;

final class OneEuroFilter {
  /// [smoothing] = style.smoothing (NaN → 0.5, clamped to [0, 1]).
  factory OneEuroFilter({
    required double smoothing,
    required double viewScale,
  }) {
    final s = smoothing.isNaN ? 0.5 : smoothing.clamp(0.0, 1.0).toDouble();
    return OneEuroFilter._(
      s,
      viewScale,
      InkTuning.oneEuroMinCutoffMax * math.pow(0.1, s),
      InkTuning.oneEuroBetaMax * math.pow(0.25, s),
    );
  }

  OneEuroFilter._(this.smoothing, this.viewScale, this.minCutoff, this.beta);

  /// style.smoothing clamped to [0, 1].
  final double smoothing;

  /// Logical px per page pt (no devicePixelRatio).
  final double viewScale;

  /// Hz.
  final double minCutoff;

  /// Hz per screen px/s.
  final double beta;

  bool get isBypass => smoothing == 0;

  Offset? _xRaw;
  Offset _xh = Offset.zero;
  Offset _dxh = Offset.zero;
  int _lastUs = 0;

  /// The last filtered position (null before the first sample).
  Offset? get value => _xRaw == null ? null : _xh;

  static double alpha(double cutoffHz, double dtSeconds) =>
      1 / (1 + 1 / (2 * math.pi * cutoffHz * dtSeconds));

  /// Feeds one raw position (page pt) and returns the filtered position.
  Offset filter(Offset raw, int timeUs) {
    final prev = _xRaw;
    _xRaw = raw;
    if (prev == null || isBypass) {
      _lastUs = timeUs;
      return _xh = raw;
    }
    final dt = sampleDtMs(_lastUs, timeUs) / 1000;
    _lastUs = timeUs;
    final dx = (raw - prev) / dt;
    _dxh = Offset.lerp(_dxh, dx, alpha(InkTuning.oneEuroDCutoff, dt))!;
    final fc = minCutoff + beta * _dxh.distance * viewScale;
    return _xh = Offset.lerp(_xh, raw, alpha(fc, dt))!;
  }
}
