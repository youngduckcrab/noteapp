// S11 (9.1.2, 6.5.3): 3,000 strokes pile up offline (several pushes / commits); the second
// commit fails. Only the first commit's entries are acknowledged, the retry sends the rest,
// and the devices converge.
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/src/codec/chunk_codec.dart';
import 'package:sync_engine/testing.dart';

import 'support/scenario_checks.dart';
import 'support/sync_scenario.dart';

void main() {
  syncScenario('S11 3,000-stroke backlog, the second commit fails', (h) {
    final a = h.device('A');
    final b = h.device('B');
    final note = a.createNote('S11', pages: 3);
    h.settle();
    final pages = a.pageIdsOf(note);
    a.goOffline();
    final created = [
      for (var i = 0; i < 3000; i++)
        a.addStroke(pages[i % 3], seed: i, points: 20),
    ];
    h.elapse(const Duration(seconds: 1));
    final pending = a.store.outbox.length;
    expect(pending, 3000);
    final chunksBefore = h.server.chunksOf('user-1').length;
    final commits = a.link.callCount(FakeOp.commit);
    a.goOnline();
    elapseUntil(h, () => a.link.callCount(FakeOp.commit) > commits);
    a.link.failNext(const FakeNetworkError(), op: FakeOp.commit);
    elapseUntil(h, () => a.link.callCount(FakeOp.commit) > commits + 1);
    h.elapse(const Duration(milliseconds: 300)); // the failure and its handling
    final firstCommit = h.server.chunksOf('user-1').sublist(chunksBefore);
    final sent = [
      for (final c in firstCommit) ...ChunkCodec.decode(c.chunk.payload),
    ];
    expect(sent, isNotEmpty);
    expect(sent.length, lessThan(3000));
    expect(a.store.outbox.length, pending - sent.length);

    h.settle();
    expect(a.store.outbox, isEmpty);
    expectNoLoss([a, b], created);
    h.checkConverged([a, b]);
  });
}
