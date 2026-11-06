// m5-7/04-editor 8.2 E2-18, 6.5.4: BarrelRollTracker — the last Apple Pencil
// Pro barrel roll turns the calligraphy nib of the next stroke:
// nibAngleDeg' = (nibAngleDeg + roll · 180 / π) mod 180, only for a pen down
// within 500 ms of the roll (the event timestamp against the down's
// PointerEvent.timeStamp; without a timestamp the tracker's monotonic clock
// — the two bases never mixed), only for a calligraphy pen with
// followBarrelRoll on, only with capabilities.barrelRoll.
import 'dart:math' as math;

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/stylus/barrel_roll.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

const _roll = StylusCapabilities(barrelRoll: true);
const _t0 = Duration(seconds: 100);

double _rad(double deg) => deg * math.pi / 180;

core.StrokeStyle get _calligraphy =>
    core.StrokeStyle.defaultsFor(core.PenTool.calligraphy); // nib 45°

double _nib(core.StrokeStyle style) => ink.StrokeStyleInk(style).nibAngleDeg;

void main() {
  test('the default calligraphy nib is 45° and follows the roll', () {
    expect(_nib(_calligraphy), 45);
    expect(ink.StrokeStyleInk(_calligraphy).followBarrelRoll, isTrue);
  });

  test('roll 30° + base 45° → 75°; roll 170° + 45° → 35° (mod 180); '
      '−60° + 45° → 165°', () {
    final tracker = BarrelRollTracker();
    double at(double rollDeg) {
      tracker.note(_rad(rollDeg), timestamp: _t0);
      return _nib(
        tracker.styleAtPenDown(
          _calligraphy,
          downTimeStamp: _t0 + const Duration(milliseconds: 100),
          capabilities: _roll,
        ),
      );
    }

    expect(at(30), closeTo(75, 1e-9));
    expect(at(170), closeTo(35, 1e-9));
    expect(at(-60), closeTo(165, 1e-9));
    expect(at(135), closeTo(0, 1e-9)); // 180 → 0, never 180
    expect(nibAngleWithRoll(45, _rad(30)), closeTo(75, 1e-9));
    expect(nibAngleWithRoll(170, _rad(370)), closeTo(0, 1e-9));
  });

  test('only that stroke: the given style keeps its angle, other extras '
      'kept', () {
    final tracker = BarrelRollTracker()..note(_rad(30), timestamp: _t0);
    final style = ink.StrokeStyleInk(_calligraphy)
        .withInkExtras(nibAngleDeg: 60, nibAspect: 0.5);
    final turned = tracker.styleAtPenDown(
      style,
      downTimeStamp: _t0,
      capabilities: _roll,
    );
    expect(_nib(turned), closeTo(90, 1e-9));
    expect(ink.StrokeStyleInk(turned).nibAspect, 0.5);
    expect(turned.colorArgb, style.colorArgb);
    expect(turned.width, style.width);
    expect(_nib(style), 60);
  });

  test('timestamp base: a roll more than 500 ms before the down → the base '
      'angle; exactly 500 ms → turned; the monotonic clock is not used', () {
    var now = Duration.zero;
    final tracker = BarrelRollTracker(clock: () => now)
      ..note(_rad(30), timestamp: _t0);
    double nibAt(Duration down) => _nib(
      tracker.styleAtPenDown(
        _calligraphy,
        downTimeStamp: down,
        capabilities: _roll,
      ),
    );

    expect(nibAt(_t0 + const Duration(milliseconds: 500)), closeTo(75, 1e-9));
    expect(nibAt(_t0 + const Duration(milliseconds: 501)), 45);
    expect(nibAt(_t0 + const Duration(seconds: 3)), 45);
    // The clock moving on does not age a timestamped roll …
    now = const Duration(minutes: 5);
    expect(nibAt(_t0 + const Duration(milliseconds: 200)), closeTo(75, 1e-9));
    // … and a down stamped just before the roll still counts.
    expect(nibAt(_t0 - const Duration(milliseconds: 20)), closeTo(75, 1e-9));
    expect(tracker.rollAt(_t0 + const Duration(milliseconds: 600)), isNull);
  });

  test('no timestamp: the tracker clock (Stopwatch) measures the roll and '
      'the down; the down event timestamp is not compared with it', () {
    var now = const Duration(seconds: 7);
    final tracker = BarrelRollTracker(clock: () => now)..note(_rad(30));
    double nib() => _nib(
      tracker.styleAtPenDown(
        _calligraphy,
        // far from the clock's values: must not matter
        downTimeStamp: const Duration(hours: 3),
        capabilities: _roll,
      ),
    );

    now += const Duration(milliseconds: 499);
    expect(nib(), closeTo(75, 1e-9));
    now += const Duration(milliseconds: 2); // 501 ms after the roll
    expect(nib(), 45);
    // A new roll restarts the time; a timestamped roll after it uses its
    // own base again.
    tracker.note(_rad(10));
    expect(nib(), closeTo(55, 1e-9));
    tracker.note(_rad(20), timestamp: _t0);
    expect(nib(), 45); // 3 h − 100 s from the stamp
  });

  test('the default clock is a Stopwatch: a fresh roll is valid', () {
    final tracker = BarrelRollTracker()..note(_rad(30));
    expect(tracker.rollAt(Duration.zero), closeTo(_rad(30), 1e-12));
    expect(tracker.lastAngle, closeTo(_rad(30), 1e-12));
  });

  test('followBarrelRoll off → the base angle', () {
    final tracker = BarrelRollTracker()..note(_rad(30), timestamp: _t0);
    final off = ink.StrokeStyleInk(_calligraphy)
        .withInkExtras(followBarrelRoll: false);
    final out = tracker.styleAtPenDown(
      off,
      downTimeStamp: _t0,
      capabilities: _roll,
    );
    expect(out, same(off));
    expect(_nib(out), 45);
  });

  test('capabilities.barrelRoll false → the base angle (web, Android, '
      'older iPadOS)', () {
    final tracker = BarrelRollTracker()..note(_rad(30), timestamp: _t0);
    for (final caps in [
      StylusCapabilities.none,
      const StylusCapabilities(doubleTap: true, squeeze: true, hoverPose: true),
    ]) {
      final style = _calligraphy;
      final out = tracker.styleAtPenDown(
        style,
        downTimeStamp: _t0,
        capabilities: caps,
      );
      expect(out, same(style), reason: '$caps');
      expect(_nib(out), 45);
    }
  });

  test('other pens, no roll yet, a cleared or non-finite roll → the style '
      'unchanged', () {
    final tracker = BarrelRollTracker();
    final calligraphy = _calligraphy;
    expect(
      tracker.styleAtPenDown(
        calligraphy,
        downTimeStamp: _t0,
        capabilities: _roll,
      ),
      same(calligraphy),
    );
    tracker.note(_rad(30), timestamp: _t0);
    for (final tool in core.PenTool.values) {
      if (tool == core.PenTool.calligraphy) continue;
      final style = core.StrokeStyle.defaultsFor(tool);
      expect(
        tracker.styleAtPenDown(style, downTimeStamp: _t0, capabilities: _roll),
        same(style),
        reason: tool.name,
      );
    }
    tracker.note(double.nan, timestamp: _t0); // ignored: the 30° stays
    expect(tracker.lastAngle, closeTo(_rad(30), 1e-12));
    tracker.clear();
    expect(tracker.lastAngle, isNull);
    expect(
      tracker.styleAtPenDown(
        calligraphy,
        downTimeStamp: _t0,
        capabilities: _roll,
      ),
      same(calligraphy),
    );
  });
}
