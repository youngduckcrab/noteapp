// lib/src/ui/top_bar/breadcrumb_bar.dart — 05-library 6.6: the path of a
// folder section in the top bar, compressed to 4 / 3 / 2 places by size
// class; the hidden part opens from '…'. Drop targets (crumbs, '…' and its
// menu items, 700 ms hover) come with L15.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show FolderId, folderTreeProvider;

import '../../l10n/library_strings.dart';
import '../../model/breadcrumb.dart';
import '../layout/library_metrics.dart';
import '../layout/size_class.dart';
import '../library_scope.dart';

class BreadcrumbBar extends ConsumerWidget {
  const BreadcrumbBar({super.key, required this.folderId});

  /// The folder of the shown FolderSection (null = 홈).
  final FolderId? folderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = LibraryScope.of(context);
    final List<BreadcrumbItem> path;
    final id = folderId;
    if (id == null) {
      path = const [BreadcrumbItem(folderId: null, label: LibraryStrings.home)];
    } else {
      final tree = ref.watch(folderTreeProvider).value;
      if (tree == null) return const SizedBox.shrink();
      path = breadcrumbPath(tree, id);
    }
    final slots = compressBreadcrumb(
      path,
      maxVisible: breadcrumbMaxVisibleFor(scope.sizeClass),
    );
    final separatorColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      children: [
        for (var i = 0; i < slots.length; i++) ...[
          if (i > 0)
            ExcludeSemantics(
              child: Icon(Icons.chevron_right, size: 18, color: separatorColor),
            ),
          switch (slots[i]) {
            BreadcrumbCrumb(:final item, isCurrent: true) => Flexible(
              child: _CurrentCrumb(item: item),
            ),
            BreadcrumbCrumb(:final item) => Flexible(child: _Crumb(item: item)),
            BreadcrumbOverflow(:final hidden) => _HiddenPathButton(
              hidden: hidden,
            ),
          },
        ],
      ],
    );
  }
}

/// The current folder: bold, not tappable.
class _CurrentCrumb extends StatelessWidget {
  const _CurrentCrumb({required this.item});

  final BreadcrumbItem item;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: LibraryMetrics.breadcrumbCrumbMaxWidth,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          item.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// An ancestor: tap → that folder (6.4).
class _Crumb extends StatelessWidget {
  const _Crumb({required this.item});

  final BreadcrumbItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: LibraryMetrics.breadcrumbCrumbMaxWidth,
      ),
      child: TextButton(
        onPressed: () => LibraryScope.read(context).openFolder(item.folderId),
        style: TextButton.styleFrom(
          minimumSize: const Size(
            LibraryMetrics.minTapTarget,
            LibraryMetrics.minTapTarget,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          foregroundColor: theme.colorScheme.onSurfaceVariant,
          textStyle: theme.textTheme.titleMedium,
        ),
        child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// '…': a menu of the hidden folders, top → down.
class _HiddenPathButton extends StatelessWidget {
  const _HiddenPathButton({required this.hidden});

  final List<BreadcrumbItem> hidden;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final item in hidden)
          MenuItemButton(
            onPressed: () =>
                LibraryScope.read(context).openFolder(item.folderId),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: LibraryMetrics.breadcrumbCrumbMaxWidth,
              ),
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
      builder: (context, controller, _) => IconButton(
        icon: const Icon(Icons.more_horiz),
        tooltip: LibraryStrings.hiddenPath,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
