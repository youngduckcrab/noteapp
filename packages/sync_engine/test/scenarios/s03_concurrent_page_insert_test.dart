// S03 (9.1.2): A and B, offline, each insert a page after the same page. Both pages stay,
// in the same order on both devices (equal sortKey → id order).
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';

import 'support/scenario_checks.dart';
import 'support/sync_scenario.dart';

void main() {
  syncScenario('S03 concurrent page inserts after the same page', (h) {
    final a = h.device('A');
    final b = h.device('B');
    final note = a.createNote('S03', pages: 2);
    h.settle();
    final first = b.pageIdsOf(note).first;
    a.goOffline();
    b.goOffline();
    final fromA = a.insertPage(note, afterPageId: first);
    final fromB = b.insertPage(note, afterPageId: first);
    final keyA = entityOn<Page>(a, EntityKind.page, fromA)!.sortKey;
    final keyB = entityOn<Page>(b, EntityKind.page, fromB)!.sortKey;
    expect(keyA, keyB, reason: 'same neighbours → same key');
    h.elapse(const Duration(seconds: 2));
    a.goOnline();
    b.goOnline();
    h.settle();
    final order = a.pageIdsOf(note);
    expect(order, hasLength(4));
    expect(order, containsAll([fromA, fromB]));
    expect(b.pageIdsOf(note), order);
    final tied = ([fromA, fromB]..sort());
    expect(order.sublist(1, 3), tied, reason: 'equal sortKey → id order');
    h.checkConverged([a, b]);
  });
}
