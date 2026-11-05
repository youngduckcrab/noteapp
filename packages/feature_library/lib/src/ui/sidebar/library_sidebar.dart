// lib/src/ui/sidebar/library_sidebar.dart — 05-library 6.5. Layout frame of
// the sidebar (task L8): app name row, the body, settings row. The nav rows,
// the folder tree, the trash count and the sync status come with L9.
import 'package:material_ui/material_ui.dart';

import '../../l10n/library_strings.dart';
import '../layout/library_metrics.dart';
import '../library_scope.dart';

class LibrarySidebar extends StatelessWidget {
  const LibrarySidebar({super.key, this.inDrawer = false});

  /// Shown in the Scaffold drawer (medium / compact) instead of pinned.
  final bool inDrawer;

  @override
  Widget build(BuildContext context) {
    final scope = LibraryScope.of(context);
    final theme = Theme.of(context);
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
        // L9: 홈 · 최근 · 즐겨찾기 · '폴더' header · tree · 휴지통.
        const Expanded(child: SizedBox.shrink()),
        const Divider(height: 1),
        SizedBox(
          height: LibraryMetrics.sidebarEdgeRowHeight,
          child: Row(
            children: [
              // L9: SyncBadgeIndicator.
              const Spacer(),
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
