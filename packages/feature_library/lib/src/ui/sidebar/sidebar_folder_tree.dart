// lib/src/ui/sidebar/sidebar_folder_tree.dart — 05-library 6.5: the folder
// tree of the sidebar (scrolls in the height left between the '폴더' header
// and 휴지통).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show FolderId, folderTreeProvider;

import '../../common/report_error.dart';
import '../../l10n/library_strings.dart';
import '../../model/section.dart';
import '../../state/providers.dart';
import '../layout/library_metrics.dart';
import '../library_scope.dart';
import 'sidebar_rows.dart';

class SidebarFolderTree extends ConsumerWidget {
  const SidebarFolderTree({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = LibraryScope.of(context);
    final rows = ref.watch(sidebarRowsProvider);
    if (rows.hasError) {
      reportLibraryErrorOnce(
        ProviderScope.containerOf(context, listen: false),
        rows.error!,
        rows.stackTrace,
        'library sidebar: folderTreeProvider',
      );
      return _TreeLoadError(onRetry: () => ref.invalidate(folderTreeProvider));
    }
    final visible = rows.value;
    if (visible == null) return const SizedBox.shrink();
    final section = ref.watch(librarySectionProvider(scope.routeFolderId));
    final FolderId? selectedId = switch (section) {
      FolderSection(:final folderId) => folderId,
      _ => null,
    };
    return ListView.builder(
      itemExtent: LibraryMetrics.treeRowHeight,
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final row = visible[index];
        final id = row.folder.id;
        return SidebarTreeRow(
          key: ValueKey<FolderId>(id),
          row: row,
          selected: id == selectedId,
          onOpen: () => LibraryScope.read(context).openFolder(id),
          onToggle: () => ref.read(folderExpansionProvider.notifier).toggle(id),
        );
      },
    );
  }
}

/// 6.19: '불러오지 못했어요' + [다시 시도] in the tree area.
class _TreeLoadError extends StatelessWidget {
  const _TreeLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LibraryStrings.loadFailed,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: onRetry,
            child: const Text(LibraryStrings.retry),
          ),
        ],
      ),
    );
  }
}
