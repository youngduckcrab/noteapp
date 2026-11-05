// lib/src/ui/top_bar/library_search_field.dart — 05-library 6.14: the title
// search input of the top bar. Typing → 300 ms debounce → section.search
// (trimmed; empty → back to the section before the search); Enter searches
// at once; the clear button goes back at once. Text being composed by an IME
// (Hangul) counts as typed. When the section becomes something other than a
// search (sidebar, a folder result opening, …) the text is cleared.
import 'dart:async' show Timer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show FolderId;

import '../../l10n/library_strings.dart';
import '../../model/section.dart';
import '../../state/providers.dart';
import '../layout/library_metrics.dart';

class LibrarySearchField extends ConsumerStatefulWidget {
  const LibrarySearchField({
    super.key,
    required this.routeFolderId,
    this.autofocus = false,
  });

  /// The route whose librarySectionProvider the field drives. The top bar
  /// keys the field by it: a route change starts with an empty field.
  final FolderId? routeFolderId;

  /// The compact search bar focuses the field when it opens.
  final bool autofocus;

  @override
  ConsumerState<LibrarySearchField> createState() => _LibrarySearchFieldState();
}

class _LibrarySearchFieldState extends ConsumerState<LibrarySearchField> {
  late final TextEditingController _controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // A field built while a search is shown (the compact search bar, a size
    // class change, the end of selection mode) starts with its query.
    final section = ref.read(librarySectionProvider(widget.routeFolderId));
    _controller = TextEditingController(
      text: section is SearchSection ? section.query : '',
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _cancelDebounce() {
    _debounce?.cancel();
    _debounce = null;
  }

  void _changed(String _) {
    _cancelDebounce();
    _debounce = Timer(LibraryMetrics.searchDebounce, _apply);
  }

  /// section.search(text) — trimmed; empty → exitSearch (6.14).
  void _apply() {
    _cancelDebounce();
    if (!mounted) return;
    ref
        .read(librarySectionProvider(widget.routeFolderId).notifier)
        .search(_controller.text);
  }

  void _clear() {
    _cancelDebounce();
    _controller.clear();
    ref
        .read(librarySectionProvider(widget.routeFolderId).notifier)
        .exitSearch();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(librarySectionProvider(widget.routeFolderId), (_, next) {
      if (next is SearchSection) return;
      _cancelDebounce();
      if (_controller.text.isNotEmpty) _controller.clear();
    });
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, value, _) => TextField(
        controller: _controller,
        autofocus: widget.autofocus,
        onChanged: _changed,
        onSubmitted: (_) => _apply(),
        textInputAction: TextInputAction.search,
        maxLines: 1,
        decoration: InputDecoration(
          hintText: LibraryStrings.searchHint,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: LibraryStrings.clearSearch,
                  onPressed: _clear,
                ),
          isDense: true,
          filled: true,
          fillColor: scheme.surfaceContainerHigh,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(24)),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
