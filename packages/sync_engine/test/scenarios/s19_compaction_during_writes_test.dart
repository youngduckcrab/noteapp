// S19 (9.1.2, 6.13): A compacts a note scope of 400+ chunks while B keeps writing strokes
// into it. Nothing is lost: what B wrote before A read the scope is in A's snapshot, what came
// after stays as delta chunks. A new device D then reads less than 10% of the chunks it would
// have read before, and every device converges.
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import 'support/scenario_checks.dart';
import 'support/sync_scenario.dart';

const _uid = 'user-1';

List<RemoteChunk> _scopeChunks(SyncTestHarness h, String scope) => [
  for (final s in h.server.chunksOf(_uid))
    if (s.chunk.scope == scope) s.chunk,
];

void main() {
  syncScenario('S19 compaction while another device writes into the scope', (
    h,
  ) {
    final a = h.device('A');
    // B only writes here (its own compaction would make the run order-dependent).
    final b = h.device(
      'B',
      config: const SyncConfig(compaction: CompactionConfig(enabled: false)),
    );
    final note = b.createNote('S19');
    h.settle();
    final page = b.pageIdsOf(note).single;

    // 420 strokes, one chunk each, while A is paused: A takes them in on resume.
    h.run(a.engine.setPaused(true));
    final strokes = <String>[];
    for (var i = 0; i < 420; i++) {
      strokes.add(b.addStroke(page, seed: i, points: 8));
      h.elapse(const Duration(milliseconds: 600));
    }
    h.settle();
    final chunksBefore = h.server.chunksOf(_uid).length;
    expect(_scopeChunks(h, note).length, greaterThan(420));
    h.run(a.engine.setPaused(false));
    h.settle();
    expect(a.engine.status.phase, SyncPhase.live);

    // A's compaction starts with its fetchScope (a live engine fetches nothing else).
    final fetches = a.link.callCount(FakeOp.fetch);
    elapseUntil(
      h,
      () => a.link.callCount(FakeOp.fetch) > fetches,
      max: const Duration(minutes: 3),
    );
    // B writes during the run.
    for (var i = 0; i < 3; i++) {
      strokes.add(b.addStroke(page, seed: 1000 + i, points: 8));
      h.elapse(const Duration(milliseconds: 600));
    }
    h.settle();

    final after = _scopeChunks(h, note);
    final snapshots = [
      for (final c in after)
        if (c.kind == ChunkKind.snapshot) c,
    ];
    expect(snapshots, isNotEmpty);
    expect(
      snapshots.every((c) => c.authorNodeId == a.store.sync.deviceNodeId),
      isTrue,
    );
    expect(after.length - snapshots.length, lessThanOrEqualTo(3));

    final reads = h.server.readCount(_uid);
    final d = h.device('D');
    h.settle();
    final readsD = h.server.readCount(_uid) - reads;
    expect(readsD, lessThan(chunksBefore / 10));

    expectNoLoss([a, b, d], strokes);
    h.checkConverged([a, b, d]);
  });
}
