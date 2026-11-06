// lib/src/input/input_thresholds.dart — 04-editor 6.5.5 / 6.5.8; (v2)
// m5-7/04-editor 6.3.7 (the pen dot tap of contract R-5 (v2.1)).
import 'package:meta/meta.dart';

@immutable
class InputThresholds {
  const InputThresholds({
    this.touchSlop = 18.0, // = kTouchSlop
    this.scaleSlop = 18.0, // = kScaleSlop
    this.multiTapMaxDuration = const Duration(milliseconds: 350),
    this.singleTapMaxDuration = const Duration(milliseconds: 250),
    this.tapMaxMovement = 20.0,
    this.longPressDuration = const Duration(milliseconds: 500),
    this.longPressMaxMovement = 10.0,
    this.fingerStrokeCancelWindow = const Duration(milliseconds: 250),
    this.fingerStrokeCancelDistance = 12.0,
    this.minFlingVelocity = 50.0, // = kMinFlingVelocity
    this.maxFlingVelocity = 8000.0, // = kMaxFlingVelocity
    this.penTapMaxMovement = 4.0,
    this.penTapMaxDuration = const Duration(milliseconds: 200),
  });
  final double touchSlop;
  final double scaleSlop;
  final Duration multiTapMaxDuration;
  final Duration singleTapMaxDuration;
  final double tapMaxMovement;
  final Duration longPressDuration;
  final double longPressMaxMovement;
  final Duration fingerStrokeCancelWindow;
  final double fingerStrokeCancelDistance;
  final double minFlingVelocity;
  final double maxFlingVelocity;

  /// (v2) A pen dot tap (6.3.5): the contact moved at most this far …
  final double penTapMaxMovement;

  /// … and lasted at most this long (separate from the finger tap 20 px ·
  /// 250 ms).
  final Duration penTapMaxDuration;
}
