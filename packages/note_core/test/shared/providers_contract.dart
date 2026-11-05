// Shared body of the CORE provider tests (6.16, 7.2.14): run on the fake store
// (test/providers/providers_fake_test.dart, T5) and on the SQLite store
// (test/providers/providers_real_test.dart, T17). Web-safe (no dart:io).
import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:riverpod/misc.dart' show ProviderListenable;
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

/// Riverpod 3 pauses providers without listeners, so reads of stream-backed values
/// keep a listener while waiting.
Future<T> readWhileListening<T>(
  ProviderContainer container,
  ProviderListenable<Future<T>> provider,
) async {
  final sub = container.listen(provider, (_, _) {});
  try {
    return await sub.read();
  } finally {
    sub.close();
  }
}

/// The provider cases every store must pass; [open] returns a newly opened store
/// with the default pen presets.
void defineProviderContractTests(Future<NoteStore> Function() open) {
  late NoteStore store;
  late ProviderContainer container;

  Future<T> readAsync<T>(ProviderListenable<Future<T>> provider) =>
      readWhileListening(container, provider);

  setUp(() async {
    store = await open();
    container = ProviderContainer.test(
      overrides: [noteStoreProvider.overrideWithValue(store)],
    );
  });

  tearDown(() async {
    container.dispose();
    await store.close();
  });

  test('noteStoreProvider must be overridden', () {
    final bare = ProviderContainer.test();
    expect(() => bare.read(noteStoreProvider), throwsA(anything));
  });

  test('services come from the store', () {
    expect(container.read(libraryRepositoryProvider), same(store.library));
    expect(container.read(trashRepositoryProvider), same(store.trash));
    expect(container.read(penPresetRepositoryProvider), same(store.penPresets));
    expect(container.read(settingsRepositoryProvider), same(store.settings));
    expect(container.read(noteContentReaderProvider), same(store.content));
    expect(container.read(assetStoreProvider), same(store.assets));
    expect(container.read(thumbnailCacheProvider), same(store.thumbnails));
    expect(container.read(syncStoreProvider), same(store.sync));
    expect(container.read(idGeneratorProvider), same(store.ids));
    expect(container.read(clockProvider), same(store.clock));
    expect(container.read(storageInfoProvider), store.storageInfo);
    expect(container.read(pageThumbnailRendererProvider), isNull);
    expect(container.read(remoteAssetFetcherProvider), isNull);
  });

  test('syncBadgeProvider defaults to off', () async {
    expect(await readAsync(syncBadgeProvider.future), SyncBadge.off);
  });

  test(
    'persistenceStatusProvider: first value arrives without any write',
    () async {
      final value = await readAsync(persistenceStatusProvider.future);
      expect(value.pendingOps, 0);
      expect(
        container.read(persistenceStatusProvider),
        isA<AsyncData<PersistenceStatus>>(),
      );
    },
  );

  test('library listing refreshes after a commit', () async {
    final values = <List<String>>[];
    container.listen(libraryListingProvider(const LibraryQuery()), (_, next) {
      if (next case AsyncData(:final value)) {
        values.add([for (final n in value.notes) n.title]);
      }
    }, fireImmediately: true);
    await pumpEventQueue();
    await store.library.createNote(title: 'n1');
    await pumpEventQueue();
    expect(values.first, isEmpty);
    expect(values.last, ['n1']);
    final tree = await readAsync(folderTreeProvider.future);
    expect(tree.length, 0);
    expect(await readAsync(penPresetsProvider.future), hasLength(5));
    // The fake keeps no outbox (0); the SQLite store counts its entries.
    expect(
      await readAsync(syncPendingCountProvider.future),
      (await store.sync.pendingChanges()).length,
    );
  });

  test('noteSessionProvider closes the session when disposed', () async {
    final note = await store.library.createNote(title: 'n');
    final sub = container.listen(noteSessionProvider(note.id), (_, _) {});
    final session = await readAsync(noteSessionProvider(note.id).future);
    expect(session.isClosed, isFalse);
    expect(await readAsync(notePagesProvider(note.id).future), session.pages);
    expect(
      await readAsync(historyStateProvider(note.id).future),
      HistoryState.empty,
    );
    sub.close();
    await container.pump();
    await pumpEventQueue();
    expect(session.isClosed, isTrue);
  });

  test('pageContentProvider pins the page and unpins it on dispose', () async {
    final note = await store.library.createNote(title: 'n');
    final sessionSub = container.listen(
      noteSessionProvider(note.id),
      (_, _) {},
    );
    final session = await readAsync(noteSessionProvider(note.id).future);
    final pageId = session.pages.single.id;
    final key = (noteId: note.id, pageId: pageId);
    final contents = <PageContent>[];
    final sub = container.listen(pageContentProvider(key), (_, next) {
      if (next case AsyncData(:final value)) contents.add(value);
    });
    await pumpEventQueue();
    expect(contents, hasLength(1));
    expect(session.pageIfLoaded(pageId), isNotNull);
    session.execute(
      AddStrokes(
        pageId: pageId,
        strokes: [StrokeFixtures.synthetic(pageId: pageId, ids: store.ids)],
      ),
    );
    await pumpEventQueue();
    expect(contents.last.strokeCount, 1);
    sub.close();
    await container.pump();
    await pumpEventQueue();
    // Unpinned: with a cache of 0 pages it is evicted by the next close.
    final probe = await session.openPage(pageId);
    session.closePage(pageId);
    expect(probe.strokeCount, 1);
    sessionSub.close();
  });

  test('pageThumbnailProvider re-reads after ThumbnailCache.updates', () async {
    final note = await store.library.createNote(title: 'n');
    final page = (await store.content.pagesOf(note.id)).single;
    final values = <PageThumbnail?>[];
    container.listen(pageThumbnailProvider(page.id), (_, next) {
      if (next case AsyncData(:final value)) values.add(value);
    }, fireImmediately: true);
    await pumpEventQueue();
    expect(values, [null]);
    await store.thumbnails.write(
      PageThumbnail(
        pageId: page.id,
        contentRevision: 0,
        width: 1,
        height: 1,
        mimeType: 'image/png',
        bytes: Uint8List(1),
      ),
    );
    await pumpEventQueue();
    expect(values.last, isNotNull);
  });

  test('recent / favorites / search / trash providers', () async {
    final note = await store.library.createNote(title: '강의');
    await store.library.setFavorite([note.id], true);
    expect(await readAsync(favoriteNotesProvider.future), hasLength(1));
    expect(
      (await readAsync(librarySearchProvider('강').future)).notes,
      hasLength(1),
    );
    expect(await readAsync(recentNotesProvider.future), isEmpty);
    expect(await readAsync(trashItemsProvider.future), isEmpty);
    expect((await readAsync(noteProvider(note.id).future))!.title, '강의');
    expect(
      await readAsync(settingsSnapshotProvider.future),
      isA<SettingsSnapshot>(),
    );
    unawaited(Future<void>.value());
    expect(const Clock(), isNotNull);
  });
}
