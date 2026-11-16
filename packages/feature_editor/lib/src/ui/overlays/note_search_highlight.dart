// lib/src/ui/overlays/note_search_highlight.dart — (v2.13-search)
// m5-7/04-editor 18: the matched rects of the in-note search over the
// pages, while the search panel is open.
//
// Every result's rects on the mounted pages are filled (amber 45 %); the
// result the user went to also gets a 2 px tertiary border. Drawn in screen
// coordinates from the camera each frame (it follows a pan or zoom, like
// FocusFlash). Display only.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../scope/editor_scope.dart';
import '../../state/note_search.dart';
import '../search/note_search_panel.dart' show NoteSearchColors;

class NoteSearchHighlight extends ConsumerWidget {
  const NoteSearchHighlight({super.key});

  static const double inflatePx = 2;

  /// Rect [i] of the result on page [pageId].
  static ValueKey<String> rectKey(String pageId, int i) =>
      ValueKey('editor.noteSearch.highlight.$pageId.$i');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = ref.watch(editorNoteSearchProvider);
    if (!search.isOpen || search.results.isEmpty) {
      return const SizedBox.shrink();
    }
    final viewport = ref.watch(editorViewportProvider);
    final scheme = Theme.of(context).colorScheme;
    final fill = NoteSearchColors.fill(scheme);
    final border = NoteSearchColors.border(scheme);
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: viewport,
        builder: (context, _) {
          final range = viewport.mountedRange;
          if (range == null || !viewport.isPlaced) {
            return const SizedBox.shrink();
          }
          final pages = viewport.pages;
          final children = <Widget>[];
          for (final r in search.results) {
            final index =
                r.pageIndex < pages.length && pages[r.pageIndex].id == r.pageId
                ? r.pageIndex
                : pages.indexWhere((p) => p.id == r.pageId);
            if (index < range.first || index > range.last) continue;
            final selected = r.pageId == search.selectedPageId;
            for (final (i, rect) in r.rectsPt.indexed) {
              final screen = Rect.fromPoints(
                viewport.pageToScreen(index, rect.topLeft),
                viewport.pageToScreen(index, rect.bottomRight),
              ).inflate(inflatePx);
              children.add(
                Positioned.fromRect(
                  rect: screen,
                  child: DecoratedBox(
                    key: rectKey(r.pageId, i),
                    decoration: BoxDecoration(
                      color: fill,
                      border: selected
                          ? Border.all(color: border, width: 2)
                          : null,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              );
            }
          }
          return Stack(children: children);
        },
      ),
    );
  }
}
