// lib/src/actions/editor_action_runner.dart — m5-7/04-editor 6.4.1, 6.4.3
// (E2-05). Per note (scoped).
//
// Runs the EditorAction a gesture is set to (GestureSettings.actionFor):
// finger taps and the finger long press (InteractionHost), and (E2-18) the
// Apple Pencil double tap / squeeze (StylusExtrasListener). Every action
// makes at most one command (undo / redo through EditorCommands); switching
// tools and opening a popup are not commands.
import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../commands/editor_commands.dart';
import '../di/stylus_extras.dart';
import '../scope/editor_scope.dart';
import '../state/popup.dart';
import '../state/settings/editor_settings.dart';
import '../text/text_edit_session.dart';
import '../tools/tool_controller.dart';
import '../tools/tool_state.dart';
import 'follow_system.dart';

/// Where an action came from.
@immutable
sealed class ActionSource {
  const ActionSource();
}

/// A finger tap / long press at [at] (viewport px).
final class GestureSource extends ActionSource {
  const GestureSource(this.at);
  final Offset at; // viewport px

  @override
  bool operator ==(Object other) => other is GestureSource && other.at == at;

  @override
  int get hashCode => Object.hash(GestureSource, at);
}

/// An Apple Pencil double tap / squeeze: the hover point (global logical px)
/// when the pencil hovers, and the iPadOS preferred action of the event.
final class PencilSource extends ActionSource {
  const PencilSource({this.hoverGlobal, required this.preferred});
  final Offset? hoverGlobal;
  final StylusPreferredAction preferred;

  @override
  bool operator ==(Object other) =>
      other is PencilSource &&
      other.hoverGlobal == hoverGlobal &&
      other.preferred == preferred;

  @override
  int get hashCode => Object.hash(PencilSource, hoverGlobal, preferred);
}

class EditorActionRunner {
  EditorActionRunner(this._ref, {required this._commands});

  final Ref _ref;
  final EditorCommands _commands;

  /// Runs [action] once. followSystem → followSystemAction(source.preferred)
  /// (6.5.2; a finger gesture has no preferred action → none). Ignored while
  /// a tool interaction runs (router.hasActiveInteraction) except palettes.
  /// On a read-only note toggleEraser, previousTool and the palettes are
  /// ignored (the tools are disabled); undo / redo go to EditorCommands as
  /// the toolbar buttons do.
  void run(EditorAction action, ActionSource source) {
    final resolved = switch ((action, source)) {
      (EditorAction.followSystem, PencilSource(:final preferred)) =>
        followSystemAction(preferred),
      (EditorAction.followSystem, GestureSource()) => EditorAction.none,
      _ => action,
    };
    final palette =
        resolved == EditorAction.toolPalette ||
        resolved == EditorAction.colorPalette;
    if (!palette && _commands.interactionActive) return;
    switch (resolved) {
      case EditorAction.none:
      case EditorAction.followSystem: // resolved above
      // Read by the router at contact (6.2.3); nothing to run here.
      case EditorAction.eraserWhileHeld:
      case EditorAction.lassoWhileHeld:
        return;
      case EditorAction.undo:
        unawaited(_history(redo: false));
      case EditorAction.redo:
        unawaited(_history(redo: true));
      case EditorAction.contextMenu:
        if (source case GestureSource(:final at)) {
          _commands.openContextMenuAt(at);
        }
      case EditorAction.toggleEraser:
        if (_readOnly) return;
        final tools = _ref.read(editorToolProvider.notifier);
        if (_ref.read(editorToolProvider).activeTool == EditorTool.eraser) {
          tools.returnFromEraser();
        } else {
          _commands.selectTool(EditorTool.eraser);
        }
      case EditorAction.previousTool:
        if (_readOnly) return;
        _ref.read(editorToolProvider.notifier).swapWithLast();
      case EditorAction.toolPalette:
        if (_readOnly) return;
        _ref
            .read(editorPopupProvider.notifier)
            .open(QuickPenPopup(globalPosition: _hoverOf(source)));
      case EditorAction.colorPalette:
        if (_readOnly) return;
        _ref
            .read(editorPopupProvider.notifier)
            .open(ColorPalettePopup(globalPosition: _hoverOf(source)));
    }
  }

  bool get _readOnly => _ref.read(editorReadOnlyProvider);

  /// The pencil's hover point, or null (→ the pen button anchor).
  static Offset? _hoverOf(ActionSource source) => switch (source) {
    PencilSource(:final hoverGlobal) => hoverGlobal,
    GestureSource() => null,
  };

  /// A text edit session ends first (its one command), then the note's
  /// undo / redo — the whole session goes back as one step (6.11.7).
  Future<void> _history({required bool redo}) async {
    try {
      if (_ref.read(editorTextEditProvider) != null) {
        await _ref
            .read(editorTextEditProvider.notifier)
            .end(reason: TextEditEndReason.undoRedo);
      }
      await (redo ? _commands.redo() : _commands.undo());
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'feature_editor',
          context: ErrorDescription('while running a gesture undo / redo'),
        ),
      );
    }
  }
}

/// The note's action runner (6.19): InteractionHost (finger taps, long
/// press) and StylusExtrasListener (E2-18).
final editorActionRunnerProvider = Provider<EditorActionRunner>(
  (ref) => EditorActionRunner(ref, commands: ref.watch(editorCommandsProvider)),
  dependencies: [
    editorCommandsProvider,
    editorReadOnlyProvider,
    editorPopupProvider,
    editorTextEditProvider,
  ],
  name: 'editorActionRunnerProvider',
);
