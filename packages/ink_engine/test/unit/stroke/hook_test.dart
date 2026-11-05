// T05 (03-ink 8, 6.7 F3): pen-down / pen-lift hook removal.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/src/stroke/centerline.dart';

/// A straight line along +x: [n] samples [step] pt apart, 8 ms apart.
List<CenterPoint> _line(int n, {double step = 1, double t0 = 0}) => [
  for (var i = 0; i < n; i++) CenterPoint(i * step, 0, t: t0 + i * 8),
];

/// [pts] followed by [count] samples of [step] pt in direction [angle] (rad).
List<CenterPoint> _withTail(
  List<CenterPoint> pts,
  double angle,
  int count,
  double step,
) {
  final out = List.of(pts);
  for (var i = 0; i < count; i++) {
    final last = out.last;
    out.add(
      CenterPoint(
        last.x + step * math.cos(angle),
        last.y + step * math.sin(angle),
        t: last.t + 8,
      ),
    );
  }
  return out;
}

void main() {
  const width = 1.6; // ballpoint default: end window 1.6 pt, start 1.2 pt

  test('windows: end max(1.5, width), start max(1.0, 0.75 · width)', () {
    expect(endHookWindowFor(1.6), 1.6);
    expect(endHookWindowFor(0.5), 1.5);
    expect(startHookWindowFor(1.6), closeTo(1.2, 1e-12));
    expect(startHookWindowFor(0.5), 1.0);
  });

  test('a 3-sample backwards hook at the end is cut', () {
    // 30 pt to the right, then 3 × 0.5 pt back and down (150°)
    final pts = _withTail(_line(31), math.pi * 5 / 6, 3, 0.5);
    final out = removeHooks(pts, width: width);
    final total = lengthOf(pts);
    // the stroke now ends at arc length S − W, on the line
    expect(out.last.y, closeTo(0, 1e-9));
    expect(out.last.x, closeTo(total - 1.6, 1e-9));
    expect(out.length, lessThan(pts.length));
    for (var i = 1; i < out.length; i++) {
      expect(out[i].x, greaterThan(out[i - 1].x)); // forward only
    }
    // the new end point is interpolated (t between its neighbours)
    expect(out.last.t, greaterThan(out[out.length - 2].t));
  });

  test('a backwards hook at the start is cut; the first t becomes > 0', () {
    // 3 samples 0.35 pt apart moving left-up (150°) into (0, 0), then the
    // stroke goes right: the 1.05 pt hook fits the 1.2 pt start window
    final hook = [
      for (var k = 0; k < 3; k++)
        CenterPoint(
          (3 - k) * 0.35 * math.cos(-math.pi / 6),
          (3 - k) * 0.35 * math.sin(-math.pi / 6),
          t: k * 8.0,
        ),
    ];
    final pts = [...hook, ..._line(30, t0: 24)];
    final out = removeHooks(pts, width: width);
    expect(out.first.t, greaterThan(0));
    expect(out.first.y, closeTo(0, 1e-6));
    for (var i = 1; i < out.length; i++) {
      expect(out[i].x, greaterThan(out[i - 1].x));
    }
    // sides can be switched off (rollover joins)
    expect(removeHooks(pts, width: width, start: false).length, pts.length);
  });

  test("a long normal corner ('ㄱ') is kept", () {
    final pts = _withTail(_line(21), math.pi / 2, 20, 1);
    expect(removeHooks(pts, width: width).length, pts.length);
    // a short 90° flick is not a hook either (dot = 0 > −0.34)
    final flick = _withTail(_line(31), math.pi / 2, 3, 0.5);
    expect(removeHooks(flick, width: width).length, flick.length);
  });

  test('more than 4 samples in the window → kept (a deliberate stroke)', () {
    final pts = _withTail(_line(31), math.pi * 5 / 6, 6, 0.25);
    expect(removeHooks(pts, width: width).length, pts.length);
  });

  test('the stroke before the window must be at least 3W long', () {
    // 4 pt line + 1.5 pt hook: S − W = 3.9 < 3 · 1.6
    final pts = _withTail(_line(5), math.pi * 5 / 6, 3, 0.5);
    expect(removeHooks(pts, width: width).length, pts.length);
    final end = removeHooks(pts, width: width, end: false);
    expect(end.length, pts.length);
  });

  test('tiny inputs pass through', () {
    expect(removeHooks(const [], width: width), isEmpty);
    expect(removeHooks([CenterPoint(0, 0)], width: width).length, 1);
    expect(removeHooks(_line(2), width: width).length, 2);
  });
}
