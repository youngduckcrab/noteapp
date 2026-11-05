// lib/src/state/providers.dart — every LIBRARY provider (05-library 6.3.2).
// Riverpod 3.4.3 without code generation; name: == the variable name
// (contract 7.4.4). None of them has to be overridden by the app shell.
import 'dart:async' show unawaited;
import 'dart:typed_data' show Uint8List;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart'
    show
        AssetId,
        FolderId,
        assetStoreProvider,
        favoriteNotesProvider,
        folderTreeProvider,
        libraryListingProvider,
        libraryRepositoryProvider,
        librarySearchProvider,
        noRetry,
        noteContentReaderProvider,
        noteStoreProvider,
        pageThumbnailRendererProvider,
        recentNotesProvider,
        settingsSnapshotProvider,
        thumbnailCacheProvider,
        trashItemsProvider,
        trashRepositoryProvider;

import '../common/report_error.dart';

import '../model/content.dart';
import '../model/new_note_spec.dart';
import '../model/section.dart';
import '../model/selection.dart';
import '../model/tree_rows.dart';
import '../model/view_prefs.dart';
import '../settings/library_settings_keys.dart';
import '../thumbnails/cover_thumbnail_scheduler.dart';
import 'expansion_notifier.dart';
import 'library_actions.dart';
import 'prefs_notifier.dart';
import 'section_notifier.dart';
import 'selection_notifier.dart';

/// View mode, sort and sidebar visibility (device settings, optimistic).
final libraryPrefsProvider =
    NotifierProvider<LibraryPrefsNotifier, LibraryViewPrefs>(
      LibraryPrefsNotifier.new,
      name: 'libraryPrefsProvider',
    );

/// NewNoteOptions.fromJson(snapshot.get(LibrarySettingsKeys.newNoteDefaults));
/// const NewNoteOptions() while the settings load or after a stream error.
final newNoteDefaultsProvider = Provider<NewNoteOptions>((ref) {
  final snapshot = ref.watch(settingsSnapshotProvider).value;
  if (snapshot == null) return const NewNoteOptions();
  return NewNoteOptions.fromJson(
    snapshot.get(LibrarySettingsKeys.newNoteDefaults),
  );
}, name: 'newNoteDefaultsProvider');

/// The section shown for one route folderId (6.4). Initial value
/// FolderSection(arg); a new route folderId is a new instance.
final librarySectionProvider = NotifierProvider.autoDispose
    .family<LibrarySectionNotifier, LibrarySection, FolderId?>(
      LibrarySectionNotifier.new,
      name: 'librarySectionProvider',
    );

/// Multi-select state for one route folderId (6.9); cleared whenever that
/// route's section changes.
final librarySelectionProvider = NotifierProvider.autoDispose
    .family<LibrarySelectionNotifier, LibrarySelection, FolderId?>(
      LibrarySelectionNotifier.new,
      name: 'librarySelectionProvider',
    );

/// Expanded sidebar folders (device setting library.sidebar.expanded, saved
/// 500 ms after the last change).
final folderExpansionProvider =
    NotifierProvider<FolderExpansionNotifier, Set<FolderId>>(
      FolderExpansionNotifier.new,
      name: 'folderExpansionProvider',
    );

/// The LibrarySort to use, or null while the view settings load (6.3.3: the
/// content waits for them so the first frame does not flip grid → list). A
/// settings stream error counts as loaded with the defaults.
LibrarySort? _sortOnceLoaded(Ref ref) {
  final (loaded, sort) = ref.watch(
    libraryPrefsProvider.select((p) => (p.isLoaded, p.sort)),
  );
  if (loaded) return sort;
  final failed = ref.watch(settingsSnapshotProvider.select((s) => s.hasError));
  return failed ? LibrarySort.defaults : null;
}

/// Search groups are cut at this many hits by CORE (searchLibrary limit).
const int kLibrarySearchLimit = 50;

/// The CORE stream / query of [section] as LibraryContent (6.3.3 table).
/// AsyncLoading until the view settings are loaded. TrashSection →
/// AsyncData(LibraryContent(section)) (the trash view reads trashItemsProvider).
final libraryContentProvider = Provider.autoDispose
    .family<AsyncValue<LibraryContent>, LibrarySection>((ref, section) {
      final sort = _sortOnceLoaded(ref);
      if (sort == null) return const AsyncLoading();
      switch (section) {
        case FolderSection(:final folderId):
          return ref
              .watch(libraryListingProvider(sort.queryFor(folderId)))
              .whenData(
                (l) => LibraryContent(
                  section: section,
                  folders: l.folders,
                  notes: l.notes,
                ),
              );
        case RecentSection():
          return ref
              .watch(recentNotesProvider)
              .whenData((n) => LibraryContent(section: section, notes: n));
        case FavoritesSection():
          return ref
              .watch(favoriteNotesProvider)
              .whenData((n) => LibraryContent(section: section, notes: n));
        case SearchSection(:final query):
          return ref
              .watch(librarySearchProvider(query))
              .whenData(
                (r) => LibraryContent(
                  section: section,
                  folders: r.folders,
                  notes: r.notes,
                  truncated:
                      r.folders.length >= kLibrarySearchLimit ||
                      r.notes.length >= kLibrarySearchLimit,
                ),
              );
        case TrashSection():
          return AsyncData(LibraryContent(section: section));
      }
    }, name: 'libraryContentProvider');

/// Folder tree + expansion + sort → the visible sidebar rows (6.5).
/// AsyncLoading until the view settings are loaded (the order depends on
/// the sort).
final sidebarRowsProvider =
    Provider.autoDispose<AsyncValue<List<FolderTreeRow>>>((ref) {
      final sort = _sortOnceLoaded(ref);
      if (sort == null) return const AsyncLoading();
      final expanded = ref.watch(folderExpansionProvider);
      final order = folderTreeOrderFor(sort);
      return ref
          .watch(folderTreeProvider)
          .whenData(
            (tree) => flattenFolderTree(tree, expanded: expanded, order: order),
          );
    }, name: 'sidebarRowsProvider');

/// State of a folder id (6.4): active when the tree has it; otherwise
/// getFolder → trashed (deletedAt set) or missing (null). Runs again on
/// every new tree (a remote trash / restore changes the answer) and every
/// trash change (a purge does not change the tree).
final folderLookupProvider = FutureProvider.autoDispose
    .family<FolderLookupState, FolderId>(
      (ref, id) async {
        final library = ref.watch(libraryRepositoryProvider);
        ref.watch(trashItemsProvider.select((t) => t.value));
        final tree = await ref.watch(folderTreeProvider.future);
        if (tree.byId(id) != null) return FolderLookupState.active;
        final folder = await library.getFolder(id);
        if (folder == null) return FolderLookupState.missing;
        return folder.isDeleted
            ? FolderLookupState.trashed
            : FolderLookupState.active;
      },
      retry: noRetry,
      name: 'folderLookupProvider',
    );

/// Number of trash entries (sidebar badge); 0 while loading or after an
/// error.
final trashCountProvider = Provider.autoDispose<int>((ref) {
  final items = ref.watch(trashItemsProvider);
  if (items.hasError) return 0;
  return items.value?.length ?? 0;
}, name: 'trashCountProvider');

/// CORE mutations + error classification + undo receipts (6.11). Failures
/// other than folderCycle / invalidName are reported with
/// FlutterError.reportError(library: 'feature_library').
final libraryActionsProvider = Provider<LibraryActions>(
  (ref) => LibraryActions(
    library: ref.watch(libraryRepositoryProvider),
    trash: ref.watch(trashRepositoryProvider),
    report: reportLibraryError,
  ),
  name: 'libraryActionsProvider',
);

/// Cover thumbnail scheduler (6.15.3). Disabled (isEnabled == false, does
/// nothing) while the CORE renderer slot is null — foundation stage, before
/// the app shell wires INK, and the test default. A new renderer value
/// rebuilds it; the old one is disposed.
final coverThumbnailSchedulerProvider = Provider<CoverThumbnailScheduler>((
  ref,
) {
  final scheduler = CoverThumbnailScheduler(
    reader: ref.watch(noteContentReaderProvider),
    cache: ref.watch(thumbnailCacheProvider),
    renderer: ref.watch(pageThumbnailRendererProvider),
    assetArrivals: ref.watch(assetStoreProvider).bytesArrived,
    changes: ref.watch(noteStoreProvider).changes,
    report: (error, stack) =>
        reportLibraryError(error, stack, 'library cover thumbnail'),
  );
  ref.onDispose(scheduler.dispose);
  return scheduler;
}, name: 'coverThumbnailSchedulerProvider');

/// Bytes of an AssetCover image (AssetStore.readBytes); null while they are
/// not on this device. Reads again when AssetStore.bytesArrived names [id].
final assetCoverBytesProvider = FutureProvider.autoDispose
    .family<Uint8List?, AssetId>(
      (ref, id) {
        final assets = ref.watch(assetStoreProvider);
        final sub = assets.bytesArrived
            .where((arrived) => arrived == id)
            .listen((_) => ref.invalidateSelf());
        ref.onDispose(() => unawaited(sub.cancel()));
        return assets.readBytes(id);
      },
      retry: noRetry,
      name: 'assetCoverBytesProvider',
    );
