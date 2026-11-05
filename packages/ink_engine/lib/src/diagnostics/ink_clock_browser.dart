// lib/src/diagnostics/ink_clock_browser.dart — web InkClock: performance.now(), the
// timeline of DOM event.timeStamp (6.2 W6 / W7). Only this file uses dart:js_interop.
import 'dart:js_interop';

import 'ink_clock.dart';

InkClock createPlatformInkClock() => const _PerformanceInkClock();

@JS('performance')
external _Performance get _performance;

extension type _Performance._(JSObject _) implements JSObject {
  external double now();
}

final class _PerformanceInkClock implements InkClock {
  const _PerformanceInkClock();

  @override
  int nowUs() => (_performance.now() * 1000).round();

  @override
  bool get alignedWithEventTimestamps => true;
}
