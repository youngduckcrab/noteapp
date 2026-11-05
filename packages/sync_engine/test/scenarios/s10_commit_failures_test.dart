// S10 (9.1.2, 6.5.4): a network error before the commit is retried after the backoff (1 s,
// then 2 s for a second one); a lost acknowledgement is retried with the same chunk id, so
// the server has no duplicate; the outbox ends empty and the devices converge.
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import 'support/scenario_checks.dart';
import 'support/sync_scenario.dart';

bool onServer(SyncTestHarness h, EntityKind kind, String id) =>
    h.server.mergedState('user-1').containsKey(EntityRef(kind, id));

void main() {
  syncScenario('S10 network errors before the commit: backoff 1 s, 2 s, then '
      'success', (h) {
    // Two connection failures would otherwise switch to offline (6.5.4).
    const config = SyncConfig(offlineAfterFailures: 3);
    final a = h.device('A', config: config);
    final b = h.device('B', config: config);
    h.settle();
    a.link.failNext(const FakeNetworkError(), op: FakeOp.commit, times: 2);
    final note = a.createNote('S10');
    h.elapse(const Duration(milliseconds: 500)); // debounce: the first try now
    final took = elapseUntil(
      h,
      () => onServer(h, EntityKind.note, note),
      max: const Duration(seconds: 10),
    );
    // Jittered 1 s and 2 s (±20 %) plus round trips.
    expect(took, greaterThan(const Duration(milliseconds: 2400)));
    expect(took, lessThan(const Duration(seconds: 5)));
    expect(a.link.callCount(FakeOp.commit), greaterThanOrEqualTo(3));
    h.settle();
    expect(a.engine.status.phase, SyncPhase.live);
    expect(a.store.outbox, isEmpty);
    h.checkConverged([a, b]);
  });

  syncScenario('S10 lost acknowledgement: same chunk id again, no duplicate', (
    h,
  ) {
    final a = h.device('A');
    final b = h.device('B');
    h.settle();
    final before = h.server.chunksOf('user-1').length;
    a.link.failNext(const FakeAckLost(), op: FakeOp.commit);
    final note = a.createNote('S10 ack');
    a.addStroke(a.pageIdsOf(note).single);
    h.settle();
    final chunks = h.server.chunksOf('user-1');
    final ids = [for (final c in chunks) c.chunk.id];
    expect(ids.toSet(), hasLength(ids.length), reason: 'no duplicate ids');
    expect(chunks.length - before, greaterThanOrEqualTo(1));
    expect(
      h.server.writeCount('user-1'),
      greaterThan(chunks.length),
      reason: 'the lost commit was written twice under the same id',
    );
    expect(a.store.outbox, isEmpty);
    expect(noteOn(b, note).title, 'S10 ack');
    h.checkConverged([a, b]);
  });
}
