// lib/src/stroke/width_factor.dart — INTERNAL (not exported): 03-ink 6.7 K1–K4, K6.
//
// Width factor f of one sample (0 < f; stored as widthQ = clamp(f / 4, 0, 1)):
//   K1 pressure     real: p = style.pressureCurve.evaluate(smoothed pressure)
//                   simulated: p = p_sim (6.5, no curve)
//   K2 response     f = 1 + profile.pressureGain · style.pressureSensitivity · (2p − 1),
//                   clamped to [minFactor, maxFactor]
//   K3 speed        real pressure and velocityThinning > 0 (fountain):
//                   f *= 1 − velocityThinning · smoothstep(0.3, 2.0, vf)
//   K4 tilt         k = smoothstep(0.35, 1.15, tilt), f *= 1 + tiltWidthGain · k (pencil)
//   (K5 taper: taper.dart, at finish)
//   K6 store        widthQ = clamp(f / core.kMaxWidthFactor, 0, 1); the live
//                   preview uses the same min(f, kMaxWidthFactor), so the radius
//                   does not jump on pen lift and never exceeds 2 · width (K-1).
//                   Highlighter: always core.kNominalWidthQ.
import 'dart:math' as math;

import 'package:note_core/note_core.dart' as core;

import '../input/simulated_pressure.dart' show smoothstep;
import '../model/ink_layer.dart';
import '../pen/style_ink.dart';
import '../tuning.dart';

/// K3 speed range (smoothed screen speed vf, px/ms).
const double _thinningV0 = 0.3;
const double _thinningV1 = 2.0;

/// K4 tilt range (rad, about 20° … 66°).
const double _tiltK0 = 0.35;
const double _tiltK1 = 1.15;

/// K1: the pressure fed to K2. Real pressure goes through the style's curve
/// (core.PressureCurve.evaluate, input time only — K-7+); simulated pressure is
/// used as is (the curve tunes the response to real pressure).
double bakedPressure(
  core.StrokeStyle style,
  double pressure, {
  required bool real,
}) {
  final p = pressure.isNaN ? 0.5 : pressure.clamp(0.0, 1.0).toDouble();
  return real ? style.pressureCurve.evaluate(p) : p;
}

/// K2–K4: the width factor f of one sample, before the K5 taper.
/// [pressure] = K1 output (bakedPressure), [speed] = smoothed screen speed vf
/// (px/ms, SimulatedPressure.smoothedSpeed; 0 when unknown), [tilt] in rad.
double widthFactor({
  required core.StrokeStyle style,
  required double pressure,
  required bool realPressure,
  required double speed,
  required double tilt,
}) {
  final profile = style.profile;
  var f =
      1 + profile.pressureGain * style.pressureSensitivity * (2 * pressure - 1);
  f = f.clamp(profile.minFactor, profile.maxFactor).toDouble();
  if (realPressure && profile.velocityThinning > 0) {
    f *=
        1 -
        profile.velocityThinning *
            smoothstep(_thinningV0, _thinningV1, speed.isNaN ? 0 : speed);
  }
  if (profile.tiltWidthGain > 0) {
    final k = smoothstep(_tiltK0, _tiltK1, tilt.isNaN ? 0 : tilt);
    f *= 1 + profile.tiltWidthGain * k;
  }
  return f;
}

/// K6: widthQ = clamp(f / kMaxWidthFactor, 0, 1); highlighter → kNominalWidthQ.
double widthQForFactor(double f, {required bool highlighter}) {
  if (highlighter) return core.kNominalWidthQ;
  if (f.isNaN) return core.kNominalWidthQ;
  return (f / core.kMaxWidthFactor).clamp(0.0, 1.0).toDouble();
}

/// The render radius of factor [f] for [style]: max(minRadiusPt, 2 · width ·
/// widthQ) with the K6 widthQ — the same as InkStroke.radiusAt on the stored
/// point (live = final). Highlighter: width / 2.
double radiusForFactor(core.StrokeStyle style, double f) {
  if (style.profile.layer == InkLayer.highlighter) return style.width / 2;
  return math.max(
    InkTuning.minRadiusPt,
    2 * style.width * widthQForFactor(f, highlighter: false),
  );
}
