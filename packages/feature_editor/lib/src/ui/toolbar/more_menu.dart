// lib/src/ui/toolbar/more_menu.dart — 04-editor 6.9.1 ([⋯]), 4.5 (extension
// items), 6.11.5 (menu context); (v2, m5-7/04-editor 6.14.4 — E2-14) 테이프 모두
// 보이기 / 가리기; (v2.14-ui, UI stage 1 — m5-7/04-editor 'UI 정리 1단계') the
// duplicates are gone (see EditorMoreMenu).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../di/editor_extensions.dart';
import '../../di/stylus_extras.dart';
import '../../scope/editor_scope.dart';
import '../../state/settings/editor_settings_notifier.dart';
import '../../state/tape_state.dart';
import '../../stylus/stylus_extras_listener.dart' show penOnlyEffectiveWith;
import '../../tools/tool_controller.dart';
import '../../tools/tool_state.dart';
import '../chrome/editor_chrome.dart';
import '../dev/dev_metrics.dart';
import '../editor_strings.dart';
import 'dev_menu.dart';
import 'note_info_dialog.dart';

/// (v2.14-ui, UI stage 1) 테이프 모두 보이기 / 테이프 모두 가리기 — one item,
/// only when a loaded page of the note has a tape (or the tape pen is the
/// current pen) when the menu opens; it shows the action that is not in effect
/// (가리기 while every tape is revealed, else 보이기; allowed on a read-only
/// note, nothing is stored) · 손가락으로 그리기 (check — EditorCommands
/// .toggleFingerDrawing; the toolbar [✋] moved here and to settings › 입력) ·
/// 개발자 표시 (check; only in developer mode — core.developerModeProvider — or
/// while the overlay is on) · 노트 정보 (only with [showNoteInfo]: the toolbar
/// hides the title, which opens it otherwise) · 설정 (only with
/// onOpenSettings) · 메뉴 숨기기 · 팔레트 · 개발자 메뉴 (only while the developer
/// overlay is visible — EditorDevMenu) · divider · extension items.
///
/// Gone from here (v2.14-ui), each still reachable: 노트에서 찾기 (toolbar [🔍],
/// the hidden menu's pill), 페이지 넘김 (the page panel's header and settings ›
/// 페이지 넘김), 현재 페이지 지우기 (the eraser popup), 노트 정보 (tap the title).
///
/// The EditorMenuContext is built when the menu opens (6.11.5); extension
/// items get it for isEnabled (false → greyed, not hidden) and onSelected,
/// which is awaited after the menu closes and cannot run twice at the same
/// time; an exception is reported and shows '실행하지 못했어요'.
class EditorMoreMenu extends ConsumerStatefulWidget {
  const EditorMoreMenu({
    super.key,
    this.onOpenSettings,
    this.showNoteInfo = false,
  });

  final VoidCallback? onOpenSettings;

  /// (v2.14-ui) '노트 정보' is listed (the toolbar is too narrow for the
  /// tappable title).
  final bool showNoteInfo;

  static const buttonKey = ValueKey('editor.toolbar.more');

  /// The one tape item: this key while it reveals, [tapesHideAllKey] while
  /// it hides.
  static const tapesRevealAllKey = ValueKey('editor.more.tapesRevealAll');
  static const tapesHideAllKey = ValueKey('editor.more.tapesHideAll');

  /// (v2.14-ui) '손가락으로 그리기' (check).
  static const fingerDrawingKey = ValueKey('editor.more.fingerDrawing');
  static const devOverlayKey = ValueKey('editor.more.devOverlay');
  static const noteInfoKey = ValueKey('editor.more.noteInfo');
  static const settingsKey = ValueKey('editor.more.settings');

  /// Key of the item for an EditorMenuItem.id.
  static ValueKey<String> itemKey(String id) => ValueKey('editor.more.$id');

  @override
  ConsumerState<EditorMoreMenu> createState() => _EditorMoreMenuState();
}

class _EditorMoreMenuState extends ConsumerState<EditorMoreMenu> {
  final MenuController _controller = MenuController();
  final Set<String> _running = {};
  EditorMenuContext? _menu;
  bool _hasTape = false;

  void _toggle() {
    if (_controller.isOpen) {
      _controller.close();
      return;
    }
    setState(() {
      _menu = ref.read(editorCommandsProvider).menuContext();
      _hasTape = _noteHasTape();
    });
    _controller.open();
  }

  /// A loaded page has a tape stroke, or the tape pen is the current pen
  /// (the pages not loaded are not read for this).
  bool _noteHasTape() {
    final tools = ref.read(editorToolProvider);
    if (tools.activeTool == EditorTool.pen &&
        tools.penType == core.PenTool.tape) {
      return true;
    }
    final session = ref.read(editorSessionValueProvider);
    for (final page in session.pages) {
      final content = session.pageIfLoaded(page.id);
      if (content == null) continue;
      for (final stroke in content.strokes) {
        if (stroke.style.tool == core.PenTool.tape) return true;
      }
    }
    return false;
  }

  Future<void> _run(EditorMenuItem item, EditorMenuContext menu) async {
    if (!_running.add(item.id)) return;
    try {
      await item.onSelected(context, menu);
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'feature_editor',
          context: ErrorDescription('while running more menu item ${item.id}'),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text(EditorStrings.commandFailed)),
          );
      }
    } finally {
      _running.remove(item.id);
    }
  }

  Future<void> _showNoteInfo() => showNoteInfoDialog(context, ref);

  Widget _checkBox(bool on) =>
      Icon(on ? Icons.check_box : Icons.check_box_outline_blank);

  @override
  Widget build(BuildContext context) {
    final commands = ref.watch(editorCommandsProvider);
    final settings = ref.watch(editorSettingsProvider);
    final extensions = ref.watch(editorExtensionsProvider);
    final devVisible = ref.watch(editorDevOverlayVisibleProvider);
    final developerMode = ref.watch(core.developerModeProvider);
    final capabilities = ref.watch(stylusExtrasProvider).capabilities;
    final penOnly = penOnlyEffectiveWith(settings, capabilities);
    final tapesRevealed = ref.watch(editorTapesRevealedAllProvider) ?? false;
    final openSettings = widget.onOpenSettings;
    final menu = _menu;
    return MenuAnchor(
      controller: _controller,
      menuChildren: [
        if (_hasTape)
          if (tapesRevealed)
            MenuItemButton(
              key: EditorMoreMenu.tapesHideAllKey,
              leadingIcon: const Icon(Icons.visibility_off),
              onPressed: () => ref
                  .read(editorTapesRevealedAllProvider.notifier)
                  .setAll(false),
              child: const Text(EditorStrings.tapesHideAll),
            )
          else
            MenuItemButton(
              key: EditorMoreMenu.tapesRevealAllKey,
              leadingIcon: const Icon(Icons.visibility),
              onPressed: () => ref
                  .read(editorTapesRevealedAllProvider.notifier)
                  .setAll(true),
              child: const Text(EditorStrings.tapesRevealAll),
            ),
        MenuItemButton(
          key: EditorMoreMenu.fingerDrawingKey,
          leadingIcon: _checkBox(!penOnly),
          onPressed: commands.toggleFingerDrawing,
          child: const Text(EditorStrings.fingerDrawingMenu),
        ),
        if (developerMode || settings.showDevOverlay || devVisible)
          MenuItemButton(
            key: EditorMoreMenu.devOverlayKey,
            leadingIcon: _checkBox(settings.showDevOverlay),
            onPressed: commands.toggleDevOverlay,
            child: const Text(EditorStrings.devOverlay),
          ),
        if (widget.showNoteInfo)
          MenuItemButton(
            key: EditorMoreMenu.noteInfoKey,
            onPressed: () => unawaited(_showNoteInfo()),
            child: const Text(EditorStrings.noteInfo),
          ),
        if (openSettings != null)
          MenuItemButton(
            key: EditorMoreMenu.settingsKey,
            onPressed: openSettings,
            child: const Text(EditorStrings.settings),
          ),
        // (04-editor 19) 메뉴 숨기기 · 팔레트로 떼어내기 / 메뉴에 다시 붙이기.
        ...EditorChrome.moreMenuItems(context, ref),
        if (devVisible) const EditorDevMenu(),
        if (extensions.moreMenuItems.isNotEmpty && menu != null) ...[
          const Divider(height: 1),
          for (final item in extensions.moreMenuItems)
            MenuItemButton(
              key: EditorMoreMenu.itemKey(item.id),
              leadingIcon: Icon(item.icon),
              onPressed: (item.isEnabled?.call(menu) ?? true)
                  ? () => unawaited(_run(item, menu))
                  : null,
              child: Text(item.label),
            ),
        ],
      ],
      child: IconButton(
        key: EditorMoreMenu.buttonKey,
        onPressed: _toggle,
        icon: const Icon(Icons.more_horiz, semanticLabel: EditorStrings.more),
      ),
    );
  }
}
