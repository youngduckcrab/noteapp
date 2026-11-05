// S20 (9.1.2, 6.11): A adds a stroke, B erases it, A undoes the erase as a new write
// (deletedAt = null with a new HLC) → active everywhere.
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/testing.dart';

import 'support/scenario_checks.dart';
import 'support/sync_scenario.dart';

void main() {
  syncScenario('S20 undo of a remote erase wins with a new HLC', (h) {
    final a = h.device('A');
    final b = h.device('B');
    final note = a.createNote('S20');
    final stroke = a.addStroke(a.pageIdsOf(note).single);
    h.settle();
    b.eraseStroke(stroke);
    h.settle();
    expect(strokeOn(a, stroke)!.isDeleted, isTrue);
    a.store.localWrite([
      FakeLocalWrite(
        EntityKind.stroke,
        {...strokeOn(a, stroke)!.toJson(), 'deletedAt': null},
        changedFields: const {'deletedAt'},
      ),
    ]);
    h.settle();
    expectNoLoss([a, b], [stroke]);
    h.checkConverged([a, b]);
  });
}
