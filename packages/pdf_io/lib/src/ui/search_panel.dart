// lib/src/ui/search_panel.dart — 06-pdf 4.11 showPdfSearchPanel, 6.10.2 (T11). Internal
// (not exported).
//
// The search sheet: query field (250 ms debounce, Enter searches at once), previous / next,
// progress ('찾는 중 (n/m쪽)', the storage-delay text while the pre-search flush waits on
// CORE retries), the hit list. Tapping a hit selects it and calls onNavigate with the hit's
// rects (note page pt) — the same rects the background highlights draw.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../providers.dart';
import '../text/search_notifier.dart';
import '../text/search_types.dart';
import '../tuning.dart';
import 'flows.dart';
import 'import_progress_dialog.dart';
import 'strings_ko.dart';

/// The sheet body. [noteId] is the note being searched; the active search
/// (pdfActiveSearchProvider) is shown only when it belongs to that note.
class PdfSearchPanel extends ConsumerStatefulWidget {
  const PdfSearchPanel({
    super.key,
    required this.noteId,
    required this.onNavigate,
  });

  final String noteId;
  final PdfNavigateCallback onNavigate;

  @override
  ConsumerState<PdfSearchPanel> createState() => _PdfSearchPanelState();
}

class _PdfSearchPanelState extends ConsumerState<PdfSearchPanel> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;

  PdfSearchNotifier get _search => ref.read(pdfActiveSearchProvider.notifier);

  @override
  void initState() {
    super.initState();
    final current = ref.read(pdfActiveSearchProvider);
    if (current.noteId == widget.noteId && current.query.isNotEmpty) {
      _query.text = current.query;
      if (current.status == PdfSearchStatus.idle) {
        // Stopped when the panel was closed last time: search again (after this build).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _search.start(widget.noteId, current.query);
        });
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(PdfTuning.searchDebounce, () {
      if (mounted) _search.start(widget.noteId, text);
    });
  }

  void _onSubmitted(String text) {
    _debounce?.cancel();
    _search.start(widget.noteId, text);
  }

  /// Navigates to the selected hit: focusRectPt = PdfSearchState.currentFocusRect (null when
  /// the hit has no rects).
  void _navigateToCurrent() {
    final state = ref.read(pdfActiveSearchProvider);
    final hit = state.current;
    if (hit == null) return;
    widget.onNavigate(hit.pageId, state.currentFocusRect);
  }

  void _open(int index) {
    _search.select(index);
    _navigateToCurrent();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = ref.watch(pdfActiveSearchProvider);
    final search = active.noteId == widget.noteId
        ? active
        : PdfSearchState.idle;
    final searching = search.status == PdfSearchStatus.searching;
    // Only while searching: the pre-search flush may wait on CORE commit retries.
    final writeFailing = searching && watchPdfWriteFailing(ref);
    final hasHits = search.hits.isNotEmpty;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.5;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _query,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        hintText: PdfStringsKo.searchHint,
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: _onChanged,
                      onSubmitted: _onSubmitted,
                    ),
                  ),
                  IconButton(
                    tooltip: PdfStringsKo.searchPrevious,
                    icon: const Icon(Icons.keyboard_arrow_up),
                    onPressed: hasHits
                        ? () {
                            _search.selectPrevious();
                            _navigateToCurrent();
                          }
                        : null,
                  ),
                  IconButton(
                    tooltip: PdfStringsKo.searchNext,
                    icon: const Icon(Icons.keyboard_arrow_down),
                    onPressed: hasHits
                        ? () {
                            _search.selectNext();
                            _navigateToCurrent();
                          }
                        : null,
                  ),
                  IconButton(
                    tooltip: PdfStringsKo.close,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: _Status(
                search: search,
                writeFailing: writeFailing,
                theme: theme,
              ),
            ),
            if (hasHits)
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: search.hits.length,
                  itemBuilder: (context, index) => _HitTile(
                    hit: search.hits[index],
                    selected: index == search.currentIndex,
                    onTap: () => _open(index),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({
    required this.search,
    required this.writeFailing,
    required this.theme,
  });

  final PdfSearchState search;
  final bool writeFailing;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    switch (search.status) {
      case PdfSearchStatus.idle:
        return const SizedBox.shrink();
      case PdfSearchStatus.searching:
        final total = search.totalPages;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              PdfStringsKo.searchProgress(search.scannedPages, total),
              style: muted,
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: total > 0 ? search.scannedPages / total : null,
            ),
            if (writeFailing) ...[
              const SizedBox(height: 4),
              Text(
                PdfStringsKo.storageDelay,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        );
      case PdfSearchStatus.done:
        final count = search.hits.length;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              count > 0
                  ? PdfStringsKo.searchResultCount(count, search.currentIndex)
                  : search.totalPages == 0
                  ? PdfStringsKo.searchNoPdfPages
                  : PdfStringsKo.searchNoResults,
              style: muted,
            ),
            if (search.truncated)
              Text(PdfStringsKo.searchTruncated(count), style: muted),
          ],
        );
      case PdfSearchStatus.failed:
        return Text(
          search.error?.userMessage ?? '',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        );
    }
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({
    required this.hit,
    required this.selected,
    required this.onTap,
  });

  final PdfSearchHit hit;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final snippet = hit.snippet;
    final start = hit.matchStart.clamp(0, snippet.length);
    final end = (hit.matchStart + hit.matchLength).clamp(start, snippet.length);
    return ListTile(
      dense: true,
      selected: selected,
      leading: Text(PdfStringsKo.searchHitPage(hit.notePageNumber)),
      title: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: snippet.substring(0, start)),
            TextSpan(
              text: snippet.substring(start, end),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: snippet.substring(end)),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    );
  }
}
