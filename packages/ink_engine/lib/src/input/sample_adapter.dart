// lib/src/input/sample_adapter.dart — contract 7.2.15 (03-ink 4.3, rules 6.3).
import 'dart:math' as math;

import 'package:flutter/gestures.dart';

import 'ink_sample.dart';

abstract final class InkSampleAdapter {
  /// Normalizes [event] (6.3): kind mapping (W1), pressure null on up / cancel and for
  /// mouse / trackpad, min / max kept as reported, tilt = clamp(|tilt|, 0, pi/2)
  /// (web reports a signed value, W3), NaN tilt / orientation → 0,
  /// timeUs = event.timeStamp.inMicroseconds. [pagePosition] is the event position
  /// already converted to page pt by EDITOR.
  static InkSample fromPointerEvent(
    PointerEvent event, {
    required Offset pagePosition,
  }) {
    final kind = _kindOf(event.kind);
    final noPressure =
        event is PointerUpEvent ||
        event is PointerCancelEvent ||
        kind == InkPointerKind.mouse ||
        kind == InkPointerKind.trackpad;
    final tilt = event.tilt.isNaN
        ? 0.0
        : event.tilt.abs().clamp(0.0, math.pi / 2).toDouble();
    final orientation = event.orientation.isNaN ? 0.0 : event.orientation;
    return InkSample(
      position: pagePosition,
      timeUs: event.timeStamp.inMicroseconds,
      kind: kind,
      pressure: noPressure ? null : event.pressure,
      pressureMin: event.pressureMin,
      pressureMax: event.pressureMax,
      tilt: tilt,
      orientation: orientation,
    );
  }

  static InkPointerKind _kindOf(PointerDeviceKind kind) => switch (kind) {
    PointerDeviceKind.stylus => InkPointerKind.stylus,
    PointerDeviceKind.invertedStylus => InkPointerKind.invertedStylus,
    PointerDeviceKind.touch => InkPointerKind.touch,
    PointerDeviceKind.mouse => InkPointerKind.mouse,
    PointerDeviceKind.trackpad => InkPointerKind.trackpad,
    PointerDeviceKind.unknown => InkPointerKind.unknown,
  };
}
