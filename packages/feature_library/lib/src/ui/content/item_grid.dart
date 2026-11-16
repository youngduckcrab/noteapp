// lib/src/ui/content/item_grid.dart — 05-library 6.2 / 6.7: the grid view of
// one LibraryContent (folders first, then notes), built lazily (6.21). It
// scrolls by itself near its edges during a drag (6.10.4). (v2.14-ui, UI
// stage 1) No dashed '새 노트' first cell any more: notes are made with
// '새로 만들기' (and the empty state's button).
import 'package:material_ui/material_ui.dart';

import '../../dnd/library_drag_scope.dart';
import '../../model/content.dart';
import '../../model/item_key.dart';
import '../layout/grid_metrics.dart';
import '../library_scope.dart';
import 'folder_tile.dart';
import 'note_meta.dart';
import 'note_tile.dart';

class ItemGrid extends StatefulWidget {
  const ItemGrid({super.key, required this.content});

  final LibraryContent content;

  @override
  State<ItemGrid> createState() => _ItemGridState();
}

class _ItemGridState extends State<ItemGrid> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    final sizeClass = LibraryScope.of(context).sizeClass;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final folders = content.folders;
    final notes = content.notes;
    final indexOf = {for (final (i, k) in content.orderedKeys.indexed) k: i};
    final metaStyle = NoteMetaStyle.of(content.section);
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = GridMetrics.forWidth(
          constraints.maxWidth,
          sizeClass: sizeClass,
          textScale: textScale,
        );
        return AutoScrollRegion(
          controller: _controller,
          child: CustomScrollView(
            controller: _controller,
            slivers: [
              SliverPadding(
                padding: EdgeInsets.all(metrics.padding),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: metrics.columns,
                    mainAxisSpacing: metrics.gap,
                    crossAxisSpacing: metrics.gap,
                    mainAxisExtent: metrics.tileHeight,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final i = index;
                      if (i < folders.length) {
                        final folder = folders[i];
                        return FolderTile(
                          key: ValueKey<LibraryItemKey>(folderKey(folder.id)),
                          folder: folder,
                          metrics: metrics,
                        );
                      }
                      final note = notes[i - folders.length];
                      return NoteTile(
                        key: ValueKey<LibraryItemKey>(noteKey(note.id)),
                        note: note,
                        metrics: metrics,
                        metaStyle: metaStyle,
                      );
                    },
                    childCount: folders.length + notes.length,
                    // Tiles keep their state when other items come and go.
                    findChildIndexCallback: (key) => switch (key) {
                      ValueKey<LibraryItemKey>(:final value) => indexOf[value],
                      _ => null,
                    },
                    // Tiles have their own RepaintBoundary.
                    addRepaintBoundaries: false,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
