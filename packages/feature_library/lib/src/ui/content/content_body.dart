// lib/src/ui/content/content_body.dart — 05-library 6.1 / 6.4 / 6.7: the
// content area by section. Folder sections (L10): the folder missing view or
// the listing; recent / favorites use the same listing (their own views and
// the search results view come with L17); trash → TrashView (6.13).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart'
    show
        FolderId,
        favoriteNotesProvider,
        folderTreeProvider,
        libraryListingProvider,
        librarySearchProvider,
        recentNotesProvider,
        trashItemsProvider;

import '../../common/report_error.dart';
import '../../dnd/library_drag_scope.dart';
import '../../model/content.dart';
import '../../model/section.dart';
import '../../model/view_prefs.dart';
import '../../state/providers.dart';
import '../library_scope.dart';
import '../trash/trash_view.dart';
import 'empty_state.dart';
import 'folder_missing_view.dart';
import 'item_grid.dart';
import 'item_list.dart';

class ContentBody extends StatelessWidget {
  const ContentBody({super.key, required this.section});

  final LibrarySection section;

  @override
  Widget build(BuildContext context) => switch (section) {
    FolderSection(:final folderId) => _FolderBody(
      key: ValueKey<FolderId?>(folderId),
      folderId: folderId,
    ),
    RecentSection() || FavoritesSection() || SearchSection() => ContentListing(
      key: ValueKey<LibrarySection>(section),
      section: section,
    ),
    TrashSection() => const TrashView(),
  };
}

/// 6.4: a folder that the loaded tree does not contain → its lookup state
/// (trashed / missing → FolderMissingView); otherwise the listing.
class _FolderBody extends ConsumerWidget {
  const _FolderBody({super.key, required this.folderId});

  final FolderId? folderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = folderId;
    if (id != null) {
      final tree = ref.watch(folderTreeProvider).value;
      if (tree != null && tree.byId(id) == null) {
        final lookup = ref.watch(folderLookupProvider(id));
        switch (lookup.value) {
          case FolderLookupState.trashed:
            return const FolderMissingView(state: FolderLookupState.trashed);
          case FolderLookupState.missing:
            return const FolderMissingView(state: FolderLookupState.missing);
          case null when !lookup.hasError:
            return const DelayedSpinner();
          case FolderLookupState.active || null:
            break; // a tree update is on its way (or the lookup failed)
        }
      }
    }
    return ContentListing(section: FolderSection(id));
  }
}

/// One section's LibraryContent: delayed spinner while loading, the error
/// with [다시 시도], the empty state, or the grid / list (6.7).
class ContentListing extends ConsumerStatefulWidget {
  const ContentListing({super.key, required this.section});

  final LibrarySection section;

  @override
  ConsumerState<ContentListing> createState() => _ContentListingState();
}

class _ContentListingState extends ConsumerState<ContentListing> {
  /// The last content shown: kept while another query of the same section
  /// loads (a new sort is a new CORE family instance without a value).
  LibraryContent? _last;

  /// 6.19: [다시 시도] re-subscribes the CORE source of the section.
  void _retry() => switch (widget.section) {
    FolderSection() => ref.invalidate(libraryListingProvider),
    RecentSection() => ref.invalidate(recentNotesProvider),
    FavoritesSection() => ref.invalidate(favoriteNotesProvider),
    SearchSection(:final query) => ref.invalidate(librarySearchProvider(query)),
    TrashSection() => ref.invalidate(trashItemsProvider),
  };

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final routeFolderId = LibraryScope.of(context).routeFolderId;
    // 6.7: items deleted / moved elsewhere leave the selection.
    ref.listen(libraryContentProvider(section), (_, next) {
      final content = next.value;
      if (content == null) return;
      ref
          .read(librarySelectionProvider(routeFolderId).notifier)
          .retainVisible(content.orderedKeys.toSet());
    });
    final async = ref.watch(libraryContentProvider(section));
    if (async.hasError) {
      reportLibraryErrorOnce(
        ProviderScope.containerOf(context, listen: false),
        async.error!,
        async.stackTrace,
        'library listing: $section',
      );
      return ListLoadError(onRetry: _retry);
    }
    final content = async.value ?? _last;
    if (content == null || content.section != section) {
      return const DelayedSpinner();
    }
    _last = content;
    if (content.isEmpty) return EmptyState(section: section);
    final mode = ref.watch(libraryPrefsProvider.select((p) => p.viewMode));
    if (mode == LibraryViewMode.list) return ItemList(content: content);
    final selecting = ref.watch(
      librarySelectionProvider(routeFolderId).select((s) => s.active),
    );
    // The '새 노트' tile stays while a drag that started selection mode runs
    // (the tiles do not shift under the pointer).
    return ValueListenableBuilder<bool>(
      valueListenable: LibraryDragScope.draggingOf(context),
      builder: (context, dragging, _) => ItemGrid(
        content: content,
        newNoteFolder: section is FolderSection ? section.folderId : null,
        showNewNoteTile: section is FolderSection && (!selecting || dragging),
      ),
    );
  }
}
