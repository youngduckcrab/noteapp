// T03 (03-ink 8, 6.3): InkSampleAdapter normalizes Flutter pointer events
// (web W1–W4, iOS N1).
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';

const _page = Offset(12, 34);

InkSample _adapt(PointerEvent e) =>
    InkSampleAdapter.fromPointerEvent(e, pagePosition: _page);

void main() {
  test('web stylus move: signed tilt → |tilt|, orientation 0, time in µs', () {
    final s = _adapt(
      const PointerMoveEvent(
        timeStamp: Duration(microseconds: 1234567),
        kind: PointerDeviceKind.stylus,
        position: Offset(500, 600),
        pressure: 0.42,
        pressureMin: 0, // web: PointerData default 0 (W2)
        tilt: -0.6,
      ),
    );
    expect(s.position, _page); // EDITOR's page position, not the event's
    expect(s.timeUs, 1234567);
    expect(s.kind, InkPointerKind.stylus);
    expect(s.pressure, 0.42);
    expect(s.pressureMin, 0);
    expect(s.pressureMax, 1);
    expect(s.normalizedPressure, closeTo(0.42, 1e-12));
    expect(s.tilt, closeTo(0.6, 1e-12));
    expect(s.orientation, 0);
  });

  test('tilt is clamped to [0, pi/2]; NaN tilt / orientation → 0', () {
    final big = _adapt(
      const PointerMoveEvent(kind: PointerDeviceKind.stylus, tilt: -2.5),
    );
    expect(big.tilt, math.pi / 2);
    final nan = _adapt(
      const PointerMoveEvent(
        kind: PointerDeviceKind.stylus,
        tilt: double.nan,
        orientation: double.nan,
      ),
    );
    expect(nan.tilt, 0);
    expect(nan.orientation, 0);
    final o = _adapt(
      const PointerMoveEvent(kind: PointerDeviceKind.stylus, orientation: -1.2),
    );
    expect(o.orientation, -1.2);
  });

  test('up and cancel report no pressure (web up events carry 0)', () {
    final up = _adapt(
      const PointerUpEvent(kind: PointerDeviceKind.stylus, pressure: 0),
    );
    expect(up.pressure, isNull);
    expect(up.normalizedPressure, isNull);
    final cancel = _adapt(
      const PointerCancelEvent(kind: PointerDeviceKind.stylus),
    );
    expect(cancel.pressure, isNull);
  });

  test('iOS: pressureMax 4.17 is normalized by min / max', () {
    final s = _adapt(
      const PointerMoveEvent(
        kind: PointerDeviceKind.stylus,
        pressure: 2.085,
        pressureMin: 0,
        pressureMax: 4.17,
      ),
    );
    expect(s.pressure, 2.085);
    expect(s.pressureMax, 4.17);
    expect(s.normalizedPressure, closeTo(0.5, 1e-12));
    final over = _adapt(
      const PointerMoveEvent(
        kind: PointerDeviceKind.stylus,
        pressure: 5,
        pressureMin: 0,
        pressureMax: 4.17,
      ),
    );
    expect(over.normalizedPressure, 1);
  });

  test('max == min (iOS finger) → normalizedPressure null', () {
    final s = _adapt(
      const PointerMoveEvent(
        kind: PointerDeviceKind.touch,
        pressure: 1,
        pressureMin: 1,
        pressureMax: 1,
      ),
    );
    expect(s.kind, InkPointerKind.touch);
    expect(s.pressure, 1);
    expect(s.normalizedPressure, isNull);
    const tiny = InkSample(
      position: Offset.zero,
      timeUs: 0,
      kind: InkPointerKind.touch,
      pressure: 0.5,
      pressureMin: 0.5,
      pressureMax: 0.5000001,
    );
    expect(tiny.normalizedPressure, isNull);
  });

  test('mouse and trackpad report no pressure', () {
    final m = _adapt(
      const PointerDownEvent(kind: PointerDeviceKind.mouse, pressure: 1),
    );
    expect(m.kind, InkPointerKind.mouse);
    expect(m.pressure, isNull);
    // Trackpad events are pan / zoom events (Flutter asserts on other kinds).
    final t = _adapt(const PointerPanZoomStartEvent());
    expect(t.kind, InkPointerKind.trackpad);
    expect(t.pressure, isNull);
  });

  test('kind mapping (W1); inverted stylus is passed on as is', () {
    const map = {
      PointerDeviceKind.stylus: InkPointerKind.stylus,
      PointerDeviceKind.invertedStylus: InkPointerKind.invertedStylus,
      PointerDeviceKind.touch: InkPointerKind.touch,
      PointerDeviceKind.mouse: InkPointerKind.mouse,
      PointerDeviceKind.trackpad: InkPointerKind.trackpad,
      PointerDeviceKind.unknown: InkPointerKind.unknown,
    };
    expect(map.keys.toSet(), PointerDeviceKind.values.toSet());
    for (final MapEntry(:key, :value) in map.entries) {
      final event = key == PointerDeviceKind.trackpad
          ? const PointerPanZoomStartEvent()
          : PointerDownEvent(kind: key);
      expect(_adapt(event).kind, value);
    }
    final inv = _adapt(
      const PointerDownEvent(
        kind: PointerDeviceKind.invertedStylus,
        pressure: 0.3,
      ),
    );
    expect(inv.pressure, 0.3);
  });
}
