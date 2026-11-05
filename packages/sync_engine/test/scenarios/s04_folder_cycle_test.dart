// S04 (9.1.2): concurrent folder moves that make a loop (6.7.2). Two devices (X into Y on
// A, Y into X on B) and three (X→Y, Y→Z, Z→X): no loop remains, the folder of the latest
// move goes to the top level, FolderCycleResolved, at most one repair write per device,
// converged.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import 'support/scenario_checks.dart';
import 'support/sync_scenario.dart';

Folder folderOn(TestDevice d, String id) =>
    entityOn<Folder>(d, EntityKind.folder, id)!;

/// No folder of [d] reaches itself through parentId.
void expectNoLoop(TestDevice d, Iterable<String> folders) {
  for (final start in folders) {
    final seen = <String>{};
    String? at = start;
    while (at != null) {
      expect(seen.add(at), isTrue, reason: '${d.name}: loop through $at');
      at = entityOn<Folder>(d, EntityKind.folder, at)?.parentId;
    }
  }
}

void main() {
  syncScenario('S04 two devices: X into Y vs Y into X', (h) {
    final a = h.device('A');
    final b = h.device('B');
    final notices = <SyncNotice>[];
    final subs = [
      a.engine.notices.listen(notices.add),
      b.engine.notices.listen(notices.add),
    ];
    final x = a.createFolder('X');
    final y = a.createFolder('Y');
    h.settle();
    a.goOffline();
    b.goOffline();
    a.moveFolder(x, y);
    h.elapse(const Duration(seconds: 1));
    b.moveFolder(y, x); // the later move
    h.elapse(const Duration(seconds: 1));
    a.goOnline();
    b.goOnline();
    h.settle();
    h.elapse(const Duration(seconds: 15)); // grace of the other device (10 s)
    h.settle();
    for (final d in [a, b]) {
      expectNoLoop(d, [x, y]);
      expect(
        folderOn(d, y).parentId,
        isNull,
        reason: '${d.name}: loser on top',
      );
      expect(folderOn(d, x).parentId, y, reason: d.name);
    }
    expect(notices.whereType<FolderCycleResolved>(), isNotEmpty);
    final repairs =
        a.engine.debug.repairsWritten + b.engine.debug.repairsWritten;
    expect(repairs, inInclusiveRange(1, 2));
    h.checkConverged([a, b]);
    for (final s in subs) {
      unawaited(s.cancel());
    }
  });

  syncScenario('S04 three devices: X→Y, Y→Z, Z→X', (h) {
    final a = h.device('A');
    final b = h.device('B');
    final c = h.device('C');
    final x = a.createFolder('X');
    final y = a.createFolder('Y');
    final z = a.createFolder('Z');
    h.settle();
    for (final d in [a, b, c]) {
      d.goOffline();
    }
    a.moveFolder(x, y);
    h.elapse(const Duration(seconds: 1));
    b.moveFolder(y, z);
    h.elapse(const Duration(seconds: 1));
    c.moveFolder(z, x); // the latest move
    h.elapse(const Duration(seconds: 1));
    for (final d in [a, b, c]) {
      d.goOnline();
    }
    h.settle();
    h.elapse(const Duration(seconds: 15));
    h.settle();
    for (final d in [a, b, c]) {
      expectNoLoop(d, [x, y, z]);
      expect(folderOn(d, z).parentId, isNull, reason: d.name);
      expect(folderOn(d, x).parentId, y, reason: d.name);
      expect(folderOn(d, y).parentId, z, reason: d.name);
    }
    final repairs = [
      for (final d in [a, b, c]) d.engine.debug.repairsWritten,
    ].reduce((p, q) => p + q);
    expect(repairs, inInclusiveRange(1, 3));
    h.checkConverged([a, b, c]);
  });
}
