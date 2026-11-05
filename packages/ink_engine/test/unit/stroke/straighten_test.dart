// T05 (03-ink 8, 6.7 F6): highlighter straightening (extras['hlStraight']).
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/stroke/centerline.dart';
import 'package:ink_engine/src/stroke/straighten.dart';
import 'package:note_core/note_core.dart' as core;

/// A [length] pt stroke from (100, 100) at [angleDeg], with a perpendicular
/// wobble y = amp · sin(2π · s / period).
List<CenterPoint> _stroke({
  double length = 60,
  double angleDeg = 0,
  double amp = 0,
  double period = 20,
}) {
  final a = angleDeg * math.pi / 180;
  final dir = Offset(math.cos(a), math.sin(a));
  final nrm = Offset(-dir.dy, dir.dx);
  return [
    for (var s = 0.0; s <= length + 1e-9; s += 0.5)
      () {
        final p =
            const Offset(100, 100) +
            dir * s +
            nrm * (amp * math.sin(2 * math.pi * s / period));
        return CenterPoint(p.dx, p.dy, t: s * 4);
      }(),
  ];
}

void main() {
  final hl = core.StrokeStyle.defaultsFor(core.PenTool.highlighter); // 12 pt
  final width = hl.width;
  HighlighterStraightening mode(HighlighterStraightening m) =>
      hl.withHighlighterStraightening(m).highlighterStraightening;

  test('snapOnLift: nearly straight → 2 points', () {
    final pts = _stroke(angleDeg: 20, amp: 0.4);
    final out = straighten(
      pts,
      mode: mode(HighlighterStraightening.snapOnLift),
      width: width,
    );
    expect(out.length, 2);
    expect(out.first.position, pts.first.position);
    expect(out.last.position, pts.last.position); // 20°: no axis snap
    expect(out.first.t, pts.first.t);
    expect(out.last.t, pts.last.t);
  });

  test('snapOnLift: a wave is kept as drawn', () {
    final pts = _stroke(amp: 10);
    final out = straighten(
      pts,
      mode: mode(HighlighterStraightening.snapOnLift),
      width: width,
    );
    expect(identical(out, pts), isTrue);
  });

  test('snapOnLift: shorter than 2 · width is kept', () {
    final pts = _stroke(length: 20);
    expect(
      identical(
        straighten(
          pts,
          mode: HighlighterStraightening.snapOnLift,
          width: width,
        ),
        pts,
      ),
      isTrue,
    );
  });

  test('deviation limit = max(0.6 · width, 0.04 · L)', () {
    // L = 60: limit max(7.2, 2.4) = 7.2
    expect(isNearlyStraight(_stroke(amp: 7), width), isTrue);
    expect(isNearlyStraight(_stroke(amp: 7.5), width), isFalse);
    // a long stroke with a thin pen: 0.04 · L wins (L = 300 → 12)
    expect(
      isNearlyStraight(_stroke(length: 300, amp: 11, period: 100), 2),
      isTrue,
    );
    expect(
      isNearlyStraight(_stroke(length: 300, amp: 13, period: 100), 2),
      isFalse,
    );
  });

  test('3° tilt → snapped horizontal; 6° → left as is', () {
    final three = straighten(
      _stroke(angleDeg: 3),
      mode: HighlighterStraightening.snapOnLift,
      width: width,
    );
    expect(three.length, 2);
    expect(three.last.y, three.first.y);
    expect(three.last.x, closeTo(100 + 60 * math.cos(3 * math.pi / 180), 1e-9));

    final six = straighten(
      _stroke(angleDeg: 6),
      mode: HighlighterStraightening.snapOnLift,
      width: width,
    );
    expect(six.length, 2);
    expect(six.last.y, isNot(six.first.y));

    final vertical = straighten(
      _stroke(angleDeg: 87),
      mode: HighlighterStraightening.alwaysStraight,
      width: width,
    );
    expect(vertical.last.x, vertical.first.x);
    final up = straighten(
      _stroke(angleDeg: -92),
      mode: HighlighterStraightening.alwaysStraight,
      width: width,
    );
    expect(up.last.x, up.first.x);
    final left = straighten(
      _stroke(angleDeg: 177.5),
      mode: HighlighterStraightening.alwaysStraight,
      width: width,
    );
    expect(left.last.y, left.first.y);
  });

  test('alwaysStraight: start → end, even for a wave', () {
    final pts = _stroke(amp: 10, angleDeg: 30);
    final out = straighten(
      pts,
      mode: mode(HighlighterStraightening.alwaysStraight),
      width: width,
    );
    expect(out.length, 2);
    expect(out.first.position, pts.first.position);
    expect(out.last.position, pts.last.position);
    // the input points are not changed
    expect(pts.length, greaterThan(2));
  });

  test('alwaysStraight live: start → current position, axis snapped', () {
    const start = Offset(10, 10);
    expect(straightLine(start, const Offset(50, 30)), (
      start,
      const Offset(50, 30),
    ));
    expect(straightLine(start, const Offset(50, 11)), (
      start,
      const Offset(50, 10),
    ));
    expect(straightLine(start, const Offset(9, 60)), (
      start,
      const Offset(10, 60),
    ));
    expect(axisSnapped(start, start), start);
  });

  test('off (the default) and unknown values change nothing', () {
    final pts = _stroke(angleDeg: 2);
    expect(hl.highlighterStraightening, HighlighterStraightening.off);
    expect(
      identical(
        straighten(pts, mode: hl.highlighterStraightening, width: width),
        pts,
      ),
      isTrue,
    );
    final junk = hl.copyWith(extras: {'hlStraight': 'sideways'});
    expect(
      identical(
        straighten(pts, mode: junk.highlighterStraightening, width: width),
        pts,
      ),
      isTrue,
    );
  });
}
