// lib/src/ui/toolbar/undo_redo_buttons.dart — 04-editor 6.8, 6.9.1 ([↶] [↷]).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../scope/editor_scope.dart';
import '../../text/text_edit_session.dart';
import '../editor_strings.dart';

/// [↶] [↷] of the toolbar. Enabled from `core.historyStateProvider(noteId)`
/// (canUndo / canRedo; HistoryState.empty while loading — EDITOR keeps no
/// history provider of its own, contract 7.2.0); both disabled on a
/// read-only note. Taps run EditorCommands.undo / redo (ignored during a tool
/// interaction; a racing ReadOnlyNoteException is caught there — N-4 v1.1).
/// No tooltips (6.9.1): semantics labels only. (v2, E2-10 — 6.11.7) an open
/// text session ends first — the button's down already ended it
/// (tapOutside); the undo waits for its command, so the whole session goes
/// back as one step. [↶] is enabled during a session too (its command may
/// be the step to undo). (04-editor 17) [compact]: the restore pill's
/// smaller buttons (own keys), one [part] each.
class UndoRedoButtons extends ConsumerWidget {
  const UndoRedoButtons({
    super.key,
    this.compact = false,
    this.part = UndoRedoPart.both,
  });

  final bool compact;
  final UndoRedoPart part;

  static const undoKey = ValueKey('editor.toolbar.undo');
  static const redoKey = ValueKey('editor.toolbar.redo');

  /// (04-editor 17) The restore pill's [↶] [↷].
  static const pillUndoKey = ValueKey('editor.restorePill.undo');
  static const pillRedoKey = ValueKey('editor.restorePill.redo');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final noteId = ref.watch(editorNoteIdProvider);
    final history =
        ref.watch(core.historyStateProvider(noteId)).value ??
        core.HistoryState.empty;
    final readOnly = ref.watch(editorReadOnlyProvider);
    final commands = ref.watch(editorCommandsProvider);
    final editing = ref.watch(editorTextEditProvider.select((s) => s != null));
    Future<void> afterSession(Future<void> Function() step) async {
      await ref
          .read(editorTextEditProvider.notifier)
          .end(reason: TextEditEndReason.undoRedo);
      await step();
    }

    final density = compact ? VisualDensity.compact : null;
    final iconSize = compact ? 20.0 : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (part != UndoRedoPart.redo)
          IconButton(
            key: compact ? pillUndoKey : undoKey,
            visualDensity: density,
            iconSize: iconSize,
            onPressed: !readOnly && (history.canUndo || editing)
                ? () => unawaited(afterSession(commands.undo))
                : null,
            icon: const Icon(Icons.undo, semanticLabel: EditorStrings.undo),
          ),
        if (part != UndoRedoPart.undo)
          IconButton(
            key: compact ? pillRedoKey : redoKey,
            visualDensity: density,
            iconSize: iconSize,
            onPressed: !readOnly && history.canRedo
                ? () => unawaited(afterSession(commands.redo))
                : null,
            icon: const Icon(Icons.redo, semanticLabel: EditorStrings.redo),
          ),
      ],
    );
  }
}

/// (04-editor 17) Which of [↶] [↷] an [UndoRedoButtons] shows.
enum UndoRedoPart { both, undo, redo }
