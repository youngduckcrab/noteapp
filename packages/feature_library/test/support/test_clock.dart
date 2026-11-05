// test/support/test_clock.dart — 05-library 5.7 (L0).
import 'package:clock/clock.dart';

/// Adjustable clock shared by the fake store and the screen (clockProvider =
/// store.clock).
final class TestClock {
  /// [start] defaults to 2026-11-04 14:05 local time.
  TestClock([DateTime? start])
    : current = start ?? DateTime(2026, 11, 4, 14, 5);

  /// The time every reader of [clock] sees.
  DateTime current;

  /// `Clock(() => current)` (package:clock, dev dependency). The same instance
  /// on every read, so tests can check which clock a store received.
  late final Clock clock = Clock(() => current);

  void advance(Duration d) => current = current.add(d);
}
