// lib/src/ui/top_bar/library_top_bar.dart — 05-library 6.2 (top bar table).
// Leading button, the breadcrumb (folder sections) or the section title, and
// on the right the sort menu and the view toggle (L10; in the compact class
// both live in ⋯). Still to come on the right: search (L17), '선택' (L14),
// '새로 만들기' (L12 / L18).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/library_strings.dart';
import '../../model/section.dart';
import '../../state/providers.dart';
import '../layout/library_metrics.dart';
import '../layout/size_class.dart';
import '../library_scope.dart';
import 'breadcrumb_bar.dart';
import 'sort_menu_button.dart';

class LibraryTopBar extends ConsumerWidget {
  const LibraryTopBar({super.key, required this.section});

  final LibrarySection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = LibraryScope.of(context);
    final theme = Theme.of(context);
    final sortEnabled = section is FolderSection;
    final showViewToggle = section is! TrashSection;
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
            Expanded(
              child: switch (section) {
                FolderSection(:final folderId) => BreadcrumbBar(
                  folderId: folderId,
                ),
                _ => _SectionTitle(section: section),
              },
            ),
            const SizedBox(width: 8),
            if (scope.sizeClass == LibrarySizeClass.compact)
              CompactListingMenu(
                sortEnabled: sortEnabled,
                showViewToggle: showViewToggle,
              )
            else ...[
              SortMenuButton(enabled: sortEnabled),
              if (showViewToggle) const ViewModeButton(),
            ],
            const SizedBox(width: 8),
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

/// Title of a non-folder section (6.6).
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.section});

  final LibrarySection section;

  @override
  Widget build(BuildContext context) {
    final title = switch (section) {
      FolderSection() => '',
      RecentSection() => LibraryStrings.recent,
      FavoritesSection() => LibraryStrings.favorites,
      TrashSection() => LibraryStrings.trash,
      SearchSection(:final query) => LibraryStrings.searchResultsTitle(query),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
