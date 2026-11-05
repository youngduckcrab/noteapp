// S22 (9.1.2, 6.10.5): unauthenticated → refreshSession once and retry (success); when the
// refresh fails → reauthRequired (blocking, no retry); signing in again continues.
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import 'support/scenario_checks.dart';
import 'support/sync_scenario.dart';

bool onServer(SyncTestHarness h, String noteId) => h.server
    .mergedState('user-1')
    .containsKey(EntityRef(EntityKind.note, noteId));

void main() {
  syncScenario('S22 session expired: refresh succeeds → the push goes on', (h) {
    final a = h.device('A');
    final b = h.device('B');
    h.settle();
    a.link.failNext(
      const FakeErrorCode(SyncErrorCode.unauthenticated),
      op: FakeOp.commit,
    );
    final note = a.createNote('S22');
    h.settle();
    expect(onServer(h, note), isTrue);
    expect(a.engine.status.phase, SyncPhase.live);
    expect(a.engine.status.issues, isEmpty);
    expect(noteOn(b, note).title, 'S22');
  });

  syncScenario(
    'S22 refresh fails → reauthRequired; signing in again continues',
    (h) {
      final a = h.device('A');
      final b = h.device('B');
      h.settle();
      a.link.failNext(
        const FakeErrorCode(SyncErrorCode.unauthenticated),
        op: FakeOp.commit,
      );
      a.auth.failNextRefresh();
      final note = a.createNote('S22 again');
      h.settle();
      final status = a.engine.status;
      expect(status.phase, SyncPhase.error);
      expect(status.display, SyncDisplayState.error);
      expect(
        status.issues
            .singleWhere((i) => i.code == SyncIssueCode.reauthRequired)
            .isBlocking,
        isTrue,
      );
      h.elapse(const Duration(minutes: 30));
      expect(onServer(h, note), isFalse, reason: 'no retry while waiting');
      a.auth.setUser(null);
      h.settle();
      a.auth.setUser(const AuthUser(uid: 'user-1'));
      h.settle();
      expect(a.engine.status.phase, SyncPhase.live);
      expect(onServer(h, note), isTrue);
      expect(noteOn(b, note).title, 'S22 again');
      h.checkConverged([a, b]);
    },
  );
}
