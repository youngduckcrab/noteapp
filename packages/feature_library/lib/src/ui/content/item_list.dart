// lib/src/ui/content/item_list.dart — 05-library 6.8: the list view of one
// LibraryContent (rows of 64, folders first). The ⋯ menu comes with L13,
// selection checkboxes with L14, drag / drop with L15.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show Folder, Note, clockProvider;

import '../../l10n/library_date_format.dart';
import '../../l10n/library_strings.dart';
import '../../model/content.dart';
import '../../model/item_key.dart';
import '../../state/library_actions.dart';
import '../../state/providers.dart';
import '../feedback/library_snack_bar.dart';
import '../layout/library_metrics.dart';
import '../library_scope.dart';
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

/// `[cover 40×52][16][title / meta]` — the tappable part of a row.
class _RowMain extends StatelessWidget {
  const _RowMain({
    required this.semanticsLabel,
    required this.onTap,
    required this.leading,
    required this.title,
    required this.meta,
  });

  final String semanticsLabel;
  final VoidCallback onTap;
  final Widget leading;
  final String title;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      button: true,
      label: semanticsLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 16),
          child: Row(
            children: [
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

  Future<void> _toggleFavorite(BuildContext context, WidgetRef ref) async {
    final scope = LibraryScope.read(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final outcome = await ref.read(libraryActionsProvider).setFavorite([
      note.id,
    ], !note.isFavorite);
    if (outcome case ActionFailure(:final kind) when messenger != null) {
      showLibrarySnackBarOn(
        messenger,
        message: libraryFailureMessage(kind),
        sizeClass: scope.sizeClass,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final date = formatLibraryDate(
      note.updatedAt,
      now: ref.watch(clockProvider).now(),
    );
    return Row(
      children: [
        Expanded(
          child: _RowMain(
            semanticsLabel: LibraryStrings.noteSemantics(note.title, date),
            onTap: () => openLibraryNote(context, note),
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
          onPressed: () => _toggleFavorite(context, ref),
        ),
        // L13: the ⋯ menu (44 × 44).
        const SizedBox(width: LibraryMetrics.minTapTarget + 8),
      ],
    );
  }
}

/// `[folder icon 32 in 40×52][16][name / '폴더'][⋯ 44]`.
class FolderListRow extends StatelessWidget {
  const FolderListRow({super.key, required this.folder});

  final Folder folder;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _RowMain(
            semanticsLabel: LibraryStrings.folderSemantics(folder.name),
            onTap: () => LibraryScope.read(context).openFolder(folder.id),
            leading: FolderPicture(
              folder: folder,
              iconSize: 32,
              background: false,
            ),
            title: folder.name,
            meta: LibraryStrings.folders,
          ),
        ),
        // L13: the ⋯ menu (44 × 44).
        const SizedBox(width: LibraryMetrics.minTapTarget + 8),
      ],
    );
  }
}
