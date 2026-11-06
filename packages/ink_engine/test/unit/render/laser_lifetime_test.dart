// m5-7/03-ink T30 (6.6-2, review S-8): the laser trail's lifetime on a FakeInkClock.
// While the pen is down, the tail older than laserFadeMs fades (and drops off once
// fully faded — a long circle never fills the screen); after the lift the whole
// trail fades to 0 at laserFadeMs, then the trail is removed; a 17th trail removes
// the oldest; laserFadeMs is read with its [300, 5000] clamp; and the lifetimes use
// the InkClock time of arrival only — samples whose event times are far from the
// InkClock (native) give the same lifetimes.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show laserTrailsOf;
import 'package:ink_engine/src/render/laser_trail.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

InkSample _at(double x, double y, int timeUs) => InkSample(
  position: ui.Offset(x, y),
  timeUs: timeUs,
  kind: InkPointerKind.stylus,
  pressure: 0.5,
);

core.StrokeStyle _laser({int? fadeMs}) {
  final s = core.StrokeStyle.defaultsFor(core.PenTool.laser);
  return fadeMs == null ? s : s.withInkExtras(laserFadeMs: fadeMs);
}

void main() {
  late FakeInkClock clock;
  late InkPageController c;

  setUp(() {
    clock = FakeInkClock(startUs: 1000000);
    c = createTestPageController(clock: clock)
      ..updateContent(SyntheticInk.pageContent());
  });
  tearDown(() => c.dispose());

  /// Writes a horizontal laser line of [n] samples, [dtMs] of InkClock apart (event
  /// times from [eventUs] — another clock); returns the open session.
  StrokeSession write({
    int n = 40,
    double dtMs = 10,
    int eventUs = 0,
    double y = 100,
    core.StrokeStyle? style,
  }) {
    final session = c.beginStroke(
      _at(20, y, eventUs),
      style: style ?? _laser(),
      viewScale: 1,
    );
    for (var i = 1; i < n; i++) {
      clock.advanceMs(dtMs);
      session.addSample(_at(20 + 5.0 * i, y, eventUs + i * 8333));
    }
    return session;
  }

  List<double> opacities(LaserTrail t) => [
    for (var i = 0; i < t.length; i++) t.opacityAt(i, clock.nowUs()),
  ];

  test('a laser session draws a trail; end() → null, nothing pending', () {
    final s = write();
    final trails = laserTrailsOf(c);
    expect(trails.trails, hasLength(1));
    expect(trails.trails.single.isWritten, isTrue);
    expect(trails.trails.single.length, greaterThan(20));
    expect(s.live.frozenPath.getBounds().isEmpty, isTrue);
    expect(s.end(_at(220, 100, 0)), isNull);
    expect(c.pendingIds, isEmpty);
    expect(trails.trails.single.isWritten, isFalse);
  });

  test('while written: the tail older than laserFadeMs fades, fresh points '
      'stay opaque; fully faded points drop off', () {
    // 1500 ms default: 400 samples × 10 ms = 4 s of writing
    final s = c.beginStroke(_at(20, 100, 0), style: _laser(), viewScale: 1);
    final t = laserTrailsOf(c).trails.single;
    for (var i = 1; i < 400; i++) {
      clock.advanceMs(10);
      s.addSample(
        _at(200 + 100 * math.cos(i / 20), 200 + 100 * math.sin(i / 20), 0),
      );
      laserTrailsOf(c).prune(clock.nowUs());
    }
    final o = opacities(t);
    expect(o.last, 1, reason: 'the newest point');
    // the newest 1500 ms (≈ 150 points) are opaque
    for (final v in o.sublist(o.length - 140)) {
      expect(v, 1);
    }
    // older ones fade: decreasing towards the head, the head nearly gone
    expect(o.first, lessThan(0.2));
    expect(o[o.length ~/ 4], lessThan(1));
    for (var i = 1; i < o.length; i++) {
      expect(o[i], greaterThanOrEqualTo(o[i - 1] - 1e-12));
    }
    // points older than 2 × 1500 ms are gone: ≤ 3000 ms of points (+ 1 kept)
    expect(t.length, lessThanOrEqualTo(302));
    expect(t.length, greaterThan(250));
    s.end();
  });

  test('after the lift: the whole trail fades to 0 at laserFadeMs, then it is '
      'removed', () {
    final s = write(n: 20);
    final t = laserTrailsOf(c).trails.single;
    s.end();
    expect(opacities(t).every((v) => v == 1), isTrue, reason: 'at the lift');
    clock.advanceMs(750);
    for (final v in opacities(t)) {
      expect(v, closeTo(0.5, 1e-9));
    }
    expect(laserLevelOf(0.5), 0.5);
    expect(laserLevelOf(0.51), 5 / 8, reason: '8 levels');
    clock.advanceMs(749);
    expect(laserTrailsOf(c).prune(clock.nowUs()), isTrue);
    for (final v in opacities(t)) {
      expect(v, greaterThan(0));
    }
    clock.advanceMs(1);
    for (final v in opacities(t)) {
      expect(v, 0, reason: 'laserFadeMs after the lift');
    }
    expect(laserTrailsOf(c).prune(clock.nowUs()), isFalse);
    expect(laserTrailsOf(c).trails, isEmpty, reason: 'then removed');
  });

  test('the 17th trail removes the oldest (laserMaxTrails = 16)', () {
    expect(InkTuning.laserMaxTrails, 16);
    final first = <LaserTrail>[];
    for (var k = 0; k < 17; k++) {
      write(n: 3, dtMs: 1, y: 20.0 + 10 * k).end();
      first.add(laserTrailsOf(c).trails.last);
    }
    final trails = laserTrailsOf(c).trails;
    expect(trails, hasLength(16));
    expect(trails.contains(first.first), isFalse, reason: 'the oldest went');
    expect(trails.first, same(first[1]));
    expect(trails.last, same(first.last));
  });

  for (final (asked, used) in [
    (300, 300),
    (5000, 5000),
    (100, 300),
    (9000, 5000),
  ]) {
    test('laserFadeMs $asked → a $used ms fade', () {
      final s = write(n: 5, style: _laser(fadeMs: asked));
      final t = laserTrailsOf(c).trails.single;
      expect(t.fadeUs, used * 1000);
      s.end();
      clock.advanceMs(used - 1.0);
      expect(laserTrailsOf(c).prune(clock.nowUs()), isTrue);
      expect(t.opacityAt(0, clock.nowUs()), greaterThan(0));
      clock.advanceMs(1);
      expect(t.opacityAt(0, clock.nowUs()), 0);
      expect(laserTrailsOf(c).prune(clock.nowUs()), isFalse);
    });
  }

  test('S-8: event times far from the InkClock (native) give the same '
      'lifetimes — only InkClock times of arrival count', () {
    List<double> run(int eventUs) {
      final s = write(n: 30, dtMs: 100, eventUs: eventUs);
      final t = laserTrailsOf(c).trails.last;
      final writing = opacities(t);
      s.end();
      clock.advanceMs(600);
      return [...writing, ...opacities(t)];
    }

    final aligned = run(clock.nowUs());
    clock.advanceMs(10000); // the first trail is gone
    laserTrailsOf(c).prune(clock.nowUs());
    final skewed = run(987654321000); // a different time base, 11 days away
    clock.advanceMs(10000);
    laserTrailsOf(c).prune(clock.nowUs());
    final backwards = run(-5000000);
    expect(skewed, aligned);
    expect(backwards, aligned);
    // and the tail faded while written (2.9 s of writing at 1.5 s)
    expect(aligned.first, lessThan(1));
  });

  test('cancel() removes the trail at once', () {
    final s = write(n: 10);
    expect(laserTrailsOf(c).trails, hasLength(1));
    s.cancel();
    expect(laserTrailsOf(c).trails, isEmpty);
  });
}
