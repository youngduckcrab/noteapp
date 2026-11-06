// lib/src/input/editor_shortcuts.dart — 04-editor 6.8 (keyboard).
//
// EditorShortcuts = Shortcuts + Actions around the editor root; every key of
// the 6.8 table is registered with ⌘ (macOS, iPadOS) and Ctrl (others).
// EditorCanvasFocus is the canvas focus node (autofocus, focused again by any
// pointer down on the page area) and handles P / E / L while it is the
// primary focus. (v2, E2-07a — m5-7/04-editor 6.7.6) ⌘X cut, ⌘D duplicate,
// S / T the shape / text tool; a focused text field (the text box editor
// included) still gets every key (⌘C / ⌘V copy and paste its text through
// the system clipboard). (E2-10 — 6.11.3 '캔버스 포커스 양보') while a text
// edit session is open the canvas does not take the focus on a pointer down,
// and it takes it back when the session ends. (E2-12 — 6.8) ⌘V with an
// empty app clipboard pastes an image when the image slot offers the
// clipboard source (its picker starts inside the key event).
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../commands/editor_commands.dart';
import '../di/editor_image_importer.dart';
import '../objects/image_flows.dart';
import '../scope/editor_scope.dart';
import '../text/text_box_editor.dart';
import '../text/text_edit_session.dart';
import '../tools/element_clipboard.dart';
import '../tools/tool_state.dart';

/// What a key of the 6.8 table does.
enum EditorKeyAction {
  undo,
  redo,
  copy,
  paste,
  delete,

  /// (v2) ⌘X
  cut,

  /// (v2) ⌘D
  duplicate,
  escape,
  zoomIn,
  zoomOut,
  zoomToFit,
  nextScreen,
  previousScreen,
  toggleDevOverlay,
}

/// The intent of every editor shortcut.
@immutable
final class EditorKeyIntent extends Intent {
  const EditorKeyIntent(this.action);

  final EditorKeyAction action;

  @override
  bool operator ==(Object other) =>
      other is EditorKeyIntent && other.action == action;

  @override
  int get hashCode => action.hashCode;
}

/// ⌘ and Ctrl variants of one key.
List<SingleActivator> _commandKey(
  LogicalKeyboardKey key, {
  bool shift = false,
}) => [
  SingleActivator(key, meta: true, shift: shift),
  SingleActivator(key, control: true, shift: shift),
];

/// 04-editor 6.8 table (⌘ and Ctrl both registered). P / E / L are not here:
/// they are handled by [EditorCanvasFocus] only while the canvas is the
/// primary focus.
final Map<ShortcutActivator, EditorKeyIntent> editorShortcutMap = () {
  const undo = EditorKeyIntent(EditorKeyAction.undo);
  const redo = EditorKeyIntent(EditorKeyAction.redo);
  const zoomIn = EditorKeyIntent(EditorKeyAction.zoomIn);
  const zoomOut = EditorKeyIntent(EditorKeyAction.zoomOut);
  const fit = EditorKeyIntent(EditorKeyAction.zoomToFit);
  const next = EditorKeyIntent(EditorKeyAction.nextScreen);
  const previous = EditorKeyIntent(EditorKeyAction.previousScreen);
  const delete = EditorKeyIntent(EditorKeyAction.delete);
  return <ShortcutActivator, EditorKeyIntent>{
    for (final a in _commandKey(LogicalKeyboardKey.keyZ)) a: undo,
    for (final a in _commandKey(LogicalKeyboardKey.keyZ, shift: true)) a: redo,
    const SingleActivator(LogicalKeyboardKey.keyY, control: true): redo,
    for (final a in _commandKey(LogicalKeyboardKey.keyC))
      a: const EditorKeyIntent(EditorKeyAction.copy),
    for (final a in _commandKey(LogicalKeyboardKey.keyV))
      a: const EditorKeyIntent(EditorKeyAction.paste),
    for (final a in _commandKey(LogicalKeyboardKey.keyX))
      a: const EditorKeyIntent(EditorKeyAction.cut),
    for (final a in _commandKey(LogicalKeyboardKey.keyD))
      a: const EditorKeyIntent(EditorKeyAction.duplicate),
    const SingleActivator(LogicalKeyboardKey.delete): delete,
    const SingleActivator(LogicalKeyboardKey.backspace): delete,
    const SingleActivator(LogicalKeyboardKey.escape): const EditorKeyIntent(
      EditorKeyAction.escape,
    ),
    // ⌘= and ⌘+ (= Shift + '=' on most layouts, or the '+' / keypad keys).
    for (final key in [
      LogicalKeyboardKey.equal,
      LogicalKeyboardKey.add,
      LogicalKeyboardKey.numpadAdd,
    ]) ...{
      for (final a in _commandKey(key)) a: zoomIn,
      for (final a in _commandKey(key, shift: true)) a: zoomIn,
    },
    for (final key in [
      LogicalKeyboardKey.minus,
      LogicalKeyboardKey.numpadSubtract,
    ])
      for (final a in _commandKey(key)) a: zoomOut,
    for (final key in [LogicalKeyboardKey.digit0, LogicalKeyboardKey.numpad0])
      for (final a in _commandKey(key)) a: fit,
    const SingleActivator(LogicalKeyboardKey.pageDown): next,
    const SingleActivator(LogicalKeyboardKey.space): next,
    const SingleActivator(LogicalKeyboardKey.pageUp): previous,
    const SingleActivator(LogicalKeyboardKey.space, shift: true): previous,
    for (final a in _commandKey(LogicalKeyboardKey.keyD, shift: true))
      a: const EditorKeyIntent(EditorKeyAction.toggleDevOverlay),
  };
}();

/// True while a text input (EditableText — HEX field, width number, preset
/// name …) has the primary focus. Every editor Action is disabled then, so
/// ShortcutManager returns KeyEventResult.ignored and the key reaches the text
/// field's own shortcuts (⌘Z = undo typing).
bool editorTextInputHasFocus() =>
    primaryFocus?.context?.findAncestorStateOfType<EditableTextState>() != null;

/// Shortcuts + Actions of the 6.8 table around the editor root (per note:
/// it reads editorCommandsProvider when a key is pressed).
class EditorShortcuts extends ConsumerStatefulWidget {
  const EditorShortcuts({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<EditorShortcuts> createState() => _EditorShortcutsState();
}

class _EditorShortcutsState extends ConsumerState<EditorShortcuts> {
  late final _EditorKeyActionHandler _action = _EditorKeyActionHandler(
    () => ref.read(editorCommandsProvider),
    paste: _paste,
  );

  /// ⌘V (6.8): the app clipboard when it has content; else, when the image
  /// slot offers the clipboard source (and the note is not read-only), an
  /// image paste at the visible centre (ImageFlows.paste — started inside
  /// this key event, a user activation on the web too).
  void _paste() {
    if (ref.read(editorClipboardProvider) == null &&
        !ref.read(editorReadOnlyProvider) &&
        ImageFlows.canPasteImage(ref.read(editorImageImporterProvider))) {
      unawaited(ref.read(editorImageFlowsProvider).paste());
      return;
    }
    unawaited(ref.read(editorCommandsProvider).paste()); // screen centre
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: editorShortcutMap,
    debugLabel: 'EditorShortcuts',
    child: Actions(
      actions: <Type, Action<Intent>>{EditorKeyIntent: _action},
      child: widget.child,
    ),
  );
}

class _EditorKeyActionHandler extends Action<EditorKeyIntent> {
  _EditorKeyActionHandler(this._commands, {required this._paste});

  final EditorCommands Function() _commands;
  final VoidCallback _paste;

  @override
  bool isEnabled(EditorKeyIntent intent) => !editorTextInputHasFocus();

  @override
  Object? invoke(EditorKeyIntent intent) {
    final commands = _commands();
    switch (intent.action) {
      case EditorKeyAction.undo:
        unawaited(commands.undo());
      case EditorKeyAction.redo:
        unawaited(commands.redo());
      case EditorKeyAction.copy:
        commands.copySelection();
      case EditorKeyAction.paste:
        _paste(); // the app clipboard, else an image (E2-12)
      case EditorKeyAction.delete:
        commands.deleteSelectionOrPages(); // strokes, else selected pages
      case EditorKeyAction.cut:
        commands.cutSelection();
      case EditorKeyAction.duplicate:
        commands.duplicateSelection();
      case EditorKeyAction.escape:
        commands.escape();
      case EditorKeyAction.zoomIn:
        commands.zoomIn();
      case EditorKeyAction.zoomOut:
        commands.zoomOut();
      case EditorKeyAction.zoomToFit:
        commands.zoomToFit();
      case EditorKeyAction.nextScreen:
        commands.scrollByViewport(1);
      case EditorKeyAction.previousScreen:
        commands.scrollByViewport(-1);
      case EditorKeyAction.toggleDevOverlay:
        commands.toggleDevOverlay();
    }
    return null;
  }
}

/// The canvas focus (6.8): `Focus(autofocus: true)` around the page area,
/// focused again whenever a pointer goes down on it. While it is the primary
/// focus, P / E / L (no modifier) select the pen / eraser / lasso and (v2)
/// S / T the shape / text tool — not on a read-only note, where those tools
/// are disabled (6.9.1).
///
/// (v2, E2-10 — m5-7/04-editor 6.11.3 '캔버스 포커스 양보', V7) While a text
/// edit session is open a pointer down does not ask for the focus (a pinch,
/// a rejected palm or a pen-only finger scroll keeps the editor focused —
/// the router decides which canvas input ends the session, 6.11.5). The
/// state is read when this Listener gets the down — after the router (the
/// inner Listener) has handled it, so a pen contact that ended the session
/// asks for the focus as in the 1st round. When a session ends, the canvas
/// takes the focus back in a microtask if the primary focus is nobody's, a
/// focus scope's or the session editor's own (TextSessionFocusNode); another
/// text field keeps it (a focusLost end — V7 ⑤).
class EditorCanvasFocus extends ConsumerStatefulWidget {
  const EditorCanvasFocus({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<EditorCanvasFocus> createState() => _EditorCanvasFocusState();
}

class _EditorCanvasFocusState extends ConsumerState<EditorCanvasFocus> {
  final FocusNode _node = FocusNode(debugLabel: 'EditorCanvas');

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final tool = switch (event.logicalKey) {
      LogicalKeyboardKey.keyP => EditorTool.pen,
      LogicalKeyboardKey.keyE => EditorTool.eraser,
      LogicalKeyboardKey.keyL => EditorTool.lasso,
      LogicalKeyboardKey.keyS => EditorTool.shape,
      LogicalKeyboardKey.keyT => EditorTool.text,
      _ => null,
    };
    if (tool == null || ref.read(editorReadOnlyProvider)) {
      return KeyEventResult.ignored;
    }
    ref.read(editorCommandsProvider).selectTool(tool);
    return KeyEventResult.handled;
  }

  /// In a microtask: a text field that loses the pointer (EditableText
  /// onTapOutside → unfocus) handles the same pointer down after this
  /// Listener, and the last focus request of the event wins.
  void _onPointerDown(PointerDownEvent event) {
    if (ref.read(editorTextEditProvider) != null) return;
    scheduleMicrotask(() {
      if (mounted && !_node.hasPrimaryFocus) _node.requestFocus();
    });
  }

  /// (v2, 6.11.3 2) A session ended: back to the canvas unless another text
  /// field holds the focus.
  void _onSessionEnded() {
    scheduleMicrotask(() {
      if (!mounted || _node.hasPrimaryFocus) return;
      final primary = FocusManager.instance.primaryFocus;
      if (primary == null ||
          primary is FocusScopeNode ||
          primary is TextSessionFocusNode) {
        _node.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(editorTextEditProvider.select((s) => s != null), (
      previous,
      open,
    ) {
      if (previous == true && !open) _onSessionEnded();
    });
    return Focus(
      focusNode: _node,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        child: widget.child,
      ),
    );
  }
}
