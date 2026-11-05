// T10: the phase transitions of 6.8.2 on the fake server, network and local store — K3 is
// covered in clock_skew_guard_test, the account attach in auth_attach_test, the lifecycle in
// lifecycle_test. Every test runs on fakeAsync virtual time.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../support/engine_harness.dart';

const _user = AuthUser(uid: 'user-1');

void main() {
  test(
    'no backendFactory → disabled: start, syncNow and pause change nothing',
    () {
      fakeAsync((async) {
        final store = FakeLocalStore(
          nodeId: '00000000000000aa',
          clock: async.getClock(kEngineStart),
        );
        final engine = SyncEngine(local: store, auth: AuthService(null));
        expect(engine.status.phase, SyncPhase.disabled);
        expect(engine.status.display, SyncDisplayState.off);
        expect(engine.isStarted, isFalse);
        engine.start();
        async.flushMicrotasks();
        expect(engine.isStarted, isTrue);
        engine
          ..syncNow()
          ..setPaused(true)
          ..setLifecycle(SyncLifecycle.background);
        async.elapse(const Duration(minutes: 1));
        expect(engine.status.phase, SyncPhase.disabled);
        expect(engine.status.display, SyncDisplayState.off);
        bool? flushed;
        engine.flushPendingUploads().then((v) => flushed = v);
        async.flushMicrotasks();
        expect(flushed, isFalse);
        engine.dispose();
        async.flushMicrotasks();
      });
    },
  );

  group('connecting → initialSync / catchingUp → live', () {
    harnessTest('signed out, then signed in: connecting → initialSync → live, '
        'InitialSyncCompleted', (h, async) {
      final b = liveDevice(h, 'B');
      b.createNote('from B');
      h.settle();
      final a = h.device('A', signedIn: false);
      final log = EngineLog(a.engine);
      h.settle();
      expect(a.engine.status.phase, SyncPhase.signedOut);
      expect(a.engine.status.display, SyncDisplayState.off);
      expect(a.engine.status.user, isNull);
      a.auth.setUser(_user);
      h.settle();
      expect(log.phases, [
        SyncPhase.signedOut,
        SyncPhase.connecting,
        SyncPhase.initialSync,
        SyncPhase.live,
      ]);
      final status = a.engine.status;
      expect(status.user, _user);
      expect(status.display, SyncDisplayState.done);
      expect(status.initialSync, isNull);
      expect(status.lastSyncedAt, isNotNull);
      expect(status.isOnline, isTrue);
      final during = log.statuses.where(
        (s) => s.phase == SyncPhase.initialSync,
      );
      expect(during, isNotEmpty);
      expect(during.every((s) => s.initialSync != null), isTrue);
      expect(
        during.every((s) => s.display == SyncDisplayState.inProgress),
        isTrue,
      );
      final done = log.notices.whereType<InitialSyncCompleted>().single;
      expect(done.records, greaterThan(0));
      h.checkConverged([a, b]);
    });

    harnessTest('with a stored cursor: connecting → catchingUp → live', (
      h,
      async,
    ) {
      final a = liveDevice(h, 'A');
      final log = EngineLog(a.engine);
      a.auth.setUser(null);
      h.settle();
      a.auth.setUser(_user);
      h.settle();
      expect(log.phases, [
        SyncPhase.live,
        SyncPhase.signedOut,
        SyncPhase.connecting,
        SyncPhase.catchingUp,
        SyncPhase.live,
      ]);
      expect(log.notices.whereType<InitialSyncCompleted>(), isEmpty);
    });
  });

  harnessTest('live → catchingUp on a listener error, then live again', (
    h,
    async,
  ) {
    final a = liveDevice(h, 'A');
    final b = liveDevice(h, 'B');
    final log = EngineLog(a.engine);
    final watches = a.link.callCount(FakeOp.watch);
    a.link.failNext(const FakeNetworkError(), op: FakeOp.watch);
    // The 15-minute rollover opens a new query, which fails.
    h.elapse(const Duration(minutes: 15));
    h.settle();
    expect(log.takePhases(), [
      SyncPhase.live,
      SyncPhase.catchingUp,
      SyncPhase.live,
    ]);
    expect(a.link.callCount(FakeOp.watch), watches + 2);
    final n = b.createNote('after the error');
    h.settle();
    expect(a.doc(EntityKind.note, n), isNotNull);
  });

  group('→ offline and back', () {
    harnessTest('connecting → offline after two connection failures; the 30 s '
        'probe reconnects', (h, async) {
      final a = h.device('A');
      a.link.failNext(const FakeNetworkError(), op: FakeOp.profile, times: 2);
      final log = EngineLog(a.engine);
      h.settle();
      expect(log.takePhases(), [
        SyncPhase.signedOut,
        SyncPhase.connecting,
        SyncPhase.offline,
      ]);
      expect(a.link.callCount(FakeOp.profile), 2);
      final status = a.engine.status;
      expect(status.display, SyncDisplayState.offline);
      expect(status.isOnline, isFalse);
      // Offline since the last 10 ms settle step at most.
      expect(
        status.nextRetryAt,
        inInclusiveRange(nowMillis(h) + 29990, nowMillis(h) + 30000),
      );
      untilRetry(h, a);
      h.settle();
      expect(log.takePhases(), [
        SyncPhase.offline,
        SyncPhase.catchingUp,
        SyncPhase.initialSync,
        SyncPhase.live,
      ]);
      expect(a.engine.status.isOnline, isTrue);
    });

    harnessTest('initialSync → offline when two fetches fail; a failed probe '
        'stays offline', (h, async) {
      final a = h.device('A');
      a.link.failNext(const FakeNetworkError(), op: FakeOp.fetch, times: 3);
      final log = EngineLog(a.engine);
      h.settle();
      expect(log.takePhases(), [
        SyncPhase.signedOut,
        SyncPhase.connecting,
        SyncPhase.initialSync,
        SyncPhase.offline,
      ]);
      untilRetry(h, a); // the probe takes the third fault
      h.settle();
      expect(a.engine.status.phase, SyncPhase.offline);
      untilRetry(h, a);
      h.settle();
      expect(a.engine.status.phase, SyncPhase.live);
    });

    harnessTest('catchingUp → offline when two fetches fail', (h, async) {
      final a = liveDevice(h, 'A');
      a.auth.setUser(null);
      h.settle();
      a.link.failNext(const FakeNetworkError(), op: FakeOp.fetch, times: 2);
      final log = EngineLog(a.engine);
      a.auth.setUser(_user);
      h.settle();
      expect(log.takePhases(), [
        SyncPhase.signedOut,
        SyncPhase.connecting,
        SyncPhase.catchingUp,
        SyncPhase.offline,
      ]);
    });

    harnessTest(
      'live → offline on the signal; online again → catchingUp → live '
      'at once',
      (h, async) {
        final a = liveDevice(h, 'A');
        final b = liveDevice(h, 'B');
        final log = EngineLog(a.engine);
        a.goOffline();
        h.elapse(Duration.zero);
        expect(a.engine.status.phase, SyncPhase.offline);
        expect(a.engine.status.isOnline, isFalse);
        final mine = a.createNote('offline edit');
        final theirs = b.createNote('while A is offline');
        h.settle();
        expect(a.engine.status.pendingUploads, 2); // note + first page
        expect(a.engine.status.display, SyncDisplayState.offline);
        expect(onServer(h, mine), isFalse);
        a.goOnline();
        h.settle();
        expect(log.takePhases(), [
          SyncPhase.live,
          SyncPhase.offline,
          SyncPhase.catchingUp,
          SyncPhase.live,
        ]);
        expect(onServer(h, mine), isTrue);
        expect(a.doc(EntityKind.note, theirs), isNotNull);
        h.checkConverged([a, b]);
      },
    );

    harnessTest('live → offline after two failed pushes', (h, async) {
      final a = liveDevice(h, 'A');
      final log = EngineLog(a.engine);
      final commits = a.link.callCount(FakeOp.commit);
      a.link.failNext(const FakeNetworkError(), op: FakeOp.commit, times: 2);
      final n = a.createNote('N');
      h.settle();
      expect(log.takePhases(), [SyncPhase.live, SyncPhase.offline]);
      expect(a.link.callCount(FakeOp.commit), commits + 2);
      h.elapse(const Duration(seconds: 30));
      h.settle();
      expect(a.engine.status.phase, SyncPhase.live);
      expect(onServer(h, n), isTrue);
    });
  });

  group('live → error (halting issues) and back', () {
    for (final (code, issue) in [
      (SyncErrorCode.permissionDenied, SyncIssueCode.permissionDenied),
      (SyncErrorCode.failedPrecondition, SyncIssueCode.backendMisconfigured),
    ]) {
      harnessTest('${code.name} → error (${issue.name}), retried after 10 min '
          '→ catchingUp → live', (h, async) {
        final a = liveDevice(h, 'A');
        final log = EngineLog(a.engine);
        a.link.failNext(FakeErrorCode(code), op: FakeOp.commit);
        final n = a.createNote('N');
        h.settle();
        expect(log.takePhases(), [SyncPhase.live, SyncPhase.error]);
        final status = a.engine.status;
        expect(status.display, SyncDisplayState.error);
        expect(status.issues.first.code, issue);
        expect(status.issues.first.isBlocking, isTrue);
        expect(
          status.nextRetryAt,
          nowMillis(h) + const Duration(minutes: 10).inMilliseconds,
        );
        h.elapse(const Duration(minutes: 9, seconds: 59));
        expect(a.engine.status.phase, SyncPhase.error);
        h.elapse(const Duration(seconds: 1));
        h.settle();
        expect(log.takePhases(), [
          SyncPhase.error,
          SyncPhase.catchingUp,
          SyncPhase.live,
        ]);
        expect(a.engine.status.issues, isEmpty);
        expect(onServer(h, n), isTrue);
      });
    }

    harnessTest('the local store failing 5 times in a row → localStoreFailure; '
        'the retry recovers', (h, async) {
      final a = liveDevice(h, 'A');
      final n = a.createNote('N');
      a.store.failNextWrites(5);
      h.settle();
      expect(a.engine.status.phase, SyncPhase.error);
      final issue = issueOf(a, SyncIssueCode.localStoreFailure)!;
      expect(issue.isBlocking, isTrue);
      expect(a.engine.status.nextRetryAt, isNotNull);
      h.elapse(const Duration(minutes: 2));
      h.settle();
      expect(a.engine.status.phase, SyncPhase.live);
      expect(a.engine.status.issues, isEmpty);
      expect(onServer(h, n), isTrue);
      expect(a.engine.status.pendingUploads, 0);
    });

    harnessTest('unauthenticated: refreshed once and sent at once', (h, async) {
      final a = liveDevice(h, 'A');
      a.link.failNext(
        const FakeErrorCode(SyncErrorCode.unauthenticated),
        op: FakeOp.commit,
      );
      final n = a.createNote('N');
      h.settle();
      expect(a.engine.status.phase, SyncPhase.live);
      expect(a.engine.status.issues, isEmpty);
      expect(onServer(h, n), isTrue);
    });

    harnessTest('unauthenticated and the refresh fails → error '
        '(reauthRequired, no retry); signing in again → live', (h, async) {
      final a = liveDevice(h, 'A');
      a.link.failNext(
        const FakeErrorCode(SyncErrorCode.unauthenticated),
        op: FakeOp.commit,
      );
      a.auth.failNextRefresh();
      final n = a.createNote('N');
      h.settle();
      expect(a.engine.status.phase, SyncPhase.error);
      expect(issueOf(a, SyncIssueCode.reauthRequired)!.isBlocking, isTrue);
      expect(a.engine.status.nextRetryAt, isNull);
      h.elapse(const Duration(hours: 1));
      expect(a.engine.status.phase, SyncPhase.error);
      expect(onServer(h, n), isFalse);
      a.auth.setUser(null);
      h.settle();
      a.auth.setUser(_user);
      h.settle();
      expect(a.engine.status.phase, SyncPhase.live);
      expect(a.engine.status.issues, isEmpty);
      expect(onServer(h, n), isTrue);
    });

    harnessTest('unauthenticated while receiving: refresh once, then '
        'reauthRequired when it fails', (h, async) {
      final a = h.device('A');
      a.link.failNext(
        const FakeErrorCode(SyncErrorCode.unauthenticated),
        op: FakeOp.fetch,
      );
      h.settle();
      expect(a.engine.status.phase, SyncPhase.live);
      a.auth.setUser(null);
      h.settle();
      a.link.failNext(
        const FakeErrorCode(SyncErrorCode.unauthenticated),
        op: FakeOp.fetch,
      );
      a.auth.failNextRefresh();
      a.auth.setUser(_user);
      h.settle();
      expect(a.engine.status.phase, SyncPhase.error);
      expect(issueOf(a, SyncIssueCode.reauthRequired), isNotNull);
    });
  });

  harnessTest('resourceExhausted → quotaExceeded (not blocking), phase stays '
      'live, the push waits 5 min', (h, async) {
    final a = liveDevice(h, 'A');
    a.link.failNext(
      const FakeErrorCode(SyncErrorCode.resourceExhausted),
      op: FakeOp.commit,
    );
    final n = a.createNote('N');
    h.elapse(const Duration(seconds: 2));
    final status = a.engine.status;
    expect(status.phase, SyncPhase.live);
    final quota = issueOf(a, SyncIssueCode.quotaExceeded)!;
    expect(quota.isBlocking, isFalse);
    expect(status.display, SyncDisplayState.inProgress);
    expect(status.nextRetryAt, greaterThanOrEqualTo(nowMillis(h) + 290000));
    h.elapse(const Duration(minutes: 4, seconds: 55));
    expect(onServer(h, n), isFalse);
    h.settle();
    expect(onServer(h, n), isTrue);
    expect(issueOf(a, SyncIssueCode.quotaExceeded), isNull);
  });

  harnessTest('live → paused → catchingUp → live', (h, async) {
    final a = liveDevice(h, 'A');
    final b = liveDevice(h, 'B');
    final log = EngineLog(a.engine);
    h.run(a.engine.setPaused(true));
    expect(a.engine.status.phase, SyncPhase.paused);
    expect(a.engine.status.display, SyncDisplayState.off);
    final mine = a.createNote('paused edit');
    final theirs = b.createNote('while A is paused');
    h.settle();
    expect(onServer(h, mine), isFalse);
    expect(a.doc(EntityKind.note, theirs), isNull);
    h.run(a.engine.setPaused(false));
    h.settle();
    expect(log.takePhases(), [
      SyncPhase.live,
      SyncPhase.paused,
      SyncPhase.catchingUp,
      SyncPhase.live,
    ]);
    expect(onServer(h, mine), isTrue);
    expect(a.doc(EntityKind.note, theirs), isNotNull);
  });

  harnessTest('live → signedOut: the listener stops, local data stays', (
    h,
    async,
  ) {
    final a = liveDevice(h, 'A');
    final b = liveDevice(h, 'B');
    final kept = a.createNote('kept');
    h.settle();
    a.auth.setUser(null);
    h.settle();
    final status = a.engine.status;
    expect(status.phase, SyncPhase.signedOut);
    expect(status.display, SyncDisplayState.off);
    expect(status.user, isNull);
    final theirs = b.createNote('after sign-out');
    h.settle();
    expect(a.doc(EntityKind.note, theirs), isNull);
    expect(a.doc(EntityKind.note, kept), isNotNull);
  });

  harnessTest(
    'statusStream: the current status on listen, then never two equal '
    'values in a row',
    (h, async) {
      final a = liveDevice(h, 'A');
      final b = liveDevice(h, 'B');
      final log = EngineLog(a.engine);
      expect(log.statuses, isEmpty);
      h.elapse(Duration.zero);
      expect(log.statuses, [a.engine.status]);
      for (var i = 0; i < 5; i++) {
        a.createNote('a$i');
        b.createNote('b$i');
        h.elapse(const Duration(milliseconds: 120));
      }
      a.goOffline();
      a.goOnline();
      h.settle();
      h.elapse(
        const Duration(milliseconds: 250),
      ); // the last throttled change goes out
      expect(log.statuses.length, greaterThan(3));
      for (var i = 1; i < log.statuses.length; i++) {
        expect(log.statuses[i], isNot(log.statuses[i - 1]), reason: 'at $i');
      }
      expect(log.statuses.last, a.engine.status);
    },
  );
}
