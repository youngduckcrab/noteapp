// lib/src/ui/content/note_meta.dart — 05-library 6.8 / 6.14: the meta line
// of a note tile / row by section, the location of an item, and the search
// match highlight of a title.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart'
    show
        FolderId,
        MarkdownLimits,
        Note,
        clockProvider,
        folderTreeProvider,
        markdownDocProvider;

import '../../l10n/library_date_format.dart';
import '../../l10n/library_strings.dart';
import '../../model/location_label.dart';
import '../../model/search_match.dart';
import '../../model/section.dart';

/// What the meta line of a note says (6.8 / 6.14).
enum NoteMetaStyle {
  /// Folder sections: the modified date (list rows add the page count).
  modified,

  /// Recent: `'<location> · <last opened>'`.
  recent,

  /// Favorites: `'<location> · 수정 <modified>'`.
  favorite,

  /// Search results: `'<location>'`.
  location;

  static NoteMetaStyle of(LibrarySection section) => switch (section) {
    RecentSection() => recent,
    FavoritesSection() => favorite,
    SearchSection() => location,
    FolderSection() || TrashSection() => modified,
  };
}

/// locationLabel of [folderId] (6.14), rebuilding only when the label
/// changes; null while the folder tree loads or after its error.
String? watchLocationLabel(WidgetRef ref, FolderId? folderId) => ref.watch(
  folderTreeProvider.select((tree) {
    final value = tree.value;
    return value == null ? null : locationLabel(value, folderId);
  }),
);

/// The meta line of [note] in [style]; [listRow] adds the page count to the
/// modified date (6.8). A note of a newer app version says so instead.
String watchNoteMeta(
  WidgetRef ref,
  Note note,
  NoteMetaStyle style, {
  required bool listRow,
}) {
  if (note.requiresNewerApp) return LibraryStrings.requiresNewerApp;
  final now = ref.watch(clockProvider).now();
  final modified = formatLibraryDate(note.updatedAt, now: now);
  switch (style) {
    case NoteMetaStyle.modified:
      if (!listRow) return modified;
      // (v2.17-md, 08-markdown 9) an MD 문서 row: '<modified> · 문서 · 2.1 KB'.
      if (note.isMarkdown) {
        final doc = ref.watch(markdownDocProvider(note.id)).value;
        return LibraryStrings.markdownListMeta(
          modified,
          doc == null ? null : MarkdownLimits.utf8BytesOf(doc.text),
        );
      }
      return LibraryStrings.noteListMeta(modified, note.pageCount);
    case NoteMetaStyle.recent:
      final location = watchLocationLabel(ref, note.folderId);
      final openedAt = note.lastOpenedAt;
      final opened = openedAt == null
          ? modified
          : formatLibraryDate(openedAt, now: now);
      return location == null
          ? opened
          : LibraryStrings.recentNoteMeta(location, opened);
    case NoteMetaStyle.favorite:
      final location = watchLocationLabel(ref, note.folderId);
      return location == null
          ? LibraryStrings.modifiedOn(modified)
          : LibraryStrings.favoriteNoteMeta(location, modified);
    case NoteMetaStyle.location:
      return watchLocationLabel(ref, note.folderId) ?? '';
  }
}

/// [text] with the part matching [query] (searchMatchRange) in w700 +
/// primary (6.14); plain when there is no query or no visible match.
InlineSpan highlightedTitleSpan(
  BuildContext context,
  String text,
  String? query,
) {
  final range = query == null ? null : searchMatchRange(text, query);
  if (range == null) return TextSpan(text: text);
  return TextSpan(
    children: [
      if (range.start > 0) TextSpan(text: text.substring(0, range.start)),
      TextSpan(
        text: text.substring(range.start, range.end),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      if (range.end < text.length) TextSpan(text: text.substring(range.end)),
    ],
  );
}
