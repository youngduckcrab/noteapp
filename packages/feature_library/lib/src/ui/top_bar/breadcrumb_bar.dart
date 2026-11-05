// lib/src/ui/top_bar/breadcrumb_bar.dart — 05-library 6.6: the path of a
// folder section in the top bar, compressed to 4 / 3 / 2 places by size
// class; the hidden part opens from '…'. Ancestor crumbs and the items of
// the hidden path menu are drop targets (into that folder, 6.10.2); a drag
// that stays 700 ms on '…' opens the menu.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show FolderId, folderTreeProvider;

import '../../dnd/drop_decision.dart';
import '../../dnd/library_drop_zone.dart';
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

/// primaryContainer behind a crumb / menu item that a drop would go into.
const BorderRadius _dropRadius = BorderRadius.all(Radius.circular(8));

Widget _dropHighlight(BuildContext context, bool on, Widget child) =>
    DecoratedBox(
      decoration: BoxDecoration(
        color: on ? Theme.of(context).colorScheme.primaryContainer : null,
        borderRadius: _dropRadius,
      ),
      child: child,
    );

/// An ancestor: tap → that folder (6.4); a drop target (into it).
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
      child: LibraryDropZone(
        target: FolderDropTarget(item.folderId),
        builder: (context, decision) => _dropHighlight(
          context,
          decision != null,
          TextButton(
            onPressed: () =>
                LibraryScope.read(context).openFolder(item.folderId),
            style: TextButton.styleFrom(
              minimumSize: const Size(
                LibraryMetrics.minTapTarget,
                LibraryMetrics.minTapTarget,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: theme.colorScheme.onSurfaceVariant,
              textStyle: theme.textTheme.titleMedium,
            ),
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

/// '…': a menu of the hidden folders, top → down. A drag that stays 700 ms
/// on it opens the menu; its items are drop targets.
class _HiddenPathButton extends StatefulWidget {
  const _HiddenPathButton({required this.hidden});

  final List<BreadcrumbItem> hidden;

  @override
  State<_HiddenPathButton> createState() => _HiddenPathButtonState();
}

class _HiddenPathButtonState extends State<_HiddenPathButton> {
  final MenuController _controller = MenuController();

  void _close() {
    if (_controller.isOpen) _controller.close();
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _controller,
      menuChildren: [
        for (final item in widget.hidden)
          LibraryDropZone(
            target: FolderDropTarget(item.folderId),
            onDropped: _close,
            // The menu item's context is gone once the menu closes: the
            // button's own context opens the folder.
            builder: (zoneContext, decision) => _dropHighlight(
              zoneContext,
              decision != null,
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
            ),
          ),
      ],
      child: LibraryDropZone(
        target: null,
        holdNeedsDrop: false,
        onHold: () {
          if (!_controller.isOpen) _controller.open();
        },
        builder: (context, _) => IconButton(
          icon: const Icon(Icons.more_horiz),
          tooltip: LibraryStrings.hiddenPath,
          onPressed: () =>
              _controller.isOpen ? _controller.close() : _controller.open(),
        ),
      ),
    );
  }
}
