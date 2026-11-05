// S06 (9.1.2, 6.7.3): page deleted on A vs new strokes from B. (a) B adds offline while A
// deletes; (b) B uploads first and A, offline, deletes without knowing; both → the page
// comes back with B's strokes and PageRestored. (c) A had B's strokes before deleting →
// the delete stays.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import 'support/scenario_checks.dart';
import 'support/sync_scenario.dart';

Page pageOn(TestDevice d, String id) => entityOn<Page>(d, EntityKind.page, id)!;

void main() {
  syncScenario('S06 (a) delete on A while B adds strokes offline', (h) {
    final a = h.device('A');
    final b = h.device('B');
    final restored = <PageRestored>[];
    final subs = [
      for (final d in [a, b])
        d.engine.notices.listen((n) {
          if (n is PageRestored) restored.add(n);
        }),
    ];
    final note = a.createNote('S06a', pages: 2);
    h.settle();
    final page = a.pageIdsOf(note).last;
    b.goOffline();
    a.deletePage(page);
    h.settle();
    final strokes = [for (var i = 0; i < 3; i++) b.addStroke(page, seed: i)];
    h.elapse(const Duration(seconds: 1));
    b.goOnline();
    h.settle();
    for (final d in [a, b]) {
      expect(pageOn(d, page).isDeleted, isFalse, reason: d.name);
      expect(d.pageIdsOf(note), contains(page), reason: d.name);
    }
    expect(restored.map((n) => n.pageId), contains(page));
    expectNoLoss([a, b], strokes);
    h.checkConverged([a, b]);
    for (final s in subs) {
      unawaited(s.cancel());
    }
  });

  syncScenario('S06 (b) B uploads first, then A deletes without knowing', (h) {
    final a = h.device('A');
    final b = h.device('B');
    final restored = <PageRestored>[];
    final sub = a.engine.notices.listen((n) {
      if (n is PageRestored) restored.add(n);
    });
    final note = a.createNote('S06b', pages: 2);
    h.settle();
    final page = a.pageIdsOf(note).last;
    a.goOffline();
    final strokes = [for (var i = 0; i < 3; i++) b.addStroke(page, seed: i)];
    h.settle();
    a.deletePage(page);
    h.elapse(const Duration(seconds: 1));
    a.goOnline();
    h.settle();
    for (final d in [a, b]) {
      expect(pageOn(d, page).isDeleted, isFalse, reason: d.name);
    }
    expect(restored.map((n) => n.pageId), [page]);
    expectNoLoss([a, b], strokes);
    h.checkConverged([a, b]);
    unawaited(sub.cancel());
  });

  syncScenario('S06 (c) A deletes after it received B\'s strokes: the delete '
      'stays', (h) {
    final a = h.device('A');
    final b = h.device('B');
    final note = a.createNote('S06c', pages: 2);
    h.settle();
    final page = a.pageIdsOf(note).last;
    final strokes = [for (var i = 0; i < 3; i++) b.addStroke(page, seed: i)];
    h.settle();
    expect(strokeOn(a, strokes.first), isNotNull);
    a.deletePage(page);
    h.settle();
    for (final d in [a, b]) {
      expect(pageOn(d, page).isDeleted, isTrue, reason: d.name);
    }
    expectNoLoss([a, b], strokes);
    h.checkConverged([a, b]);
  });
}
