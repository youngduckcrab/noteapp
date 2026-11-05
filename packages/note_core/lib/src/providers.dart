// lib/src/providers.dart — contract 00-overview 7.2.13 / 7.2.14, CORE 4.9, 6.16.
// package:riverpod 3.4.3, no code generation. Every provider: top-level final, name: == the
// variable name (7.4.4). Repository stream providers turn automatic retry off.
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:riverpod/riverpod.dart';

import 'assets/asset_store.dart';
import 'common/ids.dart';
import 'edit/applied_edit.dart';
import 'model/note.dart';
import 'model/page.dart';
import 'model/pen_preset.dart';
import 'repo/content_reader.dart';
import 'repo/folder_tree.dart';
import 'repo/library_repository.dart';
import 'repo/library_types.dart';
import 'repo/note_store.dart';
import 'repo/pen_preset_repository.dart';
import 'repo/settings_repository.dart';
import 'repo/status.dart';
import 'repo/trash_repository.dart';
import 'session/note_session.dart';
import 'session/page_content.dart';
import 'sync/sync_display.dart';
import 'sync/sync_store.dart';

Duration? noRetry(int retryCount, Object error) => null;

typedef PageKey = ({NoteId noteId, PageId pageId});

// Root — the app shell MUST override this (INFRA CoreModule, 7.3.3).
final noteStoreProvider = Provider<NoteStore>(
  (ref) => throw UnimplementedError(
    'noteStoreProvider must be overridden by the app shell',
  ),
  name: 'noteStoreProvider',
);

// Repositories and services
final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => ref.watch(noteStoreProvider).library,
  name: 'libraryRepositoryProvider',
);
final trashRepositoryProvider = Provider<TrashRepository>(
  (ref) => ref.watch(noteStoreProvider).trash,
  name: 'trashRepositoryProvider',
);
final penPresetRepositoryProvider = Provider<PenPresetRepository>(
  (ref) => ref.watch(noteStoreProvider).penPresets,
  name: 'penPresetRepositoryProvider',
);
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => ref.watch(noteStoreProvider).settings,
  name: 'settingsRepositoryProvider',
);
final noteContentReaderProvider = Provider<NoteContentReader>(
  (ref) => ref.watch(noteStoreProvider).content,
  name: 'noteContentReaderProvider',
);
final assetStoreProvider = Provider<AssetStore>(
  (ref) => ref.watch(noteStoreProvider).assets,
  name: 'assetStoreProvider',
);
final thumbnailCacheProvider = Provider<ThumbnailCache>(
  (ref) => ref.watch(noteStoreProvider).thumbnails,
  name: 'thumbnailCacheProvider',
);
final syncStoreProvider = Provider<SyncStore>(
  (ref) => ref.watch(noteStoreProvider).sync,
  name: 'syncStoreProvider',
);
final idGeneratorProvider = Provider<IdGenerator>(
  (ref) => ref.watch(noteStoreProvider).ids,
  name: 'idGeneratorProvider',
);
final clockProvider = Provider<Clock>(
  (ref) => ref.watch(noteStoreProvider).clock,
  name: 'clockProvider',
);

// Optional slots (null until the app shell overrides them, 7.3.3)
final pageThumbnailRendererProvider = Provider<PageThumbnailRenderer?>(
  (ref) => null,
  name: 'pageThumbnailRendererProvider',
);
final remoteAssetFetcherProvider = Provider<RemoteAssetFetcher?>(
  (ref) => null,
  name: 'remoteAssetFetcherProvider',
);

/// Default: off ("이 기기에 저장"). From M4 the app shell overrides it with SYNC's status.
final syncBadgeProvider = StreamProvider<SyncBadge>(
  (ref) => Stream<SyncBadge>.value(SyncBadge.off),
  name: 'syncBadgeProvider',
);

// Library (LIBRARY)
final folderTreeProvider = StreamProvider<FolderTree>(
  (ref) => ref.watch(libraryRepositoryProvider).watchFolderTree(),
  retry: noRetry,
  name: 'folderTreeProvider',
);
final libraryListingProvider = StreamProvider.autoDispose
    .family<LibraryListing, LibraryQuery>(
      (ref, q) => ref.watch(libraryRepositoryProvider).watchListing(q),
      retry: noRetry,
      name: 'libraryListingProvider',
    );
final noteProvider = StreamProvider.autoDispose.family<Note?, NoteId>(
  (ref, id) => ref.watch(libraryRepositoryProvider).watchNote(id),
  retry: noRetry,
  name: 'noteProvider',
);
final recentNotesProvider = StreamProvider.autoDispose<List<Note>>(
  (ref) => ref.watch(libraryRepositoryProvider).watchRecentNotes(),
  retry: noRetry,
  name: 'recentNotesProvider',
);
final favoriteNotesProvider = StreamProvider.autoDispose<List<Note>>(
  (ref) => ref.watch(libraryRepositoryProvider).watchFavoriteNotes(),
  retry: noRetry,
  name: 'favoriteNotesProvider',
);
final librarySearchProvider = FutureProvider.autoDispose
    .family<LibrarySearchResult, String>(
      (ref, q) => ref.watch(libraryRepositoryProvider).searchLibrary(q),
      retry: noRetry,
      name: 'librarySearchProvider',
    );
final trashItemsProvider = StreamProvider.autoDispose<List<TrashItem>>(
  (ref) => ref.watch(trashRepositoryProvider).watchTrash(),
  retry: noRetry,
  name: 'trashItemsProvider',
);

// Editor (EDITOR)
/// openSession on first listen; session.close() (flush) when disposed (6.16).
final noteSessionProvider = FutureProvider.autoDispose
    .family<NoteSession, NoteId>(
      (ref, id) async {
        final store = ref.watch(noteStoreProvider);
        var disposed = false;
        NoteSession? session;
        ref.onDispose(() {
          disposed = true;
          final s = session;
          if (s != null) unawaited(s.close());
        });
        final opened = await store.openSession(id);
        if (disposed) {
          // Disposed while opening: release the reference right away (6.16).
          unawaited(opened.close());
        } else {
          session = opened;
        }
        return opened;
      },
      retry: noRetry,
      name: 'noteSessionProvider',
    );

/// session.pagesStream seeded with session.pages.
final notePagesProvider = StreamProvider.autoDispose.family<List<Page>, NoteId>(
  (ref, id) async* {
    final session = await ref.watch(noteSessionProvider(id).future);
    yield session.pages;
    yield* session.pagesStream;
  },
  retry: noRetry,
  name: 'notePagesProvider',
);

/// openPage on first listen, pageChanges(pageId).map((c) => c.content), closePage on dispose.
final pageContentProvider = StreamProvider.autoDispose
    .family<PageContent, PageKey>(
      (ref, key) async* {
        final sessionFuture = ref.watch(noteSessionProvider(key.noteId).future);
        var disposed = false;
        NoteSession? pinned;
        ref.onDispose(() {
          disposed = true;
          pinned?.closePage(key.pageId);
        });
        final session = await sessionFuture;
        await session.openPage(key.pageId);
        if (disposed) {
          session.closePage(key.pageId);
          return;
        }
        pinned = session;
        // pageChanges emits a `load` change with the current content first.
        yield* session.pageChanges(key.pageId).map((c) => c.content);
      },
      retry: noRetry,
      name: 'pageContentProvider',
    );

/// session.historyStream seeded with session.history.
final historyStateProvider = StreamProvider.autoDispose
    .family<HistoryState, NoteId>(
      (ref, id) async* {
        final session = await ref.watch(noteSessionProvider(id).future);
        yield session.history;
        yield* session.historyStream;
      },
      retry: noRetry,
      name: 'historyStateProvider',
    );

final penPresetsProvider = StreamProvider<List<PenPreset>>(
  (ref) => ref.watch(penPresetRepositoryProvider).watchPresets(),
  retry: noRetry,
  name: 'penPresetsProvider',
);
final settingsSnapshotProvider = StreamProvider<SettingsSnapshot>(
  (ref) => ref.watch(settingsRepositoryProvider).watchAll(),
  retry: noRetry,
  name: 'settingsSnapshotProvider',
);

/// thumbnails.read(pageId); invalidates itself when ThumbnailCache.updates emits pageId.
final pageThumbnailProvider = FutureProvider.autoDispose
    .family<PageThumbnail?, PageId>(
      (ref, pageId) async {
        final cache = ref.watch(thumbnailCacheProvider);
        final sub = cache.updates
            .where((id) => id == pageId)
            .listen((_) => ref.invalidateSelf());
        ref.onDispose(() => unawaited(sub.cancel()));
        return cache.read(pageId);
      },
      retry: noRetry,
      name: 'pageThumbnailProvider',
    );

// Status (EDITOR developer overlay, settings screen, LIBRARY/EDITOR banner, SYNC)
/// First value right after listen, without any write (7.2.12 v1.1); no seeding needed.
final persistenceStatusProvider = StreamProvider<PersistenceStatus>(
  (ref) => ref.watch(noteStoreProvider).persistenceStatusStream,
  retry: noRetry,
  name: 'persistenceStatusProvider',
);

/// NoteStore.storageInfo. Plain Provider: whoever calls refreshStorageInfo() then calls
/// ref.invalidate(storageInfoProvider) (7.2.12 v1.1); backend / isDurable never change at runtime.
final storageInfoProvider = Provider<StorageInfo>(
  (ref) => ref.watch(noteStoreProvider).storageInfo,
  name: 'storageInfoProvider',
);
final syncPendingCountProvider = StreamProvider<int>(
  (ref) => ref.watch(syncStoreProvider).watchPendingCount(),
  retry: noRetry,
  name: 'syncPendingCountProvider',
);
