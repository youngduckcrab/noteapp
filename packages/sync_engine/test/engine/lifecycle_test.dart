// T10: app lifecycle (4.5 setLifecycle): background flushes at once, foreground after more
// than reconnectAfterBackground re-subscribes from the cursor; flushPendingUploads and
// syncNow.
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../support/engine_harness.dart';

void main() {
  harnessTest('background → the pending push goes at once (no debounce)', (
    h,
    async,
  ) {
    final a = liveDevice(h, 'A');
    final debounced = a.createNote('debounced');
    // One round trip (2 × 50 ms) is well inside the 500 ms debounce.
    h.elapse(const Duration(milliseconds: 150));
    expect(onServer(h, debounced), isFalse);
    h.settle();
    expect(onServer(h, debounced), isTrue);

    final flushed = a.createNote('flushed');
    a.engine.setLifecycle(SyncLifecycle.background);
    h.elapse(const Duration(milliseconds: 150));
    expect(onServer(h, flushed), isTrue);
  });

  harnessTest('foreground after more than 30 s → catchingUp from the cursor, a '
      'new live query', (h, async) {
    final a = liveDevice(h, 'A');
    final b = liveDevice(h, 'B');
    final log = EngineLog(a.engine);
    final watches = a.link.callCount(FakeOp.watch);
    final fetches = a.link.callCount(FakeOp.fetch);
    a.engine.setLifecycle(SyncLifecycle.background);
    h.elapse(const Duration(seconds: 31));
    a.engine.setLifecycle(SyncLifecycle.foreground);
    h.settle();
    expect(log.takePhases(), [
      SyncPhase.live,
      SyncPhase.catchingUp,
      SyncPhase.live,
    ]);
    expect(a.link.callCount(FakeOp.watch), watches + 1);
    expect(a.link.callCount(FakeOp.fetch), fetches + 1);
    final n = b.createNote('after the reconnect');
    h.settle();
    expect(a.doc(EntityKind.note, n), isNotNull);
  });

  harnessTest('foreground within 30 s keeps the live query', (h, async) {
    final a = liveDevice(h, 'A');
    final log = EngineLog(a.engine);
    final watches = a.link.callCount(FakeOp.watch);
    a.engine.setLifecycle(SyncLifecycle.background);
    h.elapse(const Duration(seconds: 30));
    a.engine.setLifecycle(SyncLifecycle.foreground);
    h.settle();
    expect(log.takePhases(), [SyncPhase.live]);
    expect(a.link.callCount(FakeOp.watch), watches);
    // A second background period starts its own clock.
    a.engine
      ..setLifecycle(SyncLifecycle.background)
      ..setLifecycle(SyncLifecycle.foreground);
    h.settle();
    expect(a.link.callCount(FakeOp.watch), watches);
  });

  group('flushPendingUploads', () {
    harnessTest('true once everything is sent, without waiting for the '
        'debounce', (h, async) {
      final a = liveDevice(h, 'A');
      final n = a.createNote('N');
      final result = h.run(
        a.engine.flushPendingUploads(),
        step: const Duration(milliseconds: 1),
      );
      expect(result, isTrue);
      expect(onServer(h, n), isTrue);
      expect(
        nowMillis(h) - kEngineStart.millisecondsSinceEpoch,
        lessThan(5000),
      );
    });

    harnessTest('false when the timeout ends first or the engine is offline', (
      h,
      async,
    ) {
      final a = liveDevice(h, 'A');
      a.link.failNext(
        const FakeErrorCode(SyncErrorCode.aborted),
        op: FakeOp.commit,
        times: 100,
      );
      a.createNote('N');
      final start = nowMillis(h);
      expect(
        h.run(
          a.engine.flushPendingUploads(timeout: const Duration(seconds: 2)),
        ),
        isFalse,
      );
      expect(nowMillis(h) - start, lessThanOrEqualTo(2010));
      a.goOffline();
      h.settle();
      expect(h.run(a.engine.flushPendingUploads()), isFalse);
      expect(nowMillis(h) - start, lessThan(5000));
    });

    harnessTest('true with nothing pending', (h, async) {
      final a = liveDevice(h, 'A');
      expect(h.run(a.engine.flushPendingUploads()), isTrue);
    });
  });

  group('syncNow', () {
    harnessTest('pushes without the debounce and pulls once', (h, async) {
      final a = liveDevice(h, 'A');
      final n = a.createNote('N');
      final fetches = a.link.callCount(FakeOp.fetch);
      final start = nowMillis(h);
      h.run(a.engine.syncNow(), step: const Duration(milliseconds: 1));
      expect(onServer(h, n), isTrue);
      expect(a.link.callCount(FakeOp.fetch), fetches + 1);
      expect(nowMillis(h) - start, lessThan(500));
      expect(a.engine.status.lastSyncedAt, nowMillis(h));
    });

    harnessTest('does nothing unless live', (h, async) {
      final a = liveDevice(h, 'A');
      a.goOffline();
      h.settle();
      final calls = a.link.callCount(FakeOp.any);
      h.run(a.engine.syncNow());
      expect(a.link.callCount(FakeOp.any), calls);
    });
  });
}
