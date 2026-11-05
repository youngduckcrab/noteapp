// CORE T14 — SyncStore.duplicateNoteForRecovery (6.10.5, contract 7.2.10 v1.1): an active
// copy of a (possibly trashed) note with its active pages and strokes under new ids,
// title + suffix, outbox '*', ChangeBatch(origin: local); null when the row is gone.
@TestOn('vm')
library;

import 'dart:async';

import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import '../storage/storage_support.dart';

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

  /// A note in [folderId] with two pages: page 1 holds two strokes (one erased), page
  /// 2 is deleted.
  Future<Note> seed({FolderId? folderId, String title = 'source'}) async {
    final n = await store.library.createNote(
      title: title,
      folderId: folderId,
      pages: const [PageDraft.blankA4, PageDraft.blankA4],
    );
    final session = await store.openSession(n.id);
    final p1 = session.pages[0].id;
    final p2 = session.pages[1].id;
    await session.openPage(p1);
    final a = StrokeFixtures.synthetic(pageId: p1, ids: store.ids, seed: 1);
    final b = StrokeFixtures.synthetic(pageId: p1, ids: store.ids, seed: 2);
    await session.execute(AddStrokes(pageId: p1, strokes: [a, b])).persisted;
    await session
        .execute(RemoveStrokes(pageId: p1, strokeIds: [b.id]))
        .persisted;
    await session.execute(DeletePages(pageIds: [p2])).persisted;
    await session.close();
    return (await store.library.getNote(n.id))!;
  }

  Future<void> ackAll() async => store.sync.acknowledge([
    for (final e in await store.sync.pendingChanges(limit: 100000)) e.ack,
  ]);

  test(
    'a trashed note → an active copy at top level (its folder is trashed)',
    () async {
      final f = await store.library.createFolder(name: 'f');
      final src = await seed(folderId: f.id);
      await store.library.trashItems([FolderRef(f.id)]);
      await ackAll();
      await pumpEventQueue();
      batches.clear();

      final copyId = await store.sync.duplicateNoteForRecovery(
        src.id,
        titleSuffix: ' (복구)',
      );
      expect(copyId, isNotNull);
      expect(copyId, isNot(src.id));
      final copy = (await store.library.getNote(copyId!))!;
      expect(copy.isDeleted, isFalse);
      expect(copy.trashRootId, isNull);
      expect(copy.folderId, isNull);
      expect(copy.title, 'source (복구)');
      expect(copy.lastOpenedAt, isNull);
      expect(copy.pageCount, 1);

      final pages = await (store.db.select(
        store.db.pages,
      )..where((t) => t.noteId.equals(copyId))).get();
      expect(pages, hasLength(1), reason: 'active pages only');
      expect(pages.single.deletedAt, isNull);
      expect(pages.single.contentRev, 0);
      expect(copy.firstPageId, pages.single.id);
      final strokes = await (store.db.select(
        store.db.strokes,
      )..where((t) => t.noteId.equals(copyId))).get();
      expect(strokes, hasLength(1), reason: 'active strokes only');
      final srcStrokes = await (store.db.select(
        store.db.strokes,
      )..where((t) => t.noteId.equals(src.id))).get();
      expect(srcStrokes.map((s) => s.id), isNot(contains(strokes.single.id)));
      expect(strokes.single.pageId, pages.single.id);

      final entries = await store.sync.pendingChanges();
      expect(
        {for (final e in entries) e.entityId},
        {copyId, pages.single.id, strokes.single.id},
      );
      expect(entries.map((e) => e.changedFields), everyElement({kAllFields}));
      await pumpEventQueue();
      expect(batches.single.origin, ChangeOrigin.local);
      // The original stays in the trash.
      expect((await store.library.getNote(src.id))!.isDeleted, isTrue);
    },
  );

  test(
    'an active folder keeps the copy; the suffix is kept within 200 chars',
    () async {
      final f = await store.library.createFolder(name: 'f');
      final long = 'x' * 200;
      final src = await seed(folderId: f.id, title: long);
      final copyId = await store.sync.duplicateNoteForRecovery(
        src.id,
        titleSuffix: ' (copy)',
      );
      final copy = (await store.library.getNote(copyId!))!;
      expect(copy.folderId, f.id);
      expect(copy.title.length, 200);
      expect(copy.title, endsWith(' (copy)'));
      final listing = await store.library
          .watchListing(
            LibraryQuery(folderId: f.id, sort: LibrarySortField.custom),
          )
          .first;
      expect(
        listing.notes.map((n) => n.id).last,
        copyId,
        reason: 'sorted last',
      );
    },
  );

  test('no row → null; a too long suffix → ArgumentError', () async {
    expect(
      await store.sync.duplicateNoteForRecovery('gone', titleSuffix: ' (c)'),
      isNull,
    );
    final src = await seed();
    await expectLater(
      store.sync.duplicateNoteForRecovery(src.id, titleSuffix: 'y' * 200),
      throwsA(isA<ArgumentError>()),
    );
  });
}
