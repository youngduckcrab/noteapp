// lib/src/ui/content/folder_tile.dart — 05-library 6.8: a folder in the
// grid. The folder picture in the cover place, then `[name 2 lines][⋯]` and
// '폴더'. The ⋯ menu comes with L13, selection with L14, drag / drop with L15.
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show Folder;

import '../../l10n/library_strings.dart';
import '../layout/grid_metrics.dart';
import '../layout/library_metrics.dart';
import '../library_scope.dart';
import 'tile_parts.dart';

class FolderTile extends StatelessWidget {
  const FolderTile({super.key, required this.folder, required this.metrics});

  final Folder folder;
  final GridMetrics metrics;

  @override
  Widget build(BuildContext context) {
    void open() => LibraryScope.read(context).openFolder(folder.id);
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
                excludeSemantics: true,
                onTap: open,
                child: InkWell(
                  onTap: open,
                  borderRadius: TileCoverBox.radius,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TileCoverBox(
                        width: metrics.tileWidth,
                        height: metrics.coverHeight,
                        child: FolderPicture(folder: folder, iconSize: 56),
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
            // L13: the ⋯ menu (44 × 44) at the end of the name row.
          ],
        ),
      ),
    );
  }
}
