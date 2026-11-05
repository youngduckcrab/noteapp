// lib/src/ui/content/search_results_view.dart — 05-library 6.14: the results
// of a title search (the whole library). '폴더 (n)' — list rows with the
// location; '노트 (n)' — the grid or the list (view setting) with the
// location as meta. An empty group is not shown; results cut at the search
// limit end with a hint. The query is highlighted in names / titles. Rows and
// tiles are the listing's own (⋯, selection, drag and drop all work).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../dnd/library_drag_scope.dart';
import '../../l10n/library_strings.dart';
import '../../model/content.dart';
import '../../model/item_key.dart';
import '../../model/section.dart';
import '../../model/view_prefs.dart';
import '../../state/providers.dart';
import '../layout/grid_metrics.dart';
import '../layout/library_metrics.dart';
import '../library_scope.dart';
import 'item_list.dart';
import 'note_meta.dart';
import 'note_tile.dart';

class SearchResultsView extends ConsumerStatefulWidget {
  const SearchResultsView({super.key, required this.content});

  /// Content of a SearchSection, not empty.
  final LibraryContent content;

  @override
  ConsumerState<SearchResultsView> createState() => _SearchResultsViewState();
}

class _SearchResultsViewState extends ConsumerState<SearchResultsView> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    final query = (content.section as SearchSection).query;
    final folders = content.folders;
    final notes = content.notes;
    final sizeClass = LibraryScope.of(context).sizeClass;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final grid =
        ref.watch(libraryPrefsProvider.select((p) => p.viewMode)) ==
        LibraryViewMode.grid;
    final folderIndex = {
      for (final (i, f) in folders.indexed) folderKey(f.id): i,
    };
    final noteIndex = {for (final (i, n) in notes.indexed) noteKey(n.id): i};
    int? indexIn(Map<LibraryItemKey, int> index, Key key) =>
        key is ValueKey<LibraryItemKey> ? index[key.value] : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = GridMetrics.forWidth(
          constraints.maxWidth,
          sizeClass: sizeClass,
          textScale: textScale,
        );
        final side = metrics.padding;
        return AutoScrollRegion(
          controller: _controller,
          child: CustomScrollView(
            controller: _controller,
            slivers: [
              if (folders.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: SearchGroupHeader(
                    label: LibraryStrings.searchFolderGroup(folders.length),
                    side: side,
                  ),
                ),
                SliverFixedExtentList(
                  itemExtent: LibraryMetrics.listRowHeight,
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => FolderListRow(
                      key: ValueKey<LibraryItemKey>(folderKey(folders[i].id)),
                      folder: folders[i],
                      showLocation: true,
                      highlight: query,
                    ),
                    childCount: folders.length,
                    findChildIndexCallback: (key) => indexIn(folderIndex, key),
                  ),
                ),
              ],
              if (notes.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: SearchGroupHeader(
                    label: LibraryStrings.searchNoteGroup(notes.length),
                    side: side,
                  ),
                ),
                if (grid)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(side, 0, side, side),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: metrics.columns,
                        mainAxisSpacing: metrics.gap,
                        crossAxisSpacing: metrics.gap,
                        mainAxisExtent: metrics.tileHeight,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => NoteTile(
                          key: ValueKey<LibraryItemKey>(noteKey(notes[i].id)),
                          note: notes[i],
                          metrics: metrics,
                          metaStyle: NoteMetaStyle.location,
                          highlight: query,
                        ),
                        childCount: notes.length,
                        findChildIndexCallback: (key) =>
                            indexIn(noteIndex, key),
                        // Tiles have their own RepaintBoundary.
                        addRepaintBoundaries: false,
                      ),
                    ),
                  )
                else
                  SliverFixedExtentList(
                    itemExtent: LibraryMetrics.listRowHeight,
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => NoteListRow(
                        key: ValueKey<LibraryItemKey>(noteKey(notes[i].id)),
                        note: notes[i],
                        metaStyle: NoteMetaStyle.location,
                        highlight: query,
                      ),
                      childCount: notes.length,
                      findChildIndexCallback: (key) => indexIn(noteIndex, key),
                    ),
                  ),
              ],
              if (content.truncated)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(side, 8, side, 24),
                    child: Text(
                      LibraryStrings.searchTruncated,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
            ],
          ),
        );
      },
    );
  }
}

/// '폴더 (n)' / '노트 (n)' above a result group (a semantics header).
class SearchGroupHeader extends StatelessWidget {
  const SearchGroupHeader({super.key, required this.label, required this.side});

  final String label;

  /// Left / right padding (the grid padding).
  final double side;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(side, 16, side, 8),
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
