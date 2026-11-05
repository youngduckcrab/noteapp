// lib/src/commands/editor_commands.dart — 04-editor 6.8, 5.1.3.
//
// E-08: the three CORE entry points (_run, _runAsync, _runHistory), the ink
// hand-off (commitInkEdit), undo / redo and the user messages. Copy / paste,
// page commands, navigation and UI actions join with E-09..E-19.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../document/mounted_pages.dart';
import '../input/input_router.dart';
import '../scope/editor_scope.dart';
import '../tools/tool_controller.dart';
import '../ui/editor_strings.dart';
import '../viewport/viewport_controller.dart';

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
  bool _disposed = false;

  /// Short notices for the user (snackbar text): a command refused on a
  /// read-only note, a command that failed.
  Stream<String> get messages => _messages.stream;

  /// The mounted pages this note's commands may touch (contract E-2).
  MountedPages get pages => _pages;

  /// Called by editorInputRouterProvider: undo / redo are ignored while the
  /// router drives a tool interaction.
  void bindRouter(InputRouter router) => _router = router;

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
    unawaited(_messages.close());
  }
}
