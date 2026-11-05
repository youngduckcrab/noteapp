// lib/src/ui/sidebar/sidebar_folder_tree.dart — 05-library 6.5: the folder
// tree of the sidebar (scrolls in the height left between the '폴더' header
// and 휴지통). Every row has the tree row menu (6.5: long press released
// without moving, or a secondary click), is a drag source (that folder
// alone, 6.10.1) and a drop target (into the folder; a collapsed row with
// children expands after 700 ms with a possible drop, 6.10.4). The list
// scrolls by itself near its edges during a drag.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show FolderId, folderTreeProvider;

import '../../appearance/folder_appearance.dart';
import '../../common/report_error.dart';
import '../../dnd/drag_payload.dart';
import '../../dnd/drop_decision.dart';
import '../../dnd/library_drag_scope.dart';
import '../../dnd/library_draggable.dart';
import '../../dnd/library_drop_zone.dart';
import '../../l10n/library_strings.dart';
import '../../model/item_key.dart';
import '../../model/section.dart';
import '../../model/tree_rows.dart';
import '../../state/providers.dart';
import '../content/tile_parts.dart' show folderColorOr;
import '../layout/library_metrics.dart';
import '../library_scope.dart';
import '../menus/item_context_menu.dart';
import 'sidebar_rows.dart';

class SidebarFolderTree extends ConsumerStatefulWidget {
  const SidebarFolderTree({super.key});

  @override
  ConsumerState<SidebarFolderTree> createState() => _SidebarFolderTreeState();
}

class _SidebarFolderTreeState extends ConsumerState<SidebarFolderTree> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
    final indexOf = {for (final (i, row) in visible.indexed) row.folder.id: i};
    return AutoScrollRegion(
      controller: _controller,
      child: ListView.builder(
        controller: _controller,
        itemExtent: LibraryMetrics.treeRowHeight,
        itemCount: visible.length,
        // Rows keep their state when rows above them come and go (a dragged
        // row while a folder auto-expands).
        findChildIndexCallback: (key) =>
            key is ValueKey<FolderId> ? indexOf[key.value] : null,
        itemBuilder: (context, index) {
          final row = visible[index];
          return _TreeItem(
            key: ValueKey<FolderId>(row.folder.id),
            row: row,
            selected: row.folder.id == selectedId,
          );
        },
      ),
    );
  }
}

/// One tree row with its menu, drag and drop.
class _TreeItem extends ConsumerWidget {
  const _TreeItem({super.key, required this.row, required this.selected});

  final FolderTreeRow row;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folder = row.folder;
    final id = folder.id;
    final key = folderKey(id);
    final collapsed = row.hasChildren && !row.isExpanded;
    return SidebarRowMenu(
      folder: folder,
      builder: (context, openMenu) => LibraryDropZone(
        target: FolderDropTarget(id),
        onHold: collapsed
            ? () => ref.read(folderExpansionProvider.notifier).expand(id)
            : null,
        builder: (context, decision) => LibraryDraggable(
          payloadBuilder: () => LibraryDragPayload(
            items: [key],
            parents: {key: folder.parentId},
            source: LibraryDragSource.sidebar,
          ),
          feedbackBuilder: (payload) => LibraryDragFeedback(
            payload: payload,
            icon: FolderIcons.iconFor(folder.icon),
            iconColor: folderColorOr(
              folder.colorArgb,
              Theme.of(context).colorScheme,
            ),
            label: folder.name,
          ),
          onLongPressReleased: openMenu,
          child: SidebarTreeRow(
            row: row,
            selected: selected,
            drop: decision != null
                ? SidebarDropLook.folder
                : SidebarDropLook.none,
            onOpen: () => LibraryScope.read(context).openFolder(id),
            onToggle: () =>
                ref.read(folderExpansionProvider.notifier).toggle(id),
          ),
        ),
      ),
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
