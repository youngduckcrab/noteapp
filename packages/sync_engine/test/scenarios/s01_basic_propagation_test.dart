// S01 (9.1.2): one stroke from A is active on B within 1.9 s (one-way latency 150 ms); one
// chunk written; one chunk read per live device (B's live query, and A's own chunk coming
// back on A's live query — skipped as its own delta).
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';

import 'support/scenario_checks.dart';
import 'support/sync_scenario.dart';

void main() {
  syncScenario(
    'S01 a stroke reaches B within 1.9 s: 1 chunk write, 1 chunk read '
    'per device',
    (h) {
      const latency = Duration(milliseconds: 150);
      final a = h.device('A', latency: latency);
      final b = h.device('B', latency: latency);
      final note = a.createNote('S01');
      h.settle();
      final page = b.pageIdsOf(note).single;
      final writes = h.server.writeCount('user-1');
      final reads = h.server.readCount('user-1');

      final stroke = a.addStroke(page);
      final took = elapseUntil(h, () => strokeOn(b, stroke) != null);
      expect(took, lessThanOrEqualTo(const Duration(milliseconds: 1900)));
      expect(strokeOn(b, stroke)!.isDeleted, isFalse);
      h.settle();
      expect(h.server.writeCount('user-1') - writes, 1);
      expect(h.server.readCount('user-1') - reads, 2);
      expect(b.engine.debug.recordsApplied, greaterThan(0));
      h.checkConverged([a, b]);
      expectNoLoss([a, b], [stroke]);
      expect(b.store.rows[EntityRef(EntityKind.note, note)], isNotNull);
    },
  );
}
