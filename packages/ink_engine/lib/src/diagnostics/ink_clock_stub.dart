// lib/src/diagnostics/ink_clock_stub.dart — VM / native InkClock (Stopwatch).
import 'ink_clock.dart';

InkClock createPlatformInkClock() => _StopwatchInkClock();

final class _StopwatchInkClock implements InkClock {
  _StopwatchInkClock() : _watch = Stopwatch()..start();

  final Stopwatch _watch;

  @override
  int nowUs() => _watch.elapsedMicroseconds;

  @override
  bool get alignedWithEventTimestamps => false;
}
