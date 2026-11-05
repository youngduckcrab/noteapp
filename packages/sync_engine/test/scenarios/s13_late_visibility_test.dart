// S13 (9.1.2, 6.6.2): the server shows a commit 3 s after its serverTime; meanwhile B
// commits (its cursor passes that serverTime) and reconnects. The 5-minute overlap of the
// cursor makes B get the late chunk anyway.
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';

import 'support/scenario_checks.dart';
import 'support/sync_scenario.dart';

void main() {
  syncScenario('S13 late visibility: B does not miss the chunk', (h) {
    final a = h.device('A');
    final b = h.device('B');
    h.settle();
    h.server.delayVisibilityOfNextCommit(const Duration(seconds: 3));
    final late = a.createNote('late');
    h.elapse(
      const Duration(milliseconds: 700),
    ); // A's commit is stored, not visible
    expect(entityOn<Note>(b, EntityKind.note, late), isNull);
    b.createNote('from B');
    h.elapse(
      const Duration(milliseconds: 800),
    ); // B's own commit passes A's serverTime
    b.goOffline();
    h.elapse(const Duration(milliseconds: 200));
    b.goOnline();
    h.elapse(const Duration(seconds: 5));
    h.settle();
    expect(noteOn(b, late).title, 'late');
    h.checkConverged([a, b]);
  });
}
