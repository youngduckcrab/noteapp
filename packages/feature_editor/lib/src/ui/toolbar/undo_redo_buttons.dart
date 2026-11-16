// lib/src/ui/toolbar/undo_redo_buttons.dart — 04-editor 6.8, 6.9.1 ([↶] [↷]).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:ui_kit/ui_kit.dart';

import '../../scope/editor_scope.dart';
import '../../text/text_edit_session.dart';
import '../editor_strings.dart';
import 'tool_glyph.dart';

/// [↶] [↷] of the toolbar. Enabled from `core.historyStateProvider(noteId)`
/// (canUndo / canRedo; HistoryState.empty while loading — EDITOR keeps no
/// history provider of its own, contract 7.2.0); both disabled on a
/// read-only note. Taps run EditorCommands.undo / redo (ignored during a tool
/// interaction; a racing ReadOnlyNoteException is caught there — N-4 v1.1).
/// No long-press tooltips (6.9.1): semantics labels, and (UI stage 2) the
/// names on stylus hover (HoverName). (v2, E2-10 — 6.11.7) an open
/// text session ends first — the button's down already ended it
/// (tapOutside); the undo waits for its command, so the whole session goes
/// back as one step. [↶] is enabled during a session too (its command may
/// be the step to undo). (04-editor 19) [compact]: the restore pill's
/// buttons (own keys, smaller icons, still 48 dp targets), one [part] each.
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

  /// (04-editor 19) The restore pill's [↶] [↷].
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

    final iconSize = compact ? 20.0 : ToolGlyph.toolbarIconSize;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (part != UndoRedoPart.redo)
          HoverName(
            name: EditorStrings.undo,
            child: IconButton(
              key: compact ? pillUndoKey : undoKey,
              onPressed: !readOnly && (history.canUndo || editing)
                  ? () => unawaited(afterSession(commands.undo))
                  : null,
              icon: ToolGlyph(
                AppIconKind.undo,
                size: iconSize,
                semanticLabel: EditorStrings.undo,
              ),
            ),
          ),
        if (part != UndoRedoPart.undo)
          HoverName(
            name: EditorStrings.redo,
            child: IconButton(
              key: compact ? pillRedoKey : redoKey,
              onPressed: !readOnly && history.canRedo
                  ? () => unawaited(afterSession(commands.redo))
                  : null,
              icon: ToolGlyph(
                AppIconKind.redo,
                size: iconSize,
                semanticLabel: EditorStrings.redo,
              ),
            ),
          ),
      ],
    );
  }
}

/// (04-editor 19) Which of [↶] [↷] an [UndoRedoButtons] shows.
enum UndoRedoPart { both, undo, redo }
