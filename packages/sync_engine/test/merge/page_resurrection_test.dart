// T11: page resurrection after an apply group (6.7.3) — input = MergeRecorder outcomes of
// committed calls. (a) the deleter brings a page back for a stroke it did not know, (b) the
// writer brings it back for its unsent stroke creation, a third device does not decide, a
// stroke already known keeps the page deleted (S06c), and a page whose note row is gone (a
// purged note's orphan, SYNC-3-3) is never brought back while a trashed note's page is.
// 2nd round S2-5 (07-sync 6.2.6): a page object counts like a stroke in (a) and (b); a
// change of a known object, a handwriting result and a recording are no reason.
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/src/merge/merge_recorder.dart';
import 'package:sync_engine/src/merge/page_resurrection.dart';
import 'package:sync_engine/testing.dart';

import '../support/entity_fixtures.dart' show fixtureJson;
import '../support/local_writes.dart';
import '../support/merge_rig.dart';

EntityRef objectRef(String id) => EntityRef(EntityKind.pageObject, id);
EntityRef handwritingRef(String pageId) =>
    EntityRef(EntityKind.handwriting, 'hw_$pageId');
EntityRef recordingRef(String id) => EntityRef(EntityKind.recording, id);

FakeLocalWrite recordingWrite(String id, String noteId) => FakeLocalWrite(
  EntityKind.recording,
  {...fixtureJson(EntityKind.recording, id: id), 'noteId': noteId},
  changedFields: const {kAllFields},
);

FakeLocalWrite pageDeleted(String id, String noteId) => FakeLocalWrite(
  EntityKind.page,
  {...pageWrite(id, noteId).json, 'deletedAt': 99},
  changedFields: const {'deletedAt'},
);

FakeLocalWrite strokeErased(String id, String pageId) => FakeLocalWrite(
  EntityKind.stroke,
  {...strokeWrite(id, pageId).json, 'deletedAt': 99},
  changedFields: const {'deletedAt'},
);

/// Note n with page p on A, B and C; outboxes acknowledged.
void notePage(MergeRig r) {
  r.write(r.a, [noteWrite('n'), pageWrite('p', 'n')]);
  for (final to in [r.b, r.c]) {
    r.transfer(r.a, to, [noteRef('n'), pageRef('p')]);
  }
  for (final s in [r.a, r.b, r.c]) {
    r.ackAll(s);
  }
}

List<PageRepair> check(
  MergeRig r,
  FakeLocalStore s,
  Map<EntityRef, MergeOutcomeKind> o,
) => r.run(PageResurrection(sync: s.sync).check(o));

void main() {
  group('(a) deleter side', () {
    test('a stroke new here (created) on a page this device deleted → the page '
        'comes back: fields {deletedAt}, deletedAt null', () {
      withMergeRig((r) {
        notePage(r);
        r.write(r.a, [pageDeleted('p', 'n')]);
        r.write(r.b, [strokeWrite('s', 'p')]);
        final outcomes = r.transfer(r.b, r.a, [strokeRef('s')]);
        expect(outcomes, {strokeRef('s'): MergeOutcomeKind.created});
        final repair = check(r, r.a, outcomes).single;
        expect(repair.pageId, 'p');
        expect(repair.noteId, 'n');
        expect(repair.write.fields, {'deletedAt'});
        final page = repair.write.entity as Page;
        expect(page.id, 'p');
        expect(page.isDeleted, isFalse);
        r.run(r.a.sync.commitRepairs([repair.write]));
        expect(r.a.rows[pageRef('p')]!.entity.isDeleted, isFalse);
      });
    });

    test('a stroke this device already knew keeps the page deleted (S06c)', () {
      withMergeRig((r) {
        notePage(r);
        r.write(r.b, [strokeWrite('s', 'p')]);
        r.transfer(r.b, r.a, [strokeRef('s')]);
        r.write(r.a, [pageDeleted('p', 'n')]);
        r.write(r.b, [
          FakeLocalWrite(
            EntityKind.stroke,
            strokeWrite('s', 'p').json,
            changedFields: const {'style'},
          ),
        ]);
        final outcomes = r.transfer(r.b, r.a, [strokeRef('s')]);
        expect(outcomes.values.single, isNot(MergeOutcomeKind.created));
        expect(check(r, r.a, outcomes), isEmpty);
      });
    });

    test('an erased stroke does not bring the page back', () {
      withMergeRig((r) {
        notePage(r);
        r.write(r.a, [pageDeleted('p', 'n')]);
        r.write(r.b, [strokeWrite('s', 'p')]);
        r.write(r.b, [strokeErased('s', 'p')]);
        final outcomes = r.transfer(r.b, r.a, [strokeRef('s')]);
        expect(outcomes.values.single, MergeOutcomeKind.created);
        expect(check(r, r.a, outcomes), isEmpty);
      });
    });

    test('a page another device deleted is not (a)', () {
      withMergeRig((r) {
        notePage(r);
        r.write(r.b, [pageDeleted('p', 'n')]);
        r.transfer(r.b, r.a, [pageRef('p')]);
        r.write(r.c, [strokeWrite('s', 'p')]);
        final outcomes = r.transfer(r.c, r.a, [strokeRef('s')]);
        expect(outcomes.values.single, MergeOutcomeKind.created);
        expect(check(r, r.a, outcomes), isEmpty);
      });
    });
  });

  group('(b) writer side', () {
    test('a received page deletion while an unsent stroke creation is on it → '
        'the page comes back', () {
      withMergeRig((r) {
        notePage(r);
        r.write(r.a, [strokeWrite('s', 'p')]); // unsent: outbox '*'
        r.write(r.b, [pageDeleted('p', 'n')]);
        final outcomes = r.transfer(r.b, r.a, [pageRef('p')]);
        expect(outcomes, {pageRef('p'): MergeOutcomeKind.taken});
        final repair = check(r, r.a, outcomes).single;
        expect(repair.pageId, 'p');
        expect((repair.write.entity as Page).isDeleted, isFalse);
      });
    });

    test('only a changed (not created) stroke in the outbox: the page stays '
        'deleted', () {
      withMergeRig((r) {
        notePage(r);
        r.write(r.a, [strokeWrite('s', 'p')]);
        r.ackAll(r.a);
        r.write(r.a, [
          FakeLocalWrite(
            EntityKind.stroke,
            strokeWrite('s', 'p').json,
            changedFields: const {'style'},
          ),
        ]);
        r.write(r.b, [pageDeleted('p', 'n')]);
        final outcomes = r.transfer(r.b, r.a, [pageRef('p')]);
        expect(check(r, r.a, outcomes), isEmpty);
      });
    });
  });

  test('a third device does not decide: it neither deleted the page nor holds '
      'an unsent stroke on it', () {
    withMergeRig((r) {
      notePage(r);
      r.write(r.a, [strokeWrite('s', 'p')]);
      r.write(r.b, [pageDeleted('p', 'n')]);
      final rows = {...r.a.rows, pageRef('p'): r.b.rows[pageRef('p')]!};
      final outcomes = r.transfer(r.a, r.c, [
        pageRef('p'),
        strokeRef('s'),
      ], rows: rows);
      expect(outcomes, {
        pageRef('p'): MergeOutcomeKind.taken,
        strokeRef('s'): MergeOutcomeKind.created,
      });
      expect(check(r, r.c, outcomes), isEmpty);
    });
  });

  group('note row gone vs trashed note', () {
    test('(a): an orphan page of a purged note is not brought back', () {
      withMergeRig((r) {
        notePage(r);
        r.write(r.a, [pageDeleted('p', 'n')]);
        final deletedPage = {pageRef('p'): r.a.rows[pageRef('p')]!};
        r.a.localPurge(noteRef('n'), group: [noteRef('n')]);
        expect(r.a.rows[pageRef('p')], isNull);
        // The narrow gap: the page record passes the gate and lands as an orphan row.
        r.transfer(r.a, r.a, [pageRef('p')], rows: deletedPage);
        expect(r.a.rows[pageRef('p')], isNotNull);
        expect(r.a.rows[noteRef('n')], isNull);
        r.write(r.b, [strokeWrite('s', 'p')]);
        final outcomes = r.transfer(r.b, r.a, [strokeRef('s')]);
        expect(outcomes.values.single, MergeOutcomeKind.created);
        expect(check(r, r.a, outcomes), isEmpty);
      });
    });

    test('(b): a page whose note row this device does not have is not brought '
        'back', () {
      withMergeRig((r) {
        r.write(r.b, [noteWrite('n2'), pageWrite('p2', 'n2')]);
        r.transfer(r.b, r.a, [pageRef('p2')]); // page row only
        r.write(r.a, [strokeWrite('s', 'p2')]);
        r.write(r.b, [pageDeleted('p2', 'n2')]);
        final outcomes = r.transfer(r.b, r.a, [pageRef('p2')]);
        expect(outcomes.values.single, MergeOutcomeKind.taken);
        expect(check(r, r.a, outcomes), isEmpty);
      });
    });

    test("a trashed note's page is brought back (the note row is there)", () {
      withMergeRig((r) {
        notePage(r);
        r.write(r.a, [
          FakeLocalWrite(
            EntityKind.note,
            {...noteWrite('n').json, 'deletedAt': 50, 'trashRootId': 'n'},
            changedFields: const {'deletedAt', 'trashRootId'},
          ),
          pageDeleted('p', 'n'),
        ]);
        r.write(r.b, [strokeWrite('s', 'p')]);
        final outcomes = r.transfer(r.b, r.a, [strokeRef('s')]);
        expect(check(r, r.a, outcomes).single.pageId, 'p');
      });
    });
  });
  group('page objects, handwriting and recordings (2nd round, S2-5)', () {
    test('(a) a page object new here (created) on a page this device deleted → '
        'the page comes back', () {
      withMergeRig((r) {
        notePage(r);
        r.write(r.a, [pageDeleted('p', 'n')]);
        r.write(r.b, [objectWrite('o', 'p', type: 'text')]);
        final outcomes = r.transfer(r.b, r.a, [objectRef('o')]);
        expect(outcomes, {objectRef('o'): MergeOutcomeKind.created});
        final repair = check(r, r.a, outcomes).single;
        expect(repair.pageId, 'p');
        expect(repair.noteId, 'n');
        expect(repair.write.fields, {'deletedAt'});
        expect((repair.write.entity as Page).isDeleted, isFalse);
      });
    });

    test('(a) an object of an unknown type counts too (user content)', () {
      withMergeRig((r) {
        notePage(r);
        r.write(r.a, [pageDeleted('p', 'n')]);
        r.write(r.b, [objectWrite('o', 'p', type: 'sticker')]);
        final outcomes = r.transfer(r.b, r.a, [objectRef('o')]);
        expect(check(r, r.a, outcomes).single.pageId, 'p');
      });
    });

    test('(a) a change (move, restyle) or a deletion of an object this device '
        'knew keeps the page deleted', () {
      withMergeRig((r) {
        notePage(r);
        r.write(r.b, [objectWrite('o', 'p'), objectWrite('o2', 'p')]);
        r.transfer(r.b, r.a, [objectRef('o'), objectRef('o2')]);
        r.write(r.a, [pageDeleted('p', 'n')]);
        r.write(r.b, [
          objectWrite(
            'o',
            'p',
            set: const {
              'frame': [140.0, 140.0, 340.0, 260.0, 0.0],
              'geometry': {
                'poly': [
                  140.0,
                  140.0,
                  340.0,
                  140.0,
                  340.0,
                  260.0,
                  140.0,
                  260.0,
                ],
                'closed': true,
              },
            },
            fields: const {'frame', 'geometry'},
          ),
          objectWrite(
            'o2',
            'p',
            set: const {'deletedAt': 99},
            fields: const {'deletedAt'},
          ),
        ]);
        final outcomes = r.transfer(r.b, r.a, [
          objectRef('o'),
          objectRef('o2'),
        ]);
        expect(outcomes.values, everyElement(isNot(MergeOutcomeKind.created)));
        expect(check(r, r.a, outcomes), isEmpty);
      });
    });

    test(
      '(a) an object erased before it arrives does not bring the page back',
      () {
        withMergeRig((r) {
          notePage(r);
          r.write(r.a, [pageDeleted('p', 'n')]);
          r.write(r.b, [objectWrite('o', 'p')]);
          r.write(r.b, [
            objectWrite(
              'o',
              'p',
              set: const {'deletedAt': 99},
              fields: const {'deletedAt'},
            ),
          ]);
          final outcomes = r.transfer(r.b, r.a, [objectRef('o')]);
          expect(outcomes.values.single, MergeOutcomeKind.created);
          expect(check(r, r.a, outcomes), isEmpty);
        });
      },
    );

    test(
      '(a) a handwriting result or a recording new here is no reason (derived '
      'data / note content without a page)',
      () {
        withMergeRig((r) {
          notePage(r);
          r.write(r.a, [pageDeleted('p', 'n')]);
          r.write(r.b, [
            handwritingWrite('p', 'n'),
            recordingWrite('rec', 'n'),
          ]);
          final outcomes = r.transfer(r.b, r.a, [
            handwritingRef('p'),
            recordingRef('rec'),
          ]);
          expect(outcomes, {
            handwritingRef('p'): MergeOutcomeKind.created,
            recordingRef('rec'): MergeOutcomeKind.created,
          });
          expect(check(r, r.a, outcomes), isEmpty);
        });
      },
    );

    test(
      '(b) a received page deletion while an unsent object creation is on it '
      '→ the page comes back',
      () {
        withMergeRig((r) {
          notePage(r);
          r.write(r.a, [objectWrite('o', 'p', type: 'math')]); // unsent: '*'
          final hint = r.a.outbox.singleWhere(
            (e) => e.kind == EntityKind.pageObject,
          );
          expect(hint.pageId, 'p');
          expect(hint.changedFields, contains(kAllFields));
          r.write(r.b, [pageDeleted('p', 'n')]);
          final outcomes = r.transfer(r.b, r.a, [pageRef('p')]);
          expect(outcomes, {pageRef('p'): MergeOutcomeKind.taken});
          final repair = check(r, r.a, outcomes).single;
          expect(repair.pageId, 'p');
          expect((repair.write.entity as Page).isDeleted, isFalse);
        });
      },
    );

    test(
      '(b) only an unsent change of a sent object: the page stays deleted',
      () {
        withMergeRig((r) {
          notePage(r);
          r.write(r.a, [objectWrite('o', 'p', type: 'text')]);
          r.ackAll(r.a);
          r.write(r.a, [
            objectWrite(
              'o',
              'p',
              type: 'text',
              set: const {'text': '바뀐 글'},
              fields: const {'text'},
            ),
          ]);
          r.write(r.b, [pageDeleted('p', 'n')]);
          final outcomes = r.transfer(r.b, r.a, [pageRef('p')]);
          expect(check(r, r.a, outcomes), isEmpty);
        });
      },
    );

    test('(b) an unsent handwriting result or recording: the page stays '
        'deleted', () {
      withMergeRig((r) {
        notePage(r);
        r.write(r.a, [handwritingWrite('p', 'n'), recordingWrite('rec', 'n')]);
        expect(
          r.a.outbox.map((e) => e.kind),
          containsAll([EntityKind.handwriting, EntityKind.recording]),
        );
        r.write(r.b, [pageDeleted('p', 'n')]);
        final outcomes = r.transfer(r.b, r.a, [pageRef('p')]);
        expect(outcomes, {pageRef('p'): MergeOutcomeKind.taken});
        expect(check(r, r.a, outcomes), isEmpty);
      });
    });

    test('an orphan page of a purged note is not brought back for an object '
        'either', () {
      withMergeRig((r) {
        notePage(r);
        r.write(r.a, [pageDeleted('p', 'n')]);
        final deletedPage = {pageRef('p'): r.a.rows[pageRef('p')]!};
        r.a.localPurge(noteRef('n'), group: [noteRef('n')]);
        r.transfer(r.a, r.a, [pageRef('p')], rows: deletedPage);
        expect(r.a.rows[noteRef('n')], isNull);
        r.write(r.b, [objectWrite('o', 'p')]);
        final outcomes = r.transfer(r.b, r.a, [objectRef('o')]);
        expect(outcomes.values.single, MergeOutcomeKind.created);
        expect(check(r, r.a, outcomes), isEmpty);
      });
    });
  });
}
