// S07 (9.1.2): A moves a note to the trash while B, offline, renames it → in the trash with
// the new title. Then B restores it: the restore (newer HLC) wins, active on both.
import 'package:flutter_test/flutter_test.dart';

import 'support/scenario_checks.dart';
import 'support/sync_scenario.dart';

void main() {
  syncScenario('S07 trash on A vs rename on B, then restore on B', (h) {
    final a = h.device('A');
    final b = h.device('B');
    final note = a.createNote('S07');
    h.settle();
    b.goOffline();
    a.trashNote(note);
    h.settle();
    b.renameNote(note, 'renamed on B');
    h.elapse(const Duration(seconds: 1));
    b.goOnline();
    h.settle();
    for (final d in [a, b]) {
      final n = noteOn(d, note);
      expect(n.isDeleted, isTrue, reason: '${d.name}: still in the trash');
      expect(n.title, 'renamed on B', reason: d.name);
    }
    h.checkConverged([a, b]);

    b.restoreNote(note);
    h.settle();
    for (final d in [a, b]) {
      final n = noteOn(d, note);
      expect(n.isDeleted, isFalse, reason: '${d.name}: restored');
      expect(n.trashRootId, isNull, reason: d.name);
      expect(n.title, 'renamed on B', reason: d.name);
    }
    h.checkConverged([a, b]);
  });
}
