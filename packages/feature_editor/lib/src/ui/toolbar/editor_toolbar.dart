// lib/src/ui/toolbar/editor_toolbar.dart — 04-editor 6.9.1; (v2) the mic
// button in front of the undo button (m5-7/04-editor 6.13.1, 6.15.4 — E2-16),
// the insert menu [+] in front of it (6.13.1 — E2-12). (E2-13) Toolbar v2
// (6.13.1): the shape and text buttons after the lasso, [⋯도구] below
// [EditorToolbar.foldWidth], the title from [EditorToolbar.titleMinWidth].
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../di/editor_extensions.dart';
import '../../di/editor_image_importer.dart';
import '../../di/stylus_extras.dart';
import '../../scope/editor_scope.dart';
import '../../state/note_search.dart';
import '../../state/page_panel.dart';
import '../../state/popup.dart';
import '../../state/settings/editor_settings_notifier.dart';
import '../../stylus/stylus_extras_listener.dart' show penOnlyEffectiveWith;
import '../../tools/tool_controller.dart';
import '../../tools/tool_state.dart';
import '../chrome/editor_chrome.dart' show MenuHideButton, MenuHideSlot;
import '../editor_strings.dart';
import '../popup_host.dart';
import 'insert_menu.dart';
import 'mic_button.dart';
import 'more_menu.dart';
import 'overflow_tools_menu.dart';
import 'sync_badge_icon.dart';
import 'tool_button.dart';
import 'undo_redo_buttons.dart';
import 'zoom_chip.dart';

/// Icon of a pen type (6.9.1; (v2, m5-7/04-editor 6.14.1) the P1 types).
IconData penTypeIcon(core.PenTool tool) => switch (tool) {
  core.PenTool.ballpoint => Icons.edit,
  core.PenTool.fountain => Icons.history_edu,
  core.PenTool.highlighter => Icons.border_color,
  core.PenTool.pencil => Icons.create,
  core.PenTool.marker => Icons.brush,
  core.PenTool.brush => Icons.draw,
  core.PenTool.calligraphy => Icons.gesture,
  core.PenTool.dashed => Icons.line_style,
  core.PenTool.laser => Icons.flare,
  core.PenTool.tape => Icons.visibility_off,
  // (v2.11, C211-01) texture and decoration pens
  core.PenTool.crayon => Icons.format_paint,
  core.PenTool.chalk => Icons.school,
  core.PenTool.watercolor => Icons.water_drop,
  core.PenTool.spray => Icons.blur_on,
  core.PenTool.neon => Icons.lightbulb,
  core.PenTool.jelly => Icons.bubble_chart,
  core.PenTool.rainbow => Icons.looks,
  core.PenTool.glitter => Icons.auto_awesome,
};

/// [←] title [▤] │ [펜●] [지우개] [올가미] [도형] [텍스트] │ [+] [🎤] │ [↶] [↷] │
/// [✋] [100%] [☁] [⋯] — 52 px (v2, m5-7/04-editor 6.13.1). The title shows
/// from [titleMinWidth] (1st round 700 — more buttons now). Below
/// [foldWidth] (split screen — A-6) [도형] [텍스트] [+] [🎤] fold into
/// [⋯도구] (OverflowToolsMenu); below [scrollWidth] the buttons scroll
/// sideways instead of overflowing. [▤] toggles the page panel (E-17). On a
/// read-only note the tool buttons are disabled (6.9.1). [🎤] only when
/// EditorExtensions.recordingPanel is set; [+] only when the image slot or
/// EditorExtensions.insertMenuItems offers something (InsertMenu.hasItems).
class EditorToolbar extends ConsumerWidget {
  const EditorToolbar({super.key, required this.onBack, this.onOpenSettings});

  final VoidCallback onBack;
  final VoidCallback? onOpenSettings;

  static const double height = 52;

  /// (v2) The title shows when the toolbar is at least this wide.
  static const double titleMinWidth = 1000;

  /// (v2) Below this width [도형] [텍스트] [+] [🎤] fold into [⋯도구]. The
  /// plan's 720 px is the floor. (04-editor 19.1) Measured with every
  /// optional button on (image insert, [🎤], 수식 펜, 텍스트 펜, sync badge):
  /// the unfolded row takes 900 px, + the 48 px [🔍] 948 px (title hidden) —
  /// the earlier 820 overflowed between 820 and 900. From 952 the unfolded
  /// row always has room for [🔍] (test/widget/toolbar_width_test.dart).
  static const double foldWidth = 952;

  /// (v2) Below this width the folded toolbar (≈ 660 px with the sync
  /// badge) scrolls sideways instead of overflowing.
  static const double scrollWidth = 680;

  /// (v2.13-search) The folded toolbar (≈ 660 px with the sync badge) + the
  /// 48 px [🔍] + slack: from here it shows [🔍] without scrolling. Above
  /// [foldWidth] the unfolded row has it too (19.1).
  static const double foldedSearchMinWidth = 720;

  static const backKey = ValueKey('editor.toolbar.back');
  static const penKey = ValueKey('editor.toolbar.pen');
  static const eraserKey = ValueKey('editor.toolbar.eraser');
  static const lassoKey = ValueKey('editor.toolbar.lasso');
  static const fingerKey = ValueKey('editor.toolbar.finger');
  static const titleKey = ValueKey('editor.toolbar.title');
  static const pagePanelKey = ValueKey('editor.toolbar.pagePanel');

  /// (v2.13-search) [🔍] '노트에서 찾기' — at every width from
  /// [foldedSearchMinWidth] (review: Android tablets in portrait are about
  /// 800 wide; (19.1) [foldWidth] leaves the unfolded row room for it). The
  /// more menu's first item has it too.
  static const noteSearchKey = ValueKey('editor.toolbar.noteSearch');

  /// (v2) Appendix C.
  static const shapeKey = OverflowToolsMenu.shapeKey;
  static const textKey = OverflowToolsMenu.textKey;

  /// (math pen, phase 1) the 수식 펜 (only with EditorExtensions.mathPen).
  static const mathKey = OverflowToolsMenu.mathKey;

  /// (text pen, phase 1) the 텍스트 펜 (only with EditorExtensions.textPen).
  static const textPenKey = OverflowToolsMenu.textPenKey;
  static const overflowToolsKey = OverflowToolsMenu.buttonKey;

  /// (v2) The sideways scroll below [scrollWidth].
  static const scrollKey = ValueKey('editor.toolbar.scroll');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final title = ref.watch(editorSessionValueProvider).note.title;
    final hasPanel = ref.watch(
      editorExtensionsProvider.select((e) => e.recordingPanel != null),
    );
    final hasInsert = InsertMenu.hasItems(
      ref.watch(editorImageImporterProvider),
      ref.watch(editorExtensionsProvider.select((e) => e.insertMenuItems)),
      textPen: ref.watch(
        editorExtensionsProvider.select((e) => e.textPen != null),
      ),
    );
    return Material(
      color: scheme.surface,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fold = constraints.maxWidth < foldWidth;
            final scroll = constraints.maxWidth < scrollWidth;
            final row = Row(
              mainAxisSize: scroll ? MainAxisSize.min : MainAxisSize.max,
              children: [
                IconButton(
                  key: backKey,
                  onPressed: onBack,
                  icon: const Icon(
                    Icons.arrow_back,
                    semanticLabel: EditorStrings.back,
                  ),
                ),
                // (04-editor 19) [⌃] 메뉴 숨기기 next to [←] (also in [⋯]).
                if (scroll || constraints.maxWidth >= titleMinWidth)
                  const MenuHideButton(),
                if (constraints.maxWidth >= titleMinWidth)
                  Expanded(
                    child: Text(
                      title,
                      key: titleKey,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  )
                else if (!scroll)
                  const MenuHideSlot(), // the Spacer, [⌃] when it fits
                if (constraints.maxWidth >= foldedSearchMinWidth)
                  const _NoteSearchButton(),
                const _PagePanelButton(),
                const _Divider(),
                _ToolButtons(withObjectTools: !fold),
                const _Divider(),
                if (fold) ...[
                  OverflowToolsMenu(hasInsert: hasInsert, hasPanel: hasPanel),
                  const _Divider(),
                ] else ...[
                  if (hasInsert) const InsertMenu(),
                  if (hasPanel) const MicButton(),
                  if (hasInsert || hasPanel) const _Divider(),
                ],
                const UndoRedoButtons(),
                const _Divider(),
                const _FingerToggle(),
                const ZoomChip(),
                const EditorSyncBadgeIcon(),
                EditorMoreMenu(onOpenSettings: onOpenSettings),
                const SizedBox(width: 4),
              ],
            );
            if (!scroll) return row;
            return SingleChildScrollView(
              key: scrollKey,
              scrollDirection: Axis.horizontal,
              child: row,
            );
          },
        ),
      ),
    );
  }
}

/// (v2.13-search) Toggles the in-note search panel (18).
class _NoteSearchButton extends ConsumerWidget {
  const _NoteSearchButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(editorNoteSearchProvider.select((s) => s.isOpen));
    return IconButton(
      key: EditorToolbar.noteSearchKey,
      isSelected: open,
      onPressed: ref.read(editorNoteSearchProvider.notifier).toggle,
      icon: const Icon(Icons.search, semanticLabel: EditorStrings.noteSearch),
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
/// eraser popup. (v2, 6.13.1) With [withObjectTools], [도형] (`interests`)
/// and [텍스트] (`text_fields`) like the others: the active one again or a
/// long press (active or not) → its tool popup under the button.
class _ToolButtons extends ConsumerWidget {
  const _ToolButtons({required this.withObjectTools});

  final bool withObjectTools;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tools = ref.watch(editorToolProvider);
    final readOnly = ref.watch(editorReadOnlyProvider);
    final commands = ref.watch(editorCommandsProvider);
    final popups = ref.read(editorPopupProvider.notifier);
    final anchors = PopupHost.anchorsOf(context);
    final hasMathPen = ref.watch(
      editorExtensionsProvider.select((e) => e.mathPen != null),
    );
    final hasTextPen = ref.watch(
      editorExtensionsProvider.select((e) => e.textPen != null),
    );
    // (math pen) without the slot a stored math tool shows as the pen (the
    // text pen likewise).
    final active = switch (tools.activeTool) {
      EditorTool.math when !hasMathPen => EditorTool.pen,
      EditorTool.textPen when !hasTextPen => EditorTool.pen,
      final tool => tool,
    };

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
        if (withObjectTools) ...[
          CompositedTransformTarget(
            link: anchors.shape,
            child: ToolButton(
              key: EditorToolbar.shapeKey,
              icon: Icons.interests,
              label: EditorStrings.shapeTool,
              active: active == EditorTool.shape,
              onTap: tap(
                EditorTool.shape,
                const ShapeToolPopup(anchored: true),
              ),
              onLongPress: () =>
                  popups.open(const ShapeToolPopup(anchored: true)),
            ),
          ),
          CompositedTransformTarget(
            link: anchors.text,
            child: ToolButton(
              key: EditorToolbar.textKey,
              icon: Icons.text_fields,
              label: EditorStrings.textTool,
              active: active == EditorTool.text,
              onTap: tap(EditorTool.text, const TextToolPopup(anchored: true)),
              onLongPress: () =>
                  popups.open(const TextToolPopup(anchored: true)),
            ),
          ),
          // (math pen, phase 1) only with EditorExtensions.mathPen.
          if (hasMathPen)
            ToolButton(
              key: EditorToolbar.mathKey,
              icon: Icons.functions,
              label: EditorStrings.mathPenTool,
              active: active == EditorTool.math,
              dotColor: Color(
                tools.penStyles[core.PenTool.ballpoint]!.colorArgb,
              ),
              onTap: tap(EditorTool.math, null),
            ),
          // (text pen, phase 1) only with EditorExtensions.textPen.
          if (hasTextPen)
            ToolButton(
              key: EditorToolbar.textPenKey,
              icon: Icons.edit_note,
              label: EditorStrings.textPenTool,
              active: active == EditorTool.textPen,
              dotColor: Color(
                tools.penStyles[core.PenTool.ballpoint]!.colorArgb,
              ),
              onTap: tap(EditorTool.textPen, null),
            ),
        ],
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
    // (v2, E2-18 — 6.5.3) with iPadOS '펜슬로만 그리기' auto is pen only.
    final capabilities = ref.watch(stylusExtrasProvider).capabilities;
    final penOnly = ref.watch(
      editorSettingsProvider.select(
        (s) => penOnlyEffectiveWith(s, capabilities),
      ),
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
