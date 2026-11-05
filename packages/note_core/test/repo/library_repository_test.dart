// CORE T8 — DriftLibraryRepository details beyond the shared contract (6.8, 4.5 head):
// outbox fields, atomicity, copy depth, equal-key recovery, owner filter, orphans at the
// top level, remote re-emission and the Future rule while a commit is retried.
@TestOn('vm')
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/src/storage/outbox_writer.dart';
import 'package:note_core/src/storage/row_mappers.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import '../storage/storage_support.dart';

const _remoteNode = 'ffffffffffffffff';
var _remoteMs = 1793750400000;
EntityFieldVersions _remoteVersion() =>
    EntityFieldVersions(Hlc(_remoteMs++, 0, _remoteNode));

Future<void> _putRemote(DriftNoteStore store, List<SyncEntity> entities) =>
    store.queue.run((tx) async {
      for (final e in entities) {
        await tx.putRemote(e, _remoteVersion());
      }
    }, origin: ChangeOrigin.remote);

void main() {
  late DriftNoteStore store;
  late LibraryRepository lib;
  setUp(() async {
    store = await openStore();
    lib = store.library;
  });
  tearDown(() => store.close());

  Future<List<OutboxEntry>> outbox() => readOutbox(store.db);
  Future<void> ack() => store.db.delete(store.db.outbox).go();
  Future<OutboxEntry> entryOf(String id) async =>
      (await outbox()).singleWhere((e) => e.entityId == id);

  group('outbox fields of each command', () {
    test('create = {*}; edits = the JSON keys that changed', () async {
      final f = await lib.createFolder(name: 'f');
      final n = await lib.createNote(title: 'n');
      expect((await entryOf(f.id)).changedFields, {kAllFields});
      expect((await entryOf(n.id)).changedFields, {kAllFields});
      final page = (await store.content.pagesOf(n.id)).single;
      final pageEntry = await entryOf(page.id);
      expect(pageEntry.changedFields, {kAllFields});
      expect(pageEntry.noteId, n.id);

      Future<Set<String>> fieldsAfter(
        Future<void> Function() edit,
        String id,
      ) async {
        await ack();
        await edit();
        return (await entryOf(id)).changedFields;
      }

      expect(await fieldsAfter(() => lib.renameFolder(f.id, 'g'), f.id), {
        'name',
      });
      expect(
        await fieldsAfter(
          () => lib.setFolderAppearance(f.id, colorArgb: 0xFF000000, icon: 'x'),
          f.id,
        ),
        {'color', 'icon'},
      );
      expect(await fieldsAfter(() => lib.renameNote(n.id, 'm'), n.id), {
        'title',
      });
      expect(await fieldsAfter(() => lib.setFavorite([n.id], true), n.id), {
        'isFavorite',
      });
      expect(await fieldsAfter(() => lib.setTags(n.id, ['a']), n.id), {'tags'});
      expect(
        await fieldsAfter(
          () => lib.setCover(n.id, const ColorCover(0xFF112233)),
          n.id,
        ),
        {'cover'},
      );
      await lib.createNote(title: 'already in f', folderId: f.id);
      expect(
        await fieldsAfter(
          () => lib.moveItems([NoteRef(n.id)], targetFolderId: f.id),
          n.id,
        ),
        {'folderId', 'sortKey'},
      );
      expect(await fieldsAfter(() => lib.trashItems([NoteRef(n.id)]), n.id), {
        'deletedAt',
        'trashRootId',
      });
    });

    test(
      'no-op edits and markOpened write no outbox entry and keep the version',
      () async {
        final n = await lib.createNote(title: 'n');
        final f = await lib.createFolder(name: 'f');
        await ack();
        await lib.renameNote(n.id, 'n');
        await lib.renameFolder(f.id, ' f ');
        await lib.setFavorite([n.id], false);
        await lib.moveItems([NoteRef(n.id)], targetFolderId: null);
        await lib.markOpened(n.id);
        expect(await outbox(), isEmpty);
        final after = (await lib.getNote(n.id))!;
        expect(after.version, n.version);
        expect(after.lastOpenedAt, isNotNull);
        expect(after.updatedAt, n.updatedAt);
      },
    );

    test('a stored entity keeps version == versions.max', () async {
      final n = await lib.createNote(title: 'n');
      await lib.renameNote(n.id, 'm');
      final v = (await readVersionedRow(
        store.db,
        EntityRef(EntityKind.note, n.id),
      ))!;
      expect(v.entity.version, v.versions.max);
      expect(v.versions.of('title'), v.versions.max);
      expect(v.versions.of('folderId'), n.version);
      expect((await lib.getNote(n.id))!.version, v.versions.max);
    });
  });

  group('atomicity (C-4) and argument errors', () {
    test('a cycle changes nothing: rows and outbox stay', () async {
      final a = await lib.createFolder(name: 'a');
      final b = await lib.createFolder(name: 'b', parentId: a.id);
      final n = await lib.createNote(title: 'n');
      await ack();
      await expectLater(
        lib.moveItems([NoteRef(n.id), FolderRef(a.id)], targetFolderId: b.id),
        throwsA(isA<FolderCycleException>()),
      );
      expect(await outbox(), isEmpty);
      expect((await lib.getNote(n.id))!.folderId, isNull);
      expect((await lib.getFolder(a.id))!.parentId, isNull);
    });

    test(
      'reorderItems with mixed parents: ArgumentError, nothing written',
      () async {
        final f = await lib.createFolder(name: 'f');
        final top = await lib.createNote(title: 'top');
        final inF = await lib.createNote(title: 'inF', folderId: f.id);
        await ack();
        final before = store.queue.debugTransactionCount;
        await expectLater(
          lib.reorderItems([NoteRef(top.id), NoteRef(inF.id)]),
          throwsArgumentError,
        );
        expect(await outbox(), isEmpty);
        // Mixed kinds are rejected before the queue.
        await expectLater(
          lib.reorderItems([NoteRef(top.id), FolderRef(f.id)]),
          throwsArgumentError,
        );
        expect(store.queue.debugTransactionCount, before + 1);
      },
    );

    test('createNote with a taken draft page id: nothing written', () async {
      final n = await lib.createNote(title: 'n');
      final pageId = n.firstPageId!;
      await ack();
      await expectLater(
        lib.createNote(
          title: 'dup',
          pages: [
            PageDraft(
              id: pageId,
              size: PageSize.a4Portrait,
              background: const BlankBackground(),
            ),
          ],
        ),
        throwsArgumentError,
      );
      await expectLater(
        lib.createNote(
          title: 'dup',
          pages: const [
            PageDraft(
              id: '0193f1d2-7c40-7000-8000-0000000000b1',
              size: PageSize.a4Portrait,
              background: BlankBackground(),
            ),
            PageDraft(
              id: '0193f1d2-7c40-7000-8000-0000000000b1',
              size: PageSize.a4Portrait,
              background: BlankBackground(),
            ),
          ],
        ),
        throwsArgumentError,
      );
      await expectLater(
        lib.createNote(
          title: 'bad',
          pages: const [
            PageDraft(
              id: 'not an id!',
              size: PageSize.a4Portrait,
              background: BlankBackground(),
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(await outbox(), isEmpty);
      expect(
        (await lib.watchListing(const LibraryQuery()).first).notes,
        hasLength(1),
      );
    });

    test(
      'createNote: many pages and strokes in ONE transaction and batch',
      () async {
        final batches = <ChangeBatch>[];
        final sub = store.changes.listen(batches.add);
        final before = store.queue.debugTransactionCount;
        final note = await lib.createNote(
          title: 'pdf',
          pages: [
            for (var i = 0; i < 40; i++)
              PageDraft(
                size: PageSize.a4Portrait,
                background: PdfBackground(assetId: 'a' * 64, pdfPageIndex: i),
                strokes: [
                  if (i == 0)
                    StrokeFixtures.synthetic(
                      pageId: 'x',
                      ids: store.ids,
                      pointCount: 5,
                    ),
                ],
              ),
          ],
        );
        await pumpEventQueue();
        await sub.cancel();
        expect(store.queue.debugTransactionCount, before + 1);
        expect(batches, hasLength(1));
        expect(batches.single.changes, hasLength(1 + 40 + 1));
        final pages = await store.content.pagesOf(note.id);
        expect(pages.map((p) => (p.background as PdfBackground).pdfPageIndex), [
          for (var i = 0; i < 40; i++) i,
        ]);
        expect(note.pageCount, 40);
        final strokeEntry = (await outbox()).singleWhere(
          (e) => e.kind == EntityKind.stroke,
        );
        expect(strokeEntry.noteId, note.id);
        expect(strokeEntry.pageId, pages.first.id);
      },
    );
  });

  group('copy', () {
    test(
      'active pages and strokes only, new ids, assets shared, outbox {*}',
      () async {
        final note = await lib.createNote(
          title: 'n',
          pages: [
            PageDraft(
              size: PageSize.a4Portrait,
              background: PdfBackground(assetId: 'b' * 64, pdfPageIndex: 3),
              strokes: [
                StrokeFixtures.synthetic(pageId: 'x', ids: store.ids, seed: 1),
                StrokeFixtures.synthetic(pageId: 'x', ids: store.ids, seed: 2),
              ],
            ),
            PageDraft.blankA4,
          ],
        );
        final pages = await store.content.pagesOf(note.id);
        final content = await store.content.loadPage(pages.first.id);
        // A trashed page and a deleted stroke (as a session would write them).
        await store.queue.run((tx) async {
          await tx.putLocal(pages.last.copyWith(deletedAt: 5), const {
            'deletedAt',
          });
          await tx.putLocal(
            content.strokes.first.copyWith(deletedAt: 5),
            const {'deletedAt'},
          );
          await tx.putLocal(
            content.strokes.last.copyWith(
              recordingId: 'rec-1',
              recordingOffsetMs: 7,
            ),
            const {'recordingId', 'recordingOffsetMs'},
          );
        });
        await ack();
        final batches = <ChangeBatch>[];
        final sub = store.changes.listen(batches.add);
        final copy = (await lib.copyItems([
          NoteRef(note.id),
        ], targetFolderId: null)).single;
        await pumpEventQueue();
        await sub.cancel();
        final copied = (await lib.getNote(copy.id))!;
        expect(copied.pageCount, 1);
        final copyPages = await store.content.pagesOf(copy.id);
        expect(copyPages, hasLength(1));
        expect(copied.firstPageId, copyPages.single.id);
        expect(
          copyPages.single.background,
          PdfBackground(assetId: 'b' * 64, pdfPageIndex: 3),
        );
        final copyContent = await store.content.loadPage(copyPages.single.id);
        expect(copyContent.strokes, hasLength(1));
        expect(copyContent.strokes.single.recordingId, 'rec-1');
        expect(copyContent.strokes.single.recordingOffsetMs, 7);
        expect(copyContent.strokes.single.id, isNot(content.strokes.last.id));
        final entries = await outbox();
        expect(entries, hasLength(3)); // note, page, stroke
        expect(
          entries.every((e) => e.changedFields.contains(kAllFields)),
          isTrue,
        );
        expect(entries.map((e) => e.entityId).toSet(), {
          copy.id,
          copyPages.single.id,
          copyContent.strokes.single.id,
        });
        expect(batches, hasLength(1));
        expect(batches.single.origin, ChangeOrigin.local);
      },
    );

    test('copies more strokes than one read chunk (2,000)', () async {
      const pageId = '0193f1d2-7c40-7000-8000-0000000000c1';
      final strokes = [
        for (var i = 0; i < 2100; i++)
          StrokeFixtures.synthetic(
            pageId: pageId,
            ids: store.ids,
            seed: i,
            pointCount: 2,
            createdAt: i,
          ),
      ];
      final note = await lib.createNote(
        title: 'big',
        pages: [
          PageDraft(
            id: pageId,
            size: PageSize.a4Portrait,
            background: const BlankBackground(),
            strokes: strokes,
          ),
        ],
      );
      final copy = (await lib.copyItems([
        NoteRef(note.id),
      ], targetFolderId: null)).single;
      final page = (await store.content.pagesOf(copy.id)).single;
      final content = await store.content.loadPage(page.id);
      expect(content.strokeCount, 2100);
      expect(content.strokes.first.createdAt, 0);
      expect(content.strokes.last.createdAt, 2099);
    });

    test(
      'copy of a folder into its own descendant does not recurse into the copy',
      () async {
        final f = await lib.createFolder(name: 'f');
        final sub = await lib.createFolder(name: 'sub', parentId: f.id);
        await lib.createNote(title: 'n', folderId: sub.id);
        final copy = (await lib.copyItems([
          FolderRef(f.id),
        ], targetFolderId: sub.id)).single;
        final tree = await lib.watchFolderTree().first;
        expect(tree.length, 4);
        expect(tree.byId(copy.id)!.parentId, sub.id);
        expect(tree.childrenOf(copy.id).single.name, 'sub');
      },
    );
  });

  group('sortKey recovery (6.6)', () {
    test(
      'reorder between two notes sharing a sortKey re-keys the run',
      () async {
        final a = note('0193f1d2-7c40-7000-8000-0000000000d1', title: 'a');
        final b = note('0193f1d2-7c40-7000-8000-0000000000d2', title: 'b');
        await _putRemote(store, [a, b]); // both sortKey a0 (a sync merge)
        final c = await lib.createNote(title: 'c');
        await lib.reorderItem(NoteRef(c.id), after: NoteRef(a.id));
        final custom = await lib
            .watchListing(const LibraryQuery(sort: LibrarySortField.custom))
            .first;
        expect(custom.notes.map((n) => n.title), ['a', 'c', 'b']);
        final keys = custom.notes.map((n) => n.sortKey).toList();
        expect(keys.toSet(), hasLength(3));
        expect([...keys]..sort(), keys);
      },
    );
  });

  group('queries', () {
    test('top level also lists orphans (parent missing or trashed)', () async {
      final gone = folder('0193f1d2-7c40-7000-8000-0000000000e1');
      final orphanFolder = folder(
        '0193f1d2-7c40-7000-8000-0000000000e2',
        name: 'orphan',
        parentId: '0193f1d2-7c40-7000-8000-00000000dead',
      );
      final trashedParent = gone.copyWith(deletedAt: 9, trashRootId: gone.id);
      final orphanNote = note(
        '0193f1d2-7c40-7000-8000-0000000000e3',
        title: 'orphan note',
      ).copyWith(folderId: gone.id);
      await _putRemote(store, [trashedParent, orphanFolder, orphanNote]);
      final top = await lib.watchListing(const LibraryQuery()).first;
      expect(top.folders.map((f) => f.id), [orphanFolder.id]);
      expect(top.notes.map((n) => n.id), [orphanNote.id]);
      final tree = await lib.watchFolderTree().first;
      expect(tree.roots.map((f) => f.id), [orphanFolder.id]);
    });

    test('rows of another owner are invisible', () async {
      final theirs = note(
        '0193f1d2-7c40-7000-8000-0000000000f1',
        title: 'theirs',
      ).copyWith(ownerId: 'user-2');
      final theirFolder = folder(
        '0193f1d2-7c40-7000-8000-0000000000f2',
        name: 'theirs',
      ).copyWith(ownerId: 'user-2');
      await _putRemote(store, [theirs, theirFolder]);
      await lib.createNote(title: 'mine');
      final top = await lib.watchListing(const LibraryQuery()).first;
      expect(top.notes.map((n) => n.title), ['mine']);
      expect(top.folders, isEmpty);
      expect(await lib.getNote(theirs.id), isNull);
      expect(await lib.getFolder(theirFolder.id), isNull);
      expect((await lib.searchLibrary('theirs')).notes, isEmpty);
      expect((await lib.searchLibrary('theirs')).folders, isEmpty);
      expect((await lib.watchFolderTree().first).length, 0);
      await expectLater(
        lib.renameNote(theirs.id, 'x'),
        throwsA(isA<EntityNotFoundException>()),
      );
      await expectLater(
        lib.createNote(title: 'x', folderId: theirFolder.id),
        throwsA(isA<EntityNotFoundException>()),
      );
    });

    test('search: NFD folder name, normalized column, escapes', () async {
      final nfd = String.fromCharCodes([0x1100, 0x1161, 0x11BC]); // 강 (NFD)
      final f = await lib.createFolder(name: '$nfd의실');
      final row = await (store.db.select(
        store.db.folders,
      )..where((t) => t.id.equals(f.id))).getSingle();
      expect(row.nameNorm, '강의실');
      expect(row.name, '$nfd의실', reason: 'the name itself is kept');
      expect((await lib.searchLibrary('강의')).folders.map((x) => x.id), [f.id]);
      expect((await lib.searchLibrary('%의%')).folders, isEmpty);
    });
  });

  group('watch streams', () {
    test(
      'a remote commit re-emits the listing (C-1 local or remote)',
      () async {
        final n = await lib.createNote(title: 'n');
        final values = <LibraryListing>[];
        final sub = lib.watchListing(const LibraryQuery()).listen(values.add);
        await pumpEventQueue();
        final stored = (await lib.getNote(n.id))!;
        await _putRemote(store, [stored.copyWith(title: 'from remote')]);
        await pumpEventQueue();
        expect(values, hasLength(2));
        expect(values.last.notes.single.title, 'from remote');
        await sub.cancel();
      },
    );

    test(
      'the Future completes after the stream re-emitted (same commit)',
      () async {
        final values = <LibraryListing>[];
        final sub = lib.watchListing(const LibraryQuery()).listen(values.add);
        await pumpEventQueue();
        await lib.createNote(title: 'n');
        await Future<void>.value();
        expect(values, hasLength(2));
        await sub.cancel();
      },
    );

    test('closing the store closes the watch streams', () async {
      final other = await openStore();
      var done = false;
      other.library
          .watchListing(const LibraryQuery())
          .listen((_) {}, onDone: () => done = true);
      await pumpEventQueue();
      await other.close();
      await pumpEventQueue();
      expect(done, isTrue);
    });
  });

  test(
    'while the commit is retried the Future and the stream wait (4.5 head)',
    () {
      fakeAsync((async) {
        late DriftNoteStore s;
        openStore().then((x) => s = x);
        async.flushMicrotasks();
        final values = <LibraryListing>[];
        final sub = s.library
            .watchListing(const LibraryQuery())
            .listen(values.add);
        async.flushMicrotasks();
        expect(values, hasLength(1));
        s.queue.failNextCommits(2);
        Folder? created;
        unawaited(s.library.createFolder(name: 'f').then((f) => created = f));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 499));
        expect(created, isNull);
        expect(values, hasLength(1));
        expect(s.persistenceStatus.consecutiveFailures, 2);
        async.elapse(const Duration(milliseconds: 1));
        expect(created, isNotNull);
        expect(values, hasLength(2));
        expect(values.last.folders.single.id, created!.id);
        unawaited(sub.cancel());
        unawaited(s.close());
        async.flushMicrotasks();
      });
    },
  );
}
