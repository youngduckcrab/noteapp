// lib/src/ui/content/folder_tile.dart — 05-library 6.8: a folder in the
// grid. The folder picture in the cover place, then `[name 2 lines][⋯]` and
// '폴더'. Selection mode as in note_tile.dart (6.9); drag / drop comes with
// L15.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show Folder;

import '../../l10n/library_strings.dart';
import '../../model/item_key.dart';
import '../layout/grid_metrics.dart';
import '../layout/library_metrics.dart';
import '../library_scope.dart';
import '../menus/item_context_menu.dart';
import 'tile_parts.dart';

class FolderTile extends ConsumerWidget {
  const FolderTile({super.key, required this.folder, required this.metrics});

  final Folder folder;
  final GridMetrics metrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = folderKey(folder.id);
    final (:active, :selected) = watchItemSelection(ref, context, key);
    void onTap() => active
        ? toggleItemSelection(context, key)
        : LibraryScope.read(context).openFolder(folder.id);
    void onLongPress() => addItemToSelection(context, key);
    return RepaintBoundary(
      child: SizedBox(
        width: metrics.tileWidth,
        height: metrics.tileHeight,
        child: Stack(
          children: [
            Positioned.fill(
              child: Semantics(
                container: true,
                button: true,
                label: LibraryStrings.folderSemantics(folder.name),
                selected: active ? selected : null,
                excludeSemantics: true,
                onTap: onTap,
                onLongPress: onLongPress,
                child: InkWell(
                  onTap: onTap,
                  onLongPress: onLongPress,
                  borderRadius: TileCoverBox.radius,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TileCoverBox(
                        width: metrics.tileWidth,
                        height: metrics.coverHeight,
                        selected: active && selected,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            FolderPicture(folder: folder, iconSize: 56),
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
                          title: folder.name,
                          meta: LibraryStrings.folders,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // No ⋯ in selection mode (6.9).
            if (!active)
              PositionedDirectional(
                end: 0,
                top: metrics.coverHeight + LibraryMetrics.tileMenuTopGap,
                child: ItemMenuButton(folder: folder),
              ),
          ],
        ),
      ),
    );
  }
}
