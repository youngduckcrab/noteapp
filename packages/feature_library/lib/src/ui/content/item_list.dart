// lib/src/ui/content/item_list.dart — 05-library 6.8: the list view of one
// LibraryContent (rows of 64, folders first). In selection mode rows show a
// leading checkbox and no ⋯ (6.8 / 6.9); drag / drop comes with L15.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show Folder, Note, clockProvider;

import '../../l10n/library_date_format.dart';
import '../../l10n/library_strings.dart';
import '../../model/content.dart';
import '../../model/item_key.dart';
import '../layout/library_metrics.dart';
import '../library_scope.dart';
import '../menus/item_action_flows.dart';
import '../menus/item_context_menu.dart';
import 'note_cover_view.dart';
import 'tile_parts.dart';

class ItemList extends StatelessWidget {
  const ItemList({super.key, required this.content});

  final LibraryContent content;

  @override
  Widget build(BuildContext context) {
    final folders = content.folders;
    final notes = content.notes;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemExtent: LibraryMetrics.listRowHeight,
      itemCount: folders.length + notes.length,
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
        );
      },
    );
  }
}

/// Size of the cover / folder picture box of a list row.
const double _thumbWidth = 40, _thumbHeight = 52;
const BorderRadius _thumbRadius = BorderRadius.all(Radius.circular(4));

/// `[checkbox in selection mode][cover 40×52][16][title / meta]` — the
/// tappable part of a row. In selection mode a tap toggles the item (6.9);
/// a long press starts selection mode with it.
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
  });

  final LibraryItemKey itemKey;

  /// Selection mode, and whether this item is selected.
  final bool active, selected;
  final String semanticsLabel;
  final VoidCallback onOpen;
  final Widget leading;
  final String title;
  final String meta;

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
        onLongPress: onLongPress,
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
                    Text(
                      title,
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

/// `[cover 40×52][16][title / date · n페이지][☆/★ 44][⋯ 44]`.
class NoteListRow extends ConsumerWidget {
  const NoteListRow({super.key, required this.note});

  final Note note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final date = formatLibraryDate(
      note.updatedAt,
      now: ref.watch(clockProvider).now(),
    );
    final key = noteKey(note.id);
    final (:active, :selected) = watchItemSelection(ref, context, key);
    return Row(
      children: [
        Expanded(
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
            meta: note.requiresNewerApp
                ? LibraryStrings.requiresNewerApp
                : LibraryStrings.noteListMeta(date, note.pageCount),
          ),
        ),
        IconButton(
          icon: Icon(
            note.isFavorite ? Icons.star : Icons.star_outline,
            color: note.isFavorite ? scheme.tertiary : scheme.onSurfaceVariant,
          ),
          tooltip: note.isFavorite
              ? LibraryStrings.favoriteRemove
              : LibraryStrings.favoriteAdd,
          onPressed: () => runFavoriteFlow(
            context,
            ids: [note.id],
            favorite: !note.isFavorite,
          ),
        ),
        // No ⋯ in selection mode (6.9); the place stays (alignment).
        if (active)
          const SizedBox(width: LibraryMetrics.minTapTarget)
        else
          ItemMenuButton(note: note),
        const SizedBox(width: 8),
      ],
    );
  }
}

/// `[folder icon 32 in 40×52][16][name / '폴더'][⋯ 44]`.
class FolderListRow extends ConsumerWidget {
  const FolderListRow({super.key, required this.folder});

  final Folder folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = folderKey(folder.id);
    final (:active, :selected) = watchItemSelection(ref, context, key);
    return Row(
      children: [
        Expanded(
          child: _RowMain(
            itemKey: key,
            active: active,
            selected: selected,
            semanticsLabel: LibraryStrings.folderSemantics(folder.name),
            onOpen: () => LibraryScope.read(context).openFolder(folder.id),
            leading: FolderPicture(
              folder: folder,
              iconSize: 32,
              background: false,
            ),
            title: folder.name,
            meta: LibraryStrings.folders,
          ),
        ),
        if (active)
          const SizedBox(width: LibraryMetrics.minTapTarget)
        else
          ItemMenuButton(folder: folder),
        const SizedBox(width: 8),
      ],
    );
  }
}
