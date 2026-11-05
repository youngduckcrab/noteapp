// lib/src/input/editor_shortcuts.dart — 04-editor 6.8 (keyboard).
//
// EditorShortcuts = Shortcuts + Actions around the editor root; every key of
// the 6.8 table is registered with ⌘ (macOS, iPadOS) and Ctrl (others).
// EditorCanvasFocus is the canvas focus node (autofocus, focused again by any
// pointer down on the page area) and handles P / E / L while it is the
// primary focus.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../commands/editor_commands.dart';
import '../scope/editor_scope.dart';
import '../tools/tool_state.dart';

/// What a key of the 6.8 table does.
enum EditorKeyAction {
  undo,
  redo,
  copy,
  paste,
  delete,
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
  );

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
  _EditorKeyActionHandler(this._commands);

  final EditorCommands Function() _commands;

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
        unawaited(commands.paste()); // screen centre
      case EditorKeyAction.delete:
        commands.deleteSelection(); // + selected pages in selection mode (E-17)
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
/// focus, P / E / L (no modifier) select the pen / eraser / lasso — not on a
/// read-only note, where those tools are disabled (6.9.1).
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
    scheduleMicrotask(() {
      if (mounted && !_node.hasPrimaryFocus) _node.requestFocus();
    });
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
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
