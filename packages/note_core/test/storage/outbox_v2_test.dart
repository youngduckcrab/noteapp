// CORE T26 — outbox hints of the DB v2 kinds (m5-7/02-core 6.13, C2-13): a page object and a
// handwriting result always carry noteId and pageId, for local writes and for the entries of
// the remote paths (commitRepairs, applyRemote WriteMerged); an orphan object's entry gets its
// noteId with the commit that brings its page. A recording title change records {title}.
@TestOn('vm')
library;

import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/outbox_writer.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import '../sync/support/sync_support.dart';
import 'storage_support.dart';

void main() {
  late DriftNoteStore store;
  setUp(() async => store = await openStore());
  tearDown(() => store.close());

  Future<List<OutboxEntry>> outbox() => readOutbox(store.db);
  Future<void> ack() => store.db.delete(store.db.outbox).go();
  Future<Map<String, OutboxEntry>> byId() async => {
    for (final e in await outbox()) e.entityId: e,
  };

  HandwritingText handwriting(String pageId, NoteId noteId) => HandwritingText(
    noteId: noteId,
    pageId: pageId,
    engineId: 'fake/1:ko',
    sourceRev: HandwritingText.sourceRevOf(const []),
    lines: const [],
    createdAt: 1,
  );

  Future<void> seedNotePage() => store.queue.run((tx) async {
    await tx.putLocal(note('n1'), const {kAllFields});
    await tx.putLocal(page('p1', 'n1'), const {kAllFields});
  });

  group('local writes', () {
    test('a new object and a handwriting result: noteId and pageId', () async {
      final shape = PageObjectFixtures.shape(pageId: 'p1', id: 'o1');
      await store.queue.run((tx) async {
        await tx.putLocal(note('n1'), const {kAllFields});
        await tx.putLocal(page('p1', 'n1'), const {kAllFields});
        // Same transaction as its page: the page → note lookup is the page just written.
        await tx.putLocal(shape, const {kAllFields});
        await tx.putLocal(handwriting('p1', 'n1'), const {kAllFields});
      });
      // An object of a page written in an earlier commit (noteId from the page row).
      final text = PageObjectFixtures.textBox(pageId: 'p1', id: 'o2');
      await store.queue.run((tx) => tx.putLocal(text, const {kAllFields}));
      final e = await byId();
      for (final id in ['o1', 'o2', HandwritingText.idFor('p1')]) {
        expect((e[id]!.noteId, e[id]!.pageId), ('n1', 'p1'), reason: id);
        expect(e[id]!.op, OutboxOp.upsert);
        expect(e[id]!.changedFields, {kAllFields});
      }
      expect(e['o1']!.kind, EntityKind.pageObject);
      expect(e[HandwritingText.idFor('p1')]!.kind, EntityKind.handwriting);
      // The object rows keep the denormalized note id.
      final rows = await store.db.select(store.db.pageObjects).get();
      expect({for (final r in rows) r.noteId}, {'n1'});
    });

    test('a changed field: that field only, still both hints', () async {
      await seedNotePage();
      final text = PageObjectFixtures.textBox(pageId: 'p1', id: 'o1');
      final hw = handwriting('p1', 'n1');
      await store.queue.run((tx) async {
        await tx.putLocal(text, const {kAllFields});
        await tx.putLocal(hw, const {kAllFields});
      });
      await ack();
      await store.queue.run((tx) async {
        await tx.putLocal(text.copyWith(text: 'changed', updatedAt: 9), const {
          'text',
          'updatedAt',
        });
        await tx.putLocal(hw.copyWith(sourceRev: 'ffffffffffffffff'), const {
          'sourceRev',
        });
        await tx.putLocal(
          text.copyWith(text: 'changed').copyWithMeta(deletedAt: 10),
          const {'deletedAt'},
        );
      });
      final e = await byId();
      expect(e['o1']!.changedFields, {'deletedAt', 'text'});
      expect((e['o1']!.noteId, e['o1']!.pageId), ('n1', 'p1'));
      final h = e[hw.id]!;
      expect(h.changedFields, {'sourceRev'});
      expect((h.noteId, h.pageId), ('n1', 'p1'));
    });

    test('a purge entry of an object carries the hints given', () async {
      await seedNotePage();
      await ack();
      await store.queue.run(
        (tx) => tx.purge(
          const EntityRef(EntityKind.pageObject, 'o9'),
          noteId: 'n1',
          pageId: 'p1',
        ),
      );
      final e = (await outbox()).single;
      expect((e.op, e.noteId, e.pageId), (OutboxOp.purge, 'n1', 'p1'));
    });

    test('a recording title change records {title}', () async {
      final r = recording('r1', 'n1');
      await store.queue.run((tx) => tx.putLocal(r, const {kAllFields}));
      await ack();
      await store.queue.run(
        (tx) => tx.putLocal(r.copyWith(title: '1교시', updatedAt: 5), const {
          'title',
          'updatedAt',
        }),
      );
      final e = (await outbox()).single;
      expect(e.changedFields, {'title'});
      expect((e.kind, e.noteId, e.pageId), (EntityKind.recording, 'n1', null));
      await ack();
      await store.queue.run(
        (tx) => tx.putLocal(r.copyWith(clearTitle: true), const {'title'}),
      );
      expect((await outbox()).single.changedFields, {'title'});
    });
  });

  group('remote paths', () {
    test('remote writes themselves record nothing', () async {
      await seedNotePage();
      await ack();
      await store.sync.applyRemote([
        upsert(
          PageObjectFixtures.math(pageId: 'p1', id: 'o1'),
          remoteAfter(store),
        ),
        upsert(handwriting('p1', 'n1'), remoteAfter(store)),
      ], policy: newerVersionWinsPolicy);
      expect(await outbox(), isEmpty);
    });

    test('commitRepairs entries: noteId and pageId', () async {
      await seedNotePage();
      await ack();
      final hw = handwriting('p1', 'n1');
      await store.sync.commitRepairs([
        (
          entity: PageObjectFixtures.image(
            pageId: 'p1',
            assetId: 'a' * 64,
            id: 'o1',
          ),
          fields: {kAllFields},
        ),
        (entity: hw, fields: {'lines'}),
      ]);
      final e = await byId();
      expect((e['o1']!.noteId, e['o1']!.pageId), ('n1', 'p1'));
      expect((e[hw.id]!.noteId, e[hw.id]!.pageId), ('n1', 'p1'));
      expect(e[hw.id]!.changedFields, {kAllFields}, reason: 'no row: *');
    });

    test('a WriteMerged entry: noteId and pageId', () async {
      await seedNotePage();
      final text = PageObjectFixtures.textBox(pageId: 'p1', id: 'o1');
      final hw = handwriting('p1', 'n1');
      await store.queue.run((tx) async {
        await tx.putLocal(text, const {kAllFields});
        await tx.putLocal(hw, const {kAllFields});
      });
      await ack();
      final policy = RecordingPolicy(
        (local, remote, pending) => WriteMerged(
          remote.entity,
          remote.versions,
          fieldsToUpload: const {'style'},
        ),
      );
      await store.sync.applyRemote([
        upsert(text.copyWith(text: 'remote'), remoteAfter(store)),
        upsert(hw.copyWith(engineId: 'other/2:ko'), remoteAfter(store)),
      ], policy: policy.call);
      final e = await byId();
      expect(e['o1']!.changedFields, {'style'});
      expect((e['o1']!.noteId, e['o1']!.pageId), ('n1', 'p1'));
      expect((e[hw.id]!.noteId, e[hw.id]!.pageId), ('n1', 'p1'));
    });

    test(
      'an orphan object repair: the entry gets its noteId with the page',
      () async {
        await store.sync.commitRepairs([
          (
            entity: PageObjectFixtures.shape(pageId: 'late-page', id: 'o1'),
            fields: {kAllFields},
          ),
          // A stroke orphan of the same page (the 1차 rule, same commit).
          (entity: stroke('s1', 'late-page'), fields: {kAllFields}),
        ]);
        var e = await byId();
        expect((e['o1']!.noteId, e['o1']!.pageId), (null, 'late-page'));
        expect(e['s1']!.noteId, isNull);
        final row = await store.db.select(store.db.pageObjects).getSingle();
        expect(row.noteId, '', reason: 'stored as an orphan');

        await store.sync.applyRemote([
          upsert(page('late-page', 'n7'), remoteAfter(store)),
        ], policy: newerVersionWinsPolicy);
        e = await byId();
        expect((e['o1']!.noteId, e['o1']!.pageId), ('n7', 'late-page'));
        expect((e['s1']!.noteId, e['s1']!.pageId), ('n7', 'late-page'));
        final adopted = await store.db.select(store.db.pageObjects).getSingle();
        expect(adopted.noteId, 'n7');
      },
    );
  });
}
