// S23 (07-sync 6.7.1, 6.2.2): A moves shape X offline (t1) while B, offline, recolours it
// (t2 > t1). A known object is one merge unit (contract D3): both end with B's snapshot of
// X — B's colour at the ORIGINAL position (A's move is gone). Edits of other objects (Y on
// A, Z on B) both stay.
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';

import 'support/sync_scenario.dart';

void main() {
  syncScenario('S23 move on A vs recolour on B: one object unit, later '
      'snapshot wins; other objects keep both edits', (h) {
    final a = h.device('A');
    final b = h.device('B');
    final note = a.createNote('S23');
    final page = a.pageIdsOf(note).single;
    final x = a.addObject(page);
    final y = a.addObject(page, type: 'text', seed: 1);
    final z = a.addObject(page, type: 'math', seed: 2);
    h.settle();
    final original = b.doc(EntityKind.pageObject, x)!.json;
    expect(original['type'], 'shape');

    a.goOffline();
    b.goOffline();
    a.moveObject(x, dx: 40, dy: 25); // t1
    a.editText(y, 'A의 글');
    final moved = a.doc(EntityKind.pageObject, x)!.json;
    expect(moved['frame'], isNot(original['frame']));
    expect(moved['geometry'], isNot(original['geometry']));
    h.elapse(const Duration(seconds: 1));
    const red = 0xFFFF0000;
    const blue = 0xFF0000FF;
    b.restyleObject(x, red); // t2 > t1
    b.restyleObject(z, blue);
    h.elapse(const Duration(seconds: 1));
    a.goOnline();
    b.goOnline();
    h.settle();

    for (final d in [a, b]) {
      final json = d.doc(EntityKind.pageObject, x)!.json;
      expect(
        (json['style']! as Map)['strokeColorArgb'],
        red,
        reason: '${d.name}: B colour',
      );
      expect(json['frame'], original['frame'], reason: '${d.name}: not moved');
      expect(json['geometry'], original['geometry'], reason: d.name);
      expect(
        d.doc(EntityKind.pageObject, y)!.json['text'],
        'A의 글',
        reason: d.name,
      );
      expect(
        (d.doc(EntityKind.pageObject, z)!.json['style']! as Map)['colorArgb'],
        blue,
        reason: d.name,
      );
      expect(
        [for (final o in d.activeObjectsOf(page)) o.json['id']],
        unorderedEquals([x, y, z]),
        reason: d.name,
      );
    }
    h.checkConverged([a, b]);
  });
}
