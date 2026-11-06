// lib/src/shape/hold_detector.dart — INTERNAL (m5-7/03-ink 6.18, T39).
//
// The hold of automatic shape correction: the pen stays within
// InkTuning.shapeHoldRadiusPx (logical px → page pt by the gesture's viewScale)
// of an anchor for InkTuning.shapeHoldMs.
//  * anchor = the first sample; a sample farther than the radius from it moves
//    the anchor there (its time becomes the anchor time) and re-arms the hold —
//    after a fired hold that is 'moving again' (onMove: the preview is dropped);
//  * a sample within the radius whose time is ≥ shapeHoldMs after the anchor
//    time fires the hold (once per anchor);
//  * a dart:async Timer of shapeHoldMs, started at every anchor change, fires it
//    when no sample comes (a pen held still sends none on some platforms).
// Clock rule (review S-8, 6.6-8): sample times are only compared with sample
// times, the timer only measures its own elapsed time — an event time is never
// subtracted from InkClock.nowUs() (native: alignedWithEventTimestamps false).
import 'dart:async';
import 'dart:ui' show Offset;

import 'package:meta/meta.dart';

import '../tuning.dart';

@internal
final class HoldDetector {
  /// Starts at the pen-down sample ([start] page pt, [startUs] its event time).
  /// [viewScale] = logical px per page pt at gesture start (> 0). [onHold] runs when
  /// the hold fires, [onMove] when the pen leaves the radius after a fired hold.
  HoldDetector({
    required Offset start,
    required int startUs,
    required double viewScale,
    required this._onHold,
    required this._onMove,
    int holdMs = InkTuning.shapeHoldMs,
    double radiusPx = InkTuning.shapeHoldRadiusPx,
  }) : _holdUs = holdMs * 1000,
       _radius2 = _square(radiusPx / viewScale),
       _anchor = start.isFinite ? start : Offset.zero,
       _anchorUs = startUs,
       _lastUs = startUs {
    _arm();
  }

  static double _square(double r) => r.isFinite && r > 0 ? r * r : 0;

  final void Function() _onHold;

  /// The pen left the radius after a fired hold (the preview, if any, is dropped).
  final void Function() _onMove;
  final int _holdUs;

  /// The radius in page pt, squared.
  final double _radius2;
  Offset _anchor;
  int _anchorUs;
  int _lastUs;
  bool _fired = false;
  bool _stopped = false;
  Timer? _timer;

  /// The hold fired for the current anchor (until the pen moves again).
  bool get fired => _fired;

  /// Where the pen is held (page pt) and since when (event µs).
  Offset get anchor => _anchor;
  int get anchorUs => _anchorUs;

  /// True while the no-sample timer is armed.
  bool get timerArmed => _timer != null;

  /// One more sample (page pt, event µs). A non-finite position is ignored; a time
  /// going backwards counts as the previous one (as the stroke builder, 6.3 (1)).
  void add(Offset position, int timeUs) {
    if (_stopped || !position.isFinite) return;
    final t = timeUs < _lastUs ? _lastUs : timeUs;
    _lastUs = t;
    final dx = position.dx - _anchor.dx, dy = position.dy - _anchor.dy;
    if (dx * dx + dy * dy > _radius2) {
      _anchor = position;
      _anchorUs = t;
      final wasFired = _fired;
      _fired = false;
      _arm();
      if (wasFired) _onMove();
    }
    if (!_fired && t - _anchorUs >= _holdUs) _fire();
  }

  /// No more samples: the timer is cancelled and nothing fires any more.
  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer(Duration(microseconds: _holdUs), _timerFired);
  }

  void _timerFired() {
    _timer = null;
    if (!_stopped && !_fired) _fire();
  }

  void _fire() {
    _fired = true;
    _timer?.cancel();
    _timer = null;
    _onHold();
  }
}
