// lib/src/ui/top_bar/library_search_field.dart — 05-library 6.14: the title
// search input of the top bar. Typing → 300 ms debounce → section.search
// (trimmed; empty → back to the section before the search); Enter searches
// at once; the clear button goes back at once. Text being composed by an IME
// (Hangul) counts as typed. When the section becomes something other than a
// search (sidebar, a folder result opening, …) the text is cleared.
// (handwriting search, 6.19a) the field getting focus tells the ink search
// slot, so pages written just before are recognized while the user types.
// (v2.13-nav, m5-7/05-library 16) The soft keyboard going down (Android's back
// hides it) also lets go of the focus, so no focus history (a menu, a dialog,
// the drawer, the app resuming) can hand it back and bring the keyboard up
// without a tap; and the field tells the screen's system back whether it is
// in use ([LibrarySearchHandle]).
import 'dart:async' show Timer;

import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show FolderId;
import 'package:ui_kit/ui_kit.dart';

import '../../integration/ink_search_slot.dart';
import '../../l10n/library_strings.dart';
import '../../model/section.dart';
import '../../state/providers.dart';
import '../layout/library_metrics.dart';
import '../library_scope.dart';

/// (v2.13-nav, m5-7/05-library 16) What the screen's system back needs from
/// the search field: whether it is in use (focused, or typed in before the
/// search applies) and a way to close it. Owned by the screen (LibraryScope);
/// at most one field is attached at a time.
final class LibrarySearchHandle {
  /// The field is focused or holds text.
  final ValueNotifier<bool> engaged = ValueNotifier<bool>(false);
  _LibrarySearchFieldState? _field;
  bool _disposed = false;

  /// Clears the field's text and pending search, and lets go of its focus.
  void close() => _field?._closeFromBack();

  /// Re-reads [engaged] from the attached field; never notifies listeners
  /// mid-build (a field mounts or goes away while the tree builds).
  void _sync() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _apply());
    } else {
      _apply();
    }
  }

  void _apply() {
    if (_disposed) return;
    engaged.value = _field?._engaged ?? false;
  }

  void dispose() {
    _disposed = true;
    engaged.dispose();
  }
}

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

class _LibrarySearchFieldState extends ConsumerState<LibrarySearchField>
    with WidgetsBindingObserver {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  LibrarySearchHandle? _handle;

  /// The view's bottom inset (the soft keyboard) at the last metrics change.
  /// Read from the View: Scaffold removes it from its body's MediaQuery.
  double _keyboardInset = 0;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
    WidgetsBinding.instance.addObserver(this);
    // A field built while a search is shown (the compact search bar, a size
    // class change, the end of selection mode) starts with its query.
    final section = ref.read(librarySectionProvider(widget.routeFolderId));
    _controller = TextEditingController(
      text: section is SearchSection ? section.query : '',
    )..addListener(_publish);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _keyboardInset = View.maybeOf(context)?.viewInsets.bottom ?? 0;
    final handle = LibraryScope.of(context).searchHandle;
    if (handle == _handle) return;
    _detach();
    _handle = handle.._field = this;
    handle._sync();
  }

  void _detach() {
    final handle = _handle;
    _handle = null;
    if (handle == null || handle._field != this) return;
    handle
      .._field = null
      .._sync();
  }

  bool get _engaged => _focus.hasFocus || _controller.text.isNotEmpty;

  void _publish() {
    final handle = _handle;
    if (handle != null && handle._field == this) handle._sync();
  }

  /// System back while the field is in use (m5-7/05-library 16).
  void _closeFromBack() {
    _cancelDebounce();
    if (_controller.text.isNotEmpty) _controller.clear();
    if (_focus.hasFocus) _focus.unfocus();
  }

  /// The soft keyboard went down while the field had the focus: let go of
  /// it (UnfocusDisposition.scope also clears the route's focus history).
  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final view = View.maybeOf(context);
    if (view == null) return;
    _keyboardInsetChanged(view.viewInsets.bottom);
  }

  void _keyboardInsetChanged(double inset) {
    final wasUp = _keyboardInset > 0;
    _keyboardInset = inset;
    if (!wasUp || inset > 0 || !_focus.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _keyboardInset == 0 && _focus.hasFocus) _focus.unfocus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detach();
    _debounce?.cancel();
    _focus
      ..removeListener(_focusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _focusChanged() {
    _publish();
    if (!mounted || !_focus.hasFocus) return;
    ref.read(libraryInkSearchProvider)?.searchOpened();
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
        focusNode: _focus,
        autofocus: widget.autofocus,
        onChanged: _changed,
        onSubmitted: (_) => _apply(),
        textInputAction: TextInputAction.search,
        maxLines: 1,
        decoration: InputDecoration(
          hintText: LibraryStrings.searchHint,
          prefixIcon: const AppIcon(AppIconKind.search),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  icon: const AppIcon(AppIconKind.close),
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
