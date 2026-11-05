// CORE T14 — SyncStore.commitRepairs (6.10.4, contract 7.2.10 v1.1 / v1.2): exactly
// [fields] restamped with one fresh local HLC, outbox, ChangeBatch(origin: remote), not in
// undo history, device-local fields kept / recomputed, orphan strokes adopted.
@TestOn('vm')
library;

import 'dart:async';

import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import '../storage/storage_support.dart';
import 'support/sync_support.dart';

void main() {
  late DriftNoteStore store;
  late List<ChangeBatch> batches;
  late StreamSubscription<ChangeBatch> sub;

  setUp(() async {
    store = await openStore();
    batches = [];
    sub = store.changes.listen(batches.add);
  });
  tearDown(() async {
    await sub.cancel();
    await store.close();
  });

  Future<VersionedEntity?> read(EntityKind kind, String id) async =>
      (await store.sync.readVersioned([EntityRef(kind, id)])).single;

  Future<OutboxEntry?> entryOf(String id) async =>
      (await store.sync.pendingChanges(limit: 100000))
          .where((e) => e.entityId == id)
          .firstOrNull;

  Future<void> ackAll() async => store.sync.acknowledge([
    for (final e in await store.sync.pendingChanges(limit: 100000)) e.ack,
  ]);

  test(
    'only [fields] get the new HLC; other values and versions stay',
    () async {
      final n = await store.library.createNote(title: 'title');
      await ackAll();
      await store.library.setFavorite([n.id], true);
      final before = (await read(EntityKind.note, n.id))!;
      final fav = before.versions.of('isFavorite');
      await store.sync.commitRepairs([
        (
          entity: n.copyWith(title: 'repaired', tags: ['ignored']),
          fields: {'title'},
        ),
      ]);
      final after = (await read(EntityKind.note, n.id))!;
      final note = after.entity as Note;
      expect(note.title, 'repaired');
      expect(note.tags, isEmpty, reason: 'tags is not in fields');
      expect(note.isFavorite, isTrue);
      final h = after.versions.of('title');
      expect(h.nodeId, store.nodeId);
      expect(h > before.versions.max, isTrue);
      expect(after.versions.of('isFavorite'), fav);
      expect(after.versions.base, before.versions.base);
      expect(after.entity.version, after.versions.max);
      final e = (await entryOf(n.id))!;
      expect(e.changedFields, {'isFavorite', 'title'}, reason: 'merged');
      expect(e.hlc, h);
    },
  );

  test(
    'no row: the whole entity with * at the new HLC; hints on entries',
    () async {
      await store.sync.commitRepairs([
        (entity: note('n1'), fields: {'title'}),
        (entity: page('p1', 'n1'), fields: {'deletedAt'}),
        (entity: stroke('s1', 'p1'), fields: {'style'}),
      ]);
      final vn = (await read(EntityKind.note, 'n1'))!;
      expect(vn.versions.overrides, isEmpty);
      final h = vn.versions.base;
      expect(h.nodeId, store.nodeId);
      expect((await read(EntityKind.page, 'p1'))!.versions.max, h);
      expect(
        (await read(EntityKind.stroke, 's1'))!.versions.max,
        h,
        reason: 'one HLC per call',
      );
      final entries = {
        for (final e in await store.sync.pendingChanges()) e.entityId: e,
      };
      expect(entries['n1']!.changedFields, {kAllFields});
      expect(entries['p1']!.noteId, 'n1');
      expect((entries['s1']!.noteId, entries['s1']!.pageId), ('n1', 'p1'));
      await pumpEventQueue();
      expect(batches.single.origin, ChangeOrigin.remote);
    },
  );

  test(
    'ArgumentError: no synced field, invalid id — nothing written',
    () async {
      await expectLater(
        store.sync.commitRepairs([(entity: folder('f1'), fields: <String>{})]),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        store.sync.commitRepairs([
          (entity: folder('f1'), fields: {'name'}),
          (entity: folder('f2'), fields: {'updatedAt', 'version'}),
        ]),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        store.sync.commitRepairs([
          (entity: folder('bad id'), fields: {'name'}),
        ]),
        throwsA(isA<ArgumentError>()),
      );
      expect(await read(EntityKind.folder, 'f1'), isNull);
      expect(await store.sync.pendingChanges(), isEmpty);
    },
  );

  test('an open session gets a remote change, its history stays', () async {
    final n = await store.library.createNote(title: 'n');
    final session = await store.openSession(n.id);
    final pageId = session.pages.first.id;
    await session.openPage(pageId);
    final s = StrokeFixtures.synthetic(pageId: pageId, ids: store.ids);
    await session.execute(AddStrokes(pageId: pageId, strokes: [s])).persisted;
    final depth = session.history.undoDepth;
    final changes = <PageContentChange>[];
    final listen = session.pageChanges(pageId).listen(changes.add);
    final stored = (await read(EntityKind.stroke, s.id))!.entity as Stroke;
    await store.sync.commitRepairs([
      (entity: stored.copyWith(deletedAt: 5), fields: {'deletedAt'}),
    ]);
    await pumpEventQueue();
    expect(changes.last.origin, ChangeOrigin.remote);
    expect(session.pageIfLoaded(pageId)!.strokeById(s.id), isNull);
    expect(session.history.undoDepth, depth);
    await listen.cancel();
    await session.close();
  });

  test(
    'device-local fields: lastOpenedAt kept, revived page recomputed',
    () async {
      final n = await store.library.createNote(
        title: 'n',
        pages: const [PageDraft.blankA4, PageDraft.blankA4],
      );
      await store.library.markOpened(n.id);
      final opened = (await store.library.getNote(n.id))!.lastOpenedAt;
      final f = await store.library.createFolder(name: 'f');
      await store.sync.commitRepairs([
        (
          entity: n.copyWith(
            folderId: f.id,
            sortKey: 'b0',
            pageCount: 99,
            lastOpenedAt: 1,
          ),
          fields: {'folderId', 'sortKey'},
        ),
      ]);
      var got = (await store.library.getNote(n.id))!;
      expect((got.folderId, got.sortKey), (f.id, 'b0'));
      expect((got.lastOpenedAt, got.pageCount), (opened, 2));

      // A page deleted locally, then revived by a repair ({deletedAt}).
      final pages = await store.db.select(store.db.pages).get();
      final first = pages.firstWhere((p) => p.id == n.firstPageId);
      final session = await store.openSession(n.id);
      await session.execute(DeletePages(pageIds: [first.id])).persisted;
      await session.close();
      got = (await store.library.getNote(n.id))!;
      expect(got.pageCount, 1);
      final deleted = (await read(EntityKind.page, first.id))!.entity as Page;
      final rev = deleted.contentRevision;
      await store.sync.commitRepairs([
        (
          entity: deleted.copyWith(clearDeletedAt: true, contentRevision: 50),
          fields: {'deletedAt'},
        ),
      ]);
      got = (await store.library.getNote(n.id))!;
      expect((got.pageCount, got.firstPageId), (2, first.id));
      final revived = (await read(EntityKind.page, first.id))!.entity as Page;
      expect(revived.isDeleted, isFalse);
      expect(revived.contentRevision, rev + 1);
    },
  );

  test(
    'an orphan stroke joins the batch of the repair that creates its page',
    () async {
      final n = await store.library.createNote(title: 'n');
      await ackAll();
      await pumpEventQueue();
      batches.clear();
      await store.sync.applyRemote([
        upsert(stroke('orphan', 'new-page'), remoteAfter(store)),
      ], policy: newerVersionWinsPolicy);
      await pumpEventQueue();
      expect(batches, isEmpty);
      await store.sync.commitRepairs([
        (entity: page('new-page', n.id), fields: {kAllFields}),
      ]);
      await pumpEventQueue();
      final b = batches.single;
      expect(b.origin, ChangeOrigin.remote);
      final c = {for (final x in b.changes) x.id: x};
      expect((c['orphan']!.noteId, c['orphan']!.pageId), (n.id, 'new-page'));
      final row = await (store.db.select(
        store.db.strokes,
      )..where((t) => t.id.equals('orphan'))).getSingle();
      expect(row.noteId, n.id);
      final p = (await read(EntityKind.page, 'new-page'))!.entity as Page;
      expect(p.contentRevision, 0, reason: 'a new page row');
      expect(
        await entryOf('orphan'),
        isNull,
        reason: 'the stroke row is not rewritten',
      );
    },
  );
}
