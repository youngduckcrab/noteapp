// S12 (9.1.2, 6.6.2): C is offline for 30 days (virtual) while A and B make 2,000 chunks.
// Back online, C reads only what came after its cursor − 5 minutes (read count), and the
// three converge.
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import 'support/sync_scenario.dart';

/// One stroke in each of [notes] on [d], then a push (one chunk per note scope).
void strokeEach(SyncTestHarness h, TestDevice d, List<String> notes, int seed) {
  for (final n in notes) {
    d.addStroke(d.pageIdsOf(n).single, seed: seed, points: 10);
  }
  h.settle();
}

void main() {
  syncScenario('S12 incremental catch-up after 30 days offline', (h) {
    final a = h.device('A');
    final b = h.device('B');
    // A daily probe keeps 30 offline days cheap in virtual time.
    final c = h.device(
      'C',
      config: const SyncConfig(offlineProbeInterval: Duration(days: 1)),
    );
    final notesA = [for (var i = 0; i < 100; i++) a.createNote('A$i')];
    final notesB = [for (var i = 0; i < 100; i++) b.createNote('B$i')];
    h.settle();
    strokeEach(h, a, notesA, 1);
    // C's cursor is the serverTime of the newest chunk it has; its overlap (5 min) reaches
    // back from there, so the bulk of the old chunks must be older than that.
    h.elapse(const Duration(minutes: 10));
    a.renameNote(notesA.last, 'cursor mark');
    h.settle();
    final oldChunks = h.server.chunksOf('user-1').length;
    c.goOffline();
    h.settle();

    for (var round = 0; round < 10; round++) {
      strokeEach(h, a, notesA, 10 + round);
      strokeEach(h, b, notesB, 100 + round);
    }
    expect(
      h.server.chunksOf('user-1').length - oldChunks,
      greaterThanOrEqualTo(2000),
    );

    // 30 days: A and B paused (no hourly / per-minute timers), C offline.
    a.engine.setPaused(true);
    b.engine.setPaused(true);
    h.elapse(const Duration(days: 30));
    a.engine.setPaused(false);
    b.engine.setPaused(false);
    h.settle();
    // The newest chunk alone in the last 5 minutes before C's new live query.
    h.elapse(const Duration(minutes: 10));
    a.renameNote(notesA.first, 'last');
    h.settle();

    final newChunks = h.server.chunksOf('user-1').length - oldChunks;
    final reads = h.server.readCount('user-1');
    c.goOnline();
    h.settle();
    // The new chunks, the cursor's own chunk (overlap) and the newest again on the new
    // live query; none of the 300 older ones.
    final read = h.server.readCount('user-1') - reads;
    expect(read, greaterThanOrEqualTo(newChunks));
    expect(read, lessThanOrEqualTo(newChunks + 3));
    expect(oldChunks, greaterThan(300));
    h.checkConverged([a, b, c]);
  });
}
