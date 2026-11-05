// lib/src/ui/content/item_grid.dart — 05-library 6.2 / 6.7: the grid view of
// one LibraryContent (folders first, then notes), built lazily (6.21). It
// scrolls by itself near its edges during a drag (6.10.4).
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show FolderId;

import '../../dnd/library_drag_scope.dart';
import '../../model/content.dart';
import '../../model/item_key.dart';
import '../layout/grid_metrics.dart';
import '../library_scope.dart';
import 'folder_tile.dart';
import 'new_note_tile.dart';
import 'note_tile.dart';

class ItemGrid extends StatefulWidget {
  const ItemGrid({
    super.key,
    required this.content,
    this.newNoteFolder,
    this.showNewNoteTile = false,
  });

  final LibraryContent content;

  /// With [showNewNoteTile]: the first cell is the '새 노트' tile for this
  /// folder (null = 홈).
  final FolderId? newNoteFolder;
  final bool showNewNoteTile;

  @override
  State<ItemGrid> createState() => _ItemGridState();
}

const ValueKey<String> _newNoteKey = ValueKey<String>('new-note');

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
    final showNewNoteTile = widget.showNewNoteTile;
    final sizeClass = LibraryScope.of(context).sizeClass;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final folders = content.folders;
    final notes = content.notes;
    final lead = showNewNoteTile ? 1 : 0;
    final indexOf = {
      for (final (i, k) in content.orderedKeys.indexed) k: i + lead,
    };
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
                      if (index < lead) {
                        return NewNoteTile(
                          key: _newNoteKey,
                          folderId: widget.newNoteFolder,
                          metrics: metrics,
                        );
                      }
                      final i = index - lead;
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
                      );
                    },
                    childCount: lead + folders.length + notes.length,
                    // Tiles keep their state when the '새 노트' tile or other
                    // items come and go (a drag starting selection mode).
                    findChildIndexCallback: (key) => switch (key) {
                      ValueKey<LibraryItemKey>(:final value) => indexOf[value],
                      _newNoteKey => lead == 1 ? 0 : null,
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
