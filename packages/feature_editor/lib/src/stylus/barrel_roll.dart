// lib/src/stylus/barrel_roll.dart — m5-7/04-editor 6.5.4 (E2-18, P-B).
//
// The last Apple Pencil Pro barrel roll of this note screen → the
// calligraphy nib angle of the next stroke. Sources: StylusBarrelRoll.angle
// and StylusHoverPose.roll (a roll while hovering), both radians.
//
// The roll is only used for a pen down within [BarrelRollTracker.validFor] of
// it. (v2.1, CP-E6) With an event timestamp the age is the pen down's
// PointerEvent.timeStamp minus that timestamp; without one, the roll's
// arrival and the pen down are both read from the tracker's monotonic clock
// (a Stopwatch). The two bases are never compared with each other (6.5.3).
//
// Only that one stroke gets the turned angle: the pen setting
// (editor.penStyles) does not change (contract 7.2.9 — a fixed angle per
// stroke).
import 'dart:math' as math;

import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../di/stylus_extras.dart';
import '../input/input_router.dart' show MonotonicClock;

class BarrelRollTracker {
  /// [clock] measures a roll without a timestamp and the pen downs compared
  /// with it (default: a Stopwatch started now).
  BarrelRollTracker({MonotonicClock? clock}) : _clock = clock ?? _stopwatch();

  /// A roll older than this is ignored at pen down (6.5.4).
  static const Duration validFor = Duration(milliseconds: 500);

  final MonotonicClock _clock;

  double? _angle; // rad
  Duration? _stamp; // event timestamp (event base)
  Duration? _arrived; // on [_clock], when the event had no timestamp

  static MonotonicClock _stopwatch() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  /// The last roll (radians), or null before one.
  double? get lastAngle => _angle;

  /// A roll of [angle] radians arrived (StylusBarrelRoll.angle or
  /// StylusHoverPose.roll). Non-finite angles are ignored.
  void note(double angle, {Duration? timestamp}) {
    if (!angle.isFinite) return;
    _angle = angle;
    if (timestamp != null) {
      _stamp = timestamp;
      _arrived = null;
    } else {
      _stamp = null;
      _arrived = _clock();
    }
  }

  /// Forgets the last roll.
  void clear() {
    _angle = null;
    _stamp = null;
    _arrived = null;
  }

  /// The roll (radians) valid for a pen down whose PointerEvent.timeStamp is
  /// [downTimeStamp], or null (none, or older than [validFor]).
  double? rollAt(Duration downTimeStamp) {
    final angle = _angle;
    if (angle == null) return null;
    final stamp = _stamp;
    final Duration age;
    if (stamp != null) {
      // Same base as PointerEvent.timeStamp [추측 — C-1]: a small negative
      // difference (the roll stamped just after the down) still counts.
      age = (downTimeStamp - stamp).abs();
    } else {
      final arrived = _arrived;
      if (arrived == null) return null;
      age = _clock() - arrived;
      if (age.isNegative) return null;
    }
    return age <= validFor ? angle : null;
  }

  /// The style a pen down at [downTimeStamp] draws with: for a calligraphy
  /// pen that follows the roll (InkStyleExtras.followBarrelRoll) on a device
  /// whose source reports barrel rolls ([capabilities].barrelRoll), with a
  /// roll within [validFor]: nibAngleDeg' = (nibAngleDeg + roll · 180 / π)
  /// mod 180. Every other case → [style] unchanged (the fixed angle).
  core.StrokeStyle styleAtPenDown(
    core.StrokeStyle style, {
    required Duration downTimeStamp,
    required StylusCapabilities capabilities,
  }) {
    if (style.tool != core.PenTool.calligraphy) return style;
    if (!capabilities.barrelRoll) return style;
    if (!ink.StrokeStyleInk(style).followBarrelRoll) return style;
    final roll = rollAt(downTimeStamp);
    if (roll == null) return style;
    return ink.StrokeStyleInk(style).withInkExtras(
      nibAngleDeg: nibAngleWithRoll(
        ink.StrokeStyleInk(style).nibAngleDeg,
        roll,
      ),
    );
  }
}

/// (base + roll · 180 / π) mod 180, in [0, 180).
double nibAngleWithRoll(double baseDeg, double rollRad) {
  final folded = (baseDeg + rollRad * 180 / math.pi) % 180;
  return folded >= 180 ? 0 : folded;
}
