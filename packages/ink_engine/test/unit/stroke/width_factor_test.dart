// T05 (03-ink 8, 6.7 K1–K6): width factor of a sample and its stored widthQ.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/stroke/width_factor.dart';
import 'package:note_core/note_core.dart' as core;

core.StrokeStyle _style(core.PenTool tool) =>
    core.StrokeStyle.defaultsFor(tool);

/// f over a grid of pressure × speed × tilt × source.
List<double> _scan(core.StrokeStyle style) => [
  for (var p = 0.0; p <= 1.0001; p += 0.05)
    for (final speed in const [0.0, 0.5, 1.2, 2.0, 5.0])
      for (final tilt in const [0.0, 0.5, 0.8, 1.2, math.pi / 2])
        for (final real in const [true, false])
          widthFactor(
            style: style,
            pressure: bakedPressure(style, p, real: real),
            realPressure: real,
            speed: speed,
            tilt: tilt,
          ),
];

void main() {
  test('f range per pen (K2 clamp, K3 thinning, K4 tilt)', () {
    final expected = <core.PenTool, (double, double)>{
      // 1 ± pressureGain, inside [minFactor, maxFactor]
      core.PenTool.ballpoint: (0.82, 1.18),
      // 1 ± 0.75 → clamped below at 0.30, then up to 25 % thinner when fast
      core.PenTool.fountain: (0.30 * 0.75, 1.75),
      core.PenTool.highlighter: (1, 1),
      // 1 ± 0.45, up to (1 + 1.8) × when tilted
      core.PenTool.pencil: (0.55, 1.45 * 2.8),
      core.PenTool.marker: (0.88, 1.12),
    };
    expected.forEach((tool, range) {
      final fs = _scan(_style(tool));
      final lo = fs.reduce(math.min), hi = fs.reduce(math.max);
      expect(lo, closeTo(range.$1, 1e-9), reason: '$tool min');
      expect(hi, closeTo(range.$2, 1e-9), reason: '$tool max');
      expect(lo, greaterThan(0));
    });
  });

  test('widthQ = f / 4 (K6); the highlighter is always 0.25', () {
    expect(widthQForFactor(1, highlighter: false), 0.25);
    expect(widthQForFactor(2, highlighter: false), 0.5);
    expect(widthQForFactor(0.2, highlighter: false), closeTo(0.05, 1e-12));
    expect(widthQForFactor(4, highlighter: false), 1);
    expect(widthQForFactor(5, highlighter: false), 1);
    for (final f in const [0.1, 1.0, 3.0, 4.48]) {
      expect(widthQForFactor(f, highlighter: true), core.kNominalWidthQ);
    }
    expect(_scan(_style(core.PenTool.highlighter)).toSet(), {1.0});
  });

  test('fountain: faster → thinner, real pressure only (K3)', () {
    final style = _style(core.PenTool.fountain);
    double f(double speed, {bool real = true}) => widthFactor(
      style: style,
      pressure: 0.5,
      realPressure: real,
      speed: speed,
      tilt: 0,
    );
    expect(f(0), 1);
    expect(f(0.3), 1);
    expect(f(1.15), allOf(lessThan(1), greaterThan(0.75)));
    expect(f(2.0), closeTo(0.75, 1e-12));
    expect(f(9), closeTo(0.75, 1e-12));
    var prev = f(0);
    for (var v = 0.0; v <= 3; v += 0.1) {
      expect(f(v), lessThanOrEqualTo(prev + 1e-12));
      prev = f(v);
    }
    // simulated pressure already thins with speed (6.5): no K3
    expect(f(2.0, real: false), 1);
    // the ballpoint has no velocityThinning
    expect(
      widthFactor(
        style: _style(core.PenTool.ballpoint),
        pressure: 0.5,
        realPressure: true,
        speed: 5,
        tilt: 0,
      ),
      1,
    );
  });

  test('pencil: more tilt → wider (K4), other pens ignore tilt', () {
    final pencil = _style(core.PenTool.pencil);
    double f(double tilt) => widthFactor(
      style: pencil,
      pressure: 0.5,
      realPressure: true,
      speed: 0,
      tilt: tilt,
    );
    expect(f(0), 1);
    expect(f(0.35), 1);
    expect(f(1.15), closeTo(2.8, 1e-12));
    expect(f(math.pi / 2), closeTo(2.8, 1e-12));
    var prev = f(0);
    for (var t = 0.0; t <= math.pi / 2; t += 0.05) {
      expect(f(t), greaterThanOrEqualTo(prev - 1e-12));
      prev = f(t);
    }
    expect(f(0.8), greaterThan(1));
    for (final tool in [
      core.PenTool.ballpoint,
      core.PenTool.fountain,
      core.PenTool.marker,
    ]) {
      expect(
        widthFactor(
          style: _style(tool),
          pressure: 0.5,
          realPressure: true,
          speed: 0,
          tilt: 1.2,
        ),
        1,
      );
    }
  });

  test('soft / firm curves apply to real pressure only (K1)', () {
    final linear = _style(core.PenTool.fountain);
    final soft = linear.copyWith(pressureCurve: core.PressureCurve.soft);
    final firm = linear.copyWith(pressureCurve: core.PressureCurve.firm);
    for (final p in const [0.2, 0.3, 0.6]) {
      expect(
        bakedPressure(soft, p, real: true),
        core.PressureCurve.soft.evaluate(p),
      );
      expect(bakedPressure(soft, p, real: true), greaterThan(p));
      expect(bakedPressure(firm, p, real: true), lessThan(p));
      expect(bakedPressure(linear, p, real: true), closeTo(p, 1e-9));
      // simulated pressure: no curve
      expect(bakedPressure(soft, p, real: false), p);
      expect(bakedPressure(firm, p, real: false), p);
    }
    double f(core.StrokeStyle s, {required bool real}) => widthFactor(
      style: s,
      pressure: bakedPressure(s, 0.3, real: real),
      realPressure: real,
      speed: 0,
      tilt: 0,
    );
    expect(f(soft, real: true), greaterThan(f(linear, real: true)));
    expect(f(firm, real: true), lessThan(f(linear, real: true)));
    expect(f(soft, real: false), f(linear, real: false));
    expect(f(firm, real: false), f(linear, real: false));
  });

  test('pressureSensitivity 0 → f = 1 for any pressure', () {
    for (final tool in core.PenTool.values) {
      final style = _style(tool).copyWith(pressureSensitivity: 0);
      for (var p = 0.0; p <= 1.0001; p += 0.1) {
        for (final real in const [true, false]) {
          expect(
            widthFactor(
              style: style,
              pressure: bakedPressure(style, p, real: real),
              realPressure: real,
              speed: 0,
              tilt: 0,
            ),
            1,
            reason: '$tool p=$p',
          );
        }
      }
    }
    // half sensitivity halves the gain
    final half = _style(core.PenTool.fountain)
        .copyWith(pressureSensitivity: 0.5);
    expect(
      widthFactor(
        style: half,
        pressure: 1,
        realPressure: true,
        speed: 0,
        tilt: 0,
      ),
      closeTo(1 + 0.75 * 0.5, 1e-12),
    );
  });

  test('pencil at full pressure and full tilt saturates: widthQ 1, '
      'live radius = final radius = 2 · width (K4, K6)', () {
    final style = _style(core.PenTool.pencil);
    final f = widthFactor(
      style: style,
      pressure: bakedPressure(style, 1, real: true),
      realPressure: true,
      speed: 0,
      tilt: math.pi / 2,
    );
    // pressureGain 0.45 → K2 gives 1.45 (the 6.7 K4 bound 4.48 uses
    // maxFactor 1.6); both are above kMaxWidthFactor
    expect(f, closeTo(1.45 * 2.8, 1e-12));
    expect(f, greaterThan(core.kMaxWidthFactor));
    final bound =
        PenProfile.pencil.maxFactor * (1 + PenProfile.pencil.tiltWidthGain);
    expect(bound, closeTo(4.48, 1e-12));
    expect(widthQForFactor(bound, highlighter: false), 1);
    final q = widthQForFactor(f, highlighter: false);
    expect(q, 1);
    // live preview radius (from f) …
    final live = radiusForFactor(style, f);
    expect(live, 2 * style.width);
    // … = the radius of the stored (CORE-quantized) point
    final stroke = core.Stroke(
      id: 's1',
      pageId: 'p1',
      style: style,
      points: core.StrokePoints.fromList([core.StrokePoint(10, 10, widthQ: q)]),
      createdAt: 1,
    );
    expect(InkStroke.of(stroke).radiusAt(0), live);
    expect(InkStroke.of(stroke).maxRadius, 2 * style.width);
  });

  test('radiusForFactor: lower bound minRadiusPt, highlighter width / 2', () {
    final ball = _style(core.PenTool.ballpoint).copyWith(width: 0.1);
    expect(radiusForFactor(ball, 0.01), InkTuning.minRadiusPt);
    expect(
      radiusForFactor(_style(core.PenTool.ballpoint), 1),
      closeTo(1.6 / 2, 1e-12),
    );
    final hl = _style(core.PenTool.highlighter);
    expect(radiusForFactor(hl, 3), hl.width / 2);
  });

  test('NaN inputs do not leak', () {
    final style = _style(core.PenTool.fountain);
    expect(bakedPressure(style, double.nan, real: true), 0.5);
    final f = widthFactor(
      style: _style(core.PenTool.pencil),
      pressure: 0.5,
      realPressure: true,
      speed: double.nan,
      tilt: double.nan,
    );
    expect(f, 1);
    expect(
      widthQForFactor(double.nan, highlighter: false),
      core.kNominalWidthQ,
    );
  });
}
