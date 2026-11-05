// T10: account attach (6.10.3, 6.10.4): the first sign-in reassigns the local owner and binds
// the device, the same account continues, another account is refused (accountMismatch), and
// signing out keeps local data, outbox and binding.
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/engine/meta_keys.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../support/engine_harness.dart';

const _user1 = AuthUser(uid: 'user-1', email: 'one@example.com');
const _user2 = AuthUser(uid: 'user-2');

OwnerId? ownerOf(TestDevice d, String noteId) =>
    (d.store.rows[EntityRef(EntityKind.note, noteId)]!.entity as Note).ownerId;

void main() {
  harnessTest('first sign-in: reassignOwner(local → uid), sync.boundUid, the '
      'signed-out edits go up after receiving', (h, async) {
    final b = liveDevice(h, 'B');
    final a = h.device('A', signedIn: false);
    final n = a.createNote('written before signing in');
    h.settle();
    expect(a.store.sync.ownerId, kLocalOwnerId);
    expect(ownerOf(a, n), kLocalOwnerId);
    expect(a.store.meta[MetaKeys.boundUid], isNull);
    expect(a.store.outbox, isNotEmpty);
    expect(a.link.callCount(FakeOp.any), 0);

    a.auth.setUser(_user1);
    h.settle();
    expect(a.engine.status.phase, SyncPhase.live);
    expect(a.engine.status.user, _user1);
    expect(a.store.sync.ownerId, 'user-1');
    expect(ownerOf(a, n), 'user-1');
    expect(a.store.meta[MetaKeys.boundUid], 'user-1');
    expect(a.store.outbox, isEmpty);
    expect(onServer(h, n), isTrue);
    expect(b.doc(EntityKind.note, n), isNotNull);
    expect(h.server.profiles['user-1'], isNotNull);
    h.checkConverged([a, b]);
  });

  harnessTest('the same account again: no reassign, catching up from the '
      'cursor, edits made while signed out go up', (h, async) {
    final a = liveDevice(h, 'A');
    final b = liveDevice(h, 'B');
    final log = EngineLog(a.engine);
    a.auth.setUser(null);
    h.settle();
    final n = a.createNote('while signed out');
    final theirs = b.createNote('from B meanwhile');
    h.settle();
    expect(onServer(h, n), isFalse);
    a.auth.setUser(_user1);
    h.settle();
    expect(log.takePhases(), [
      SyncPhase.live,
      SyncPhase.signedOut,
      SyncPhase.connecting,
      SyncPhase.catchingUp,
      SyncPhase.live,
    ]);
    expect(a.store.sync.ownerId, 'user-1');
    expect(ownerOf(a, n), 'user-1'); // written under the store owner
    expect(onServer(h, n), isTrue);
    expect(a.doc(EntityKind.note, theirs), isNotNull);
    h.checkConverged([a, b]);
  });

  harnessTest('another account → error (accountMismatch, blocking, names the '
      'bound account); nothing is sent or received for it', (h, async) {
    final a = liveDevice(h, 'A');
    a.auth.setUser(null);
    h.settle();
    final n = a.createNote('stays local');
    final outbox = a.store.outbox.length;
    a.auth.setUser(_user2);
    h.settle();
    final status = a.engine.status;
    expect(status.phase, SyncPhase.error);
    expect(status.display, SyncDisplayState.error);
    expect(status.user, _user2);
    final issue = issueOf(a, SyncIssueCode.accountMismatch)!;
    expect(issue.isBlocking, isTrue);
    expect(issue.message, contains('user-1'));
    expect(status.nextRetryAt, isNull);
    h.elapse(const Duration(hours: 1));
    expect(a.engine.status.phase, SyncPhase.error);
    expect(h.server.chunksOf('user-2'), isEmpty);
    expect(h.server.profiles['user-2'], isNull);
    expect(a.store.sync.ownerId, 'user-1');
    expect(a.store.meta[MetaKeys.boundUid], 'user-1');
    expect(a.store.outbox, hasLength(outbox));

    // Back to the bound account: the issue goes away and sync resumes.
    a.auth.setUser(_user1);
    h.settle();
    expect(a.engine.status.phase, SyncPhase.live);
    expect(a.engine.status.issues, isEmpty);
    expect(onServer(h, n), isTrue);
  });

  harnessTest('a store already owned by another account (no binding) → '
      'accountMismatch', (h, async) {
    final a = h.device('A', signedIn: false);
    h.run(a.store.sync.reassignOwner(from: kLocalOwnerId, to: 'user-9'));
    a.auth.setUser(_user1);
    h.settle();
    expect(a.engine.status.phase, SyncPhase.error);
    expect(
      issueOf(a, SyncIssueCode.accountMismatch)!.message,
      contains('user-9'),
    );
    expect(a.store.meta[MetaKeys.boundUid], isNull);
  });

  harnessTest(
    'signing out keeps rows, outbox and sync.boundUid; status signedOut '
    'with no user and no issues',
    (h, async) {
      final a = liveDevice(h, 'A');
      a.link.failNext(
        const FakeErrorCode(SyncErrorCode.resourceExhausted),
        op: FakeOp.commit,
      );
      final n = a.createNote('pending at sign-out');
      h.elapse(const Duration(seconds: 2));
      expect(issueOf(a, SyncIssueCode.quotaExceeded), isNotNull);
      final rows = a.store.canonicalDump();
      final outbox = a.store.outbox.length;
      expect(outbox, greaterThan(0));
      a.auth.setUser(null);
      h.settle();
      final status = a.engine.status;
      expect(status.phase, SyncPhase.signedOut);
      expect(status.display, SyncDisplayState.off);
      expect(status.user, isNull);
      expect(status.issues, isEmpty);
      expect(status.pendingUploads, outbox);
      expect(a.store.canonicalDump(), rows);
      expect(a.store.outbox, hasLength(outbox));
      expect(a.store.meta[MetaKeys.boundUid], 'user-1');
      expect(a.store.meta[MetaKeys.cursor], isNotNull);
      h.elapse(const Duration(minutes: 10));
      expect(onServer(h, n), isFalse);
    },
  );

  harnessTest('switching straight to another signed-in user detaches first', (
    h,
    async,
  ) {
    final a = liveDevice(h, 'A');
    final log = EngineLog(a.engine);
    a.auth.setUser(_user2);
    h.settle();
    expect(log.takePhases(), [
      SyncPhase.live,
      SyncPhase.signedOut,
      SyncPhase.connecting,
      SyncPhase.error,
    ]);
    expect(issueOf(a, SyncIssueCode.accountMismatch), isNotNull);
  });
}
