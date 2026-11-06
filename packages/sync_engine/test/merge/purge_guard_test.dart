// T11: PurgeGuard (6.7.4) before received purges are applied — a note this device still
// edits (unsent page / stroke / recording entries, an unsent change of its own non-trash
// fields, or content of its scope sent in the last 10 min) is copied with
// duplicateNoteForRecovery first; otherwise the purge just applies.
// 2nd round S2-5 (07-sync 6.2.5): an unsent page object is an edit, a handwriting result
// is not (outbox or recently sent — UploadPipeline does not report a handwriting-only
// chunk), and the copy carries recordings, objects and the handwriting result.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/merge/purge_guard.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../support/engine_harness.dart';
import '../support/entity_fixtures.dart' show fixtureJson;
import '../support/local_writes.dart';
import '../support/merge_rig.dart';

FakeLocalWrite recordingWrite(String id, String noteId) => FakeLocalWrite(
  EntityKind.recording,
  {...fixtureJson(EntityKind.recording, id: id), 'noteId': noteId},
  changedFields: const {kAllFields},
);

PurgeRecord purgeOf(EntityRef ref) =>
    PurgeRecord(ref, Hlc(kMergeStart.millisecondsSinceEpoch + 1000, 0, kNodeB));

PurgeGuard guardOf(
  MergeRig r, {
  Duration window = const Duration(minutes: 10),
}) => PurgeGuard(
  sync: r.a.sync,
  titleSuffix: ' (동기화 복구)',
  window: window,
  nowMillis: () => r.a.clock.now().millisecondsSinceEpoch,
);

/// Note n with page p, stroke s and text box o on A, all sent (outbox empty).
void synced(MergeRig r) {
  r.write(r.a, [
    noteWrite('n', title: '회의'),
    pageWrite('p', 'n'),
    strokeWrite('s', 'p'),
    objectWrite('o', 'p', type: 'text'),
  ]);
  r.ackAll(r.a);
}

List<Note> notes(MergeRig r) => [
  for (final row in r.a.rows.values)
    if (row.entity case final Note note) note,
];

void main() {
  test('nothing pending and nothing sent lately: no copy, the purge just '
      'applies', () {
    withMergeRig((r) {
      synced(r);
      final notices = r.run(guardOf(r).guard([purgeOf(noteRef('n'))]));
      expect(notices, isEmpty);
      expect(notes(r), hasLength(1));
    });
  });

  for (final (what, edit) in [
    ('an unsent stroke', strokeWrite('s2', 'p')),
    ('an unsent page', pageWrite('p2', 'n')),
    (
      'an unsent title change of the note',
      noteWrite('n', title: '바뀐 제목', fields: const {'title'}),
    ),
    ('an unsent recording', recordingWrite('rec2', 'n')),
    ('an unsent page object (2nd round)', objectWrite('o2', 'p', type: 'text')),
    (
      'an unsent change of a sent page object (2nd round)',
      objectWrite(
        'o',
        'p',
        type: 'text',
        set: const {'text': '바뀐 글'},
        fields: const {'text'},
      ),
    ),
  ]) {
    test('$what → a copy (title + suffix) before the purge, '
        'NoteRecoveredFromPurge', () {
      withMergeRig((r) {
        synced(r);
        r.write(r.a, [edit]);
        final notices = r.run(guardOf(r).guard([purgeOf(noteRef('n'))]));
        final notice = notices.single;
        expect(notice.purgedNoteId, 'n');
        expect(notice.copyNoteId, isNot('n'));
        expect(notice.at, r.a.clock.now().millisecondsSinceEpoch);
        final copy = r.a.rows[noteRef(notice.copyNoteId)]!.entity as Note;
        expect(copy.title, endsWith(' (동기화 복구)'));
        expect(copy.isDeleted, isFalse);
        expect(
          r.a.outbox.any(
            (e) =>
                e.entityId == copy.id && e.changedFields.contains(kAllFields),
          ),
          isTrue,
        );
      });
    });
  }

  test('an unsent handwriting result only (created or changed) is no reason to '
      'copy (derived data, 2nd round)', () {
    withMergeRig((r) {
      synced(r);
      r.write(r.a, [
        handwritingWrite('p', 'n', strokeIds: const ['s']),
      ]);
      expect(
        r.a.outbox.map((e) => (e.kind, e.noteId)),
        contains((EntityKind.handwriting, 'n')),
      );
      expect(r.run(guardOf(r).guard([purgeOf(noteRef('n'))])), isEmpty);
      r.ackAll(r.a);
      r.write(r.a, [
        handwritingWrite('p', 'n', text: '적분', fields: const {'lines'}),
      ]);
      expect(r.run(guardOf(r).guard([purgeOf(noteRef('n'))])), isEmpty);
      expect(notes(r), hasLength(1));
    });
  });

  test('the copy carries the recordings, page objects and the handwriting '
      'result of the note (CORE copyNote, 2nd round)', () {
    withMergeRig((r) {
      synced(r);
      r.write(r.a, [
        recordingWrite('rec', 'n'),
        objectWrite('o3', 'p', type: 'math'),
        handwritingWrite('p', 'n', strokeIds: const ['s']),
      ]);
      r.ackAll(r.a);
      r.write(r.a, [strokeWrite('s2', 'p')]);
      final notice = r.run(guardOf(r).guard([purgeOf(noteRef('n'))])).single;
      final copyPages = [
        for (final row in r.a.rows.values)
          if (row.entity case final Page page
              when page.noteId == notice.copyNoteId)
            page,
      ];
      final copyPage = copyPages.single.id;
      expect(copyPage, isNot('p'));
      expect(r.a.objectsOf(copyPage).map((o) => o.runtimeType).toSet(), {
        TextBoxObject,
        MathObject,
      });
      expect(r.a.objectsOf(copyPage).map((o) => o.id), isNot(contains('o')));
      final hw = r.a.handwritingOf(copyPage)!;
      expect(hw.pageId, copyPage);
      expect(hw.noteId, notice.copyNoteId);
      expect(hw.lines.single.strokeIds.single, isNot('s'));
      final recordings = [
        for (final row in r.a.rows.values)
          if (row.entity case final Recording rec
              when rec.noteId == notice.copyNoteId)
            rec,
      ];
      expect(recordings.single.id, isNot('rec'));
    });
  });

  test('a trash-only change of the note (deletedAt, trashRootId) is no reason '
      'to copy', () {
    withMergeRig((r) {
      synced(r);
      r.write(r.a, [
        FakeLocalWrite(EntityKind.note, {
          ...noteWrite('n').json,
          'deletedAt': 5,
          'trashRootId': 'n',
        }, changedFields: kNoteTrashFields),
      ]);
      expect(r.run(guardOf(r).guard([purgeOf(noteRef('n'))])), isEmpty);
    });
  });

  test('content of the note scope sent in the last 10 min → a copy; after the '
      'window → none', () {
    withMergeRig((r) {
      synced(r);
      final guard = guardOf(r)..scopesSent({'lib', 'n'});
      expect(guard.recentlySent, {'n'});
      r.async.elapse(const Duration(minutes: 10));
      expect(r.run(guard.guard([purgeOf(noteRef('n'))])), hasLength(1));
      final later = guardOf(r)..scopesSent({'n'});
      r.async.elapse(const Duration(minutes: 10, milliseconds: 1));
      expect(r.run(later.guard([purgeOf(noteRef('n'))])), isEmpty);
      expect(later.recentlySent, isEmpty);
    });
  });

  test('only note purges are checked; pending edits of other notes do not '
      'count; a note row gone here makes no copy', () {
    withMergeRig((r) {
      synced(r);
      r.write(r.a, [noteWrite('other'), pageWrite('po', 'other')]);
      final guard = guardOf(r);
      expect(
        r.run(guard.guard([purgeOf(folderRef('f')), purgeOf(noteRef('n'))])),
        isEmpty,
      );
      // 'ghost' has pending content here but no note row: CORE returns null.
      r.write(r.a, [pageWrite('pg', 'ghost')]);
      expect(r.run(guard.guard([purgeOf(noteRef('ghost'))])), isEmpty);
    });
  });

  test('a pending local purge of the same note is not an edit', () {
    withMergeRig((r) {
      synced(r);
      r.a.localPurge(noteRef('n'), group: [noteRef('n')]);
      expect(r.run(guardOf(r).guard([purgeOf(noteRef('n'))])), isEmpty);
    });
  });

  test('the outbox is read to the end (afterSeq pages)', () {
    fakeAsync((async) {
      final r = MergeRig(async);
      synced(r);
      for (var i = 0; i < 7; i++) {
        r.write(r.a, [noteWrite('x$i')]);
      }
      r.write(r.a, [strokeWrite('late', 'p')]);
      final guard = PurgeGuard(
        sync: r.a.sync,
        titleSuffix: ' (복구)',
        window: const Duration(minutes: 10),
        nowMillis: () => 0,
        outboxPageSize: 3,
      );
      expect(r.run(guard.guard([purgeOf(noteRef('n'))])), hasLength(1));
    }, initialTime: kMergeStart);
  });

  harnessTest('in the engine: a purge received while this device has unsent '
      'strokes on the note → a recovered copy that every device gets (S08)', (
    h,
    async,
  ) {
    final a = liveDevice(h, 'A');
    final b = liveDevice(h, 'B');
    final n = a.createNote('회의록');
    h.settle();
    final log = EngineLog(b.engine);
    b.goOffline();
    h.settle();
    b.addStroke(b.pageIdsOf(n).single);
    a.purgeNote(n);
    h.settle();
    b.goOnline();
    h.settle();
    final notice = log.notices.whereType<NoteRecoveredFromPurge>().single;
    expect(notice.purgedNoteId, n);
    expect(b.doc(EntityKind.note, n), isNull);
    final copy = a.doc(EntityKind.note, notice.copyNoteId)!;
    expect(copy.json['title'], '회의록 (동기화 복구)');
    expect(
      a.activeStrokesOf(a.pageIdsOf(notice.copyNoteId).single),
      hasLength(1),
    );
    h.checkConverged([a, b]);
  });
  group('in the engine: what UploadPipeline reports as sent (2nd round, '
      'SYNC-M3)', () {
    /// B and A share note n; [edit] runs (B's part is sent — outbox empty) and A purges n
    /// within the 10 min window. Returns the recovered-copy notices of B.
    List<NoteRecoveredFromPurge> purgeAfter(
      SyncTestHarness h,
      void Function(TestDevice a, TestDevice b, String pageId) edit,
    ) {
      final a = liveDevice(h, 'A');
      final b = liveDevice(h, 'B');
      final n = a.createNote('회의록');
      h.settle();
      final page = b.pageIdsOf(n).single;
      final log = EngineLog(b.engine);
      final before = nowMillis(h);
      edit(a, b, page);
      h.settle();
      expect(b.store.outbox, isEmpty, reason: 'the edit was sent');
      a.purgeNote(n);
      h.settle();
      expect(
        nowMillis(h) - before,
        lessThan(const Duration(minutes: 10).inMilliseconds),
        reason: 'still inside purgeGuardWindow',
      );
      expect(b.doc(EntityKind.note, n), isNull, reason: 'the purge applied');
      h.checkConverged([a, b]);
      return log.notices.whereType<NoteRecoveredFromPurge>().toList();
    }

    harnessTest('B recognizes the strokes A wrote and uploads only the '
        'handwriting result just before → no copy, the purge applies', (
      h,
      async,
    ) {
      final notices = purgeAfter(h, (a, b, page) {
        a.addStroke(page);
        h.settle();
        expect(b.activeStrokesOf(page), hasLength(1));
        b.putHandwriting(page, const ['미분']);
      });
      expect(notices, isEmpty);
    });

    harnessTest('control: a stroke uploaded just before → a recovered copy', (
      h,
      async,
    ) {
      final notices = purgeAfter(h, (a, b, page) => b.addStroke(page));
      expect(notices, hasLength(1));
    });

    harnessTest('control: a page object uploaded just before → a recovered '
        'copy', (h, async) {
      final notices = purgeAfter(h, (a, b, page) => b.addObject(page));
      expect(notices, hasLength(1));
    });
  });
}
