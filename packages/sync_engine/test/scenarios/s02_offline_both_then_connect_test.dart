// S02 (9.1.2): A and B offline. A adds 100 strokes and renames the note; B adds 80 strokes
// and moves the same note into a folder. Connected A→B, B→A or at once: 180 strokes,
// title = A's, folder = B's, converged, nothing lost.
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/testing.dart';

import 'support/scenario_checks.dart';
import 'support/sync_scenario.dart';

enum _Order { aFirst, bFirst, together }

void main() {
  for (final order in _Order.values) {
    syncScenario('S02 both offline, then connected (${order.name})', (h) {
      final a = h.device('A');
      final b = h.device('B');
      final folder = a.createFolder('Inbox');
      final note = a.createNote('S02', pages: 2);
      h.settle();
      final pages = b.pageIdsOf(note);
      a.goOffline();
      b.goOffline();
      h.elapse(const Duration(seconds: 1));

      final created = <String>[
        for (var i = 0; i < 100; i++)
          a.addStroke(pages[i % 2], seed: i, points: 40),
        for (var i = 0; i < 80; i++)
          b.addStroke(pages[i % 2], seed: 1000 + i, points: 40),
      ];
      h.elapse(const Duration(seconds: 1));
      a.renameNote(note, 'renamed on A');
      h.elapse(const Duration(seconds: 1));
      b.moveNote(note, folder);
      h.elapse(const Duration(seconds: 5));

      void connect(TestDevice d) {
        d.goOnline();
        h.settle();
      }

      switch (order) {
        case _Order.aFirst:
          connect(a);
          connect(b);
        case _Order.bFirst:
          connect(b);
          connect(a);
        case _Order.together:
          a.goOnline();
          b.goOnline();
          h.settle();
      }
      h.settle();
      expect(created.toSet(), hasLength(180));
      for (final d in [a, b]) {
        expect(noteOn(d, note).title, 'renamed on A', reason: d.name);
        expect(noteOn(d, note).folderId, folder, reason: d.name);
      }
      expectNoLoss([a, b], created);
      h.checkConverged([a, b]);
    });
  }
}
