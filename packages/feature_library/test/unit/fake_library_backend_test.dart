// LIBRARY's test layer over CORE's fake store (05-library 5.7, 8 L0). Only the
// LIBRARY layer is checked here (injection, call log, seeding, overrides);
// CORE semantics are CORE T5's tests.
import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';

import '../support/fake_library_backend.dart';
import '../support/fake_thumbnail_renderer.dart';
import '../support/fixtures.dart';
import '../support/test_clock.dart';
import '../support/test_sizes.dart';

int _ms(DateTime t) => t.millisecondsSinceEpoch;

void main() {
  group('construction', () {
    test('the default constructor always has CORE faults', () async {
      final backend = FakeLibraryBackend();
      addTearDown(backend.dispose);
      expect(backend.faults, isNotNull);
      expect(backend.store.storageInfo.backend, StorageBackend.nativeFile);
      expect(backend.clock.current, DateTime(2026, 11, 4, 14, 5));
      expect(backend.store.clock, same(backend.clock.clock));
    });

    test('passed faults, clock and storageInfo are used as they are', () {
      fakeAsync((async) {
        final faults = FakeNoteStoreFaults();
        final clock = TestClock(DateTime(2025, 1, 2, 3, 4));
        final backend = FakeLibraryBackend(
          clock: clock,
          faults: faults,
          storageInfo: const StorageInfo(backend: StorageBackend.webInMemory),
        );
        expect(backend.faults, same(faults));
        expect(backend.clock, same(clock));
        expect(backend.store.storageInfo.isDurable, isFalse);

        // The faults object really is the store's: a failed commit shows up
        // in PersistenceStatus and the write completes after the 100 ms retry.
        faults.failNextCommits(1);
        var done = false;
        backend.library.createFolder(name: 'A').then((_) => done = true);
        async.flushMicrotasks();
        expect(done, isFalse);
        expect(backend.store.persistenceStatus.consecutiveFailures, 1);
        async.elapse(const Duration(milliseconds: 100));
        expect(done, isTrue);
        expect(backend.store.persistenceStatus.consecutiveFailures, 0);
        backend.dispose();
        async.flushMicrotasks();
      });
    });

    test(
      'overStore: faults == null and the opener gets the backend clock',
      () async {
        Clock? received;
        final clock = TestClock(DateTime(2026, 1, 1));
        final backend = await FakeLibraryBackend.overStore((c) async {
          received = c;
          return createFakeNoteStore(clock: c);
        }, clock: clock);
        addTearDown(backend.dispose);
        expect(backend.faults, isNull);
        expect(backend.clock, same(clock));
        expect(received, same(backend.clock.clock));
        expect(backend.store.clock.now(), DateTime(2026, 1, 1));

        // The wrapper layer works the same over any store.
        await backend.library.createFolder(name: 'A');
        expect(backend.calls, ["createFolder home 'A'"]);
      },
    );

    test('dispose closes the store', () async {
      final backend = FakeLibraryBackend();
      await backend.dispose();
      await expectLater(
        backend.store.library.createFolder(name: 'A'),
        throwsA(isA<Object>()),
      );
    });
  });

  group('injection', () {
    late FakeLibraryBackend backend;
    setUp(() => backend = FakeLibraryBackend());
    tearDown(() => backend.dispose());

    test('failNextMutation is thrown once, before delegating', () async {
      final error = StateError('x');
      backend.failNextMutation = error;
      await expectLater(
        backend.library.createFolder(name: 'A'),
        throwsA(same(error)),
      );
      expect(backend.failNextMutation, isNull);
      expect((await backend.store.library.watchFolderTree().first).length, 0);

      // Recovered: the next call goes through.
      await backend.library.createFolder(name: 'A');
      expect((await backend.store.library.watchFolderTree().first).length, 1);
      // Both calls are logged, the failed one too.
      expect(backend.calls, ["createFolder home 'A'", "createFolder home 'A'"]);
    });

    test('failNextMutation also applies to the trash wrapper', () async {
      final note = await backend.seedNote('N');
      await backend.store.library.trashItems([NoteRef(note.id)]);
      backend.failNextMutation = const FormatException('boom');
      await expectLater(
        backend.trash.restore([NoteRef(note.id)]),
        throwsFormatException,
      );
      expect(await backend.store.trash.watchTrash().first, hasLength(1));
      await backend.trash.restore([NoteRef(note.id)]);
      expect(await backend.store.trash.watchTrash().first, isEmpty);
    });

    test('queries are never failed by failNextMutation', () async {
      backend.failNextMutation = StateError('x');
      expect(await backend.library.getFolder('missing'), isNull);
      await backend.library.watchFolderTree().first;
      expect(backend.failNextMutation, isNotNull);
    });

    test('latency is awaited before every mutating call', () {
      fakeAsync((async) {
        final b = FakeLibraryBackend()
          ..latency = const Duration(milliseconds: 300);
        Folder? created;
        b.library.createFolder(name: 'A').then((f) => created = f);
        async.flushMicrotasks();
        expect(b.calls, ["createFolder home 'A'"]);

        async.elapse(const Duration(milliseconds: 299));
        expect(created, isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(created, isNotNull);

        // Reads are not delayed.
        Note? read;
        var done = false;
        b.library.getNote('missing').then((n) {
          read = n;
          done = true;
        });
        async.flushMicrotasks();
        expect(done, isTrue);
        expect(read, isNull);
        b.dispose();
        async.flushMicrotasks();
      });
    });
  });

  group('call log', () {
    late FakeLibraryBackend backend;
    late SampleLibrary sample;
    setUp(() async {
      backend = FakeLibraryBackend();
      sample = await seedSampleLibrary(backend);
    });
    tearDown(() => backend.dispose());

    test('seeding is not logged', () {
      expect(backend.calls, isEmpty);
      expect(backend.queries, isEmpty);
    });

    test(
      'every mutating call leaves one entry in the documented format',
      () async {
        final math = sample.math.id;
        final english = sample.english.id;
        final n0 = sample.homeNotes[0].id;
        final n1 = sample.homeNotes[1].id;
        final lib = backend.library;

        final f = await lib.createFolder(
          parentId: math,
          name: '새 폴더',
          colorArgb: 0xFF2F4A7A,
          icon: 'book',
        );
        await lib.renameFolder(f.id, 'B');
        await lib.setFolderAppearance(f.id, clearColor: true, clearIcon: true);
        final n = await lib.createNote(
          folderId: english,
          title: '제목 없는 노트',
          cover: const ColorCover(0xFF2E6B4F),
        );
        await lib.renameNote(n.id, 'T');
        await lib.setFavorite([n0, n1], true);
        await lib.setCover(n.id, const FirstPageCover());
        await lib.setTags(n.id, ['a', 'b']);
        await lib.moveItems([
          NoteRef(n0),
          FolderRef(f.id),
        ], targetFolderId: english);
        await lib.moveItems([NoteRef(n0)], targetFolderId: null);
        await lib.reorderItem(NoteRef(n0), after: NoteRef(n1));
        await lib.reorderItems([
          NoteRef(n0),
          NoteRef(n1),
        ], before: NoteRef(sample.homeNotes[2].id));
        final copies = await lib.copyItems(
          [NoteRef(n1)],
          targetFolderId: math,
          nameSuffix: ' (사본)',
        );
        await lib.trashItems([NoteRef(n1)]);
        await backend.trash.restore([NoteRef(n1)]);
        await backend.trash.purge([copies.single]);
        await backend.trash.emptyTrash();
        expect(await backend.trash.purgeExpired(), 0);

        expect(backend.calls, [
          "createFolder f:$math '새 폴더' color:0xFF2F4A7A icon:book",
          "renameFolder f:${f.id} 'B'",
          'setFolderAppearance f:${f.id} clearColor clearIcon',
          "createNote f:$english '제목 없는 노트' pages:1 cover:color:0xFF2E6B4F",
          "renameNote n:${n.id} 'T'",
          'setFavorite [n:$n0, n:$n1] true',
          'setCover n:${n.id} firstPage',
          'setTags n:${n.id} [a, b]',
          'moveItems [n:$n0, f:${f.id}] -> f:$english',
          'moveItems [n:$n0] -> home',
          'reorderItem n:$n0 after:n:$n1',
          'reorderItems [n:$n0, n:$n1] before:n:${sample.homeNotes[2].id}',
          "copyItems [n:$n1] -> f:$math suffix:' (사본)'",
          'trashItems [n:$n1]',
          'restore [n:$n1]',
          'purge [${copies.single is NoteRef ? 'n' : 'f'}:${copies.single.id}]',
          'emptyTrash',
          'purgeExpired',
        ]);
        expect(backend.calls.where((c) => c.startsWith('markOpened')), isEmpty);
      },
    );

    test('markOpened would be logged (S-5 checks it never is)', () async {
      await backend.library.markOpened(sample.homeNotes[0].id);
      expect(backend.calls, ['markOpened ${sample.homeNotes[0].id}']);
    });

    test('reads are logged with their arguments in queries', () async {
      const q = LibraryQuery(sort: LibrarySortField.name, descending: false);
      await backend.library.watchListing(q).first;
      await backend.library.searchLibrary('수학');
      await backend.library.watchRecentNotes().first;
      await backend.trash.watchTrash().first;
      expect(backend.queries, [
        'watchListing LibraryQuery(folder: null, name, asc)',
        "searchLibrary '수학' limit:50",
        'watchRecentNotes limit:20',
        'watchTrash',
      ]);
      expect(backend.calls, isEmpty);
    });

    test('remoteChange bypasses the log and the injection', () async {
      backend.failNextMutation = StateError('x');
      await backend.remoteChange(
        (s) => s.library.trashItems([FolderRef(sample.science.id)]),
      );
      expect(backend.calls, isEmpty);
      expect(backend.failNextMutation, isNotNull);
      final trashed = await backend.store.library.getFolder(sample.science.id);
      expect(trashed!.deletedAt, isNotNull);
    });
  });

  group('overrides', () {
    test('CORE providers derive from the wrappers', () async {
      final backend = FakeLibraryBackend();
      addTearDown(backend.dispose);
      final container = ProviderContainer.test(overrides: backend.overrides);

      expect(container.read(noteStoreProvider), same(backend.store));
      expect(container.read(libraryRepositoryProvider), same(backend.library));
      expect(container.read(trashRepositoryProvider), same(backend.trash));
      expect(container.read(clockProvider), same(backend.clock.clock));

      final sub = container.listen(folderTreeProvider, (_, _) {});
      addTearDown(sub.close);
      expect((await container.read(folderTreeProvider.future)).length, 0);
      expect(backend.queries, ['watchFolderTree']);

      // A mutation through the wrapper reaches the provider through CORE.
      await container.read(libraryRepositoryProvider).createFolder(name: '수학');
      await pumpEventQueue();
      expect(container.read(folderTreeProvider).value!.length, 1);
      expect(backend.calls, ["createFolder home '수학'"]);
    });
  });

  group('seeding', () {
    late FakeLibraryBackend backend;
    setUp(() => backend = FakeLibraryBackend());
    tearDown(() => backend.dispose());

    test('seedFolder / seedNote at: set the clock first', () async {
      final t1 = DateTime(2026, 10, 1, 8, 30);
      final t2 = DateTime(2026, 10, 2, 9);
      final folder = await backend.seedFolder(
        'A',
        colorArgb: 0xFF7FB2E5,
        icon: 'star',
        at: t1,
      );
      expect(folder.createdAt, _ms(t1));
      expect(folder.colorArgb, 0xFF7FB2E5);
      expect(folder.icon, 'star');
      final note = await backend.seedNote(
        'N',
        folderId: folder.id,
        favorite: true,
        at: t2,
      );
      expect(note.createdAt, _ms(t2));
      expect(note.folderId, folder.id);
      expect(note.isFavorite, isTrue);
      expect(backend.clock.current, t2);
    });

    test(
      'seedTrashed trashes at the given time and moves the clock back',
      () async {
        final note = await backend.seedNote('N');
        final before = backend.clock.current;
        final at = DateTime(2026, 10, 20, 10);
        await backend.seedTrashed([NoteRef(note.id)], at: at);
        expect(backend.clock.current, before);
        final trash = await backend.store.trash.watchTrash().first;
        expect(trash.single.ref, NoteRef(note.id));
        expect(trash.single.deletedAt, _ms(at));
        expect(trash.single.expiresAt, _ms(at.add(const Duration(days: 30))));
      },
    );

    test(
      "seedOpened puts the note in '최근' the real way (openSession)",
      () async {
        final a = await backend.seedNote('A');
        final b = await backend.seedNote('B');
        expect(await backend.store.library.watchRecentNotes().first, isEmpty);
        await backend.seedOpened(a.id, at: DateTime(2026, 11, 4, 9));
        await backend.seedOpened(b.id, at: DateTime(2026, 11, 4, 10));
        final recent = await backend.store.library.watchRecentNotes().first;
        expect(recent.map((n) => n.id), [b.id, a.id]);
        expect(recent.first.lastOpenedAt, _ms(DateTime(2026, 11, 4, 10)));
        // Through the store, not the wrapper: nothing logged.
        expect(backend.calls, isEmpty);
      },
    );

    test(
      'seedSampleLibrary: 3 folders and 4 notes at home, 3 nested levels',
      () async {
        final sample = await seedSampleLibrary(backend);
        final home = await backend.store.library
            .watchListing(const LibraryQuery())
            .first;
        expect(home.folders, hasLength(3));
        expect(home.notes, hasLength(4));
        final tree = await backend.store.library.watchFolderTree().first;
        expect(tree.length, 6);
        expect(tree.pathTo(sample.deepest.id).map((f) => f.name), [
          '수학',
          '미적분',
          '극한',
          '연습 문제',
        ]);
        final deep = await backend.store.library
            .watchListing(LibraryQuery(folderId: sample.deepest.id))
            .first;
        expect(deep.notes.single.id, sample.deepNote.id);
        expect(backend.clock.current, DateTime(2026, 11, 4, 14, 5));
        // Creation times are one minute apart and in order.
        expect(sample.homeNotes.map((n) => n.createdAt), [
          for (var i = 4; i < 8; i++) _ms(DateTime(2026, 11, 1, 9, i)),
        ]);
      },
    );
  });

  group('FakeThumbnailRenderer and sizes', () {
    test(
      'renders a 1x1 PNG for the page revision, or fails / gives null',
      () async {
        final backend = FakeLibraryBackend();
        addTearDown(backend.dispose);
        final note = await backend.seedNote('N');
        final page = await backend.store.content.loadPage(note.firstPageId!);
        final renderer = FakeThumbnailRenderer();

        final thumb = (await renderer.render(page))!;
        expect(thumb.pageId, page.page.id);
        expect(thumb.contentRevision, page.page.contentRevision);
        expect(thumb.mimeType, 'image/png');
        expect(thumb.bytes, kTestPng1x1);
        expect(kTestPng1x1.sublist(1, 4), 'PNG'.codeUnits);

        renderer.nullFor = {page.page.id};
        expect(await renderer.render(page), isNull);
        renderer
          ..nullFor = {}
          ..failFor = {page.page.id};
        await expectLater(renderer.render(page), throwsStateError);
        expect(renderer.rendered, [page.page.id, page.page.id, page.page.id]);
      },
    );

    test('the 8 test sizes of 9.1', () {
      expect(TestSizes.all, hasLength(8));
      expect(TestSizes.all.toSet(), hasLength(8));
      expect(TestSizes.ipad13Landscape, const Size(1376, 1032));
      expect(TestSizes.ipad13Portrait, const Size(1032, 1376));
    });
  });
}
