// S05 (9.1.2): A erases a stroke while B, offline, recolours it. Both end with the stroke
// deleted and B's style (separate units: deletedAt / style).
import 'package:flutter_test/flutter_test.dart';

import 'support/scenario_checks.dart';
import 'support/sync_scenario.dart';

void main() {
  syncScenario('S05 erase on A vs recolour on B', (h) {
    final a = h.device('A');
    final b = h.device('B');
    final note = a.createNote('S05');
    final stroke = a.addStroke(a.pageIdsOf(note).single);
    h.settle();
    expect(strokeOn(b, stroke), isNotNull);
    b.goOffline();
    a.eraseStroke(stroke);
    h.settle();
    const red = 0xFFFF0000;
    b.recolorStroke(stroke, red);
    h.elapse(const Duration(seconds: 1));
    b.goOnline();
    h.settle();
    for (final d in [a, b]) {
      final s = strokeOn(d, stroke)!;
      expect(s.isDeleted, isTrue, reason: d.name);
      expect(s.style.colorArgb, red, reason: d.name);
    }
    h.checkConverged([a, b]);
  });
}
