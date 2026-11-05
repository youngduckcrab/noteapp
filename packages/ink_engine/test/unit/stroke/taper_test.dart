// T05 (03-ink 8, 6.7 F5 = K5): start / end taper.
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/stroke/centerline.dart';
import 'package:ink_engine/src/stroke/taper.dart';

/// A straight line of [length] pt with a point every [step] pt, factor 1.
List<CenterPoint> _line(double length, {double step = 0.25}) {
  final n = (length / step).round();
  return [for (var i = 0; i <= n; i++) CenterPoint(i * length / n, 0)];
}

void main() {
  test('easeOutCubic', () {
    expect(easeOutCubic(0), 0);
    expect(easeOutCubic(1), 1);
    expect(easeOutCubic(0.5), closeTo(0.875, 1e-12));
    var prev = 0.0;
    for (var t = 0.0; t <= 1; t += 0.01) {
      expect(easeOutCubic(t), greaterThanOrEqualTo(prev));
      prev = easeOutCubic(t);
    }
  });

  test('taper lengths = min(taper · width, 0.4 · S)', () {
    final (ls, le) = taperLengths(PenProfile.fountain, 2.2, 100);
    expect(ls, closeTo(1.5 * 2.2, 1e-12));
    expect(le, closeTo(3.0 * 2.2, 1e-12));
    // a short stroke: both capped at 0.4 · S
    final (ss, se) = taperLengths(PenProfile.fountain, 2.2, 5);
    expect(ss, closeTo(2, 1e-12));
    expect(se, closeTo(2, 1e-12));
    expect(taperLengths(PenProfile.ballpoint, 1.6, 100), (0.0, 0.0));
  });

  test('fountain: thinner towards both ends, ends = taperMin', () {
    final pts = _line(100);
    applyTaper(pts, profile: PenProfile.fountain, width: 2.2);
    expect(pts.first.factor, closeTo(0.15, 1e-12));
    expect(pts.last.factor, closeTo(0.15, 1e-12));
    // middle untouched
    final mid = pts[pts.length ~/ 2];
    expect(mid.factor, 1);
    final cum = cumulativeLengthsOf(pts);
    const le = 3.0 * 2.2, ls = 1.5 * 2.2;
    for (var i = 1; i < pts.length; i++) {
      if (cum[i] >= 100 - le - 1e-9) {
        // end region: monotonically decreasing towards the end
        expect(pts[i].factor, lessThan(pts[i - 1].factor + 1e-12));
      }
      if (cum[i] <= ls) {
        // start region: increasing away from the start
        expect(pts[i].factor, greaterThan(pts[i - 1].factor - 1e-12));
      }
      if (cum[i] > ls && cum[i] < 100 - le) {
        expect(pts[i].factor, 1);
      }
    }
  });

  test('a short stroke tapers over at most 0.4 · S on each side', () {
    final pts = _line(5, step: 0.05);
    applyTaper(pts, profile: PenProfile.pencil, width: 1.4);
    final cum = cumulativeLengthsOf(pts);
    for (var i = 0; i < pts.length; i++) {
      // points farther than 0.4 · S from both ends keep their factor
      if (cum[i] >= 0.4 * 5 + 1e-9 && cum[i] <= 0.6 * 5 - 1e-9) {
        expect(pts[i].factor, 1, reason: 's = ${cum[i]}');
      } else if (cum[i] < 0.4 * 5 - 0.05 || cum[i] > 0.6 * 5 + 0.05) {
        expect(pts[i].factor, lessThan(1));
      }
    }
    expect(pts.first.factor, closeTo(PenProfile.pencil.taperMinFactor, 1e-12));
  });

  test('the factor is multiplied (pressure variation kept)', () {
    final pts = _line(100);
    for (var i = 0; i < pts.length; i++) {
      pts[i].factor = 1.5;
    }
    applyTaper(pts, profile: PenProfile.fountain, width: 2.2);
    expect(pts.first.factor, closeTo(1.5 * 0.15, 1e-12));
    expect(pts[pts.length ~/ 2].factor, 1.5);
  });

  test('pens without taper are untouched; sides can be switched off', () {
    final ball = _line(50);
    applyTaper(ball, profile: PenProfile.ballpoint, width: 1.6);
    expect(ball.every((p) => p.factor == 1), isTrue);

    final noStart = _line(50);
    applyTaper(noStart, profile: PenProfile.fountain, width: 2.2, start: false);
    expect(noStart.first.factor, 1);
    expect(noStart.last.factor, closeTo(0.15, 1e-12));

    final noEnd = _line(50);
    applyTaper(noEnd, profile: PenProfile.fountain, width: 2.2, end: false);
    expect(noEnd.first.factor, closeTo(0.15, 1e-12));
    expect(noEnd.last.factor, 1);
  });

  test('live start taper: startTaper(s, Ls)', () {
    expect(startTaper(0, 3.3), 0);
    expect(startTaper(3.3, 3.3), 1);
    expect(startTaper(10, 3.3), 1);
    expect(startTaper(0, 0), 1);
  });
}
