// S14 (9.1.2, 6.2.4): B's clock is 1 h ahead. A and B take turns changing the same field:
// HLC order decides (A's clock catches up on receive), B shows clockSkewWarning only (not
// blocking, display unaffected), pushes and applies run normally, nothing lost.
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/sync_engine.dart';

import 'support/scenario_checks.dart';
import 'support/sync_scenario.dart';

void main() {
  syncScenario('S14 B one hour ahead, alternating renames', (h) {
    final a = h.device('A');
    final b = h.device('B', clockOffset: const Duration(hours: 1));
    final note = a.createNote('start');
    final strokes = [a.addStroke(a.pageIdsOf(note).single)];
    h.settle();
    for (final (i, d) in [a, b, a, b, a].indexed) {
      d.renameNote(note, '${d.name}$i');
      strokes.add(d.addStroke(d.pageIdsOf(note).single, seed: i + 1));
      h.settle();
      for (final x in [a, b]) {
        expect(noteOn(x, note).title, '${d.name}$i', reason: 'after ${d.name}');
      }
    }
    final status = b.engine.status;
    final warning = status.issues.singleWhere(
      (i) => i.code == SyncIssueCode.clockSkewWarning,
    );
    expect(warning.isBlocking, isFalse);
    expect(status.phase, SyncPhase.live);
    expect(status.display, SyncDisplayState.done);
    expect(
      a.engine.status.issues.where((i) => i.code == SyncIssueCode.clockSkew),
      isEmpty,
    );
    expectNoLoss([a, b], strokes);
    h.checkConverged([a, b]);
  });
}
