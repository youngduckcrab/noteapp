// CORE T26 — ChangeBatch hints of the DB v2 kinds (m5-7/02-core 6.13, C2-13): page objects and
// handwriting results carry noteId and pageId in local and remote batches; a remote object
// that arrives before its page (an orphan, note_id '') is listed, with its noteId, in the batch
// of the commit that brings the page — the 1차 v1.2 orphan stroke rule extended.
@TestOn('vm')
library;

import 'dart:async';

import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import '../sync/support/sync_support.dart';
import 'storage_support.dart';

const Hlc _r1 = Hlc(10, 0, kRemoteNode);
const Hlc _r2 = Hlc(20, 0, kRemoteNode);

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

  Map<String, EntityChange> byId(ChangeBatch b) => {
    for (final c in b.changes) c.id: c,
  };

  HandwritingText handwriting(String pageId, NoteId noteId) => HandwritingText(
    noteId: noteId,
    pageId: pageId,
    engineId: 'fake/1:ko',
    sourceRev: HandwritingText.sourceRevOf(const []),
    lines: const [],
    createdAt: 1,
  );

  final hwId = HandwritingText.idFor('p1');

  test('a local batch: objects and handwriting with both hints', () async {
    await store.queue.run((tx) async {
      await tx.putLocal(note('n1'), const {kAllFields});
      await tx.putLocal(page('p1', 'n1'), const {kAllFields});
      await tx.putLocal(
        PageObjectFixtures.shape(pageId: 'p1', id: 'o1'),
        const {kAllFields},
      );
      await tx.putLocal(handwriting('p1', 'n1'), const {kAllFields});
    });
    await store.queue.run(
      (tx) => tx.putLocal(
        PageObjectFixtures.textBox(
          pageId: 'p1',
          id: 'o2',
        ).copyWithMeta(deletedAt: 3),
        const {kAllFields},
      ),
    );
    await pumpEventQueue();
    expect(batches, hasLength(2));
    final c = byId(batches.first);
    expect(batches.first.origin, ChangeOrigin.local);
    expect(
      (c['o1']!.kind, c['o1']!.noteId, c['o1']!.pageId),
      (EntityKind.pageObject, 'n1', 'p1'),
    );
    expect(
      (c[hwId]!.kind, c[hwId]!.noteId, c[hwId]!.pageId),
      (EntityKind.handwriting, 'n1', 'p1'),
    );
    final o2 = batches.last.changes.single;
    expect((o2.id, o2.noteId, o2.pageId, o2.deleted), ('o2', 'n1', 'p1', true));
  });

  test('a remote batch: the same hints (page stored earlier)', () async {
    await store.queue.run(
      (tx) => tx.putRemote(page('p1', 'n1'), const EntityFieldVersions(_r1)),
      origin: ChangeOrigin.remote,
    );
    await store.queue.run((tx) async {
      await tx.putRemote(
        PageObjectFixtures.math(
          pageId: 'p1',
          id: 'o1',
        ).copyWithMeta(version: _r2),
        const EntityFieldVersions(_r2),
      );
      await tx.putRemote(
        handwriting('p1', 'n1').copyWith(version: _r2),
        const EntityFieldVersions(_r2),
      );
    }, origin: ChangeOrigin.remote);
    await pumpEventQueue();
    final c = byId(batches.last);
    expect(batches.last.origin, ChangeOrigin.remote);
    expect((c['o1']!.noteId, c['o1']!.pageId), ('n1', 'p1'));
    expect((c[hwId]!.noteId, c[hwId]!.pageId), ('n1', 'p1'));
    final rows = await store.db.select(store.db.pageObjects).get();
    expect({for (final r in rows) r.noteId}, {'n1'});
  });

  test('an orphan object is listed with the commit that brings its page', () async {
    // Two objects (one deleted) and a stroke of a page this store has not seen.
    await store.queue.run((tx) async {
      await tx.putRemote(
        PageObjectFixtures.shape(pageId: 'p1', id: 'o1'),
        const EntityFieldVersions(_r1),
      );
      await tx.putRemote(
        PageObjectFixtures.unknown(
          pageId: 'p1',
          id: 'o2',
        ).copyWithMeta(deletedAt: 5),
        const EntityFieldVersions(_r1),
      );
    }, origin: ChangeOrigin.remote);
    await store.queue.run(
      (tx) => tx.putRemote(stroke('s1', 'p1'), const EntityFieldVersions(_r1)),
      origin: ChangeOrigin.remote,
    );
    await pumpEventQueue();
    expect(batches, isEmpty, reason: 'orphans wait for their page');
    final orphans = await store.db.select(store.db.pageObjects).get();
    expect({for (final r in orphans) r.noteId}, {''});

    await store.queue.run(
      (tx) => tx.putRemote(page('p1', 'n1'), const EntityFieldVersions(_r2)),
      origin: ChangeOrigin.remote,
    );
    await pumpEventQueue();
    final b = batches.single;
    expect(b.origin, ChangeOrigin.remote);
    final c = byId(b);
    expect(c.keys.toSet(), {'p1', 'o1', 'o2', 's1'});
    expect(
      (c['o1']!.kind, c['o1']!.noteId, c['o1']!.pageId),
      (EntityKind.pageObject, 'n1', 'p1'),
    );
    expect((c['o2']!.noteId, c['o2']!.deleted), ('n1', true));
    expect((c['s1']!.kind, c['s1']!.noteId), (EntityKind.stroke, 'n1'));
    final rows = await store.db.select(store.db.pageObjects).get();
    expect({for (final r in rows) r.noteId}, {'n1'});
  });

  test(
    'applyRemote: an orphan object then its page (two calls) → the page batch',
    () async {
      final n = await store.library.createNote(title: 'n');
      await pumpEventQueue();
      batches.clear();
      await store.sync.applyRemote([
        upsert(
          PageObjectFixtures.textBox(pageId: 'late', id: 'o1'),
          remoteAfter(store),
        ),
      ], policy: newerVersionWinsPolicy);
      await pumpEventQueue();
      expect(batches, isEmpty);
      // The object reads back while it waits (the sync window sees every row).
      final waiting = await store.sync.readVersioned([
        const EntityRef(EntityKind.pageObject, 'o1'),
      ]);
      expect(waiting.single!.entity, isA<TextBoxObject>());

      await store.sync.applyRemote([
        upsert(page('late', n.id), remoteAfter(store)),
      ], policy: newerVersionWinsPolicy);
      await pumpEventQueue();
      final c = byId(batches.single);
      expect((c['o1']!.noteId, c['o1']!.pageId), (n.id, 'late'));
      expect(c['late']!.noteId, n.id);
    },
  );

  test('an orphan and its page in one applyRemote call → one batch', () async {
    await store.sync.applyRemote([
      upsert(
        PageObjectFixtures.image(pageId: 'p1', assetId: 'b' * 64, id: 'o1'),
        remoteAfter(store),
      ),
      upsert(page('p1', 'n1'), remoteAfter(store, 2)),
    ], policy: newerVersionWinsPolicy);
    await pumpEventQueue();
    final c = byId(batches.single);
    expect(c.keys.toSet(), {'o1', 'p1'});
    expect((c['o1']!.noteId, c['o1']!.pageId), ('n1', 'p1'));
  });
}
