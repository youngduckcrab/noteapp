// lib/src/document/page_mount.dart — 04-editor 6.4.4 (E-04).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

/// Keeps one page open in the CORE session and feeds its INK controller.
///   - constructor: session.openPage(page.id) (pin, N-3) and
///     session.pageChanges(page.id).listen(_onChange) — sync broadcast: emits `load`
///     first when already loaded (CORE 4.4).
///   - _onChange(c): controller.updateContent(ink.InkPageContent.fromCore(
///         page: c.content.page, strokes: c.content.strokes, revision: c.content.revision));
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
  late final StreamSubscription<core.PageContentChange> _subscription;
  final ValueNotifier<bool> _isLoaded = ValueNotifier(false);

  /// openPage completed and its pin is held (released by [dispose]).
  bool _pinned = false;
  bool _disposed = false;

  String get pageId => _pageId;
  ink.InkPageController get controller => _controller;
  ValueListenable<bool> get isLoaded => _isLoaded;
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
        revision: c.revision,
      ),
    );
    _isLoaded.value = true;
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
  }
}
