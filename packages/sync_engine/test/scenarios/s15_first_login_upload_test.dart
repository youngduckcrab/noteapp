// S15 (9.1.2, 6.10.3, 6.7.5): before signing in, A has 3 notes and the default presets
// (one renamed), B has 2 notes and the default presets. Both sign in: owners reassigned,
// 5 notes, 5 presets (no duplicates), A's renamed preset kept.
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import 'support/scenario_checks.dart';
import 'support/sync_scenario.dart';

List<T> activeOf<T extends SyncEntity>(TestDevice d) => [
  for (final row in d.store.rows.values)
    if (row.entity case final T e when !e.isDeleted) e,
];

void main() {
  syncScenario('S15 first sign-in on two devices with local data', (h) {
    final a = h.device('A', signedIn: false);
    final b = h.device('B', signedIn: false);
    a.seedDefaultPresets();
    b.seedDefaultPresets(); // same virtual instant: identical seed rows
    final notes = [
      for (var i = 0; i < 3; i++) a.createNote('A$i'),
      for (var i = 0; i < 2; i++) b.createNote('B$i'),
    ];
    h.elapse(const Duration(seconds: 1));
    a.renamePreset('preset-default-ballpoint', 'my pen');
    h.settle();
    expect(a.store.sync.ownerId, kLocalOwnerId);

    const user = AuthUser(uid: 'user-1');
    a.auth.setUser(user);
    h.settle();
    b.auth.setUser(user);
    h.settle();
    for (final d in [a, b]) {
      expect(d.store.sync.ownerId, 'user-1', reason: d.name);
      final ns = activeOf<Note>(d);
      expect({for (final n in ns) n.id}, notes.toSet(), reason: d.name);
      expect(ns.every((n) => n.ownerId == 'user-1'), isTrue, reason: d.name);
      final presets = activeOf<PenPreset>(d);
      expect(presets, hasLength(5), reason: d.name);
      expect(
        presets.singleWhere((p) => p.id == 'preset-default-ballpoint').name,
        'my pen',
        reason: d.name,
      );
    }
    expect(noteOn(b, notes.first).title, 'A0');
    h.checkConverged([a, b]);
  });
}
