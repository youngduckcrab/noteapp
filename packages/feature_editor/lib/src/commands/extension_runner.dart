// lib/src/commands/extension_runner.dart — m5-7/04-editor 4.3.1 (the slot
// callback rules — contract 7.2.10 (v2.1) '자리 콜백의 시작과 context' + E-7),
// 6.7.4 (EditorSelectionContext), 6.21 (errors).
//
// Every slot callback the editor starts from a press — a selection menu item
// (E2-07c), an insert menu item and the image importer (E2-12) — goes
// through ExtensionRunner.run, inside the button's onPressed:
//   ① a second press of an item that has not finished is ignored;
//   ② the callback is started SYNCHRONOUSLY with the editor body's context
//      (EditorBody's State.context — never the menu's, which is unmounted
//      once the menu closes), so a browser picker / clipboard opens inside
//      the user activation;
//   ③ then the menu / sheet closes (also after a synchronous exception);
//   ④ then its Future is awaited.
// A synchronous exception or a failed Future is reported
// (FlutterError.reportError, library 'feature_editor', 'while running <id>')
// and shows [failure] ('실행하지 못했어요') while the body is mounted. A
// callback that ends after the note screen closed has its result dropped
// (no command, no snack bar — 6.21).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../di/editor_extensions.dart';
import '../scope/editor_scope.dart';
import '../tools/selection.dart';
import '../ui/editor_strings.dart';

/// Runs the extension slot callbacks of one note (4.3.1). EditorBody binds
/// its context ([bindBody]); messages go to `notify` (EditorCommands.notify
/// — the command snack bars).
class ExtensionRunner {
  ExtensionRunner({required this._notify});

  final void Function(String message) _notify;
  BuildContext Function()? _body;
  final Set<String> _running = {};
  final Set<String> _reportedDuplicates = {};
  bool _disposed = false;

  /// EditorBody passes `() => context` (and null when it goes away).
  void bindBody(BuildContext Function()? body) => _body = body;

  /// The editor body's context while it is mounted, else null.
  BuildContext? get bodyContext {
    if (_disposed) return null;
    final context = _body?.call();
    return context != null && context.mounted ? context : null;
  }

  /// Whether the item [id] has started and not finished yet.
  bool isRunning(String id) => _running.contains(id);

  /// Runs one slot callback under the rules above: [start] gets the body
  /// context synchronously, then [close] runs, then the Future is awaited.
  /// Ignored (returns null, [close] not called) while [id] still runs, when
  /// there is no mounted body or after [dispose]. Completes with the
  /// callback's value; null when it failed or the body was gone by then.
  Future<T?> run<T>(
    String id,
    Future<T> Function(BuildContext context) start, {
    VoidCallback? close,
    String failure = EditorStrings.commandFailed,
  }) {
    final context = bodyContext;
    if (context == null || _running.contains(id)) return Future.value();
    _running.add(id);
    final Future<T> future;
    try {
      future = start(context);
    } on Object catch (error, stack) {
      _close(close);
      _running.remove(id);
      _failed(id, error, stack, failure);
      return Future.value();
    }
    _close(close);
    return _finish(id, future, failure);
  }

  Future<T?> _finish<T>(String id, Future<T> future, String failure) async {
    try {
      final value = await future;
      return bodyContext == null ? null : value;
    } on Object catch (error, stack) {
      _failed(id, error, stack, failure);
      return null;
    } finally {
      _running.remove(id);
    }
  }

  void _close(VoidCallback? close) {
    if (close == null) return;
    try {
      close();
    } on Object catch (error, stack) {
      _report(error, stack, 'while closing a menu');
    }
  }

  void _failed(String id, Object error, StackTrace stack, String failure) {
    _report(error, stack, 'while running $id');
    if (bodyContext != null) _notify(failure);
  }

  /// [items] without the ones whose id an earlier item has (4.3.1); each
  /// duplicate id is reported once per note.
  List<T> withoutDuplicates<T>(List<T> items, String Function(T item) idOf) {
    final seen = <String>{};
    final out = <T>[];
    for (final item in items) {
      final id = idOf(item);
      if (seen.add(id)) {
        out.add(item);
      } else if (_reportedDuplicates.add(id)) {
        _report(
          ArgumentError.value(id, 'id', 'two extension items share this id'),
          null,
          'while building the extension items',
        );
      }
    }
    return out;
  }

  /// isVisible of a selection item (4.3.1): its value, or false after an
  /// exception — reported through [report] (the caller reports once per
  /// menu opening and item), no user message (E-7 (v2.1)).
  static bool visible(
    EditorSelectionMenuItem item,
    EditorSelectionContext selection, {
    required void Function(Object error, StackTrace stack) onError,
  }) {
    final isVisible = item.isVisible;
    if (isVisible == null) return true;
    try {
      return isVisible(selection);
    } on Object catch (error, stack) {
      onError(error, stack);
      return false;
    }
  }

  /// Reports an isVisible exception of [id].
  static void reportVisibleError(String id, Object error, StackTrace stack) =>
      _report(error, stack, 'while checking isVisible of $id');

  void dispose() {
    _disposed = true;
    _body = null;
  }

  static void _report(Object error, StackTrace? stack, String context) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'feature_editor',
        context: ErrorDescription(context),
      ),
    );
  }
}

/// The EditorSelectionContext of [selection] (6.7.4) — a value copy made at
/// the press: the selected strokes and objects of the CORE page in z order,
/// boundsPt = INK's selection bounds (page pt), [execute] and
/// [clearSelection] passed through. Null when there is no selection, INK
/// holds none, or the page is not loaded (selections only exist on loaded
/// pages — then the items are hidden).
EditorSelectionContext? selectionContextFor({
  required core.NoteSession session,
  required EditorSelection? selection,
  required ink.InkSelection? sel,
  required void Function(core.EditCommand command) execute,
  required VoidCallback clearSelection,
}) {
  if (selection == null || sel == null) return null;
  final content = session.pageIfLoaded(selection.pageId);
  if (content == null) return null;
  final ids = selection.elementIds;
  return EditorSelectionContext(
    noteId: session.noteId,
    pageId: selection.pageId,
    pageSize: content.page.size,
    strokes: List.unmodifiable([
      for (final s in content.strokes)
        if (ids.contains(s.id)) s,
    ]),
    objects: List.unmodifiable([
      for (final o in content.objects)
        if (ids.contains(o.id)) o,
    ]),
    boundsPt: sel.bounds,
    execute: execute,
    clearSelection: clearSelection,
  );
}

/// Per note (4.3.1, 6.19). EditorBody binds its context.
final editorExtensionRunnerProvider = Provider<ExtensionRunner>(
  (ref) {
    final commands = ref.watch(editorCommandsProvider);
    final runner = ExtensionRunner(notify: commands.notify);
    ref.onDispose(runner.dispose);
    return runner;
  },
  dependencies: [editorCommandsProvider],
  name: 'editorExtensionRunnerProvider',
);
