// lib/src/ui/content/note_tile.dart — 05-library 6.8: a note in the grid.
// Cover (width × width / 0.75) with the favorite ★ and the newer-app badge,
// then `[title 2 lines][⋯ 44]` and the meta line (by section, 6.14). In
// selection mode a tap toggles, the cover shows the check mark and the ⋯ is
// hidden (6.9). A long press starts a drag (selection mode with the tile,
// 6.10); in the custom order a drop on the tile reorders (insertion bar in
// the gap).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show Note, clockProvider;
import 'package:ui_kit/ui_kit.dart';

import '../../dnd/drop_decision.dart';
import '../../dnd/library_drop_zone.dart';
import '../../l10n/library_date_format.dart';
import '../../l10n/library_strings.dart';
import '../../model/item_key.dart';
import '../layout/grid_metrics.dart';
import '../layout/library_metrics.dart';
import '../menus/item_context_menu.dart';
import 'note_cover_view.dart';
import 'note_meta.dart';
import 'tile_parts.dart';

class NoteTile extends ConsumerWidget {
  const NoteTile({
    super.key,
    required this.note,
    required this.metrics,
    this.metaStyle = NoteMetaStyle.modified,
    this.highlight,
  });

  final Note note;
  final GridMetrics metrics;

  /// What the meta line says (by section, 6.14).
  final NoteMetaStyle metaStyle;

  /// Search query highlighted in the title (search results, 6.14).
  final String? highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final date = formatLibraryDate(
      note.updatedAt,
      now: ref.watch(clockProvider).now(),
    );
    final newer = note.requiresNewerApp;
    final width = metrics.tileWidth;
    final coverHeight = metrics.coverHeight;
    final key = noteKey(note.id);
    final (:active, :selected) = watchItemSelection(ref, context, key);
    void onTap() => active
        ? toggleItemSelection(context, key)
        : openLibraryNote(context, note);
    void onLongPress() => addItemToSelection(context, key);
    final main = ContentItemDraggable(
      itemKey: key,
      parentId: note.folderId,
      kind: AppIconKind.note,
      label: note.title,
      child: Semantics(
        container: true,
        button: true,
        label: LibraryStrings.noteSemantics(note.title, date),
        selected: active ? selected : null,
        excludeSemantics: true,
        onTap: onTap,
        onLongPress: onLongPress,
        child: InkWell(
          onTap: onTap,
          borderRadius: TileCoverBox.radius,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TileCoverBox(
                width: width,
                height: coverHeight,
                selected: active && selected,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NoteCoverView(
                      note: note,
                      width: width,
                      height: coverHeight,
                    ),
                    if (note.isFavorite)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: CoverCornerBadge(
                          icon: AppIconKind.favoriteOn,
                          color: scheme.tertiary,
                        ),
                      ),
                    // (v2.14-ui, UI stage 1) words, not the 'upgrade' arrow.
                    if (newer)
                      const Positioned(
                        left: 6,
                        bottom: 6,
                        child: CoverCornerLabel(
                          LibraryStrings.requiresNewerAppBadge,
                        ),
                      ),
                    if (active)
                      Positioned(
                        left: 0,
                        top: 0,
                        child: SelectionCheckBadge(selected: selected),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  end: LibraryMetrics.minTapTarget,
                ),
                child: TileFooterText(
                  title: note.title,
                  meta: watchNoteMeta(ref, note, metaStyle, listRow: false),
                  highlight: highlight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return RepaintBoundary(
      child: LibraryDropZone(
        target: TileDropTarget(key: key, axis: Axis.horizontal),
        builder: (context, decision) => SizedBox(
          width: width,
          height: metrics.tileHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: main),
              // No ⋯ in selection mode (6.9).
              if (!active)
                PositionedDirectional(
                  end: 0,
                  top: coverHeight + LibraryMetrics.tileMenuTopGap,
                  child: ItemMenuButton(note: note),
                ),
              if (decision case DropReorder(:final after))
                DropInsertionBar.forTile(after: after, gap: metrics.gap),
            ],
          ),
        ),
      ),
    );
  }
}
