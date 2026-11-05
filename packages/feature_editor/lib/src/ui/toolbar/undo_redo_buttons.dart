// lib/src/ui/toolbar/undo_redo_buttons.dart — 04-editor 6.8, 6.9.1 ([↶] [↷]).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../scope/editor_scope.dart';
import '../editor_strings.dart';

/// [↶] [↷] of the toolbar. Enabled from `core.historyStateProvider(noteId)`
/// (canUndo / canRedo; HistoryState.empty while loading — EDITOR keeps no
/// history provider of its own, contract 7.2.0); both disabled on a
/// read-only note. Taps run EditorCommands.undo / redo (ignored during a tool
/// interaction; a racing ReadOnlyNoteException is caught there — N-4 v1.1).
/// No tooltips (6.9.1): semantics labels only.
class UndoRedoButtons extends ConsumerWidget {
  const UndoRedoButtons({super.key});

  static const undoKey = ValueKey('editor.toolbar.undo');
  static const redoKey = ValueKey('editor.toolbar.redo');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final noteId = ref.watch(editorNoteIdProvider);
    final history =
        ref.watch(core.historyStateProvider(noteId)).value ??
        core.HistoryState.empty;
    final readOnly = ref.watch(editorReadOnlyProvider);
    final commands = ref.watch(editorCommandsProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: undoKey,
          onPressed: !readOnly && history.canUndo
              ? () => unawaited(commands.undo())
              : null,
          icon: const Icon(Icons.undo, semanticLabel: EditorStrings.undo),
        ),
        IconButton(
          key: redoKey,
          onPressed: !readOnly && history.canRedo
              ? () => unawaited(commands.redo())
              : null,
          icon: const Icon(Icons.redo, semanticLabel: EditorStrings.redo),
        ),
      ],
    );
  }
}
