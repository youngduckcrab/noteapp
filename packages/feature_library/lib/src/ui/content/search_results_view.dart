// lib/src/ui/content/search_results_view.dart — 05-library 6.14: the results
// of a title search (the whole library). '폴더 (n)' — list rows with the
// location; '노트 (n)' — the grid or the list (view setting) with the
// location as meta. An empty group is not shown; results cut at the search
// limit end with a hint. The query is highlighted in names / titles. Rows and
// tiles are the listing's own (⋯, selection, drag and drop all work).
// (v2) '노트 내용 (n)' — the content hits grouped by note (6.1.3,
// content_hits_view.dart); while CORE is asked again the previous rows, the
// scroll position and the expanded notes stay, with a small progress mark in
// the group header (6.1.6).
import 'package:collection/collection.dart' show SetEquality;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show Note, NoteId, PageSearchHit;

import '../../dnd/library_drag_scope.dart';
import '../../l10n/library_strings.dart';
import '../../model/content.dart';
import '../../model/content_hits.dart';
import '../../model/item_key.dart';
import '../../model/section.dart';
import '../../model/view_prefs.dart';
import '../../state/providers.dart';
import '../layout/grid_metrics.dart';
import '../layout/library_metrics.dart';
import '../library_scope.dart';
import 'content_hits_view.dart';
import 'ink_search_hint.dart';
import 'item_list.dart';
import 'note_meta.dart';
import 'note_tile.dart';
import 'tile_parts.dart';

class SearchResultsView extends ConsumerStatefulWidget {
  const SearchResultsView({
    super.key,
    required this.content,
    this.refreshing = false,
  });

  /// Content of a SearchSection, not empty.
  final LibraryContent content;

  /// (v2) CORE is being asked again; [content] is the previous result.
  final bool refreshing;

  @override
  ConsumerState<SearchResultsView> createState() => _SearchResultsViewState();
}

class _SearchResultsViewState extends ConsumerState<SearchResultsView> {
  final ScrollController _controller = ScrollController();

  /// (v2) Notes whose content hits are all shown; cleared when the query
  /// changes, notes that left the results are dropped.
  final Set<NoteId> _expanded = {};
  List<ContentHitGroup>? _flatGroups;
  Set<NoteId>? _flatExpanded;
  List<ContentEntry> _flat = const [];

  String get _query => (widget.content.section as SearchSection).query;

  @override
  void didUpdateWidget(SearchResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldQuery = (oldWidget.content.section as SearchSection).query;
    if (oldQuery != _query) {
      _expanded.clear();
    } else {
      final present = {for (final g in widget.content.contentGroups) g.noteId};
      _expanded.retainAll(present);
    }
  }

  /// The flattened content group, cached per (groups, expanded).
  List<ContentEntry> _entries(List<ContentHitGroup> groups) {
    if (!identical(groups, _flatGroups) ||
        !const SetEquality<NoteId>().equals(_flatExpanded, _expanded)) {
      _flatGroups = groups;
      _flatExpanded = {..._expanded};
      _flat = flattenContentGroups(groups, _expanded);
    }
    return _flat;
  }

  void _expand(NoteId noteId) => setState(() => _expanded.add(noteId));

  /// 6.1.4: a content hit opens its note at the hit — page + the union of
  /// its rects (null without rects). A note this app cannot open yet gets the
  /// 1차 notice instead.
  void _openHit(Note note, PageSearchHit hit) {
    if (note.requiresNewerApp) {
      openLibraryNote(context, note);
      return;
    }
    LibraryScope.read(context)
        .openNoteAt(note.id, hit.pageId, focusRectOf(hit));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    final query = _query;
    final folders = content.folders;
    final notes = content.notes;
    final contentGroups = content.contentGroups;
    final entries = _entries(contentGroups);
    final contentCount = contentGroups.fold(0, (n, g) => n + g.hits.length);
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
              // (handwriting search, 6.19a) why handwriting may be missing.
              SliverToBoxAdapter(
                child: InkSearchHint(
                  padding: EdgeInsets.fromLTRB(side, 12, side, 0),
                ),
              ),
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
              if (contentGroups.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: SearchGroupHeader(
                    label: LibraryStrings.searchContentGroup(contentCount),
                    side: side,
                    busy: widget.refreshing,
                  ),
                ),
                SliverList.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) => switch (entries[i]) {
                    ContentHeaderEntry(:final noteId) => ContentNoteHeader(
                      key: ValueKey<ContentEntry>(entries[i]),
                      noteId: noteId,
                      query: query,
                      side: side,
                    ),
                    ContentHitEntry(:final hit) => ContentHitRow(
                      key: ValueKey<ContentEntry>(entries[i]),
                      hit: hit,
                      side: side,
                      onOpen: _openHit,
                    ),
                    ContentMoreEntry(:final noteId, :final hidden) =>
                      ContentMoreRow(
                        key: ValueKey<ContentEntry>(entries[i]),
                        noteId: noteId,
                        hidden: hidden,
                        side: side,
                        onExpand: () => _expand(noteId),
                      ),
                  },
                ),
                if (content.contentTruncated)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(side, 8, side, 24),
                      child: Text(
                        LibraryStrings.contentTruncated,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
            ],
          ),
        );
      },
    );
  }
}

/// '폴더 (n)' / '노트 (n)' / (v2) '노트 내용 (n)' above a result group (a
/// semantics header).
class SearchGroupHeader extends StatelessWidget {
  const SearchGroupHeader({
    super.key,
    required this.label,
    required this.side,
    this.busy = false,
  });

  final String label;

  /// (v2) A small progress mark after the label (the group is being asked
  /// again — 6.1.6).
  final bool busy;

  /// Left / right padding (the grid padding).
  final double side;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(side, 16, side, 8),
      child: Row(
        children: [
          Flexible(
            child: Semantics(
              header: true,
              child: Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          if (busy) ...[
            const SizedBox(width: 8),
            const SizedBox.square(
              dimension: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
      ),
    );
  }
}
