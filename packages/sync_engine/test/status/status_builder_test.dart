// T10: StatusBuilder (6.12): the display table (CORE SyncDisplayState), issues blocking
// first, and the publishing rule — phase / display changes at once, anything else at most
// once per 250 ms, never two equal values in a row.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/note_core.dart' show EntityKind, EntityRef;
import 'package:sync_engine/src/status/status_builder.dart';
import 'package:sync_engine/sync_engine.dart';

const Duration _throttle = Duration(milliseconds: 250);

core.SyncDisplayState displayOf({
  required SyncPhase phase,
  bool blocking = false,
  int quarantined = 0,
  int pending = 0,
  bool pushing = false,
  AssetTransferSummary assets = AssetTransferSummary.idle,
}) => StatusBuilder.displayOf(
  phase: phase,
  hasBlockingIssue: blocking,
  quarantinedUploads: quarantined,
  pendingUploads: pending,
  isPushing: pushing,
  assets: assets,
);

/// A builder on fakeAsync time and what it published.
final class Rig {
  Rig(this.async, {SyncPhase phase = SyncPhase.live}) {
    builder = StatusBuilder(
      phase: phase,
      throttle: _throttle,
      nowMillis: () => 1000 + async.elapsed.inMilliseconds,
    );
    builder.published.listen((s) => _out.add((async.elapsed, s)));
  }

  final FakeAsync async;
  late final StatusBuilder builder;
  final List<(Duration, SyncStatus)> _out = [];

  /// What was published so far (broadcast delivery runs in microtasks).
  List<(Duration, SyncStatus)> get out {
    async.flushMicrotasks();
    return _out;
  }

  List<Duration> get times => [for (final (t, _) in out) t];
}

void main() {
  group('display (table 6.12, first match from the top)', () {
    test('off: disabled, signedOut, paused — whatever else is set', () {
      for (final phase in [
        SyncPhase.disabled,
        SyncPhase.signedOut,
        SyncPhase.paused,
      ]) {
        expect(
          displayOf(phase: phase, blocking: true, pending: 3, pushing: true),
          core.SyncDisplayState.off,
          reason: phase.name,
        );
      }
    });

    test('error: a blocking issue or quarantined uploads, before offline and '
        'progress', () {
      for (final phase in [
        SyncPhase.live,
        SyncPhase.offline,
        SyncPhase.error,
        SyncPhase.connecting,
        SyncPhase.catchingUp,
      ]) {
        expect(
          displayOf(phase: phase, blocking: true, pending: 2),
          core.SyncDisplayState.error,
        );
        expect(
          displayOf(phase: phase, quarantined: 1, pushing: true),
          core.SyncDisplayState.error,
        );
      }
    });

    test('offline: phase offline (pending uploads do not change it)', () {
      expect(
        displayOf(phase: SyncPhase.offline, pending: 5),
        core.SyncDisplayState.offline,
      );
    });

    test('inProgress: connecting / initialSync / catchingUp, pending, pushing, '
        'asset uploads; asset downloads do not count', () {
      for (final phase in [
        SyncPhase.connecting,
        SyncPhase.initialSync,
        SyncPhase.catchingUp,
      ]) {
        expect(displayOf(phase: phase), core.SyncDisplayState.inProgress);
      }
      expect(
        displayOf(phase: SyncPhase.live, pending: 1),
        core.SyncDisplayState.inProgress,
      );
      expect(
        displayOf(phase: SyncPhase.live, pushing: true),
        core.SyncDisplayState.inProgress,
      );
      expect(
        displayOf(
          phase: SyncPhase.live,
          assets: const AssetTransferSummary(uploadsPending: 1),
        ),
        core.SyncDisplayState.inProgress,
      );
      expect(
        displayOf(
          phase: SyncPhase.live,
          assets: const AssetTransferSummary(
            uploadBytesDone: 10,
            uploadBytesTotal: 20,
          ),
        ),
        core.SyncDisplayState.inProgress,
      );
      expect(
        displayOf(
          phase: SyncPhase.live,
          assets: const AssetTransferSummary(
            downloadsActive: 2,
            downloadBytesTotal: 100,
          ),
        ),
        core.SyncDisplayState.done,
      );
    });

    test('done: live with nothing waiting (non-blocking issues allowed)', () {
      expect(displayOf(phase: SyncPhase.live), core.SyncDisplayState.done);
      fakeAsync((async) {
        final r = Rig(async);
        r.builder.raiseIssue('w', SyncIssueCode.clockSkewWarning, 'warn');
        expect(r.builder.status.display, core.SyncDisplayState.done);
        r.builder.setIssue('b', SyncIssueCode.permissionDenied, 'denied');
        expect(r.builder.status.display, core.SyncDisplayState.error);
        expect(r.builder.status.hasBlockingIssue, isTrue);
      });
    });

    test('SyncStatus.display is the CORE type and feeds syncBadgeOf', () {
      fakeAsync((async) {
        final r = Rig(async)..builder.pendingUploads = 2;
        final core.SyncDisplayState display = r.builder.status.display;
        expect(display, core.SyncDisplayState.inProgress);
        expect(
          syncBadgeOf(r.builder.status),
          const core.SyncBadge(
            display: core.SyncDisplayState.inProgress,
            pendingChanges: 2,
          ),
        );
      });
    });
  });

  group('issues', () {
    test('blocking first, otherwise in the order first raised', () {
      fakeAsync((async) {
        final b = Rig(async).builder
          ..raiseIssue('m', SyncIssueCode.malformedRemoteData, 'bad chunk')
          ..setIssue('w', SyncIssueCode.clockSkewWarning, 'warn')
          ..setIssue('k', SyncIssueCode.clockSkew, 'held', nodeId: 'n1')
          ..setIssue('a', SyncIssueCode.reauthRequired, 'sign in');
        expect(
          [for (final i in b.status.issues) i.code],
          [
            SyncIssueCode.clockSkew,
            SyncIssueCode.reauthRequired,
            SyncIssueCode.malformedRemoteData,
            SyncIssueCode.clockSkewWarning,
          ],
        );
        expect(b.status.issues.first.nodeId, 'n1');
      });
    });

    test('raiseIssue counts (firstAt kept, lastAt moves); setIssue keeps '
        'count and times', () {
      fakeAsync((async) {
        final b = Rig(async).builder;
        const ref = EntityRef(EntityKind.note, 'n1');
        b.raiseIssue('x', SyncIssueCode.foreignOwnerData, 'skip', ref: ref);
        async.elapse(const Duration(seconds: 2));
        b.raiseIssue('x', SyncIssueCode.foreignOwnerData, 'skip', ref: ref);
        final counted = b.status.issues.single;
        expect(counted.count, 2);
        expect(counted.firstAt, 1000);
        expect(counted.lastAt, 3000);
        expect(counted.ref, ref);
        async.elapse(const Duration(seconds: 2));
        b.setIssue('x', SyncIssueCode.foreignOwnerData, 'skip', ref: ref);
        expect(b.status.issues.single, counted);
        b.setIssue('x', SyncIssueCode.foreignOwnerData, 'new text', ref: ref);
        expect(b.status.issues.single.message, 'new text');
        expect(b.status.issues.single.count, 2);
        expect(b.status.issues.single.firstAt, 1000);
      });
    });

    test('clearIssue / clearIssues remove by key', () {
      fakeAsync((async) {
        final b = Rig(async).builder
          ..setIssue('q:1', SyncIssueCode.rejectedByServer, 'r1')
          ..setIssue('q:2', SyncIssueCode.entityTooLarge, 'r2')
          ..setIssue('halt', SyncIssueCode.permissionDenied, 'p');
        b.clearIssue('halt');
        expect(b.status.issues, hasLength(2));
        b.clearIssues((key, issue) => key.startsWith('q:'));
        expect(b.status.issues, isEmpty);
        b.clearIssue('missing');
      });
    });
  });

  group('publishing', () {
    test(
      'changes outside phase / display: the first at once, then at most once '
      'per 250 ms with the latest value',
      () {
        fakeAsync((async) {
          final r = Rig(async)..builder.pendingUploads = 1;
          expect(r.times, [Duration.zero]);
          // Ten more changes 20 ms apart, all inside the first cool-down. The display stays
          // inProgress.
          for (var i = 2; i <= 11; i++) {
            async.elapse(const Duration(milliseconds: 20));
            r.builder.pendingUploads = i;
          }
          expect(r.out, hasLength(1));
          async.elapse(const Duration(milliseconds: 50)); // 250 ms
          expect(r.times, [Duration.zero, _throttle]);
          expect(r.out.last.$2.pendingUploads, 11);
          async.elapse(const Duration(seconds: 1));
          expect(r.out, hasLength(2));
        });
      },
    );

    test(
      'phase and display changes go out at once, even while cooling down',
      () {
        fakeAsync((async) {
          final r = Rig(async)..builder.pendingUploads = 1;
          async.elapse(const Duration(milliseconds: 10));
          r.builder.phase = SyncPhase.offline;
          expect(r.times, [Duration.zero, const Duration(milliseconds: 10)]);
          expect(r.out.last.$2.display, core.SyncDisplayState.offline);
          async.elapse(const Duration(milliseconds: 10));
          r.builder.phase = SyncPhase.live;
          r.builder.pendingUploads = 0; // inProgress → done: a display change
          expect(r.out.map((e) => e.$2.display), [
            core.SyncDisplayState.inProgress,
            core.SyncDisplayState.offline,
            core.SyncDisplayState.inProgress,
            core.SyncDisplayState.done,
          ]);
          async.elapse(const Duration(seconds: 1));
          expect(r.out, hasLength(4));
        });
      },
    );

    test('an equal value is never published twice in a row', () {
      fakeAsync((async) {
        final r = Rig(async);
        r.builder
          ..pendingUploads = 0
          ..phase = SyncPhase.live
          ..isOnline = true;
        expect(r.out, isEmpty);
        r.builder.lastSyncedAt = 5;
        async.elapse(const Duration(milliseconds: 10));
        // Changed and changed back inside the cool-down: nothing new to publish.
        r.builder
          ..lastSyncedAt = 6
          ..lastSyncedAt = 5;
        r.builder.setIssue('w', SyncIssueCode.clockSkewWarning, 'w');
        r.builder.clearIssue('w');
        async.elapse(const Duration(seconds: 1));
        expect(r.out, hasLength(1));
        for (var i = 1; i < r.out.length; i++) {
          expect(r.out[i].$2, isNot(r.out[i - 1].$2));
        }
      });
    });

    test('batch makes one change of several inputs', () {
      fakeAsync((async) {
        final r = Rig(async, phase: SyncPhase.catchingUp);
        r.builder.batch(() {
          r.builder
            ..phase = SyncPhase.live
            ..pendingUploads = 3
            ..isPushing = true;
        });
        expect(r.out, hasLength(1));
        expect(r.out.single.$2.phase, SyncPhase.live);
        expect(r.out.single.$2.pendingUploads, 3);
      });
    });

    test('status is always current; close stops publishing', () {
      fakeAsync((async) {
        final r = Rig(async)..builder.pendingUploads = 1;
        r.builder.pendingUploads = 2;
        expect(r.builder.status.pendingUploads, 2);
        expect(r.out.last.$2.pendingUploads, 1);
        r.builder.close();
        async.elapse(const Duration(seconds: 1));
        r.builder.pendingUploads = 3;
        expect(r.out, hasLength(1));
      });
    });
  });
}
