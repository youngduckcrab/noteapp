// Real-time waiting of the T16 integration tests. Real CORE runs on the real event loop and
// its write queue retries a failed commit on real timers (CORE 6.9), so these tests poll
// for a state instead of moving a fake clock, and never assert how long anything took.
//
// One budget per test: every wait of a test draws on the same [kIntegrationWaitBudget],
// and each test that waits passes `timeout: kIntegrationTimeout` — longer than the budget
// (the rest covers opening and closing the stores) — so a stuck wait fails with what it was
// waiting for instead of package:test's default 30 s timeout cutting in first.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Real time one test may spend waiting, all its waits together.
const Duration kIntegrationWaitBudget = Duration(minutes: 3);

/// package:test timeout of a test that waits: the budget plus one minute.
const Timeout kIntegrationTimeout = Timeout(Duration(minutes: 4));

const Duration _poll = Duration(milliseconds: 50);

/// The waits of one test (create it in setUp or at the start of the test).
final class RealTimeWaits {
  RealTimeWaits({this.budget = kIntegrationWaitBudget});

  final Duration budget;
  final Stopwatch _watch = Stopwatch()..start();

  /// Polls [done] every 50 ms until it holds; fails once the test's budget is spent.
  Future<void> until(String what, FutureOr<bool> Function() done) async {
    while (!await done()) {
      if (_watch.elapsed > budget) {
        fail('still waiting for $what: the test used its $budget wait budget');
      }
      await Future<void>.delayed(_poll);
    }
  }
}
