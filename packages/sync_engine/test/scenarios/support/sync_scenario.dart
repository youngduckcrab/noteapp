// test/ only, NOT exported (contract 7.2.20 v1.1): lib/testing.dart never imports
// package:fake_async or package:flutter_test, so the scenario wrapper lives here (4.11).
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/testing.dart';

/// Default virtual start: 2026-11-01T00:00:00Z.
final DateTime kScenarioStart = DateTime.utc(2026, 11, 1);

/// test() + fakeAsync wrapper:
///   syncScenario('S01 basic', (h) { final a = h.device('A'); …; h.checkConverged([a, b]); });
/// Builds SyncTestHarness(clock: async.getClock(start), elapse: async.elapse,
/// flushMicrotasks: async.flushMicrotasks, seed: seed) inside fakeAsync(…, initialTime: start)
/// and tags the test 'scenario'.
void syncScenario(
  String description,
  void Function(SyncTestHarness h) body, {
  int seed = 1,
  DateTime? start,
}) {
  final at = start ?? kScenarioStart;
  test(description, () {
    fakeAsync((async) {
      final h = SyncTestHarness(
        clock: async.getClock(at),
        elapse: async.elapse,
        flushMicrotasks: async.flushMicrotasks,
        seed: seed,
      );
      body(h);
    }, initialTime: at);
  }, tags: ['scenario']);
}
