// lib/src/diagnostics/ink_clock.dart — 03-ink 4.12. The only platform split of INK:
// the stub uses Stopwatch (VM / native), the browser file performance.now().
import 'ink_clock_stub.dart'
    if (dart.library.js_interop) 'ink_clock_browser.dart';

abstract interface class InkClock {
  /// Platform clock (web: performance.now(), VM / native: a monotonic Stopwatch).
  factory InkClock.platform() => createPlatformInkClock();

  /// Monotonic microseconds. Web: performance.now() — same timeline as PointerEvent.timeStamp.
  int nowUs();

  /// True when nowUs() shares the origin of event timestamps (web: true; native: false for now).
  bool get alignedWithEventTimestamps;
}
