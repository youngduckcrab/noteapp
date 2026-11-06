// lib/src/ui/toolbar/editor_toolbar.dart — 04-editor 6.9.1; (v2) the mic
// button in front of the undo button (m5-7/04-editor 6.13.1, 6.15.4 — E2-16).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../di/editor_extensions.dart';
import '../../scope/editor_scope.dart';
import '../../state/page_panel.dart';
import '../../state/popup.dart';
import '../../state/settings/editor_settings_notifier.dart';
import '../../tools/tool_controller.dart';
import '../../tools/tool_state.dart';
import '../editor_strings.dart';
import '../popup_host.dart';
import 'mic_button.dart';
import 'more_menu.dart';
import 'sync_badge_icon.dart';
import 'tool_button.dart';
import 'undo_redo_buttons.dart';
import 'zoom_chip.dart';

/// Icon of a pen type (6.9.1; P1 types fall back to the ballpoint icon).
IconData penTypeIcon(core.PenTool tool) => switch (tool) {
  core.PenTool.ballpoint => Icons.edit,
  core.PenTool.fountain => Icons.history_edu,
  core.PenTool.highlighter => Icons.border_color,
  core.PenTool.pencil => Icons.create,
  core.PenTool.marker => Icons.brush,
  _ => Icons.edit,
};

/// [←] title [▤] │ [펜●] [지우개] [올가미] │ [🎤] │ [↶] [↷] │ [✋] [100%] [☁] [⋯] — 52 px.
/// The title is hidden below 700 px. [▤] toggles the page panel (E-17). On a
/// read-only note the tool buttons are disabled (6.9.1). (v2) [🎤] only when
/// EditorExtensions.recordingPanel is set.
class EditorToolbar extends ConsumerWidget {
  const EditorToolbar({super.key, required this.onBack, this.onOpenSettings});

  final VoidCallback onBack;
  final VoidCallback? onOpenSettings;

  static const double height = 52;
  static const double titleMinWidth = 700;
  static const backKey = ValueKey('editor.toolbar.back');
  static const penKey = ValueKey('editor.toolbar.pen');
  static const eraserKey = ValueKey('editor.toolbar.eraser');
  static const lassoKey = ValueKey('editor.toolbar.lasso');
  static const fingerKey = ValueKey('editor.toolbar.finger');
  static const titleKey = ValueKey('editor.toolbar.title');
  static const pagePanelKey = ValueKey('editor.toolbar.pagePanel');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final title = ref.watch(editorSessionValueProvider).note.title;
    final hasPanel = ref.watch(
      editorExtensionsProvider.select((e) => e.recordingPanel != null),
    );
    return Material(
      color: scheme.surface,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              IconButton(
                key: backKey,
                onPressed: onBack,
                icon: const Icon(
                  Icons.arrow_back,
                  semanticLabel: EditorStrings.back,
                ),
              ),
              if (constraints.maxWidth >= titleMinWidth)
                Expanded(
                  child: Text(
                    title,
                    key: titleKey,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                )
              else
                const Spacer(),
              const _PagePanelButton(),
              const _Divider(),
              const _ToolButtons(),
              const _Divider(),
              if (hasPanel) ...[const MicButton(), const _Divider()],
              const UndoRedoButtons(),
              const _Divider(),
              const _FingerToggle(),
              const ZoomChip(),
              const EditorSyncBadgeIcon(),
              EditorMoreMenu(onOpenSettings: onOpenSettings),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 28,
    child: VerticalDivider(
      width: 12,
      color: Theme.of(context).colorScheme.outlineVariant,
    ),
  );
}

/// Tap: inactive tool → select it; the active pen / eraser again → its
/// settings popup. Long press: pen → quick popup (active or not), eraser →
/// eraser popup.
class _ToolButtons extends ConsumerWidget {
  const _ToolButtons();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tools = ref.watch(editorToolProvider);
    final readOnly = ref.watch(editorReadOnlyProvider);
    final commands = ref.watch(editorCommandsProvider);
    final popups = ref.read(editorPopupProvider.notifier);
    final anchors = PopupHost.anchorsOf(context);
    final active = tools.activeTool;

    VoidCallback? tap(EditorTool tool, EditorPopup? settings) {
      if (readOnly) return null;
      return () {
        if (active == tool && settings != null) {
          popups.open(settings);
        } else {
          commands.selectTool(tool);
        }
      };
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CompositedTransformTarget(
          link: anchors.pen,
          child: ToolButton(
            key: EditorToolbar.penKey,
            icon: penTypeIcon(tools.penType),
            label:
                '${EditorStrings.pen} '
                '(${EditorStrings.penTypeName(tools.penType)})',
            active: active == EditorTool.pen,
            dotColor: Color(tools.currentPen.colorArgb),
            onTap: tap(EditorTool.pen, const PenSettingsPopup()),
            onLongPress: () => popups.open(const QuickPenPopup()),
          ),
        ),
        CompositedTransformTarget(
          link: anchors.eraser,
          child: ToolButton(
            key: EditorToolbar.eraserKey,
            icon: Icons.auto_fix_normal,
            label: EditorStrings.eraser,
            active: active == EditorTool.eraser,
            onTap: tap(EditorTool.eraser, const EraserSettingsPopup()),
            onLongPress: () => popups.open(const EraserSettingsPopup()),
          ),
        ),
        ToolButton(
          key: EditorToolbar.lassoKey,
          icon: Icons.highlight_alt,
          label: EditorStrings.lasso,
          active: active == EditorTool.lasso,
          onTap: tap(EditorTool.lasso, null),
        ),
      ],
    );
  }
}

/// [▤]: opens / closes the page panel (selected while open).
class _PagePanelButton extends ConsumerWidget {
  const _PagePanelButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(editorPagePanelProvider.select((p) => p.isOpen));
    final commands = ref.watch(editorCommandsProvider);
    return IconButton(
      key: EditorToolbar.pagePanelKey,
      isSelected: open,
      onPressed: commands.togglePagePanel,
      icon: const Icon(
        Icons.view_sidebar,
        semanticLabel: EditorStrings.pagePanel,
      ),
    );
  }
}

/// [✋]: on = finger drawing, off = pen only (auto shows what it does now).
class _FingerToggle extends ConsumerWidget {
  const _FingerToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final penOnly = ref.watch(
      editorSettingsProvider.select((s) => s.isPenOnlyEffective),
    );
    final commands = ref.watch(editorCommandsProvider);
    return IconButton(
      key: EditorToolbar.fingerKey,
      isSelected: !penOnly,
      onPressed: commands.toggleFingerDrawing,
      icon: Icon(
        penOnly ? Icons.do_not_touch : Icons.touch_app,
        semanticLabel: penOnly
            ? EditorStrings.fingerDrawingOff
            : EditorStrings.fingerDrawingOn,
      ),
    );
  }
}
