// S18 (9.1.2): three devices go on- and offline while editing the same note (strokes,
// erases, recolours, renames, page inserts); everything converges with nothing lost.
import 'dart:math';

import 'support/scenario_checks.dart';
import 'support/sync_scenario.dart';

void main() {
  syncScenario('S18 three devices, on and off, one note', (h) {
    final devices = [h.device('A'), h.device('B'), h.device('C')];
    final note = devices.first.createNote('S18', pages: 2);
    h.settle();
    final random = Random(18);
    final created = <String>[];
    final erased = <String>{};
    for (var round = 0; round < 12; round++) {
      for (final d in devices) {
        if (random.nextBool()) {
          d.goOffline();
        } else {
          d.goOnline();
        }
      }
      for (final d in devices) {
        final pages = d.pageIdsOf(note);
        for (var i = 0; i < 3; i++) {
          created.add(
            d.addStroke(
              pages[random.nextInt(pages.length)],
              seed: random.nextInt(1000),
              points: 20,
            ),
          );
        }
        final mine = [
          for (final id in created)
            if (strokeOn(d, id) case final s? when !s.isDeleted) id,
        ];
        switch (random.nextInt(4)) {
          case 0 when mine.isNotEmpty:
            final id = mine[random.nextInt(mine.length)];
            d.eraseStroke(id);
            erased.add(id);
          case 1 when mine.isNotEmpty:
            d.recolorStroke(
              mine[random.nextInt(mine.length)],
              0xFF000000 + random.nextInt(0xFFFFFF),
            );
          case 2:
            d.renameNote(note, '${d.name} round $round');
          default:
            d.insertPage(note);
        }
        h.elapse(Duration(milliseconds: 200 + random.nextInt(800)));
      }
    }
    for (final d in devices) {
      d.goOnline();
    }
    h.settle();
    expectNoLoss(devices, created, erased: erased);
    h.checkConverged(devices);
  });
}
