// lib/src/ui/toolbar/editor_toolbar.dart — 04-editor 6.9.1; (v2) the mic
// button in front of the undo button (m5-7/04-editor 6.13.1, 6.15.4 — E2-16),
// the insert menu [+] in front of it (6.13.1 — E2-12). (E2-13) Toolbar v2
// (6.13.1): the shape and text buttons after the lasso, [⋯도구] below
// [EditorToolbar.foldWidth], the title from [EditorToolbar.titleMinWidth].
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:ui_kit/ui_kit.dart';

import '../../di/editor_extensions.dart';
import '../../di/editor_image_importer.dart';
import '../../scope/editor_scope.dart';
import '../../state/note_search.dart';
import '../../state/page_panel.dart';
import '../../state/popup.dart';
import '../../tools/tool_controller.dart';
import '../../tools/tool_state.dart';
import '../chrome/editor_chrome.dart' show MenuHideButton, MenuHideSlot;
import '../editor_strings.dart';
import '../popup_host.dart';
import 'insert_menu.dart';
import 'mic_button.dart';
import 'more_menu.dart';
import 'note_info_dialog.dart';
import 'overflow_tools_menu.dart';
import 'sync_badge_icon.dart';
import 'tool_button.dart';
import 'tool_glyph.dart';
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

/// [←] title [100%] [☁] │ [펜●] [지우개] [올가미] [도형] [텍스트] │ [+]
/// [🎤] │ [↶] [↷] │ [📄 2 / 4] [🔍] [⋯] — 52 px (v2, m5-7/04-editor 6.13.1;
/// (UI stage 2, 04-editor 20.2) ui_kit line icons, the small names under
/// 올가미 · 도형 · 텍스트 · 삽입 (StyleTokens.toolLabels), the page button with
/// the page count, [📄] [🔍] [⋯] together at the right end). (v2.14-ui, UI
/// stage 1) No [✋] (⋯ '손가락으로 그리기' and settings › 입력 instead); [100%] only
/// while the zoom is not 100 % and [☁] only while sync is not done
/// (ZoomChip, EditorSyncBadgeIcon — after the title, whose slot absorbs
/// their width, so the tools never shift when they appear); a tap on the title opens 노트 정보 (⋯ has
/// it while the title is hidden). The title shows
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

  /// (04-editor 19.1) The least the title keeps: beside it [⌃] shows only
  /// while the title still gets this much (else [⌃] is in [⋯] only). [⌃]
  /// (19) and [🔍] (18) together left the title 3.6 px at 1000 with every
  /// optional button on (test/widget/toolbar_width_test.dart).
  static const double titleLeastWidth = 48;

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
  static const titleKey = ValueKey('editor.toolbar.title');

  /// (v2.14-ui review) The ▾ after the title (it opens 노트 정보).
  static const titleAffordanceKey = ValueKey('editor.toolbar.titleAffordance');

  /// (v2.14-ui) The whole title slot (the title's [titleKey] is the tappable
  /// part; the rest of the slot is blank toolbar).
  static const titleSlotKey = ValueKey('editor.toolbar.titleSlot');
  static const pagePanelKey = ValueKey('editor.toolbar.pagePanel');

  /// (UI stage 2) The '2 / 4' on [pagePanelKey].
  static const pageCountKey = ValueKey('editor.toolbar.pageCount');

  /// (v2.13-search) [🔍] '노트에서 찾기' — at every width from
  /// [foldedSearchMinWidth] (review: Android tablets in portrait are about
  /// 800 wide; (19.1) [foldWidth] leaves the unfolded row room for it).
  /// (v2.14-ui review) Below that width it is the more menu's first item.
  static const noteSearchKey = ValueKey('editor.toolbar.noteSearch');

  /// (v2) Appendix C.
  static const shapeKey = OverflowToolsMenu.shapeKey;
  static const textKey = OverflowToolsMenu.textKey;

  /// (math pen, phase 1) the 수식 펜 (only with EditorExtensions.mathPen).
  static const mathKey = OverflowToolsMenu.mathKey;

  /// (text pen, phase 1) the 텍스트 펜 (only with EditorExtensions.textPen).
  static const textPenKey = OverflowToolsMenu.textPenKey;
  static const overflowToolsKey = OverflowToolsMenu.buttonKey;

  /// (UI stage 2) From this width the page button shows '2 / 4' after its
  /// icon (below it the icon alone; the folded row has no room to spare).
  static const double pageCountMinWidth = 760;

  /// (v2) The sideways scroll below [scrollWidth].
  static const scrollKey = ValueKey('editor.toolbar.scroll');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = ref.watch(editorNoteTitleProvider);
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
      color: StyleTokens.of(context).toolbar,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fold = constraints.maxWidth < foldWidth;
            final scroll = constraints.maxWidth < scrollWidth;
            final row = Row(
              mainAxisSize: scroll ? MainAxisSize.min : MainAxisSize.max,
              children: [
                HoverName(
                  name: EditorStrings.back,
                  child: IconButton(
                    key: backKey,
                    onPressed: onBack,
                    icon: const ToolGlyph(
                      AppIconKind.back,
                      semanticLabel: EditorStrings.back,
                    ),
                  ),
                ),
                // (04-editor 19) [⌃] 메뉴 숨기기 next to [←] (also in [⋯]).
                // With the title [⌃] only while the title keeps
                // titleLeastWidth (19.1).
                if (scroll) const MenuHideButton(),
                if (constraints.maxWidth >= titleMinWidth)
                  Expanded(
                    key: titleSlotKey,
                    child: _TitleSlot(title: title),
                  )
                else if (!scroll)
                  const MenuHideSlot(), // the Spacer, [⌃] when it fits
                // (v2.14-ui review) [100%] and [☁] come and go, so they sit
                // on the title side: the title / Spacer absorbs their width
                // and the tools after them never move.
                const ZoomChip(),
                const EditorSyncBadgeIcon(),
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
                _PagePanelButton(
                  showCount: constraints.maxWidth >= pageCountMinWidth,
                ),
                if (constraints.maxWidth >= foldedSearchMinWidth)
                  const _NoteSearchButton(),
                EditorMoreMenu(
                  onOpenSettings: onOpenSettings,
                  showNoteInfo: constraints.maxWidth < titleMinWidth,
                  showNoteSearch: constraints.maxWidth < foldedSearchMinWidth,
                ),
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

/// (19.1) The title, with [⌃] before it while the title keeps
/// [EditorToolbar.titleLeastWidth]. (v2.14-ui) A tap on it opens 노트 정보
/// (NoteInfoDialog); the ink area is the text's width, at most the slot.
class _TitleSlot extends ConsumerWidget {
  const _TitleSlot({required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Align(
      alignment: AlignmentDirectional.centerStart,
      child: Semantics(
        button: true,
        hint: EditorStrings.titleOpensNoteInfo,
        child: InkWell(
          key: EditorToolbar.titleKey,
          borderRadius: BorderRadius.circular(8),
          onTap: () => showNoteInfoDialog(context, ref),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              // (v2.14-ui review) ▾ after the title: it can be tapped.
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 2),
                  AppIcon(
                    AppIconKind.chevronDown,
                    key: EditorToolbar.titleAffordanceKey,
                    size: 18,
                    color: StyleTokens.of(context).textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxWidth >=
              MenuHideButton.width + EditorToolbar.titleLeastWidth
          ? Row(
              children: [
                const MenuHideButton(),
                Expanded(child: text),
              ],
            )
          : text,
    );
  }
}

/// (v2.13-search) Toggles the in-note search panel (18).
class _NoteSearchButton extends ConsumerWidget {
  const _NoteSearchButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(editorNoteSearchProvider.select((s) => s.isOpen));
    return HoverName(
      name: EditorStrings.noteSearch,
      child: IconButton(
        key: EditorToolbar.noteSearchKey,
        isSelected: open,
        onPressed: ref.read(editorNoteSearchProvider.notifier).toggle,
        icon: const ToolGlyph(
          AppIconKind.search,
          semanticLabel: EditorStrings.noteSearch,
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
    child: VerticalDivider(width: 12, color: StyleTokens.of(context).hairline),
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
          glyph: AppIconKind.lasso,
          caption: EditorStrings.lasso,
          label: EditorStrings.lasso,
          active: active == EditorTool.lasso,
          onTap: tap(EditorTool.lasso, null),
        ),
        if (withObjectTools) ...[
          CompositedTransformTarget(
            link: anchors.shape,
            child: ToolButton(
              key: EditorToolbar.shapeKey,
              glyph: AppIconKind.shape,
              caption: EditorStrings.shapeTool,
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
              glyph: AppIconKind.text,
              caption: EditorStrings.textTool,
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
              glyph: AppIconKind.math,
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
              icon: AppIconKind.textPen.material,
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

/// [📄 2 / 4] (UI stage 2 — the page panel button and the page count in
/// one, 04-editor 20.2): opens / closes the page panel (selected while
/// open); the count is the current page / all pages.
class _PagePanelButton extends ConsumerWidget {
  const _PagePanelButton({required this.showCount});

  /// Whether the '2 / 4' shows (EditorToolbar.pageCountMinWidth).
  final bool showCount;

  /// The widest the count gets; a longer one ('128 / 256') scales down.
  static const double countMaxWidth = 40;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(editorPagePanelProvider.select((p) => p.isOpen));
    final commands = ref.watch(editorCommandsProvider);
    final index = ref.watch(editorCurrentPageIndexProvider);
    final viewport = ref.watch(editorViewportProvider);
    return HoverName(
      name: EditorStrings.pagePanel,
      child: ListenableBuilder(
        listenable: viewport,
        builder: (context, _) {
          final count = viewport.pages.length;
          final label = count == 0 || !showCount
              ? null
              : EditorStrings.pageIndicator(
                  index.clamp(0, count - 1) + 1,
                  count,
                );
          return IconButton(
            key: EditorToolbar.pagePanelKey,
            isSelected: open,
            onPressed: commands.togglePagePanel,
            style: label == null
                ? null
                : IconButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
            icon: Semantics(
              label: EditorStrings.pagePanel,
              value: label,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ToolGlyph(AppIconKind.pages),
                  if (label != null) ...[
                    const SizedBox(width: 4),
                    ExcludeSemantics(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: countMaxWidth,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            key: EditorToolbar.pageCountKey,
                            maxLines: 1,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                  color: IconTheme.of(context).color,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
