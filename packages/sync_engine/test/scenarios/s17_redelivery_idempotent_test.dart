// S17 (9.1.2): every chunk delivered again (cursor reset): all records kept, no local change,
// the outbox stays empty.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';

import 'support/sync_scenario.dart';

void main() {
  syncScenario('S17 redelivery of every chunk is idempotent', (h) {
    final a = h.device('A');
    final b = h.device('B');
    final note = a.createNote('S17', pages: 2);
    for (final page in a.pageIdsOf(note)) {
      for (var i = 0; i < 5; i++) {
        a.addStroke(page, seed: i);
      }
    }
    b.createFolder('from B');
    h.settle();
    final dump = b.store.canonicalDump();
    final kept = b.engine.debug.recordsKept;
    final ownSkipped = b.engine.debug.ownChunksSkipped;
    var localChanges = 0;
    final sub = b.store.localChanges.listen((_) => localChanges++);

    b.auth.setUser(null);
    h.settle();
    h.run(b.store.sync.writeMeta({'sync.cursor': ''}));
    b.auth.setUser(const AuthUser(uid: 'user-1'));
    h.settle();
    expect(b.engine.status.phase, SyncPhase.live);
    // A's 13 records (note, 2 pages, 10 strokes) kept; B's own delta chunk (the folder)
    // skipped (6.6.3 step 2).
    expect(b.engine.debug.recordsKept - kept, 13);
    expect(b.engine.debug.ownChunksSkipped - ownSkipped, 1);
    expect(b.store.canonicalDump(), dump);
    expect(b.store.outbox, isEmpty);
    expect(localChanges, 0);
    h.checkConverged([a, b]);
    unawaited(sub.cancel());
  });
}
