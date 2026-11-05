// lib/src/ui/toolbar/more_menu.dart — 04-editor 6.9.1 ([⋯]), 4.5 (extension
// items), 6.11.5 (menu context).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../di/editor_extensions.dart';
import '../../scope/editor_scope.dart';
import '../../state/settings/editor_settings.dart';
import '../../state/settings/editor_settings_notifier.dart';
import '../../tools/tool_controller.dart';
import '../dev/dev_metrics.dart';
import '../editor_strings.dart';
import '../eraser/eraser_popup.dart';
import 'dev_menu.dart';
import 'note_info_dialog.dart';

/// 페이지 넘김 (세로 스크롤 / 좌우 넘기기) · 현재 페이지 지우기 · 개발자 표시 (check) ·
/// 노트 정보 · 설정 (only with onOpenSettings) · 개발자 메뉴 (only while the
/// developer overlay is visible — EditorDevMenu) · divider · extension items.
///
/// The EditorMenuContext is built when the menu opens (6.11.5); extension
/// items get it for isEnabled (false → greyed, not hidden) and onSelected,
/// which is awaited after the menu closes and cannot run twice at the same
/// time; an exception is reported and shows '실행하지 못했어요'.
class EditorMoreMenu extends ConsumerStatefulWidget {
  const EditorMoreMenu({super.key, this.onOpenSettings});

  final VoidCallback? onOpenSettings;

  static const buttonKey = ValueKey('editor.toolbar.more');
  static const verticalKey = ValueKey('editor.more.pageFlip.vertical');
  static const horizontalKey = ValueKey('editor.more.pageFlip.horizontal');
  static const pageFlipKey = ValueKey('editor.more.pageFlip');
  static const clearPageKey = ValueKey('editor.more.clearPage');
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

  void _toggle() {
    if (_controller.isOpen) {
      _controller.close();
      return;
    }
    setState(() => _menu = ref.read(editorCommandsProvider).menuContext());
    _controller.open();
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

  Future<void> _showNoteInfo() {
    final session = ref.read(editorSessionValueProvider);
    return showDialog<void>(
      context: context,
      builder: (_) =>
          NoteInfoDialog(note: session.note, pageCount: session.pages.length),
    );
  }

  Widget _check(bool on) =>
      Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked);

  @override
  Widget build(BuildContext context) {
    final commands = ref.watch(editorCommandsProvider);
    final readOnly = ref.watch(editorReadOnlyProvider);
    final settings = ref.watch(editorSettingsProvider);
    final extensions = ref.watch(editorExtensionsProvider);
    final devVisible = ref.watch(editorDevOverlayVisibleProvider);
    final openSettings = widget.onOpenSettings;
    final menu = _menu;
    final flip = settings.pageFlipMode;
    return MenuAnchor(
      controller: _controller,
      menuChildren: [
        SubmenuButton(
          key: EditorMoreMenu.pageFlipKey,
          menuChildren: [
            MenuItemButton(
              key: EditorMoreMenu.verticalKey,
              leadingIcon: _check(flip == PageFlipMode.verticalScroll),
              onPressed: () =>
                  commands.setPageFlipMode(PageFlipMode.verticalScroll),
              child: const Text(EditorStrings.pageFlipVertical),
            ),
            MenuItemButton(
              key: EditorMoreMenu.horizontalKey,
              leadingIcon: _check(flip == PageFlipMode.horizontalPaged),
              onPressed: () =>
                  commands.setPageFlipMode(PageFlipMode.horizontalPaged),
              child: const Text(EditorStrings.pageFlipHorizontal),
            ),
          ],
          child: const Text(EditorStrings.pageFlip),
        ),
        MenuItemButton(
          key: EditorMoreMenu.clearPageKey,
          onPressed: readOnly
              ? null
              : () => unawaited(
                  confirmClearCurrentPage(
                    context,
                    commands: commands,
                    filter: ref.read(editorToolProvider).eraser.filter,
                  ),
                ),
          child: const Text(EditorStrings.clearPage),
        ),
        MenuItemButton(
          key: EditorMoreMenu.devOverlayKey,
          leadingIcon: Icon(
            settings.showDevOverlay
                ? Icons.check_box
                : Icons.check_box_outline_blank,
          ),
          onPressed: commands.toggleDevOverlay,
          child: const Text(EditorStrings.devOverlay),
        ),
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
