// S24 (07-sync 6.7.1, 6.2.2): A deletes text box T while B, offline, edits its text. The
// delete (deletedAt) is a unit apart from the object unit: both end with T deleted AND
// B's text (the same shape as v1 S05 for strokes).
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';

import 'support/sync_scenario.dart';

void main() {
  syncScenario('S24 delete on A vs text edit on B: deleted, with B text', (h) {
    final a = h.device('A');
    final b = h.device('B');
    final note = a.createNote('S24');
    final page = a.pageIdsOf(note).single;
    final t = a.addObject(page, type: 'text');
    h.settle();
    expect(b.doc(EntityKind.pageObject, t), isNotNull);

    b.goOffline();
    a.deleteObject(t);
    h.settle();
    b.editText(t, 'B가 고친 글');
    h.elapse(const Duration(seconds: 1));
    b.goOnline();
    h.settle();

    for (final d in [a, b]) {
      final json = d.doc(EntityKind.pageObject, t)!.json;
      expect(json['deletedAt'], isNotNull, reason: d.name);
      expect(json['text'], 'B가 고친 글', reason: d.name);
      expect(d.activeObjectsOf(page), isEmpty, reason: d.name);
    }
    h.checkConverged([a, b]);
  });
}
