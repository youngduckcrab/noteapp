// S08b (9.1.2, 6.7.4, SYNC-2-2): N (2 pages, 20 strokes) on both. Offline, A trashes and
// purges N (the purge only in its outbox) while B renames N and adds 5 strokes. B connects
// first and uploads; within 10 minutes A connects and receives first: N's upsert and its
// page / stroke records are dropped on A (no orphan rows), A's purge entry stays and is
// sent. B receives the purge right after its own upload → PurgeGuard makes a recovery copy
// (B's title + suffix, all 25 strokes) before purging N. Both end without N, with the
// copy, converged, nothing lost (9.1.1 exception: copies keep the strokes' content).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import 'support/scenario_checks.dart';
import 'support/sync_scenario.dart';

List<Note> notesTitled(TestDevice d, String title) => [
  for (final row in d.store.rows.values)
    if (row.entity case final Note n when !n.isDeleted && n.title == title) n,
];

Set<Object?> pointsOf(TestDevice d, String noteId) => {
  for (final page in d.pageIdsOf(noteId))
    for (final s in d.activeStrokesOf(page)) s.json['points'],
};

/// Rows of [d] that belong to note [noteId] (its pages and their strokes).
List<EntityRef> rowsOfNote(TestDevice d, String noteId, Set<String> pages) => [
  for (final MapEntry(key: ref, value: row) in d.store.rows.entries)
    if ((row.entity is Page && (row.entity as Page).noteId == noteId) ||
        (row.entity is Stroke && pages.contains((row.entity as Stroke).pageId)))
      ref,
];

void main() {
  syncScenario('S08b unsent purge on A, B uploads first, A receives first', (
    h,
  ) {
    final a = h.device('A');
    final b = h.device('B');
    final recovered = <NoteRecoveredFromPurge>[];
    final sub = b.engine.notices.listen((n) {
      if (n is NoteRecoveredFromPurge) recovered.add(n);
    });
    final note = a.createNote('Lecture', pages: 2);
    final pages = a.pageIdsOf(note);
    final original = [
      for (var i = 0; i < 20; i++)
        a.addStroke(pages[i % 2], seed: i, points: 20),
    ];
    h.settle();
    a.goOffline();
    b.goOffline();
    a.purgeNote(note);
    expect(
      a.store.outbox.where(
        (e) =>
            e.ref == EntityRef(EntityKind.note, note) && e.op == OutboxOp.purge,
      ),
      hasLength(1),
    );
    b.renameNote(note, 'Lecture v2');
    final added = [
      for (var i = 0; i < 5; i++)
        b.addStroke(pages[i % 2], seed: 100 + i, points: 20),
    ];
    final points = pointsOf(b, note);
    expect(points, hasLength(25));
    h.elapse(const Duration(seconds: 1));

    b.goOnline();
    h.settle();
    expect(
      h.server.mergedState('user-1')[EntityRef(EntityKind.stroke, added.first)],
      isNotNull,
    );
    h.elapse(const Duration(minutes: 1));
    a.goOnline();
    h.settle();

    const copyTitle = 'Lecture v2 (동기화 복구)';
    for (final d in [a, b]) {
      expect(entityOn<Note>(d, EntityKind.note, note), isNull, reason: d.name);
      expect(rowsOfNote(d, note, pages.toSet()), isEmpty, reason: d.name);
      for (final id in [...original, ...added]) {
        expect(strokeOn(d, id), isNull, reason: '${d.name}: $id');
      }
      final copies = notesTitled(d, copyTitle);
      expect(copies, hasLength(1), reason: d.name);
      expect(pointsOf(d, copies.single.id), points, reason: d.name);
    }
    expect(a.store.outbox, isEmpty, reason: "A's purge was sent");
    expect(recovered, hasLength(1));
    expect(recovered.single.purgedNoteId, note);
    expect(
      h.server.mergedState('user-1')[EntityRef(EntityKind.note, note)],
      isNull,
    );
    expect(a.engine.status.display, SyncDisplayState.done);
    h.checkConverged([a, b]);
    unawaited(sub.cancel());
  });
}
