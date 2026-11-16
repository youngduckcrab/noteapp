// lib/src/ui/search/note_search_panel.dart — (v2.13-search) m5-7/04-editor
// 17: the in-note search panel ('노트에서 찾기').
//
// A right overlay over the page viewport (the viewport keeps its size and
// zoom, like the page panel on the left): the query field (focused when the
// panel opens), the handwriting hint (NoteSearchInkHint — the library's
// sentences), and one result per page in page order: "n쪽 · 손글씨" + the
// snippet with the match in bold. A tap goes to the page with the matched
// rects in view (EditorCommands.navigateToPage → position flash) and keeps
// them highlighted (NoteSearchHighlight) while the panel is open.
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../di/editor_ink_search.dart';
import '../../scope/editor_scope.dart';
import '../../state/note_search.dart';
import '../editor_strings.dart';

class NoteSearchPanel extends ConsumerWidget {
  const NoteSearchPanel({super.key});

  static const double maxWidth = 360;

  static const panelKey = ValueKey('editor.noteSearch');
  static const fieldKey = ValueKey('editor.noteSearch.field');
  static const closeKey = ValueKey('editor.noteSearch.close');
  static const listKey = ValueKey('editor.noteSearch.list');
  static const emptyKey = ValueKey('editor.noteSearch.empty');
  static const countKey = ValueKey('editor.noteSearch.count');

  static ValueKey<String> resultKey(String pageId) =>
      ValueKey('editor.noteSearch.result.$pageId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(editorNoteSearchProvider.select((s) => s.isOpen));
    if (!open) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(maxWidth, constraints.maxWidth * 0.6);
        return Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: width,
            height: constraints.maxHeight,
            child: const Material(
              key: panelKey,
              elevation: 2,
              child: _PanelBody(),
            ),
          ),
        );
      },
    );
  }
}

class _PanelBody extends ConsumerStatefulWidget {
  const _PanelBody();

  @override
  ConsumerState<_PanelBody> createState() => _PanelBodyState();
}

class _PanelBodyState extends ConsumerState<_PanelBody> {
  late final TextEditingController _field = TextEditingController(
    text: ref.read(editorNoteSearchProvider).query,
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _go(NoteSearchResult result) {
    ref.read(editorNoteSearchProvider.notifier).select(result.pageId);
    ref
        .read(editorCommandsProvider)
        .navigateToPage(result.pageId, result.boundsPt);
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(editorNoteSearchProvider);
    final notifier = ref.read(editorNoteSearchProvider.notifier);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final hasQuery = search.query.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: NoteSearchPanel.fieldKey,
                  controller: _field,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: EditorStrings.noteSearchHint,
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: notifier.setQuery,
                  onSubmitted: (_) => notifier.submit(),
                ),
              ),
              IconButton(
                key: NoteSearchPanel.closeKey,
                onPressed: notifier.close,
                icon: const Icon(
                  Icons.close,
                  semanticLabel: EditorStrings.noteSearchClose,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 2,
          child: search.searching ? const LinearProgressIndicator() : null,
        ),
        const NoteSearchInkHint(padding: EdgeInsets.fromLTRB(16, 4, 12, 4)),
        if (!hasQuery)
          Padding(
            key: NoteSearchPanel.emptyKey,
            padding: const EdgeInsets.all(16),
            child: Text(EditorStrings.noteSearchEmptyQuery, style: muted),
          )
        else if (search.failed)
          Padding(
            key: NoteSearchPanel.emptyKey,
            padding: const EdgeInsets.all(16),
            child: Text(EditorStrings.noteSearchFailed, style: muted),
          )
        else if (search.results.isEmpty && !search.searching)
          Padding(
            key: NoteSearchPanel.emptyKey,
            padding: const EdgeInsets.all(16),
            child: Text(EditorStrings.noteSearchNoResults, style: muted),
          )
        else ...[
          if (search.results.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                EditorStrings.noteSearchCount(search.results.length),
                key: NoteSearchPanel.countKey,
                style: theme.textTheme.labelMedium,
              ),
            ),
          Expanded(
            child: ListView.builder(
              key: NoteSearchPanel.listKey,
              itemCount: search.results.length,
              itemBuilder: (context, i) {
                final r = search.results[i];
                return _ResultTile(
                  key: NoteSearchPanel.resultKey(r.pageId),
                  result: r,
                  selected: r.pageId == search.selectedPageId,
                  onTap: () => _go(r),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

IconData _sourceIcon(core.SearchSource source) => switch (source) {
  core.SearchSource.ink => Icons.draw_outlined,
  core.SearchSource.text => Icons.text_fields,
  core.SearchSource.math => Icons.functions,
  core.SearchSource.pdf => Icons.picture_as_pdf_outlined,
};

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    super.key,
    required this.result,
    required this.selected,
    required this.onTap,
  });

  final NoteSearchResult result;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snippet = result.snippet;
    final (start, end) = result.matchRange;
    final a = start.clamp(0, snippet.length);
    final b = end.clamp(a, snippet.length);
    return ListTile(
      selected: selected,
      dense: true,
      minVerticalPadding: 8,
      leading: Icon(
        _sourceIcon(result.source),
        semanticLabel: EditorStrings.noteSearchSource(result.source),
      ),
      title: Text(
        '${EditorStrings.noteSearchPage(result.pageIndex + 1)} · '
        '${EditorStrings.noteSearchSource(result.source)}',
        style: theme.textTheme.labelLarge,
      ),
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: snippet.substring(0, a)),
            TextSpan(
              text: snippet.substring(a, b),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                backgroundColor: NoteSearchColors.fill(theme.colorScheme),
              ),
            ),
            TextSpan(text: snippet.substring(b)),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    );
  }
}

/// The highlight colours of the search (list and pages).
abstract final class NoteSearchColors {
  static Color fill(ColorScheme scheme) =>
      const Color(0xFFFFD54F).withValues(alpha: 0.45);
  static Color border(ColorScheme scheme) => scheme.tertiary;
}

/// One short line on why this note's handwriting is not found yet, with its
/// action — the library search hint's sentences (05-library 6.19a); the
/// count is this note's pages. Nothing without the slot or when ready.
class NoteSearchInkHint extends ConsumerWidget {
  const NoteSearchInkHint({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsetsGeometry padding;

  static const hintKey = ValueKey('editor.noteSearch.inkHint');
  static const actionKey = ValueKey('editor.noteSearch.inkHint.action');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slot = ref.watch(editorInkSearchProvider);
    if (slot == null) return const SizedBox.shrink();
    final noteId = ref.watch(editorNoteIdProvider);
    return ListenableBuilder(
      listenable: slot.changes,
      builder: (context, _) {
        final state = slot.stateOf(noteId);
        if (state.phase == EditorInkSearchPhase.ready) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: padding,
          child: _HintLine(key: hintKey, slot: slot, state: state),
        );
      },
    );
  }
}

class _HintLine extends StatefulWidget {
  const _HintLine({super.key, required this.slot, required this.state});

  final EditorInkSearch slot;
  final EditorInkSearchState state;

  @override
  State<_HintLine> createState() => _HintLineState();
}

class _HintLineState extends State<_HintLine> {
  /// The first [지금 받기] of a cellular download was pressed.
  bool _confirming = false;

  @override
  void didUpdateWidget(_HintLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.phase != widget.state.phase) _confirming = false;
  }

  bool get _cellular =>
      widget.state.phase == EditorInkSearchPhase.waitingForWifi ||
      widget.state.confirmCellularFirst;

  void _download() {
    if (_cellular && !_confirming) {
      setState(() => _confirming = true);
      return;
    }
    final cellular = _cellular;
    setState(() => _confirming = false);
    widget.slot.downloadModel(cellular: cellular);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    String confirmOr(String text) =>
        _confirming ? EditorStrings.inkCellularConfirm : text;
    final (
      String text,
      String? action,
      VoidCallback? onAction,
    ) = switch (state.phase) {
      EditorInkSearchPhase.autoIndexOff => (
        EditorStrings.inkAutoIndexOff,
        EditorStrings.inkTurnOn,
        widget.slot.turnOnAutoIndex,
      ),
      EditorInkSearchPhase.modelMissing => (
        confirmOr(EditorStrings.inkModelMissing),
        EditorStrings.inkDownloadNow,
        _download,
      ),
      EditorInkSearchPhase.waitingForWifi => (
        confirmOr(EditorStrings.inkWaitingForWifi),
        EditorStrings.inkDownloadNow,
        _download,
      ),
      EditorInkSearchPhase.modelFailed => (
        confirmOr(EditorStrings.inkModelFailed),
        EditorStrings.inkDownloadNow,
        _download,
      ),
      EditorInkSearchPhase.modelDownloading => (
        EditorStrings.inkModelDownloading,
        null,
        null,
      ),
      EditorInkSearchPhase.indexing => (
        EditorStrings.inkIndexing(state.remainingPages),
        null,
        null,
      ),
      EditorInkSearchPhase.unsupported => (
        EditorStrings.inkUnsupported,
        null,
        null,
      ),
      EditorInkSearchPhase.ready => ('', null, null),
    };
    final theme = Theme.of(context);
    final busy =
        state.phase == EditorInkSearchPhase.indexing ||
        state.phase == EditorInkSearchPhase.modelDownloading;
    return Row(
      children: [
        Icon(
          busy ? Icons.hourglass_empty : Icons.draw_outlined,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: 4),
          TextButton(
            key: NoteSearchInkHint.actionKey,
            style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
            onPressed: onAction,
            child: Text(action),
          ),
        ],
      ],
    );
  }
}
