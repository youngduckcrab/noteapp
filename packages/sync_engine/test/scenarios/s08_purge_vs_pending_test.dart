// S08 (9.1.2, 6.7.4): A purges a note while B, offline, adds strokes to it. B receives the
// purge with pending edits → a recovery copy (title + suffix, B's strokes inside) before
// the purge; the copy reaches A; the original is gone everywhere; old chunks of the
// original delivered again later (cursor reset) do not bring it back.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import 'support/scenario_checks.dart';
import 'support/sync_scenario.dart';

/// Active notes of [d] titled [title].
List<Note> notesTitled(TestDevice d, String title) => [
  for (final row in d.store.rows.values)
    if (row.entity case final Note n when !n.isDeleted && n.title == title) n,
];

/// The points (base64) of the active strokes of [noteId] on [d].
Set<Object?> pointsOf(TestDevice d, String noteId) => {
  for (final page in d.pageIdsOf(noteId))
    for (final s in d.activeStrokesOf(page)) s.json['points'],
};

void main() {
  syncScenario('S08 purge on A vs strokes added offline on B', (h) {
    final a = h.device('A');
    final b = h.device('B');
    final recovered = <NoteRecoveredFromPurge>[];
    final sub = b.engine.notices.listen((n) {
      if (n is NoteRecoveredFromPurge) recovered.add(n);
    });
    final note = a.createNote('Lecture');
    final page = a.pageIdsOf(note).single;
    final original = [for (var i = 0; i < 4; i++) a.addStroke(page, seed: i)];
    h.settle();
    b.goOffline();
    a.purgeNote(note);
    h.settle();
    final added = [
      for (var i = 0; i < 3; i++) b.addStroke(page, seed: 100 + i),
    ];
    final points = pointsOf(b, note);
    expect(points, hasLength(7));
    h.elapse(const Duration(seconds: 1));
    b.goOnline();
    h.settle();

    const copyTitle = 'Lecture (동기화 복구)';
    for (final d in [a, b]) {
      expect(entityOn<Note>(d, EntityKind.note, note), isNull, reason: d.name);
      for (final id in [...original, ...added]) {
        expect(strokeOn(d, id), isNull, reason: '${d.name}: $id purged');
      }
      final copies = notesTitled(d, copyTitle);
      expect(copies, hasLength(1), reason: d.name);
      expect(pointsOf(d, copies.single.id), points, reason: d.name);
    }
    expect(recovered, hasLength(1));
    expect(recovered.single.purgedNoteId, note);
    expect(recovered.single.copyNoteId, notesTitled(b, copyTitle).single.id);
    h.checkConverged([a, b]);

    // Every chunk again from the start (the original's upserts come before its purge).
    b.auth.setUser(null);
    h.settle();
    h.run(b.store.sync.writeMeta({'sync.cursor': ''}));
    b.auth.setUser(const AuthUser(uid: 'user-1'));
    h.settle();
    expect(b.engine.status.phase, SyncPhase.live);
    expect(entityOn<Note>(b, EntityKind.note, note), isNull);
    expect(strokeOn(b, original.first), isNull);
    h.checkConverged([a, b]);
    unawaited(sub.cancel());
  });
}
