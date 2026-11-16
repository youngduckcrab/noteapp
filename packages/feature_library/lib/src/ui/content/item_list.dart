// lib/src/ui/content/item_list.dart — 05-library 6.8: the list view of one
// LibraryContent (rows of 64, folders first). In selection mode rows show a
// leading checkbox and no ⋯ (6.8 / 6.9). Rows are drag sources and drop
// targets (6.10): into a folder row = primaryContainer background, a reorder
// = a bar along the top / bottom edge. The list scrolls by itself near its
// edges during a drag.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show Folder, Note, clockProvider;

import '../../appearance/folder_appearance.dart';
import '../../dnd/drop_decision.dart';
import '../../dnd/library_drag_scope.dart';
import '../../dnd/library_drop_zone.dart';
import '../../l10n/library_date_format.dart';
import '../../l10n/library_strings.dart';
import '../../model/content.dart';
import '../../model/item_key.dart';
import '../layout/library_metrics.dart';
import '../library_scope.dart';
import '../menus/item_action_flows.dart';
import '../menus/item_context_menu.dart';
import 'note_cover_view.dart';
import 'note_meta.dart';
import 'tile_parts.dart';

class ItemList extends StatefulWidget {
  const ItemList({super.key, required this.content});

  final LibraryContent content;

  @override
  State<ItemList> createState() => _ItemListState();
}

class _ItemListState extends State<ItemList> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    final folders = content.folders;
    final notes = content.notes;
    final indexOf = {for (final (i, k) in content.orderedKeys.indexed) k: i};
    final metaStyle = NoteMetaStyle.of(content.section);
    return AutoScrollRegion(
      controller: _controller,
      child: ListView.builder(
        controller: _controller,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemExtent: LibraryMetrics.listRowHeight,
        itemCount: folders.length + notes.length,
        // Rows keep their state when others come and go (a drag in progress).
        findChildIndexCallback: (key) =>
            key is ValueKey<LibraryItemKey> ? indexOf[key.value] : null,
        itemBuilder: (context, index) {
          if (index < folders.length) {
            final folder = folders[index];
            return FolderListRow(
              key: ValueKey<LibraryItemKey>(folderKey(folder.id)),
              folder: folder,
            );
          }
          final note = notes[index - folders.length];
          return NoteListRow(
            key: ValueKey<LibraryItemKey>(noteKey(note.id)),
            note: note,
            metaStyle: metaStyle,
          );
        },
      ),
    );
  }
}

/// A list row with its drop highlight (6.8): into → primaryContainer behind
/// the row, reorder → the insertion bar on the top / bottom edge.
class _RowDropFrame extends StatelessWidget {
  const _RowDropFrame({required this.decision, required this.child});

  final DropDecision? decision;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final decision = this.decision;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (decision is DropInto)
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
          ),
        child,
        if (decision case DropReorder(:final after))
          DropInsertionBar.forRow(after: after),
      ],
    );
  }
}

/// Size of the cover / folder picture box of a list row.
const double _thumbWidth = 40, _thumbHeight = 52;
const BorderRadius _thumbRadius = BorderRadius.all(Radius.circular(4));

/// `[checkbox in selection mode][cover 40×52][16][title / meta]` — the
/// tappable part of a row. In selection mode a tap toggles the item (6.9);
/// a long press starts a drag (selection mode with it, 6.10).
class _RowMain extends StatelessWidget {
  const _RowMain({
    required this.itemKey,
    required this.active,
    required this.selected,
    required this.semanticsLabel,
    required this.onOpen,
    required this.leading,
    required this.title,
    required this.meta,
    this.highlight,
  });

  final LibraryItemKey itemKey;

  /// Selection mode, and whether this item is selected.
  final bool active, selected;
  final String semanticsLabel;
  final VoidCallback onOpen;
  final Widget leading;
  final String title;
  final String meta;

  /// Search query highlighted in [title] (6.14).
  final String? highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void onTap() => active ? toggleItemSelection(context, itemKey) : onOpen();
    void onLongPress() => addItemToSelection(context, itemKey);
    return Semantics(
      container: true,
      button: true,
      label: semanticsLabel,
      selected: active ? selected : null,
      excludeSemantics: true,
      onTap: onTap,
      onLongPress: onLongPress,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsetsDirectional.only(start: active ? 4 : 16),
          child: Row(
            children: [
              // Decorative: the row itself toggles and carries selected.
              if (active)
                IgnorePointer(
                  child: ExcludeSemantics(
                    child: Checkbox(value: selected, onChanged: (_) {}),
                  ),
                ),
              SizedBox(
                width: _thumbWidth,
                height: _thumbHeight,
                child: leading,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      highlightedTitleSpan(context, title, highlight),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge,
                    ),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `[cover 40×52][16][title / meta][☆/★ 44][⋯ 44]` — meta = `date ·
/// n페이지` in folder sections, by section otherwise (6.14).
class NoteListRow extends ConsumerWidget {
  const NoteListRow({
    super.key,
    required this.note,
    this.metaStyle = NoteMetaStyle.modified,
    this.highlight,
  });

  final Note note;
  final NoteMetaStyle metaStyle;

  /// Search query highlighted in the title (6.14).
  final String? highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final date = formatLibraryDate(
      note.updatedAt,
      now: ref.watch(clockProvider).now(),
    );
    final key = noteKey(note.id);
    final (:active, :selected) = watchItemSelection(ref, context, key);
    final main = ContentItemDraggable(
      itemKey: key,
      parentId: note.folderId,
      icon: Icons.description_outlined,
      label: note.title,
      child: _RowMain(
        itemKey: key,
        active: active,
        selected: selected,
        semanticsLabel: LibraryStrings.noteSemantics(note.title, date),
        onOpen: () => openLibraryNote(context, note),
        leading: ClipRRect(
          borderRadius: _thumbRadius,
          child: NoteCoverView(
            note: note,
            width: _thumbWidth,
            height: _thumbHeight,
          ),
        ),
        title: note.title,
        meta: watchNoteMeta(ref, note, metaStyle, listRow: true),
        highlight: highlight,
      ),
    );
    return LibraryDropZone(
      target: TileDropTarget(key: key, axis: Axis.vertical),
      builder: (context, decision) => _RowDropFrame(
        decision: decision,
        child: Row(
          children: [
            Expanded(child: main),
            // (v2.14-ui, UI stage 1) ★ only on a favourite (tap → remove);
            // the other rows keep its place empty (alignment) — 즐겨찾기 is
            // added from the row's ⋯ or the selection bar.
            if (note.isFavorite)
              IconButton(
                icon: Icon(Icons.star, color: scheme.tertiary),
                tooltip: LibraryStrings.favoriteRemove,
                onPressed: () =>
                    runFavoriteFlow(context, ids: [note.id], favorite: false),
              )
            else
              const SizedBox(width: LibraryMetrics.minTapTarget),
            // No ⋯ in selection mode (6.9); the place stays (alignment).
            if (active)
              const SizedBox(width: LibraryMetrics.minTapTarget)
            else
              ItemMenuButton(note: note),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

/// `[folder icon 32 in 40×52][16][name / '폴더'][⋯ 44]`; in search results
/// the meta is the folder's location and the match is highlighted (6.14).
class FolderListRow extends ConsumerWidget {
  const FolderListRow({
    super.key,
    required this.folder,
    this.showLocation = false,
    this.highlight,
  });

  final Folder folder;

  /// Meta = locationLabel of the parent instead of '폴더'.
  final bool showLocation;

  /// Search query highlighted in the name.
  final String? highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = folderKey(folder.id);
    final (:active, :selected) = watchItemSelection(ref, context, key);
    final main = ContentItemDraggable(
      itemKey: key,
      parentId: folder.parentId,
      icon: FolderIcons.iconFor(folder.icon),
      iconColor: folderColorOr(folder.colorArgb, Theme.of(context).colorScheme),
      label: folder.name,
      child: _RowMain(
        itemKey: key,
        active: active,
        selected: selected,
        semanticsLabel: LibraryStrings.folderSemantics(folder.name),
        onOpen: () => LibraryScope.read(context).openFolder(folder.id),
        leading: FolderPicture(folder: folder, iconSize: 32, background: false),
        title: folder.name,
        meta: showLocation
            ? watchLocationLabel(ref, folder.parentId) ?? LibraryStrings.folders
            : LibraryStrings.folders,
        highlight: highlight,
      ),
    );
    return LibraryDropZone(
      target: TileDropTarget(key: key, axis: Axis.vertical),
      builder: (context, decision) => _RowDropFrame(
        decision: decision,
        child: Row(
          children: [
            Expanded(child: main),
            if (active)
              const SizedBox(width: LibraryMetrics.minTapTarget)
            else
              ItemMenuButton(folder: folder),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
