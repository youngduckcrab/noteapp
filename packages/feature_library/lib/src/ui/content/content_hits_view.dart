// lib/src/ui/content/content_hits_view.dart — (v2) 05-library 6.1.3: the '노트 내용'
// group of the search results. Per note: a header (title with the match, location —
// opens the note), its first 3 hits (source badge, page, snippet with the match — open
// the note at the hit) and '이 노트에서 n개 더 보기'. A note that is in the trash or gone
// hides its whole group. Rows have different heights, so the group is one flat list of
// entries built from (groups, expanded) — SliverList.builder makes only visible rows.
// No selection, drag or ⋯ on these rows (1.3); in selection mode a tap does nothing.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart'
    show Note, NoteId, PageSearchHit, SearchSource, noteProvider;

import '../../common/report_error.dart';
import '../../l10n/library_strings.dart';
import '../../model/content_hits.dart';
import '../../state/providers.dart';
import '../layout/library_metrics.dart';
import '../library_scope.dart';
import 'note_meta.dart';
import 'tile_parts.dart';

/// Hits shown per note before '이 노트에서 n개 더 보기' (6.1.3).
const int kContentHitsPerNote = 3;

/// One row of the flattened content group.
@immutable
sealed class ContentEntry {
  const ContentEntry(this.noteId);
  final NoteId noteId;
}

final class ContentHeaderEntry extends ContentEntry {
  const ContentHeaderEntry(super.noteId);

  @override
  bool operator ==(Object other) =>
      other is ContentHeaderEntry && other.noteId == noteId;
  @override
  int get hashCode => Object.hash('header', noteId);
}

final class ContentHitEntry extends ContentEntry {
  ContentHitEntry(this.hit) : super(hit.noteId);
  final PageSearchHit hit;

  @override
  bool operator ==(Object other) =>
      other is ContentHitEntry && other.hit == hit;
  @override
  int get hashCode => Object.hash('hit', hit);
}

final class ContentMoreEntry extends ContentEntry {
  const ContentMoreEntry(super.noteId, this.hidden);

  /// Hits behind the row.
  final int hidden;

  @override
  bool operator ==(Object other) =>
      other is ContentMoreEntry &&
      other.noteId == noteId &&
      other.hidden == hidden;
  @override
  int get hashCode => Object.hash('more', noteId, hidden);
}

/// Header, the first [perNote] hits (all of them when the note is in
/// [expanded]) and a 'more' row, per group, in group order.
List<ContentEntry> flattenContentGroups(
  List<ContentHitGroup> groups,
  Set<NoteId> expanded, {
  int perNote = kContentHitsPerNote,
}) => [
  for (final g in groups) ...[
    ContentHeaderEntry(g.noteId),
    if (expanded.contains(g.noteId) || g.hits.length <= perNote)
      for (final h in g.hits) ContentHitEntry(h)
    else ...[
      for (final h in g.hits.take(perNote)) ContentHitEntry(h),
      ContentMoreEntry(g.noteId, g.hits.length - perNote),
    ],
  ],
];

/// The note of a content group, or null while it loads; [hidden] when the
/// note is in the trash (isDeleted) or gone (null) — 6.1.3 (S-5).
({Note? note, bool hidden}) _watchGroupNote(WidgetRef ref, NoteId noteId) {
  final async = ref.watch(noteProvider(noteId));
  final note = async.value;
  if (async.hasValue && (note == null || note.isDeleted)) {
    return (note: null, hidden: true);
  }
  return (note: note, hidden: false);
}

bool _watchSelecting(WidgetRef ref, BuildContext context) => ref.watch(
  librarySelectionProvider(LibraryScope.of(context).routeFolderId)
      .select((s) => s.active),
);

/// The note title (match highlighted, 1 line) and its location; opens the
/// note (onOpenNote — no page). 52 px.
class ContentNoteHeader extends ConsumerWidget {
  const ContentNoteHeader({
    super.key,
    required this.noteId,
    required this.query,
    required this.side,
  });

  final NoteId noteId;
  final String query;
  final double side;

  static const double height = 52;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (:note, :hidden) = _watchGroupNote(ref, noteId);
    if (hidden) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final selecting = _watchSelecting(ref, context);
    final title = note?.title ?? '';
    final location = note == null
        ? ''
        : watchLocationLabel(ref, note.folderId) ?? '';
    return Semantics(
      container: true,
      button: true,
      label: '$title, $location',
      excludeSemantics: true,
      onTap: note == null || selecting
          ? null
          : () => openLibraryNote(context, note),
      child: InkWell(
        onTap: note == null || selecting
            ? null
            : () => openLibraryNote(context, note),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: side),
            child: Row(
              children: [
                Flexible(
                  child: Text.rich(
                    highlightedTitleSpan(context, title, query),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (location.isNotEmpty) ...[
                  Text(
                    LibraryStrings.metaSeparator,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One content hit: badge + page (`'3쪽'`, `'페이지'` while unknown) and the
/// snippet (2 lines, match highlighted). ≥ 64 px. [onOpen] opens the note at
/// the hit (6.1.4).
class ContentHitRow extends ConsumerWidget {
  const ContentHitRow({
    super.key,
    required this.hit,
    required this.side,
    required this.onOpen,
  });

  final PageSearchHit hit;
  final double side;
  final void Function(Note note, PageSearchHit hit) onOpen;

  static const double minHeight = LibraryMetrics.listRowHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (:note, :hidden) = _watchGroupNote(ref, hit.noteId);
    if (hidden) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final selecting = _watchSelecting(ref, context);
    // (v2.17-md) an MD 문서 hit has no page: '문서' instead of 'n쪽'.
    final markdown = hit.source == SearchSource.markdown;
    final pages = ref.watch(notePageIndexProvider(hit.noteId));
    if (!markdown && pages.hasError) {
      reportLibraryErrorOnce(
        ProviderScope.containerOf(context, listen: false),
        pages.error!,
        pages.stackTrace,
        'library content page index: ${hit.noteId}',
      );
    }
    final index = pages.value?[hit.pageId];
    final page = markdown
        ? LibraryStrings.markdownKind
        : index == null
        ? LibraryStrings.pageUnknown
        : LibraryStrings.pageLabel(index);
    final source = LibraryStrings.sourceLabel(hit.source);
    void open() {
      if (note != null && !selecting) onOpen(note, hit);
    }

    return Semantics(
      key: markdown ? ValueKey('library.hit.markdown.${hit.noteId}') : null,
      container: true,
      button: true,
      label: LibraryStrings.contentHitSemantics(
        note?.title ?? '',
        page,
        source,
        hit.snippet,
      ),
      excludeSemantics: true,
      onTap: open,
      child: InkWell(
        onTap: open,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(side + 16, 8, side, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SourceBadge(source: hit.source),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        page,
                        maxLines: 1,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      SnippetText(
                        snippet: hit.snippet,
                        matchRange: hit.matchRange,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// '이 노트에서 n개 더 보기' — shows the rest of the note's hits. 44 px.
class ContentMoreRow extends ConsumerWidget {
  const ContentMoreRow({
    super.key,
    required this.noteId,
    required this.hidden,
    required this.side,
    required this.onExpand,
  });

  final NoteId noteId;
  final int hidden;
  final double side;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (_watchGroupNote(ref, noteId).hidden) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return InkWell(
      onTap: onExpand,
      child: SizedBox(
        height: LibraryMetrics.minTapTarget,
        child: Padding(
          padding: EdgeInsetsDirectional.only(start: side + 16, end: side),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              LibraryStrings.contentMore(hidden),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 손글씨 / PDF / 텍스트 / 수식 on secondaryContainer.
class SourceBadge extends StatelessWidget {
  const SourceBadge({super.key, required this.source});

  final SearchSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          LibraryStrings.sourceLabel(source),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}

/// The snippet, 2 lines with an ellipsis; [matchRange] in w700 + primary when
/// it lies inside the snippet, otherwise no highlight (6.1.3).
class SnippetText extends StatelessWidget {
  const SnippetText({
    super.key,
    required this.snippet,
    required this.matchRange,
  });

  final String snippet;
  final (int, int) matchRange;

  /// [matchRange] when 0 ≤ start < end ≤ snippet.length, else null.
  static (int, int)? visibleRange(String snippet, (int, int) range) {
    final (start, end) = range;
    if (start < 0 || end > snippet.length || start >= end) return null;
    return range;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final range = visibleRange(snippet, matchRange);
    final style = theme.textTheme.bodyMedium;
    final span = range == null
        ? TextSpan(text: snippet)
        : TextSpan(
            children: [
              if (range.$1 > 0) TextSpan(text: snippet.substring(0, range.$1)),
              TextSpan(
                text: snippet.substring(range.$1, range.$2),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
              if (range.$2 < snippet.length)
                TextSpan(text: snippet.substring(range.$2)),
            ],
          );
    return Text.rich(
      span,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}
