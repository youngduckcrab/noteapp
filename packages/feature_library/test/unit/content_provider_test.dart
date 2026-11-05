// libraryContentProvider / sidebarRowsProvider / folderLookupProvider /
// trashCountProvider (05-library 6.3.2 / 6.3.3, 8 L6) over the CORE fake.
import 'dart:async';

import 'package:feature_library/src/model/content.dart';
import 'package:feature_library/src/model/item_key.dart';
import 'package:feature_library/src/model/section.dart';
import 'package:feature_library/src/model/view_prefs.dart';
import 'package:feature_library/src/settings/library_settings_keys.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';

import '../support/fake_library_backend.dart';
import '../support/fixtures.dart';

void main() {
  late FakeLibraryBackend backend;
  late ProviderContainer container;
  late SampleLibrary lib;

  ProviderContainer makeContainer([List<Override> extra = const []]) =>
      ProviderContainer.test(overrides: [...backend.overrides, ...extra]);

  setUp(() async {
    backend = FakeLibraryBackend();
    lib = await seedSampleLibrary(backend);
    container = makeContainer();
  });
  tearDown(() => backend.dispose());

  /// Listens to [p] (keeps autoDispose providers alive) and returns a reader.
  AsyncValue<T> Function() listen<T>(ProviderListenable<AsyncValue<T>> p) {
    final sub = container.listen(p, (_, _) {});
    return sub.read;
  }

  /// Waits until [read] gives data that satisfies [test] (default: any data).
  Future<T> until<T>(
    AsyncValue<T> Function() read, [
    bool Function(T value)? test,
  ]) async {
    for (var i = 0; i < 40; i++) {
      final v = read();
      if (v is AsyncData<T> && (test == null || test(v.value))) return v.value;
      await pumpEventQueue();
    }
    fail('no matching data; last: ${read()}');
  }

  Future<LibraryContent> contentOf(LibrarySection section) =>
      until(listen(libraryContentProvider(section)));

  List<String> titles(LibraryContent c) => [for (final n in c.notes) n.title];
  List<String> names(LibraryContent c) => [for (final f in c.folders) f.name];

  group('libraryContentProvider — five sections', () {
    test('home folder: listing with the current sort, folders first', () async {
      final c = await contentOf(const FolderSection(null));
      expect(c.section, const FolderSection(null));
      // Default sort: updatedAt descending.
      expect(names(c), ['과학', '영어', '수학']);
      expect(titles(c), ['일기', '아이디어', '독서 기록', '회의록']);
      expect(c.truncated, isFalse);
      expect(c.isEmpty, isFalse);
      expect(c.orderedKeys.first, folderKey(lib.science.id));
      expect(c.orderedKeys.last, noteKey(lib.homeNotes.first.id));
      expect(c.orderedKeys, hasLength(7));
      expect(
        backend.queries,
        contains('watchListing LibraryQuery(folder: null, updatedAt, desc)'),
      );
    });

    test('sub folder and the stored sort (name ascending)', () async {
      await backend.store.settings.set(LibrarySettingsKeys.sortField, 'name');
      await backend.store.settings.set(
        LibrarySettingsKeys.sortDescending,
        false,
      );
      final c = await contentOf(FolderSection(lib.deepest.id));
      expect(titles(c), ['극한 정리']);
      expect(c.folders, isEmpty);
      expect(
        backend.queries,
        contains(
          'watchListing LibraryQuery(folder: ${lib.deepest.id}, name, asc)',
        ),
      );
    });

    test('a sort change re-queries the listing', () async {
      final read = listen(libraryContentProvider(const FolderSection(null)));
      await until(read);
      await container
          .read(libraryPrefsProvider.notifier)
          .selectSort(LibrarySortField.name);
      final c = await until(read, (c) => c.folders.first.name == '과학');
      // Name ascending: 과학 < 수학 < 영어.
      expect(names(c), ['과학', '수학', '영어']);
      expect(
        backend.queries,
        contains('watchListing LibraryQuery(folder: null, name, asc)'),
      );
    });

    test('unknown folder → empty listing (C-2)', () async {
      final c = await contentOf(const FolderSection('nope'));
      expect(c.isEmpty, isTrue);
      expect(c.orderedKeys, isEmpty);
    });

    test('recent: notes only, after openSession', () async {
      expect((await contentOf(const RecentSection())).isEmpty, isTrue);
      final read = listen(libraryContentProvider(const RecentSection()));
      await until(read);
      await backend.seedOpened(lib.homeNotes[1].id);
      final c = await until(read, (c) => c.notes.isNotEmpty);
      expect(titles(c), ['독서 기록']);
      expect(c.folders, isEmpty);
    });

    test('favorites: notes only', () async {
      await backend.seedNote('즐겨찾는 노트', favorite: true);
      final c = await contentOf(const FavoritesSection());
      expect(titles(c), ['즐겨찾는 노트']);
      expect(c.folders, isEmpty);
    });

    test('search: folders and notes of the whole library', () async {
      final c = await contentOf(
        const SearchSection('극한', returnTo: FolderSection(null)),
      );
      expect(names(c), ['극한']);
      expect(titles(c), ['극한 정리']);
      expect(c.truncated, isFalse);
      expect(backend.queries, contains("searchLibrary '극한' limit:50"));
    });

    test('trash: empty content (the trash view reads the trash)', () async {
      final c = await contentOf(const TrashSection());
      expect(c, const LibraryContent(section: TrashSection()));
      expect(c.isEmpty, isTrue);
    });
  });

  group('search truncated', () {
    test('50 notes → truncated, 49 → not', () async {
      for (var i = 0; i < 49; i++) {
        await backend.seedNote('단어장 $i');
      }
      var c = await contentOf(
        const SearchSection('단어장', returnTo: RecentSection()),
      );
      expect(c.notes, hasLength(49));
      expect(c.truncated, isFalse);

      await backend.seedNote('단어장 49');
      await backend.seedNote('단어장 50');
      // The search is a one-time query: invalidate to search again.
      container.invalidate(librarySearchProvider('단어장'));
      c = await until(
        listen(
          libraryContentProvider(
            const SearchSection('단어장', returnTo: RecentSection()),
          ),
        ),
        (c) => c.notes.length == 50,
      );
      expect(c.truncated, isTrue);
    });

    test('50 folders → truncated', () async {
      for (var i = 0; i < 50; i++) {
        await backend.seedFolder('묶음 $i');
      }
      final c = await contentOf(
        const SearchSection('묶음', returnTo: RecentSection()),
      );
      expect(c.folders, hasLength(50));
      expect(c.notes, isEmpty);
      expect(c.truncated, isTrue);
    });
  });

  group('loading until the view settings are loaded', () {
    test('first read is loading, then data', () async {
      final read = listen(libraryContentProvider(const FolderSection(null)));
      expect(read(), isA<AsyncLoading<LibraryContent>>());
      expect(container.read(libraryPrefsProvider).isLoaded, isFalse);
      await until(read);
      expect(container.read(libraryPrefsProvider).isLoaded, isTrue);
    });

    test('listing ready but settings never arrive → still loading', () async {
      final never = StreamController<SettingsSnapshot>();
      addTearDown(never.close);
      container = makeContainer([
        settingsSnapshotProvider.overrideWith((ref) => never.stream),
      ]);
      final read = listen(libraryContentProvider(const FolderSection(null)));
      final rows = listen(sidebarRowsProvider);
      final listing = listen(
        libraryListingProvider(LibrarySort.defaults.queryFor(null)),
      );
      await until(listing);
      await pumpEventQueue();
      expect(read(), isA<AsyncLoading<LibraryContent>>());
      expect(rows(), isA<AsyncLoading<Object?>>());
      // Every section waits, the trash placeholder too.
      for (final section in const [RecentSection(), TrashSection()]) {
        expect(
          container.read(libraryContentProvider(section)),
          isA<AsyncLoading<LibraryContent>>(),
        );
      }
    });

    test('a settings stream error counts as loaded (defaults)', () async {
      container = makeContainer([
        settingsSnapshotProvider.overrideWith(
          (ref) => Stream<SettingsSnapshot>.error(StateError('settings')),
        ),
      ]);
      final c = await until(
        listen(libraryContentProvider(const FolderSection(null))),
      );
      expect(names(c), ['과학', '영어', '수학']);
      expect(await until(listen(sidebarRowsProvider)), hasLength(3));
    });
  });

  test('a CORE stream error is passed through as AsyncError', () async {
    container = makeContainer([
      recentNotesProvider.overrideWith(
        (ref) => Stream<List<Note>>.error(StateError('recent')),
      ),
    ]);
    final read = listen(libraryContentProvider(const RecentSection()));
    for (var i = 0; i < 40 && read() is! AsyncError; i++) {
      await pumpEventQueue();
    }
    expect(read(), isA<AsyncError<LibraryContent>>());
    expect(read().error, isA<StateError>());
  });

  group('sidebarRowsProvider', () {
    test('top level in name order, expanded folders open', () async {
      final read = listen(sidebarRowsProvider);
      var rows = await until(read);
      expect([for (final r in rows) r.folder.name], ['과학', '수학', '영어']);
      expect(rows[1].hasChildren, isTrue);
      expect(rows[1].isExpanded, isFalse);

      container.read(folderExpansionProvider.notifier).expand(lib.math.id);
      rows = await until(read, (r) => r.length == 4);
      expect(
        [for (final r in rows) '${r.folder.name}@${r.depth}'],
        ['과학@0', '수학@0', '미적분@1', '영어@0'],
      );
    });

    test('custom sort → CORE order (creation order here)', () async {
      final read = listen(sidebarRowsProvider);
      await until(read);
      await container
          .read(libraryPrefsProvider.notifier)
          .selectSort(LibrarySortField.custom);
      final rows = await until(read, (r) => r.first.folder.name == '수학');
      expect([for (final r in rows) r.folder.name], ['수학', '영어', '과학']);
    });

    test('a new folder from another device appears', () async {
      final read = listen(sidebarRowsProvider);
      await until(read);
      await backend.remoteChange((s) => s.library.createFolder(name: '가나다'));
      final rows = await until(read, (r) => r.length == 4);
      expect(rows.first.folder.name, '가나다');
    });
  });

  group('folderLookupProvider', () {
    test('folder in the tree → active', () async {
      expect(
        await until(listen(folderLookupProvider(lib.math.id))),
        FolderLookupState.active,
      );
    });

    test('unknown id → missing', () async {
      expect(
        await until(listen(folderLookupProvider('nope'))),
        FolderLookupState.missing,
      );
    });

    test('trashed → trashed; restored → active; purged → missing', () async {
      final read = listen(folderLookupProvider(lib.english.id));
      expect(await until(read), FolderLookupState.active);

      await backend.remoteChange(
        (s) => s.library.trashItems([FolderRef(lib.english.id)]),
      );
      expect(
        await until(read, (v) => v == FolderLookupState.trashed),
        FolderLookupState.trashed,
      );

      await backend.remoteChange(
        (s) => s.trash.restore([FolderRef(lib.english.id)]),
      );
      expect(
        await until(read, (v) => v == FolderLookupState.active),
        FolderLookupState.active,
      );

      await backend.remoteChange(
        (s) => s.library.trashItems([FolderRef(lib.english.id)]),
      );
      await until(read, (v) => v == FolderLookupState.trashed);
      await backend.remoteChange(
        (s) => s.trash.purge([FolderRef(lib.english.id)]),
      );
      expect(
        await until(read, (v) => v == FolderLookupState.missing),
        FolderLookupState.missing,
      );
    });

    test('a sub folder of a trashed folder → trashed', () async {
      await backend.remoteChange(
        (s) => s.library.trashItems([FolderRef(lib.math.id)]),
      );
      expect(
        await until(listen(folderLookupProvider(lib.deepest.id))),
        FolderLookupState.trashed,
      );
    });
  });

  group('trashCountProvider', () {
    test('0 while loading, then the number of trash entries', () async {
      final sub = container.listen(trashCountProvider, (_, _) {});
      expect(sub.read(), 0);
      await backend.seedTrashed([
        FolderRef(lib.english.id),
        NoteRef(lib.homeNotes.first.id),
      ], at: DateTime(2026, 11, 3));
      for (var i = 0; i < 40 && sub.read() != 2; i++) {
        await pumpEventQueue();
      }
      expect(sub.read(), 2);
    });

    test('0 after a stream error', () async {
      container = makeContainer([
        trashItemsProvider.overrideWith(
          (ref) => Stream<List<TrashItem>>.error(StateError('trash')),
        ),
      ]);
      final sub = container.listen(trashCountProvider, (_, _) {});
      await pumpEventQueue();
      expect(sub.read(), 0);
    });
  });
}
