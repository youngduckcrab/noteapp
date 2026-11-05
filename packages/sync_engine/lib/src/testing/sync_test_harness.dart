// Pure Dart: no package:fake_async / test / matcher (contract 7.2.20 v1.1). Virtual time is
// injected by the caller.
import 'package:clock/clock.dart';

import '../config.dart';
import 'fake_sync_server.dart';
import 'test_device.dart';

final class SyncTestHarness {
  /// [clock] is the base virtual clock (server time, no device offset); [elapse] advances
  /// virtual time and runs due timers and microtasks; [flushMicrotasks] runs pending
  /// microtasks only. With package:fake_async (test/ only):
  ///   SyncTestHarness(clock: async.getClock(start), elapse: async.elapse,
  ///       flushMicrotasks: async.flushMicrotasks)
  SyncTestHarness({
    required Clock clock,
    required void Function(Duration duration) elapse,
    required void Function() flushMicrotasks,
    int seed = 1,
  }) : server = FakeSyncServer(clock: clock),
       _clock = clock;

  final FakeSyncServer server;
  final Clock _clock;

  /// The injected base clock. Every engine's stopwatch comes from it (6.2.4); device clocks
  /// are this plus TestDevice.clockOffset.
  Clock get serverClock => _clock;

  TestDevice device(
    String name, {
    String uid = 'user-1',
    Duration clockOffset = Duration.zero,
    bool signedIn = true,
    SyncConfig? config,
    Duration latency = const Duration(milliseconds: 50),
  }) => throw UnimplementedError('SYNC T6');

  /// Flushes microtasks, then calls elapse([step]) until [future] completes; returns its
  /// value or rethrows its error. StateError after [timeout] of virtual time.
  T run<T>(
    Future<T> future, {
    Duration timeout = const Duration(minutes: 10),
    Duration step = const Duration(milliseconds: 10),
  }) => throw UnimplementedError('SYNC T6');

  /// Calls the injected elapse, then flushMicrotasks.
  void elapse(Duration duration) => throw UnimplementedError('SYNC T6');

  /// Elapses (in 10 ms steps) until every engine is idle (no pending, not pushing, no
  /// queued work, live or offline) or [max] (then StateError naming the busy devices).
  void settle({Duration max = const Duration(minutes: 5)}) =>
      throw UnimplementedError('SYNC T6');

  /// Convergence check without matcher: canonicalDump() equal on all devices (and equal to
  /// server.mergedState when [includeServer]); Note.updatedAt is left out on both sides
  /// (5.1.2 S-11). Throws StateError whose message lists every differing key (first 20)
  /// with each device's value; returns normally when converged.
  void checkConverged(
    Iterable<TestDevice> devices, {
    bool includeServer = true,
  }) => throw UnimplementedError('SYNC T6');
}
