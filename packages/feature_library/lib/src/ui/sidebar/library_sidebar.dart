// lib/src/ui/sidebar/library_sidebar.dart — 05-library 6.5. Top → bottom:
// app name row (56) · 홈 · 최근 · 즐겨찾기 · '폴더' header · folder tree (the
// height left, scrolls) · divider · 휴지통 (count) · sync status + settings
// button row (56). The same widget is pinned (expanded class) or lives in the
// drawer.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/library_strings.dart';
import '../../model/section.dart';
import '../../state/providers.dart';
import '../../state/section_notifier.dart';
import '../dialogs/create_flows.dart';
import '../layout/library_metrics.dart';
import '../library_scope.dart';
import 'sidebar_folder_tree.dart';
import 'sidebar_rows.dart';
import 'sync_badge_indicator.dart';

class LibrarySidebar extends ConsumerWidget {
  const LibrarySidebar({super.key, this.inDrawer = false});

  /// Shown in the Scaffold drawer (medium / compact) instead of pinned.
  final bool inDrawer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = LibraryScope.of(context);
    final theme = Theme.of(context);
    final section = ref.watch(librarySectionProvider(scope.routeFolderId));
    final trashCount = ref.watch(trashCountProvider);

    /// 최근 / 즐겨찾기 / 휴지통: the drawer closes first; the address stays.
    void show(void Function(LibrarySectionNotifier section) change) {
      final current = LibraryScope.read(context);
      current.closeDrawer();
      change(ref.read(librarySectionProvider(current.routeFolderId).notifier));
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: LibraryMetrics.sidebarEdgeRowHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                LibraryStrings.appTitle,
                style: theme.textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        SidebarNavRow(
          icon: Icons.home_outlined,
          label: LibraryStrings.home,
          selected: section == const FolderSection(null),
          onTap: () => LibraryScope.read(context).openFolder(null),
        ),
        SidebarNavRow(
          icon: Icons.schedule,
          label: LibraryStrings.recent,
          selected: section is RecentSection,
          onTap: () => show((s) => s.showRecent()),
        ),
        SidebarNavRow(
          icon: Icons.star_outline,
          label: LibraryStrings.favorites,
          selected: section is FavoritesSection,
          onTap: () => show((s) => s.showFavorites()),
        ),
        // '폴더' header + '+' (new folder): into the current folder section's
        // folder, else 홈 (6.5).
        SizedBox(
          height: LibraryMetrics.navRowHeight,
          child: Row(
            children: [
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  LibraryStrings.folders,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: LibraryStrings.newFolder,
                onPressed: () => runNewFolderFlow(
                  context,
                  parentId: switch (section) {
                    FolderSection(:final folderId) => folderId,
                    _ => null,
                  },
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
        const Expanded(child: SidebarFolderTree()),
        const Divider(height: 1),
        SidebarNavRow(
          icon: Icons.delete_outline,
          label: LibraryStrings.trash,
          selected: section is TrashSection,
          count: trashCount,
          onTap: () => show((s) => s.showTrash()),
        ),
        SizedBox(
          height: LibraryMetrics.sidebarEdgeRowHeight,
          child: Row(
            children: [
              const SizedBox(width: 4),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SyncBadgeIndicator(onTap: scope.openSettings),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: LibraryStrings.settings,
                onPressed: scope.openSettings,
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ],
    );
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: inDrawer
          ? SafeArea(child: body)
          : SizedBox(width: LibraryMetrics.sidebarWidth, child: body),
    );
  }
}
