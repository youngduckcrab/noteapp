// lib/src/input/input_sample.dart — 04-editor 6.5.5.
import 'package:flutter/gestures.dart';
import 'package:meta/meta.dart';

/// Routing view of one pointer event. No normalization here: pressure, tilt and
/// orientation are normalized by INK (ink.InkSampleAdapter, contract 7.2.15) when a
/// tool interaction converts the event (6.6.3).
@immutable
class InputSample {
  const InputSample(this.event);
  factory InputSample.fromEvent(PointerEvent event) => InputSample(event);

  /// The raw event (tools pass it to ink.InkSampleAdapter.fromPointerEvent).
  final PointerEvent event;

  int get pointer => event.pointer;
  PointerDeviceKind get kind => event.kind;
  Offset get position =>
      event.localPosition; // screen (viewport-local logical px)
  Duration get timeStamp => event.timeStamp;
  double get radiusMajor => event.radiusMajor; // 0 on web (P5 off)
  int get buttons => event.buttons;
}
