// lib/src/commands/editor_commands.dart — 04-editor 6.8, 5.1.3.
//
// E-08: the three CORE entry points (_run, _runAsync, _runHistory), the ink
// hand-off (commitInkEdit), undo / redo and the user messages. E-09: clearing
// the current page. E-10: copy / paste / delete of the selection, clearing it
// and selecting a tool. E-12: zoom, screen scrolling, the developer overlay
// toggle and Esc for the keyboard shortcuts. E-13: flushAll (leaving), the
// menu context and navigateToPage, the finger-drawing toggle, the page flip
// mode, adding a page at the end. E-14: the eyedropper and notices. The page
// panel commands join with E-17.
import 'dart:async';
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../di/editor_extensions.dart';
import '../document/mounted_pages.dart';
import '../input/input_router.dart';
import '../scope/editor_scope.dart';
import '../state/color_palette.dart';
import '../state/popup.dart';
import '../state/preset_bar.dart';
import '../state/settings/editor_settings.dart';
import '../state/settings/editor_settings_notifier.dart';
import '../tools/interaction_host.dart';
import '../tools/selection.dart';
import '../tools/stroke_clipboard.dart';
import '../tools/tool_controller.dart';
import '../tools/tool_state.dart';
import '../ui/editor_strings.dart';
import '../viewport/viewport_controller.dart';
import '../viewport/viewport_memory.dart';

/// Single place for actions shared by toolbar, gestures, shortcuts, menus — and the
/// only place that runs CORE commands (5.1.3). Per note (scoped).
class EditorCommands {
  EditorCommands(
    this._ref, {
    required this._session,
    required this._viewport,
    required this._pages,
  });

  final Ref _ref;
  final core.NoteSession _session;
  final ViewportController _viewport;
  final MountedPages _pages;
  final StreamController<String> _messages = StreamController.broadcast();
  InputRouter? _router;
  InteractionHost? _host;
  bool _disposed = false;

  /// Short notices for the user (snackbar text): a command refused on a
  /// read-only note, a command that failed.
  Stream<String> get messages => _messages.stream;

  /// The mounted pages this note's commands may touch (contract E-2).
  MountedPages get pages => _pages;

  /// Called by editorInputRouterProvider: undo / redo are ignored while the
  /// router drives a tool interaction.
  void bindRouter(InputRouter router) => _router = router;

  /// Called by editorInteractionHostProvider: Esc closes the host's context
  /// menu (the host depends on these commands, so it is bound afterwards).
  void bindHost(InteractionHost host) => _host = host;

  // ---- commands (5.1.3) ----

  /// One gesture = one InkEdit = one execute (contract E-1, 7.2.15 hand-off).
  /// Commit failure (contract 7.2.15 v1.1, C11-16): when execute throws (ReadOnlyNoteException
  /// etc.), _run calls onRejected → controller.discardEdit(edit), which drops the pending
  /// display of every id of the edit (added, removedIds, targetIds) — erased / split /
  /// moved strokes show their committed state again at once. Returns true when committed.
  bool commitInkEdit(ink.InkPageController controller, ink.InkEdit edit) {
    if (edit.isEmpty) return false; // nothing pending (INK 4.6)
    return _run(
          edit.toCommand(),
          onRejected: () => controller.discardEdit(edit),
        ) !=
        null;
  }

  /// After the confirmation dialog (6.6.4 #5, E-09):
  /// core.ClearPage(pageId: current page, filter: eraser filter) through _runAsync.
  /// Ignored on a read-only note.
  Future<void> clearCurrentPage() async {
    if (_disposed || _ref.read(editorReadOnlyProvider)) return;
    final pages = _session.pages;
    if (pages.isEmpty) return;
    final index = _viewport.currentPageIndex.value.clamp(0, pages.length - 1);
    await _runAsync(
      core.ClearPage(
        pageId: pages[index].id,
        filter: _ref.read(editorToolProvider).eraser.filter,
      ),
    );
  }

  /// Copies the selected strokes (CORE state — session.pageIfLoaded) to the
  /// app clipboard (6.6.7). Allowed on a read-only note.
  void copySelection() {
    if (_disposed) return;
    final selection = _ref.read(editorSelectionProvider);
    if (selection == null) return;
    final page = _session.pageIfLoaded(selection.pageId);
    if (page == null) return;
    final strokes = [
      for (final id in selection.strokeIds) ?page.strokeById(id),
    ];
    if (strokes.isEmpty) return;
    _ref.read(editorClipboardProvider.notifier).copy(strokes);
  }

  /// Pastes the clipboard (6.6.7): at [screenPoint] when it is on a page,
  /// else centred on the screen centre in the current page's coordinates
  /// (repeated pastes move +16 pt each). One core.AddStrokes through _runAsync,
  /// then the lasso tool with the pasted strokes selected (controller.select —
  /// contract 7.2.15 paste rule). Ignored on a read-only note.
  Future<void> paste({Offset? screenPoint}) async {
    if (_disposed || _ref.read(editorReadOnlyProvider)) return;
    final clipboard = _ref.read(editorClipboardProvider.notifier);
    if (_ref.read(editorClipboardProvider) == null) return;
    final pages = _session.pages;
    if (pages.isEmpty || _viewport.viewportSize.isEmpty) return;
    final hit = screenPoint == null ? null : _viewport.hitPage(screenPoint);
    final int index;
    final Offset center;
    if (hit != null) {
      index = hit.index;
      center = _viewport.screenToPage(index, screenPoint!);
    } else {
      index = _viewport.currentPageIndex.value.clamp(0, pages.length - 1);
      center = _viewport.screenToPage(
        index,
        _viewport.viewportSize.center(Offset.zero),
      );
    }
    final page = pages[index];
    final strokes = clipboard.instantiate(
      pageId: page.id,
      pageSize: Size(page.size.width, page.size.height),
      center: center,
      explicitPoint: hit != null,
      newId: _ref.read(core.idGeneratorProvider).newId,
      createdAt: _ref.read(core.clockProvider).now().millisecondsSinceEpoch,
    );
    if (strokes.isEmpty) return;
    final receipt = await _runAsync(
      core.AddStrokes(pageId: page.id, strokes: strokes),
    );
    if (_disposed || receipt == null) return;
    _ref.read(editorToolProvider.notifier).selectTool(EditorTool.lasso);
    _ref.read(editorSelectionProvider.notifier).select(page.id, {
      for (final s in strokes) s.id,
    });
  }

  /// Deletes the selected strokes: commitInkEdit(controller, sel.delete())
  /// (one RemoveStrokes). A rejected commit shows them again (discardEdit) and
  /// keeps the selection. Ignored on a read-only note.
  void deleteSelection() {
    if (_disposed || _ref.read(editorReadOnlyProvider)) return;
    final selection = _ref.read(editorSelectionProvider);
    final sel = inkSelectionOf(_pages, selection);
    if (selection == null || sel == null) return;
    final controller = _pages[selection.pageId]!.controller;
    if (commitInkEdit(controller, sel.delete())) {
      _ref.read(editorSelectionProvider.notifier).clear();
    }
  }

  void clearSelection() {
    if (_disposed) return;
    _ref.read(editorSelectionProvider.notifier).clear();
  }

  void selectTool(EditorTool tool) {
    if (_disposed) return;
    _ref.read(editorToolProvider.notifier).selectTool(tool);
  }

  // ---- navigation / UI (6.8) ----

  /// ×1.25 about the screen centre (ViewportController.zoomStep).
  void zoomIn() {
    if (!_disposed) unawaited(_viewport.zoomStep(zoomIn: true));
  }

  /// ÷1.25 about the screen centre.
  void zoomOut() {
    if (!_disposed) unawaited(_viewport.zoomStep(zoomIn: false));
  }

  /// Zoom 1 = fit width (paged mode: the current page centred).
  void zoomToFit() {
    if (!_disposed) unawaited(_viewport.zoomToFit());
  }

  /// ±0.9 viewport along the main axis; the next / previous page in paged
  /// mode. [direction] > 0 = forward.
  void scrollByViewport(int direction) {
    if (!_disposed) unawaited(_viewport.scrollByViewport(direction));
  }

  /// Flips EditorSettings.showDevOverlay (device setting). The overlay is
  /// shown when this or the URL flag is on (6.12, E-19).
  void toggleDevOverlay() {
    if (_disposed) return;
    _ref.read(editorSettingsProvider.notifier).toggleDevOverlay();
  }

  /// Pen panel [스포이드] (6.6.8): closes the popup (and the context menu)
  /// and turns the eyedropper on — the banner shows and the next down on the
  /// canvas picks a stroke's colour. Allowed on a read-only note.
  void startEyedropper() {
    if (_disposed) return;
    _ref.read(editorPopupProvider.notifier).close();
    _host?.closeContextMenu();
    _ref.read(editorToolProvider.notifier).setEyedropper(true);
  }

  /// A short notice for the user (snack bar — the eyedropper's result).
  void notify(String message) => _message(message);

  /// Esc: close popup → cancel eyedropper → leave page selection mode → clear selection
  /// (first that applies). The open context menu counts as a popup (E-10);
  /// the page selection mode joins with E-17.
  void escape() {
    if (_disposed) return;
    if (_ref.read(editorPopupProvider) != null) {
      _ref.read(editorPopupProvider.notifier).close();
      return;
    }
    final host = _host;
    if (host != null && host.contextMenu.value != null) {
      host.closeContextMenu();
      return;
    }
    if (_ref.read(editorToolProvider).eyedropperActive) {
      _ref.read(editorToolProvider.notifier).setEyedropper(false);
      return;
    }
    _ref.read(editorSelectionProvider.notifier).clear();
  }

  /// Finger drawing on ↔ off: on = InputMode.fingerDrawing, off =
  /// InputMode.penOnly (6.9.1 [✋]). From auto it goes to the opposite of
  /// what auto does now (EditorSettings.isPenOnlyEffective).
  void toggleFingerDrawing() {
    if (_disposed) return;
    final settings = _ref.read(editorSettingsProvider);
    _ref
        .read(editorSettingsProvider.notifier)
        .setInputMode(
          settings.isPenOnlyEffective
              ? InputMode.fingerDrawing
              : InputMode.penOnly,
        );
  }

  /// More menu '페이지 넘김' (vertical scroll / horizontal paging). The
  /// viewport follows the setting (editorViewportProvider).
  void setPageFlipMode(PageFlipMode mode) {
    if (_disposed) return;
    _ref.read(editorSettingsProvider.notifier).setPageFlipMode(mode);
  }

  /// 04-editor 4.5 table: built when the more menu opens (6.11.5).
  /// selectedPageIds stays empty until the page panel selection mode (E-17).
  EditorMenuContext menuContext() {
    final ids = [for (final p in _session.pages) p.id];
    return EditorMenuContext(
      noteId: _session.noteId,
      pageIds: ids,
      currentPageIndex: _viewport.currentPageIndex.value,
      navigateToPage: navigateToPage,
    );
  }

  /// 6.11.6: an unknown id (deleted page) is ignored; else the page is
  /// brought into view, and [focusRectPt] (displayed page pt, clipped to the
  /// page) is shown when given.
  void navigateToPage(String pageId, Rect? focusRectPt) {
    if (_disposed) return;
    final pages = _session.pages;
    final index = pages.indexWhere((p) => p.id == pageId);
    if (index < 0) return;
    final size = pages[index].size;
    final rect = focusRectPt?.intersect(
      Rect.fromLTWH(0, 0, size.width, size.height),
    );
    unawaited(
      _viewport.revealPageRect(
        index,
        focusRectPt: rect == null || rect.isEmpty ? null : rect,
      ),
    );
  }

  /// A page like the last one (size, background) at the end, then the
  /// viewport goes to it (6.11.4 '+ 페이지'; also the '페이지가 없어요' state —
  /// blank A4 when there is no page). Ignored on a read-only note.
  Future<void> addPageAtEndLikeLast() async {
    if (_disposed || _ref.read(editorReadOnlyProvider)) return;
    final pages = _session.pages;
    final draft = pages.isEmpty
        ? core.PageDraft.blankA4
        : core.PageDraft(
            size: pages.last.size,
            background: pages.last.background,
          );
    final receipt = await _runAsync(
      core.InsertPages(drafts: [draft], position: const core.PageAtEnd()),
    );
    if (_disposed || receipt == null) return;
    unawaited(_viewport.jumpToPage(_session.pages.length - 1));
  }

  /// session.flush() + settings / tool / colour / viewport debounced writers (6.17).
  /// The current position is saved first. Each failure is reported; the
  /// Future completes when every write has finished (no timeout — contract
  /// 7.2.9 v1.2).
  Future<void> flushAll() async {
    if (_disposed) return;
    final memory = _ref.read(editorViewportMemoryProvider);
    final anchor = _viewport.captureAnchor();
    if (anchor != null) memory.save(_session.noteId, anchor);
    Future<void> guarded(Future<void> Function() write, String what) async {
      try {
        await write();
      } on Object catch (error, stack) {
        _report(error, stack, 'while flushing $what');
      }
    }

    await Future.wait([
      guarded(_session.flush, 'the note session'),
      guarded(_ref.read(editorSettingsProvider.notifier).flush, 'settings'),
      guarded(_ref.read(editorToolProvider.notifier).flush, 'tool state'),
      guarded(_ref.read(editorColorPaletteProvider.notifier).flush, 'colours'),
      guarded(_ref.read(editorPresetBarProvider.notifier).flush, 'preset bar'),
      guarded(memory.flush, 'the last position'),
    ]);
  }

  /// Through _runHistory (5.1.3): ignored while an interaction is active or read-only;
  /// a racing ReadOnlyNoteException (N-4 v1.1) is caught there.
  Future<void> undo() => _history(_session.undo);
  Future<void> redo() => _history(_session.redo);

  Future<void> _history(Future<core.UndoRedoResult> Function() step) async {
    if (_disposed) return;
    if (_router?.hasActiveInteraction ?? false) return;
    if (_ref.read(editorReadOnlyProvider)) return;
    final result = await _runHistory(step);
    if (_disposed || result == null || !result.applied) return;
    final affected = result.affectedPageIds;
    if (affected.isEmpty) return;
    // The first affected page in note order; scrolled to when off screen.
    final index = _session.pages.indexWhere((p) => affected.contains(p.id));
    if (index >= 0) await _viewport.ensurePageVisible(index);
  }

  // ---- CORE entry points: the only callers of session.execute /
  // executeAsync / undo / redo (EDITOR-3-1) ----

  /// Runs one CORE command for one user action, synchronously (N-1). Never called from a
  /// session stream listener (N-2 v1.1: that would throw StateError). Returns null when the
  /// command was rejected; [onRejected] then runs exactly once before returning — gesture
  /// commits pass () => controller.discardEdit(edit) (contract 7.2.15 v1.1 'commit failure').
  core.CommandReceipt? _run(
    core.EditCommand command, {
    VoidCallback? onRejected,
  }) {
    try {
      return _session.execute(command);
    } on Object catch (error, stack) {
      _rejected(error, stack, onRejected, 'while running ${command.label}');
      return null;
    }
  }

  /// Same for commands that may need pages loaded first (N-3). Applied after the first
  /// await (N-2 v1.1).
  Future<core.CommandReceipt?> _runAsync(
    core.EditCommand command, {
    VoidCallback? onRejected,
  }) async {
    try {
      return await _session.executeAsync(command);
    } on Object catch (error, stack) {
      _rejected(error, stack, onRejected, 'while running ${command.label}');
      return null;
    }
  }

  /// session.undo / session.redo (applied after the first await, N-2 v1.1). Read-only notes
  /// throw ReadOnlyNoteException here too (N-4 v1.1). null when rejected.
  Future<core.UndoRedoResult?> _runHistory(
    Future<core.UndoRedoResult> Function() step,
  ) async {
    try {
      return await step();
    } on Object catch (error, stack) {
      _rejected(error, stack, null, 'while undoing or redoing');
      return null;
    }
  }

  /// [_run] for tests (editor_commands_test: the exception table of 5.1.3).
  @visibleForTesting
  core.CommandReceipt? debugRun(
    core.EditCommand command, {
    VoidCallback? onRejected,
  }) => _run(command, onRejected: onRejected);

  /// [_runAsync] for tests.
  @visibleForTesting
  Future<core.CommandReceipt?> debugRunAsync(
    core.EditCommand command, {
    VoidCallback? onRejected,
  }) => _runAsync(command, onRejected: onRejected);

  /// [_runHistory] for tests.
  @visibleForTesting
  Future<core.UndoRedoResult?> debugRunHistory(
    Future<core.UndoRedoResult> Function() step,
  ) => _runHistory(step);

  /// All three catch:
  ///   ReadOnlyNoteException     → read-only toast, editorReadOnlyProvider refreshed
  ///   PageNotOpenException      → reportError (bug: gesture on an unmounted page)
  ///   LastPageDeletionException → reportError (button should have been disabled)
  ///   SessionClosedException    → ignored (screen is closing)
  ///   StateError                → reportError (bug: re-entered from a listener, N-2 v1.1)
  ///   anything else             → reportError + snackbar "실행하지 못했어요" (ArgumentError etc.)
  /// On every rejection: onRejected?.call() once, then return null (never rethrow).
  void _rejected(
    Object error,
    StackTrace stack,
    VoidCallback? onRejected,
    String context,
  ) {
    if (onRejected != null) {
      try {
        onRejected();
      } on Object catch (e, s) {
        _report(e, s, 'while dropping a rejected edit');
      }
    }
    switch (error) {
      case core.ReadOnlyNoteException():
        _message(EditorStrings.readOnlyToast);
        if (!_disposed) _ref.read(editorReadOnlyProvider.notifier).refresh();
      case core.SessionClosedException():
        break;
      case core.PageNotOpenException() ||
          core.LastPageDeletionException() ||
          StateError():
        _report(error, stack, context);
      default:
        _report(error, stack, context);
        _message(EditorStrings.commandFailed);
    }
  }

  void _message(String text) {
    if (!_disposed) _messages.add(text);
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
    _disposed = true;
    _router = null;
    _host = null;
    unawaited(_messages.close());
  }
}
