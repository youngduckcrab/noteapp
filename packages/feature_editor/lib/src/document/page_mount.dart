// lib/src/document/page_mount.dart — 04-editor 6.4.4 (E-04); (v2)
// m5-7/04-editor 6.14.4, 6.15.2, I-10 (E2-02): page objects go to INK, the
// note-level tape 'show all' is applied again after every updateContent, and
// a new mount gets the playback focus.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

/// Keeps one page open in the CORE session and feeds its INK controller.
///   - constructor: session.openPage(page.id) (pin, N-3) and
///     session.pageChanges(page.id).listen(_onChange) — sync broadcast: emits `load`
///     first when already loaded (CORE 4.4).
///   - _onChange(c): controller.updateContent(ink.InkPageContent.fromCore(
///         page: c.content.page, strokes: c.content.strokes,
///         objects: c.content.objects (v2), revision: c.content.revision));
///     (v2, I-10) then, when [tapesRevealedAll] says true, setAllTapesRevealed(true)
///     — INK applies it to the tapes present now only, so tapes that arrived
///     with this content (drawn, undone, remote) are revealed too; (v2) on the
///     first content, the [playbackFocus] of the note (if any) is set on the
///     controller (a page mounted during playback is emphasized at once);
///     isLoaded.value = true; then onContentChanged(c) (selection revalidation, 6.6.6;
///     dev metrics stroke count). MUST NOT call session.execute — inside a session
///     stream listener it throws StateError (contract 7.2.8 N-2 v1.1).
///   - dispose(): cancel subscription, session.closePage(page.id). Idempotent.
/// openPage errors (page deleted meanwhile, session closed) are reported and leave
/// isLoaded false; the page then shows the loading cover until it is unmounted.
final class PageMount {
  PageMount({
    required core.NoteSession session,
    required core.Page page,
    required this._controller,
    this._onContentChanged,
    this._tapesRevealedAll,
    this._playbackFocus,
  }) : _session = session,
       _pageId = page.id {
    // Listen first: a page that is already loaded delivers its `load` change
    // one microtask after listen, one that is still loading delivers it when
    // openPage installs it — either way before any later change (CORE 4.4).
    _subscription = session
        .pageChanges(_pageId)
        .listen(_onChange, onError: _onStreamError);
    _open();
  }

  final core.NoteSession _session;
  final String _pageId;
  final ink.InkPageController _controller;
  final void Function(core.PageContentChange change)? _onContentChanged;

  /// (v2) The note-level tape state (editorTapesRevealedAllProvider): true =
  /// 'show all', read at every content change.
  final bool? Function()? _tapesRevealedAll;

  /// (v2) The note's playback focus, applied once to a new mount (E2-17 gives
  /// the value; null = none).
  final ink.InkPlaybackFocus? Function()? _playbackFocus;
  late final StreamSubscription<core.PageContentChange> _subscription;
  final ValueNotifier<bool> _isLoaded = ValueNotifier(false);
  final ValueNotifier<int> _contentChanges = ValueNotifier(0);

  /// openPage completed and its pin is held (released by [dispose]).
  bool _pinned = false;
  bool _disposed = false;

  String get pageId => _pageId;
  ink.InkPageController get controller => _controller;
  ValueListenable<bool> get isLoaded => _isLoaded;

  /// (v2, m5-7/04-editor 6.7.2) How many CORE content changes reached this
  /// mount (after the controller got each one): the selection menu follows
  /// it (the '색' dot after a recolor).
  ValueListenable<int> get contentChanges => _contentChanges;
  core.PageContent? get content => _session.pageIfLoaded(_pageId);

  /// True after [dispose].
  bool get isDisposed => _disposed;

  void _open() {
    final Future<core.PageContent> opening;
    try {
      opening = _session.openPage(_pageId);
    } on Object catch (error, stack) {
      _report(error, stack, 'while opening page $_pageId');
      return;
    }
    unawaited(
      opening.then(
        (_) {
          if (_disposed) {
            // Unmounted while loading: release the pin this call took
            // (closePage before the load would have released nothing).
            _session.closePage(_pageId);
          } else {
            _pinned = true;
          }
        },
        onError: (Object error, StackTrace stack) {
          if (_disposed) return;
          _report(error, stack, 'while opening page $_pageId');
        },
      ),
    );
  }

  void _onChange(core.PageContentChange change) {
    if (_disposed) return;
    final c = change.content;
    _controller.updateContent(
      ink.InkPageContent.fromCore(
        page: c.page,
        strokes: c.strokes,
        objects: c.objects,
        revision: c.revision,
      ),
    );
    if (_tapesRevealedAll?.call() ?? false) {
      _controller.setAllTapesRevealed(true);
    }
    if (!_isLoaded.value) {
      final focus = _playbackFocus?.call();
      if (focus != null) _controller.setPlaybackFocus(focus);
    }
    _isLoaded.value = true;
    _contentChanges.value++;
    _onContentChanged?.call(change);
  }

  void _onStreamError(Object error, StackTrace stack) {
    if (_disposed) return;
    _report(error, stack, 'while listening to page $_pageId');
  }

  void _report(Object error, StackTrace? stack, String context) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'feature_editor',
        context: ErrorDescription(context),
      ),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_subscription.cancel());
    if (_pinned) {
      _pinned = false;
      _session.closePage(_pageId);
    }
    _isLoaded.dispose();
    _contentChanges.dispose();
  }
}
