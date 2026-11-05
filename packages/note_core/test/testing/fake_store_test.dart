// createFakeNoteStore() behaviour (contract 7.6 'B2 테스트·개발 도우미', CORE 6.19, 8.1 T5).
import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

const _start = 1793750400000;

void main() {
  group('library (C-1 .. C-10)', () {
    late NoteStore store;
    late LibraryRepository lib;
    var ms = _start;

    setUp(() {
      ms = _start;
      store = createFakeNoteStore(
        clock: Clock(
          () => DateTime.fromMillisecondsSinceEpoch(ms++, isUtc: true),
        ),
      );
      lib = store.library;
    });

    tearDown(() => store.close());

    test(
      'C-1: watch streams emit on listen and after affecting commits',
      () async {
        final values = <LibraryListing>[];
        final sub = lib.watchListing(const LibraryQuery()).listen(values.add);
        await pumpEventQueue();
        expect(values, hasLength(1));
        expect(values.single.notes, isEmpty);
        await lib.createNote(title: 'a');
        await pumpEventQueue();
        expect(values, hasLength(2));
        expect(values.last.notes.single.title, 'a');
        await store.settings.set(SettingKey.integer('editor.x', 0), 1);
        await pumpEventQueue();
        expect(
          values,
          hasLength(2),
          reason: 'unrelated commit does not re-emit',
        );
        await sub.cancel();
      },
    );

    test(
      'C-2: folders first, ordered as asked; unknown folder → empty listing',
      () async {
        final f1 = await lib.createFolder(name: 'Beta');
        final f2 = await lib.createFolder(name: 'alpha');
        final n1 = await lib.createNote(title: 'Zeta');
        final n2 = await lib.createNote(title: 'eta');
        Future<LibraryListing> list(LibraryQuery q) =>
            lib.watchListing(q).first;
        final byName = await list(
          const LibraryQuery(sort: LibrarySortField.name, descending: false),
        );
        expect(byName.folders.map((f) => f.id), [f2.id, f1.id]);
        expect(byName.notes.map((n) => n.id), [n2.id, n1.id]);
        final byNameDesc = await list(
          const LibraryQuery(sort: LibrarySortField.name),
        );
        expect(byNameDesc.notes.map((n) => n.id), [n1.id, n2.id]);
        final created = await list(
          const LibraryQuery(
            sort: LibrarySortField.createdAt,
            descending: false,
          ),
        );
        expect(created.notes.map((n) => n.id), [n1.id, n2.id]);
        final updated = await list(const LibraryQuery());
        expect(updated.notes.map((n) => n.id), [n2.id, n1.id]);
        final custom = await list(
          const LibraryQuery(sort: LibrarySortField.custom),
        );
        expect(custom.folders.map((f) => f.id), [f1.id, f2.id]);
        final unknown = await list(const LibraryQuery(folderId: 'nope'));
        expect(unknown.folders, isEmpty);
        expect(unknown.notes, isEmpty);
      },
    );

    test('C-3 / C-8: get returns trashed items; restore moves to the nearest active ancestor', () async {
      final parent = await lib.createFolder(name: 'parent');
      final child = await lib.createFolder(name: 'child', parentId: parent.id);
      final note = await lib.createNote(title: 'n', folderId: child.id);
      await lib.trashItems([NoteRef(note.id)]);
      expect((await lib.getNote(note.id))!.isDeleted, isTrue);
      await lib.trashItems([FolderRef(child.id)]);
      await store.trash.restore([NoteRef(note.id)]);
      final restored = (await lib.getNote(note.id))!;
      expect(restored.isDeleted, isFalse);
      expect(restored.folderId, parent.id);
      expect(await lib.getNote('purged-or-unknown'), isNull);
    });

    test('C-4: move ignores items already there; a cycle throws and changes nothing', () async {
      final a = await lib.createFolder(name: 'a');
      final b = await lib.createFolder(name: 'b', parentId: a.id);
      final n = await lib.createNote(title: 'n');
      await expectLater(
        lib.moveItems([FolderRef(a.id), NoteRef(n.id)], targetFolderId: b.id),
        throwsA(isA<FolderCycleException>()),
      );
      expect((await lib.getNote(n.id))!.folderId, isNull, reason: 'atomic');
      await lib.moveItems([
        NoteRef(n.id),
        FolderRef(b.id),
      ], targetFolderId: a.id);
      expect((await lib.getNote(n.id))!.folderId, a.id);
      expect((await lib.getFolder(b.id))!.parentId, a.id);
      await expectLater(
        lib.moveItems([NoteRef(n.id)], targetFolderId: 'missing'),
        throwsA(isA<EntityNotFoundException>()),
      );
    });

    test('C-5: copy cuts the original name, never a surrogate pair', () async {
      final emoji = '😀' * 99 + 'ab'; // 200 code units
      final n = await lib.createNote(title: emoji);
      final copies = await lib.copyItems(
        [NoteRef(n.id)],
        targetFolderId: null,
        nameSuffix: ' 사본',
      );
      final copy = (await lib.getNote(copies.single.id))!;
      expect(copy.title.length, lessThanOrEqualTo(200));
      expect(copy.title.endsWith(' 사본'), isTrue);
      final body = copy.title.substring(0, copy.title.length - 3);
      expect(body.codeUnits.last, isNot(inInclusiveRange(0xD800, 0xDBFF)));
      expect(copy.id, isNot(n.id));
    });

    test(
      'copy is deep: folders, notes, pages, strokes under new ids',
      () async {
        final f = await lib.createFolder(name: 'f');
        final sub = await lib.createFolder(name: 'sub', parentId: f.id);
        final note = await lib.createNote(title: 'n', folderId: sub.id);
        final session = await store.openSession(note.id);
        final pageId = session.pages.single.id;
        await session.openPage(pageId);
        session.execute(
          AddStrokes(
            pageId: pageId,
            strokes: [StrokeFixtures.synthetic(pageId: pageId, ids: store.ids)],
          ),
        );
        await session.close();
        final copies = await lib.copyItems(
          [FolderRef(f.id)],
          targetFolderId: null,
          nameSuffix: ' 사본',
        );
        final tree = await lib.watchFolderTree().first;
        final copyRoot = tree.byId(copies.single.id)!;
        expect(copyRoot.name, 'f 사본');
        final copySub = tree.childrenOf(copyRoot.id).single;
        expect(copySub.name, 'sub');
        final listing = await lib
            .watchListing(LibraryQuery(folderId: copySub.id))
            .first;
        final copiedNote = listing.notes.single;
        expect(copiedNote.id, isNot(note.id));
        final pages = await store.content.pagesOf(copiedNote.id);
        final content = await store.content.loadPage(pages.single.id);
        expect(content.strokes, hasLength(1));
        expect(pages.single.id, isNot(pageId));
      },
    );

    test('C-6: names are trimmed, 1..200 chars, else ArgumentError before any write', () async {
      expect((await lib.createFolder(name: '  hi  ')).name, 'hi');
      await expectLater(lib.createFolder(name: '   '), throwsArgumentError);
      await expectLater(lib.createNote(title: 'x' * 201), throwsArgumentError);
      await expectLater(
        lib.createNote(title: 'ok', pages: const []),
        throwsArgumentError,
      );
      expect(store.persistenceStatus.pendingOps, 0);
    });

    test(
      'C-7: recent / favorites / search exclude trashed; empty query → empty',
      () async {
        final a = await lib.createNote(title: '강의 노트');
        final b = await lib.createNote(title: 'Lecture');
        await lib.setFavorite([a.id, b.id], true);
        final s = await store.openSession(a.id);
        await s.close();
        await store.flush();
        expect((await lib.watchRecentNotes().first).map((n) => n.id), [a.id]);
        expect(await lib.watchFavoriteNotes().first, hasLength(2));
        final nfd = String.fromCharCodes([0x1100, 0x1161, 0x11BC]); // 강 (NFD)
        expect((await lib.searchLibrary(nfd)).notes.map((n) => n.id), [a.id]);
        expect((await lib.searchLibrary('LECT')).notes.map((n) => n.id), [
          b.id,
        ]);
        expect((await lib.searchLibrary('  ')).notes, isEmpty);
        await lib.trashItems([NoteRef(a.id)]);
        expect(await lib.watchRecentNotes().first, isEmpty);
        expect((await lib.watchFavoriteNotes().first).map((n) => n.id), [b.id]);
        expect((await lib.searchLibrary('강의')).notes, isEmpty);
      },
    );

    test(
      'C-9: firstPageId; a content change bumps contentRevision and updatedAt',
      () async {
        final note = await lib.createNote(
          title: 'n',
          pages: const [PageDraft.blankA4, PageDraft.blankA4],
        );
        final pages = await store.content.pagesOf(note.id);
        expect(note.pageCount, 2);
        expect(note.firstPageId, pages.first.id);
        final session = await store.openSession(note.id);
        await session.openPage(pages.first.id);
        session.execute(
          AddStrokes(
            pageId: pages.first.id,
            strokes: [
              StrokeFixtures.synthetic(pageId: pages.first.id, ids: store.ids),
            ],
          ),
        );
        await session.close();
        final after = (await lib.getNote(note.id))!;
        expect(after.updatedAt, greaterThan(note.updatedAt));
        expect(
          (await store.content.getPage(pages.first.id))!.contentRevision,
          1,
        );
        expect(
          (await store.content.getPage(pages.last.id))!.contentRevision,
          0,
        );
      },
    );

    test('C-10 / reorderItems: one commit, relative order kept, mixed kinds rejected', () async {
      final n = [
        for (var i = 0; i < 4; i++) await lib.createNote(title: 'n$i'),
      ];
      await lib.reorderItem(NoteRef(n[3].id), before: NoteRef(n[0].id));
      await lib.reorderItems([
        NoteRef(n[2].id),
        NoteRef(n[1].id),
      ], after: NoteRef(n[0].id));
      final custom = await lib
          .watchListing(const LibraryQuery(sort: LibrarySortField.custom))
          .first;
      expect(custom.notes.map((x) => x.title), ['n3', 'n0', 'n1', 'n2']);
      final f = await lib.createFolder(name: 'f');
      await expectLater(
        lib.reorderItems([NoteRef(n[0].id), FolderRef(f.id)]),
        throwsArgumentError,
      );
      final inF = await lib.createNote(title: 'x', folderId: f.id);
      await expectLater(
        lib.reorderItems([NoteRef(n[0].id), NoteRef(inF.id)]),
        throwsArgumentError,
      );
    });

    test(
      'trash groups: folder takes its active subtree; purge removes the group',
      () async {
        final f = await lib.createFolder(name: 'f');
        final sub = await lib.createFolder(name: 'sub', parentId: f.id);
        final inSub = await lib.createNote(title: 'inSub', folderId: sub.id);
        final early = await lib.createNote(title: 'early', folderId: f.id);
        await lib.trashItems([NoteRef(early.id)]);
        await lib.trashItems([FolderRef(f.id)]);
        final trash = await store.trash.watchTrash().first;
        expect(trash.map((t) => t.ref), [FolderRef(f.id), NoteRef(early.id)]);
        final folderItem = trash.first as TrashedFolder;
        expect(folderItem.folderCount, 1);
        expect(folderItem.noteCount, 1);
        expect(
          folderItem.expiresAt,
          folderItem.deletedAt + const Duration(days: 30).inMilliseconds,
        );
        expect(
          (await lib.getNote(early.id))!.trashRootId,
          early.id,
          reason: 'keeps its own group',
        );
        await store.trash.restore([FolderRef(f.id)]);
        expect((await lib.getNote(inSub.id))!.isDeleted, isFalse);
        expect((await lib.getNote(early.id))!.isDeleted, isTrue);
        await store.trash.purge([NoteRef(early.id)]);
        expect(await lib.getNote(early.id), isNull);
        expect(await store.trash.watchTrash().first, isEmpty);
      },
    );

    test('purgeExpired: 30 days', () async {
      final n = await lib.createNote(title: 'old');
      await lib.trashItems([NoteRef(n.id)]);
      expect(await store.trash.purgeExpired(), 0);
      ms += const Duration(days: 30).inMilliseconds;
      expect(await store.trash.purgeExpired(), 1);
      expect(await lib.getNote(n.id), isNull);
    });

    test('owner filter', () async {
      final other = createFakeNoteStore(ownerId: 'user-1');
      final n = await other.library.createNote(title: 'mine');
      expect(n.ownerId, 'user-1');
      expect(other.ownerId, 'user-1');
      expect(other.sync.ownerId, 'user-1');
      await other.close();
    });
  });

  group('presets', () {
    test(
      '5 deterministic defaults, re-seeding never re-creates deleted ones',
      () async {
        final store = createFakeNoteStore();
        final presets = await store.penPresets.getPresets();
        expect(presets.map((p) => p.id), [
          'preset-default-ballpoint',
          'preset-default-fountain',
          'preset-default-highlighter',
          'preset-default-pencil',
          'preset-default-marker',
        ]);
        expect(presets.map((p) => p.name), ['볼펜', '만년필', '형광펜', '연필', '마커']);
        expect(presets.map((p) => p.sortKey), ['a0', 'a1', 'a2', 'a3', 'a4']);
        expect(presets.every((p) => p.pinned && p.group == null), isTrue);
        expect(
          presets.every(
            (p) => p.version == const Hlc(1, 0, '0000000000000000'),
          ),
          isTrue,
        );
        expect(presets[2].style, StrokeStyle.defaultsFor(PenTool.highlighter));
        await store.penPresets.deletePreset('preset-default-pencil');
        await store.penPresets.ensureDefaults();
        expect(
          (await store.penPresets.getPresets()).map((p) => p.id),
          isNot(contains('preset-default-pencil')),
        );
        expect(
          await createFakeNoteStore(seedDefaultPenPresets: false).penPresets
              .getPresets(),
          isEmpty,
        );
        await store.close();
      },
    );

    test('create / update / reorderPresets', () async {
      final store = createFakeNoteStore();
      final p = await store.penPresets.createPreset(
        name: ' 수업용 ',
        style: StrokeStyle.defaultsFor(PenTool.marker),
        after: 'preset-default-ballpoint',
      );
      expect(p.name, '수업용');
      expect((await store.penPresets.getPresets())[1].id, p.id);
      await expectLater(
        store.penPresets.createPreset(
          name: 'x' * 61,
          style: StrokeStyle.defaultsFor(PenTool.marker),
        ),
        throwsArgumentError,
      );
      await store.penPresets.updatePreset(
        p.copyWith(name: '시험용', pinned: false),
      );
      expect((await store.penPresets.getPresets())[1].name, '시험용');
      await store.penPresets.reorderPresets([
        'preset-default-marker',
        'nope',
        p.id,
      ]);
      final order = (await store.penPresets.getPresets())
          .map((x) => x.id)
          .toList();
      expect(order.take(2), ['preset-default-marker', p.id]);
      expect(order.skip(2), [
        'preset-default-ballpoint',
        'preset-default-fountain',
        'preset-default-highlighter',
        'preset-default-pencil',
      ]);
      await store.close();
    });
  });

  group('settings', () {
    test('typed get / set / reset / watch / watchAll', () async {
      final store = createFakeNoteStore();
      final key = SettingKey.intList('editor.recentColors', const []);
      final device = SettingKey.boolean(
        'editor.penOnlyMode',
        false,
        scope: SettingScope.device,
      );
      expect(await store.settings.get(key), isEmpty);
      final seen = <List<int>>[];
      final sub = store.settings.watch(key).listen(seen.add);
      await store.settings.set(key, [1, 2]);
      await store.settings.set(key, [1, 2]);
      await store.settings.set(device, true);
      expect(await store.settings.get(key), [1, 2]);
      expect(await store.settings.get(device), isTrue);
      final snap = await store.settings.watchAll().first;
      expect(snap.get(key), [1, 2]);
      expect(snap.get(device), isTrue);
      await store.settings.reset(key);
      expect(await store.settings.get(key), isEmpty);
      await pumpEventQueue();
      expect(seen, [
        <int>[],
        [1, 2],
        <int>[],
      ]);
      await expectLater(
        store.settings.set(SettingKey.string('sync.cursor', ''), 'x'),
        throwsArgumentError,
      );
      await sub.cancel();
      await store.close();
    });
  });

  group('assets and thumbnails', () {
    test('put dedupes by SHA-256 and announces new bytes once', () async {
      final store = createFakeNoteStore();
      final arrived = <AssetId>[];
      final sub = store.assets.bytesArrived.listen(arrived.add);
      final bytes = Uint8List.fromList([1, 2, 3]);
      final a = await store.assets.put(
        bytes,
        type: AssetType.pdf,
        mimeType: 'application/pdf',
        fileName: 'x.pdf',
      );
      expect(
        a.id,
        '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
      );
      final again = await store.assets.put(
        Uint8List.fromList([1, 2, 3]),
        type: AssetType.pdf,
        mimeType: 'application/pdf',
      );
      expect(again, a);
      await pumpEventQueue();
      expect(arrived, [a.id]);
      expect(await store.assets.readBytes(a.id), bytes);
      expect(await store.assets.hasBytes(a.id), isTrue);
      expect(await store.assets.readBytes('missing'), isNull);
      expect(await store.assets.listAssets(uploaded: false), [a]);
      await store.assets.markUploaded(a.id, 'users/local/${a.id}');
      expect(
        (await store.assets.listAssets(uploaded: true)).single.storagePath,
        isNotNull,
      );
      await expectLater(
        store.assets.putDownloadedBytes(a.id, Uint8List.fromList([9])),
        throwsA(isA<AssetHashMismatchException>()),
      );
      final usage = await store.assets.usage();
      expect(usage.assetCount, 1);
      expect(usage.totalBytes, 3);
      await sub.cancel();
      await store.close();
    });

    test(
      'thumbnail cache: read / write / delete / updates; isStaleFor',
      () async {
        final store = createFakeNoteStore();
        final note = await store.library.createNote(title: 'n');
        final page = (await store.content.pagesOf(note.id)).single;
        final updates = <PageId>[];
        final sub = store.thumbnails.updates.listen(updates.add);
        final thumb = PageThumbnail(
          pageId: page.id,
          contentRevision: page.contentRevision,
          width: 10,
          height: 14,
          mimeType: 'image/png',
          bytes: Uint8List(4),
        );
        await store.thumbnails.write(thumb);
        expect(
          (await store.thumbnails.read(page.id))!.isStaleFor(page),
          isFalse,
        );
        expect(thumb.isStaleFor(page.copyWith(contentRevision: 1)), isTrue);
        await store.thumbnails.delete(page.id);
        expect(await store.thumbnails.read(page.id), isNull);
        await pumpEventQueue();
        expect(updates, [page.id, page.id]);
        await sub.cancel();
        await store.close();
      },
    );
  });

  group('failure injection (FakeNoteStoreFaults)', () {
    test('failed commits are retried; Futures complete after the successful commit', () {
      fakeAsync((async) {
        final faults = FakeNoteStoreFaults()..failNextCommits(3);
        final store = createFakeNoteStore(
          clock: async.getClock(DateTime.utc(2026, 11, 5)),
          faults: faults,
        );
        final statuses = <PersistenceStatus>[];
        store.persistenceStatusStream.listen(statuses.add);
        Note? created;
        store.library.createNote(title: 'n').then((n) => created = n);
        async.flushMicrotasks();
        expect(created, isNull);
        expect(store.persistenceStatus.consecutiveFailures, 1);
        async.elapse(const Duration(milliseconds: 100));
        expect(store.persistenceStatus.consecutiveFailures, 2);
        async.elapse(const Duration(milliseconds: 400));
        expect(store.persistenceStatus.consecutiveFailures, 3);
        expect(
          storageWarningOf(store.storageInfo, store.persistenceStatus),
          StorageWarning.writeFailing,
        );
        expect(created, isNull);
        async.elapse(const Duration(milliseconds: 1599));
        expect(created, isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(created, isNotNull);
        expect(store.persistenceStatus.consecutiveFailures, 0);
        expect(store.persistenceStatus.lastError, isA<FormatException>());
        expect(
          statuses.map((s) => s.consecutiveFailures),
          containsAllInOrder([0, 1, 2, 3, 0]),
        );
        // flush() waits for queued writes the same way.
        faults.failNextCommits(1);
        var flushed = false;
        store.library.createFolder(name: 'f');
        store.flush().then((_) => flushed = true);
        async.flushMicrotasks();
        expect(flushed, isFalse);
        async.elapse(const Duration(milliseconds: 100));
        expect(flushed, isTrue);
      });
    });

    test('put during failNextCommits(3): pending, no bytesArrived; then once (CORE-3-2)', () {
      fakeAsync((async) {
        final faults = FakeNoteStoreFaults()..failNextCommits(3);
        final store = createFakeNoteStore(faults: faults);
        final arrived = <AssetId>[];
        store.assets.bytesArrived.listen(arrived.add);
        Asset? asset;
        store.assets
            .put(
              Uint8List.fromList([7, 7]),
              type: AssetType.pdf,
              mimeType: 'application/pdf',
            )
            .then((a) => asset = a);
        async.elapse(const Duration(milliseconds: 2099));
        expect(asset, isNull);
        expect(arrived, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(asset, isNotNull);
        expect(arrived, [asset!.id]);
        // Same bytes again: no commit, no second bytesArrived.
        store.assets.put(
          Uint8List.fromList([7, 7]),
          type: AssetType.pdf,
          mimeType: 'application/pdf',
        );
        async.flushMicrotasks();
        expect(arrived, hasLength(1));
      });
    });

    test('commitDelay delays every commit', () {
      fakeAsync((async) {
        final faults = FakeNoteStoreFaults()
          ..commitDelay = const Duration(seconds: 1);
        final store = createFakeNoteStore(faults: faults);
        var done = false;
        store.library.createFolder(name: 'f').then((_) => done = true);
        async.elapse(const Duration(milliseconds: 999));
        expect(done, isFalse);
        expect(store.persistenceStatus.pendingOps, 1);
        async.elapse(const Duration(milliseconds: 1));
        expect(done, isTrue);
        expect(store.persistenceStatus.pendingOps, 0);
      });
    });

    test('domain errors are not retried', () {
      fakeAsync((async) {
        final store = createFakeNoteStore();
        Object? error;
        store.library
            .renameNote('missing', 'x')
            .catchError((Object e) => error = e);
        async.flushMicrotasks();
        expect(error, isA<EntityNotFoundException>());
        expect(store.persistenceStatus.consecutiveFailures, 0);
      });
    });
  });

  group('status, storage info, sync store, backup', () {
    test(
      'persistenceStatusStream emits the current value right after listen',
      () async {
        final store = createFakeNoteStore();
        final first = await store.persistenceStatusStream.first;
        expect(first.pendingOps, 0);
        expect(first.isWriting, isFalse);
        await store.close();
      },
    );

    test('storageInfo: nativeFile by default (no banner), webInMemory → notDurable', () async {
      final store = createFakeNoteStore();
      expect(store.storageInfo.backend, StorageBackend.nativeFile);
      expect(
        storageWarningOf(store.storageInfo, store.persistenceStatus),
        isNull,
      );
      expect(await store.refreshStorageInfo(), store.storageInfo);
      final web = createFakeNoteStore(
        storageInfo: const StorageInfo(backend: StorageBackend.webInMemory),
      );
      expect(
        storageWarningOf(web.storageInfo, web.persistenceStatus),
        StorageWarning.notDurable,
      );
      await store.close();
      await web.close();
    });

    test('SyncStore: values for ownerId / deviceNodeId / pending, UnsupportedError for the rest', () async {
      final store = createFakeNoteStore();
      final sync = store.sync;
      expect(sync.ownerId, kLocalOwnerId);
      expect(sync.deviceNodeId, '0000000000000001');
      expect(await sync.pendingChanges(), isEmpty);
      expect(await sync.watchPendingCount().first, 0);
      final members = <String, Object? Function()>{
        'acknowledge': () => sync.acknowledge(const []),
        'readVersioned': () => sync.readVersioned(const []),
        'applyRemote': () =>
            sync.applyRemote(const [], policy: newerVersionWinsPolicy),
        'commitRepairs': () => sync.commitRepairs(const []),
        'readMeta': () => sync.readMeta('sync.x'),
        'writeMeta': () => sync.writeMeta(const {}),
        'reassignOwner': () => sync.reassignOwner(from: 'local', to: 'u'),
        'duplicateNoteForRecovery': () =>
            sync.duplicateNoteForRecovery('n', titleSuffix: ' (복구)'),
      };
      expect(members, hasLength(8));
      for (final e in members.entries) {
        expect(e.value, throwsUnsupportedError, reason: e.key);
      }
      await store.close();
    });

    test('exportBackupJson writes the backup format (CORE T19)', () async {
      final store = createFakeNoteStore();
      final bytes = await store.exportBackupJson();
      expect(
        String.fromCharCodes(bytes.take(26)),
        '{"format":"noteapp-backup"',
      );
      await store.close();
    });

    test('ids and clock are the injected ones', () async {
      final ids = SequentialIdGenerator(prefix: 't');
      final clock = Clock.fixed(DateTime.utc(2030));
      final store = createFakeNoteStore(ids: ids, clock: clock);
      expect(identical(store.ids, ids), isTrue);
      expect(identical(store.clock, clock), isTrue);
      final n = await store.library.createNote(title: 'n');
      expect(n.id, startsWith('t-'));
      expect(n.createdAt, DateTime.utc(2030).millisecondsSinceEpoch);
      final defaultStore = createFakeNoteStore();
      expect(defaultStore.ids, isA<SequentialIdGenerator>());
      await store.close();
      await defaultStore.close();
    });

    test('changes: one ChangeBatch per commit with hints', () async {
      final store = createFakeNoteStore();
      final batches = <ChangeBatch>[];
      final sub = store.changes.listen(batches.add);
      final note = await store.library.createNote(title: 'n');
      await pumpEventQueue();
      final batch = batches.single;
      expect(batch.origin, ChangeOrigin.local);
      final page = batch.changes.firstWhere((c) => c.kind == EntityKind.page);
      expect(page.noteId, note.id);
      await sub.cancel();
      await store.close();
      unawaited(Future<void>.value());
    });
  });
}
