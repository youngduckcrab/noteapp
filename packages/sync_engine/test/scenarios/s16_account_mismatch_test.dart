// S16 (9.1.2, 6.10.4): a device bound to user-1 signed in as user-2 → accountMismatch
// (blocking), nothing written under user-2.
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';

import 'support/sync_scenario.dart';

void main() {
  syncScenario('S16 bound to user-1, signed in as user-2', (h) {
    final a = h.device('A');
    a.createNote('mine');
    h.settle();
    a.auth.setUser(null);
    h.settle();
    a.auth.setUser(const AuthUser(uid: 'user-2'));
    a.createNote('while mismatched');
    h.settle();
    final status = a.engine.status;
    expect(status.phase, SyncPhase.error);
    final issue = status.issues.singleWhere(
      (i) => i.code == SyncIssueCode.accountMismatch,
    );
    expect(issue.isBlocking, isTrue);
    expect(issue.message, contains('user-1'));
    expect(h.server.writeCount('user-2'), 0);
    expect(h.server.chunksOf('user-2'), isEmpty);
  });
}
