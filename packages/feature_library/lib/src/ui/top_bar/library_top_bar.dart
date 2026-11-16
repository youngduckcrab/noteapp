// lib/src/ui/top_bar/library_top_bar.dart — 05-library 6.2 (top bar table).
// Leading button, the breadcrumb (folder sections) or the section title, and
// on the right the search field (240 / 200, L17), the sort menu, the view
// toggle (L10) and '선택' (L14) — in the compact class a search icon (the
// whole bar becomes the search field, 6.2) and ⋯ with the other three — and
// '새로 만들기' (L12; not in the trash). Still to come: 'PDF 가져오기' in the
// new menu (L18). In selection mode the selection bar replaces this bar.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show FolderId;

import '../../l10n/library_strings.dart';
import '../../model/section.dart';
import '../../state/providers.dart';
import '../layout/library_metrics.dart';
import '../layout/size_class.dart';
import '../library_scope.dart';
import 'breadcrumb_bar.dart';
import 'library_search_field.dart';
import 'new_menu_button.dart';
import 'sort_menu_button.dart';

class LibraryTopBar extends ConsumerStatefulWidget {
  const LibraryTopBar({super.key, required this.section});

  final LibrarySection section;

  @override
  ConsumerState<LibraryTopBar> createState() => _LibraryTopBarState();
}

class _LibraryTopBarState extends ConsumerState<LibraryTopBar> {
  void _closeCompactSearch(LibraryScope scope) {
    scope.compactSearchOpen.value = false;
    ref.read(librarySectionProvider(scope.routeFolderId).notifier).exitSearch();
  }

  @override
  Widget build(BuildContext context) {
    final scope = LibraryScope.of(context);
    final route = scope.routeFolderId;
    // Leaving the search for another place (not the field going back to
    // where the search started) closes the compact search bar.
    ref.listen(librarySectionProvider(route), (previous, next) {
      if (next is SearchSection || !scope.compactSearchOpen.value) return;
      if (previous is SearchSection && previous.returnTo == next) return;
      scope.compactSearchOpen.value = false;
    });
    // Compact class: the search icon was pressed (the bar is the search
    // field). The bar is also the field whenever the section is a search.
    // The screen owns the flag (system back closes the bar, m5-7/05-library
    // 16).
    return ValueListenableBuilder<bool>(
      valueListenable: scope.compactSearchOpen,
      builder: (context, compactSearchOpen, _) =>
          _bar(context, scope, compactSearchOpen),
    );
  }

  Widget _bar(BuildContext context, LibraryScope scope, bool compactOpen) {
    final section = widget.section;
    final route = scope.routeFolderId;
    final theme = Theme.of(context);
    final compact = scope.sizeClass == LibrarySizeClass.compact;
    final searchField = LibrarySearchField(
      key: ValueKey<FolderId?>(route),
      routeFolderId: route,
      // Only right after the user pressed the search icon (never on a
      // route or section change, 6.14).
      autofocus: compact && compactOpen,
    );
    if (compact && (compactOpen || section is SearchSection)) {
      return Material(
        color: theme.colorScheme.surface,
        child: SizedBox(
          height: LibraryMetrics.topBarHeight,
          child: Row(
            children: [
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: LibraryStrings.closeSearch,
                onPressed: () => _closeCompactSearch(scope),
              ),
              const SizedBox(width: 8),
              Expanded(child: searchField),
              const SizedBox(width: 16),
            ],
          ),
        ),
      );
    }
    final sortEnabled = section is FolderSection;
    final showViewToggle = section is! TrashSection;
    // '선택' (6.9): selection mode with nothing selected yet.
    void beginSelection() =>
        ref.read(librarySelectionProvider(route).notifier).begin();
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
            if (compact) ...[
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: LibraryStrings.search,
                onPressed: () => scope.compactSearchOpen.value = true,
              ),
              CompactListingMenu(
                sortEnabled: sortEnabled,
                showViewToggle: showViewToggle,
                onSelect: beginSelection,
              ),
            ] else ...[
              SizedBox(
                width: scope.sizeClass == LibrarySizeClass.expanded
                    ? LibraryMetrics.searchFieldWidthExpanded
                    : LibraryMetrics.searchFieldWidthMedium,
                child: searchField,
              ),
              const SizedBox(width: 8),
              SortMenuButton(enabled: sortEnabled),
              if (showViewToggle) const ViewModeButton(),
              const SizedBox(width: 4),
              TextButton(
                onPressed: beginSelection,
                child: const Text(LibraryStrings.select),
              ),
            ],
            if (section is! TrashSection) ...[
              const SizedBox(width: 8),
              NewMenuButton(section: section, sizeClass: scope.sizeClass),
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
