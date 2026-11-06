// S28 (07-sync 6.7.1, 6.2.5, SYNC-M3): handwriting results. A writes the result of page P,
// B receives it; A and B, offline, each recognize P again (other lines) → one result id
// hw_P, the later write wins. Then B, connected, writes P's result again (B's "recently
// sent" holds nothing for N: a chunk with handwriting only is left out), goes offline two
// minutes later — inside the 10 min window — and writes yet another result while A trashes
// and purges N. B connects: no recovery copy (no NoteRecoveredFromPurge), the late result
// is gone with N on both sides. Contrast: the same flow where B sent a STROKE two minutes
// before → one copy (v1 rule).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import 'support/scenario_checks.dart';
import 'support/sync_scenario.dart';

const String _copyTitle = 'S28 (동기화 복구)';

List<String> linesOf(SyncDoc doc) => [
  for (final line in doc.json['lines']! as List)
    (line as Map)['text']! as String,
];

/// Handwriting row ids of [d] (removed ones included).
Set<String> handwritingIdsOn(TestDevice d) => {
  for (final ref in d.store.rows.keys)
    if (ref.kind == EntityKind.handwriting) ref.id,
};

List<Note> notesTitled(TestDevice d, String title) => [
  for (final row in d.store.rows.values)
    if (row.entity case final Note n when !n.isDeleted && n.title == title) n,
];

/// Second half of S28: B's last send before A purges N is a handwriting result or, with
/// [strokeSent], a stroke. Returns both devices and the recovery notices B raised.
({TestDevice a, TestDevice b, List<NoteRecoveredFromPurge> recovered})
purgeAfterRecentSend(SyncTestHarness h, {required bool strokeSent}) {
  final a = h.device('A');
  final b = h.device('B');
  final recovered = <NoteRecoveredFromPurge>[];
  final sub = b.engine.notices.listen((n) {
    if (n is NoteRecoveredFromPurge) recovered.add(n);
  });
  final note = a.createNote('S28');
  final page = a.pageIdsOf(note).single;
  a.addStroke(page);
  a.putHandwriting(page, ['적분']);
  h.settle();
  expect(linesOf(b.handwritingOf(page)!), ['적분']);

  // B, connected, sends its last edit of N.
  if (strokeSent) {
    b.addStroke(page, seed: 7);
  } else {
    b.putHandwriting(page, ['적분 다시']);
  }
  h.settle();
  expect(b.store.outbox, isEmpty);
  h.elapse(const Duration(minutes: 2));
  b.goOffline();
  a.purgeNote(note);
  h.settle();
  b.putHandwriting(page, ['늦은 결과']);
  h.elapse(const Duration(seconds: 1));
  b.goOnline();
  h.settle();

  for (final d in [a, b]) {
    expect(entityOn<Note>(d, EntityKind.note, note), isNull, reason: d.name);
    expect(
      d.doc(EntityKind.handwriting, HandwritingText.idFor(page)),
      isNull,
      reason: '${d.name}: the late result went with N',
    );
  }
  unawaited(sub.cancel());
  return (a: a, b: b, recovered: recovered);
}

void main() {
  syncScenario('S28 two offline results for one page: one id hw_P, the later '
      'write wins', (h) {
    final a = h.device('A');
    final b = h.device('B');
    final note = a.createNote('S28');
    final page = a.pageIdsOf(note).single;
    for (var i = 0; i < 3; i++) {
      a.addStroke(page, seed: i);
    }
    a.putHandwriting(page, ['미분']);
    h.settle();
    expect(linesOf(b.handwritingOf(page)!), ['미분']);

    a.goOffline();
    b.goOffline();
    a.putHandwriting(page, ['미분 계수', '도함수']);
    h.elapse(const Duration(seconds: 1));
    b.putHandwriting(page, ['미분법']); // later
    h.elapse(const Duration(seconds: 1));
    a.goOnline();
    b.goOnline();
    h.settle();
    for (final d in [a, b]) {
      expect(handwritingIdsOn(d), {
        HandwritingText.idFor(page),
      }, reason: d.name);
      expect(linesOf(d.handwritingOf(page)!), ['미분법'], reason: d.name);
    }
    h.checkConverged([a, b]);
  });

  syncScenario('S28 only a handwriting result sent 2 min before the purge, '
      'only a result pending: no recovery copy', (h) {
    final (:a, :b, :recovered) = purgeAfterRecentSend(h, strokeSent: false);
    expect(recovered, isEmpty);
    for (final d in [a, b]) {
      expect(notesTitled(d, _copyTitle), isEmpty, reason: d.name);
      expect(handwritingIdsOn(d), isEmpty, reason: d.name);
    }
    h.checkConverged([a, b]);
  });

  syncScenario('S28 contrast: a stroke sent 2 min before the purge → one '
      'recovery copy with the late result', (h) {
    final (:a, :b, :recovered) = purgeAfterRecentSend(h, strokeSent: true);
    expect(recovered, hasLength(1));
    for (final d in [a, b]) {
      final copies = notesTitled(d, _copyTitle);
      expect(copies, hasLength(1), reason: d.name);
      final page = d.pageIdsOf(copies.single.id).single;
      expect(d.activeStrokesOf(page), hasLength(2), reason: d.name);
      expect(linesOf(d.handwritingOf(page)!), ['늦은 결과'], reason: d.name);
    }
    expect(recovered.single.copyNoteId, notesTitled(b, _copyTitle).single.id);
    h.checkConverged([a, b]);
  });
}
