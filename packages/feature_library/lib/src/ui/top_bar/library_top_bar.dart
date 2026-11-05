// lib/src/ui/top_bar/library_top_bar.dart — 05-library 6.2 (top bar table).
// Frame of the bar (task L8): the leading button and the title. The slots on
// the right are filled by later tasks: search (L17), sort and view (L10),
// '선택' (L14), '새로 만들기' (L12 / L18). The breadcrumb replaces the folder
// title in L10.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show folderTreeProvider;

import '../../l10n/library_strings.dart';
import '../../model/section.dart';
import '../../state/providers.dart';
import '../layout/library_metrics.dart';
import '../layout/size_class.dart';
import '../library_scope.dart';

class LibraryTopBar extends ConsumerWidget {
  const LibraryTopBar({super.key, required this.section});

  final LibrarySection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = LibraryScope.of(context);
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SizedBox(
        height: LibraryMetrics.topBarHeight,
        child: Row(
          children: [
            const SizedBox(width: 8),
            if (scope.sizeClass == LibrarySizeClass.expanded)
              const _SidebarToggle()
            else
              IconButton(
                icon: const Icon(Icons.menu),
                tooltip: LibraryStrings.openMenu,
                onPressed: scope.openDrawer,
              ),
            const SizedBox(width: 8),
            Expanded(child: _SectionTitle(section: section)),
            // Slots (L10, L12, L14, L17, L18) go here.
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}

/// ☰ in the expanded class: shows / hides the pinned sidebar
/// (library.sidebar.visible).
class _SidebarToggle extends ConsumerWidget {
  const _SidebarToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(
      libraryPrefsProvider.select((p) => p.sidebarVisible),
    );
    return IconButton(
      icon: const Icon(Icons.menu),
      tooltip: visible
          ? LibraryStrings.hideSidebar
          : LibraryStrings.showSidebar,
      isSelected: visible,
      onPressed: () =>
          ref.read(libraryPrefsProvider.notifier).setSidebarVisible(!visible),
    );
  }
}

/// Section title (6.6: non-folder sections). A folder shows its own name
/// until the breadcrumb bar (L10).
class _SectionTitle extends ConsumerWidget {
  const _SectionTitle({required this.section});

  final LibrarySection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = switch (section) {
      FolderSection(folderId: null) => LibraryStrings.home,
      FolderSection(:final folderId?) =>
        ref.watch(folderTreeProvider).value?.byId(folderId)?.name ?? '',
      RecentSection() => LibraryStrings.recent,
      FavoritesSection() => LibraryStrings.favorites,
      TrashSection() => LibraryStrings.trash,
      SearchSection(:final query) => LibraryStrings.searchResultsTitle(query),
    };
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
