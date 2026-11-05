@TestOn('browser')
library;

// T11 (03-ink 8, 4.12, 6.15): on the web InkClock.platform() is
// performance.now() — aligned with event timestamps, monotonic, on the same
// timeline as a DOM Event's timeStamp — so event→paint is meaningful there.
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';

@JS('Event')
extension type _DomEvent._(JSObject _) implements JSObject {
  external factory _DomEvent(String type);
  external double get timeStamp;
}

void main() {
  test('aligned with event timestamps', () {
    final clock = InkClock.platform();
    expect(clock.alignedWithEventTimestamps, isTrue);
    expect(
      InkDiagnostics(clock: clock).snapshot.clockAligned,
      isTrue,
      reason: 'the developer display shows event→paint as meaningful',
    );
  });

  test('monotonic, microseconds, never negative', () {
    final clock = InkClock.platform();
    var last = clock.nowUs();
    expect(last, greaterThanOrEqualTo(0));
    for (var i = 0; i < 20000; i++) {
      final now = clock.nowUs();
      expect(now, greaterThanOrEqualTo(last));
      last = now;
    }
    // a busy loop of ~2 ms moves the clock by about that much (µs units)
    final start = clock.nowUs();
    final watch = Stopwatch()..start();
    while (watch.elapsedMicroseconds < 2000) {}
    final moved = clock.nowUs() - start;
    expect(moved, inInclusiveRange(1000, 200000));
  });

  test('the same timeline as DOM Event.timeStamp', () {
    final clock = InkClock.platform();
    final before = clock.nowUs();
    final event = _DomEvent('ink-clock');
    final after = clock.nowUs();
    final eventUs = (event.timeStamp * 1000).round();
    // browsers coarsen both values (≥ 5 µs, Safari ≈ 1 ms)
    expect(eventUs, inInclusiveRange(before - 1000, after + 1000));
  });
}
