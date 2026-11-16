// lib/src/ui/toolbar/editor_toolbar.dart — 04-editor 6.9.1; (v2) the mic
// button in front of the undo button (m5-7/04-editor 6.13.1, 6.15.4 — E2-16),
// the insert menu [+] in front of it (6.13.1 — E2-12). (E2-13) Toolbar v2
// (6.13.1): the shape and text buttons after the lasso, [⋯도구] on narrow
// screens. (v2.15-ui — 22.4) The pen tray instead of the pen and eraser
// buttons; what gives way at each width is [EditorToolbar.planFor].
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:ui_kit/ui_kit.dart';

import '../../di/editor_extensions.dart';
import '../../di/editor_image_importer.dart';
import '../../scope/editor_scope.dart';
import '../../state/note_search.dart';
import '../../state/page_panel.dart';
import '../../state/panel.dart';
import '../../state/popup.dart';
import '../../state/settings/editor_device_state.dart';
import '../../tools/tool_controller.dart';
import '../../tools/tool_state.dart';
import '../chrome/editor_chrome.dart' show MenuHideButton;
import '../editor_strings.dart';
import '../pen/pen_tray.dart';
import '../popup_host.dart';
import 'insert_menu.dart';
import 'mic_button.dart';
import 'more_menu.dart';
import 'note_info_dialog.dart';
import 'overflow_tools_menu.dart';
import 'sync_badge_icon.dart';
import 'tool_button.dart';
import 'undo_redo_buttons.dart';
import 'zoom_chip.dart';

/// The toolbar's layout at one width (v2.15-ui, m5-7/04-editor 22.4).
@immutable
class ToolbarPlan {
  const ToolbarPlan({
    required this.trayPens,
    required this.title,
    required this.search,
    required this.fold,
    required this.scroll,
  });

  /// Pens the tray shows (0: the tray is in the floating palette).
  final int trayPens;
  final bool title;
  final bool search;

  /// [도형] [텍스트] [+] (and a recording [🎤]) are in [⋯도구].
  final bool fold;

  /// The row scrolls sideways.
  final bool scroll;

  @override
  String toString() =>
      'ToolbarPlan(pens: $trayPens, title: $title, search: $search, '
      'fold: $fold, scroll: $scroll)';
}

/// [←] title [100%] [☁] [🔍] [▤] [pen tray: pens · eraser] [올가미] [도형]
/// [텍스트] │ [+] [🎤] │ [↶] [↷] │ [⋯] — 52 px.
///
/// (v2.15-ui, UI stages 3–5 — m5-7/04-editor 22) The pen tray (PenTray) takes
/// the place of the pen and eraser buttons and of the preset row under the
/// toolbar. 수식 펜 · 텍스트 펜 are in [+] ('수식 쓰기', '손글씨를 텍스트로') and
/// so is 녹음; [🎤] shows in the row only while this note records or the
/// recording panel is open. What gives way as the toolbar narrows
/// ([planFor]): the tray 8 → 5 pens, then the title, then [🔍] (into ⋯),
/// then the tray 5 → 3; [올가미] [도형] [텍스트] [+] fold into [⋯도구] only
/// below that (split screen), and the row scrolls only past that.
///
/// (v2.14-ui, UI stage 1) No [✋]; [100%] only while the zoom is not 100 %
/// and [☁] only while sync is not done — in the flexible slot with the
/// title, shown when they fit, so the tools never shift and never overflow
/// when they appear. A tap on the title opens 노트 정보 (⋯ has it while the
/// title is hidden). [▤] toggles the page panel (E-17). On a read-only note
/// the tools are disabled (6.9.1). [+] only when the image slot or
/// EditorExtensions offer something (InsertMenu.hasItems).
class EditorToolbar extends ConsumerWidget {
  const EditorToolbar({super.key, required this.onBack, this.onOpenSettings});

  final VoidCallback onBack;
  final VoidCallback? onOpenSettings;

  static const double height = 52;

  /// (04-editor 19.1) The least the title keeps: beside it [⌃] shows only
  /// while the title still gets this much (else [⌃] is in [⋯] only).
  static const double titleLeastWidth = 48;

  /// (v2.15-ui) The title shows only when it gets at least this much.
  static const double titleMinRoom = 160;

  /// (v2.15-ui) The least the flexible slot keeps without the title: room
  /// for a narrow [☁] (a sync problem must stay visible).
  static const double flexLeast = 36;

  /// Widths of the fixed parts (IconButton / ToolButton 48, divider 12).
  static const double _button = 48;
  static const double _divider = 12;

  /// The width of the row without the tray, the title slot and [🔍].
  static double fixedWidth({
    required bool hasInsert,
    required bool mic,
    required bool fold,
  }) {
    var w = _button /* ← */ + _button /* ▤ */ + 4 /* end */;
    w += fold ? 2 * _button : 3 * _button; // 올가미 (+ 도형 텍스트 | ⋯도구)
    w += _divider;
    if (!fold && (hasInsert || mic)) {
      w += (hasInsert ? _button : 0) + (mic ? _button : 0) + _divider;
    }
    w += 2 * _button + _divider; // ↶ ↷
    w += _button; // ⋯
    return w;
  }

  /// (v2.15-ui) The layout at [width]: the first that fits of — 8 pens +
  /// [🔍] + title, 5 pens + [🔍] + title, 5 + [🔍], 5, 3, then folded with 3,
  /// then scrolling. With [detached] the tray is in the floating palette.
  static ToolbarPlan planFor(
    double width, {
    required bool hasInsert,
    required bool mic,
    bool detached = false,
  }) {
    double tray(int pens) => detached ? 0 : PenTray.widthFor(pens);
    final pensAt = detached ? 0 : 1; // 0 pens when detached
    final fixed = fixedWidth(hasInsert: hasInsert, mic: mic, fold: false);
    final room = width - fixed;
    final options = <(int, bool, bool)>[
      (8, true, true),
      (5, true, true),
      (5, true, false),
      (5, false, false),
      (3, false, false),
    ];
    for (final (pens, search, title) in options) {
      // The flexible slot keeps at least [flexLeast] (a narrow [☁]).
      final need =
          tray(pens) +
          (search ? _button : 0) +
          (title ? titleMinRoom : flexLeast);
      if (room >= need) {
        return ToolbarPlan(
          trayPens: pens * pensAt,
          title: title,
          search: search,
          fold: false,
          scroll: false,
        );
      }
    }
    final folded = fixedWidth(hasInsert: hasInsert, mic: mic, fold: true);
    return ToolbarPlan(
      trayPens: 3 * pensAt,
      title: false,
      search: false,
      fold: true,
      scroll: width < folded + tray(3),
    );
  }

  static const backKey = ValueKey('editor.toolbar.back');

  /// The tray's current pen (the lifted one while the pen is the tool).
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

  /// (v2.13-search) [🔍] '노트에서 찾기' (where [planFor] keeps it; else the
  /// more menu's first item).
  static const noteSearchKey = ValueKey('editor.toolbar.noteSearch');

  /// (v2) Appendix C.
  static const shapeKey = OverflowToolsMenu.shapeKey;
  static const textKey = OverflowToolsMenu.textKey;
  static const overflowToolsKey = OverflowToolsMenu.buttonKey;

  /// (v2) The sideways scroll.
  static const scrollKey = ValueKey('editor.toolbar.scroll');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = ref.watch(editorNoteTitleProvider);
    final hasPanel = ref.watch(
      editorExtensionsProvider.select((e) => e.recordingPanel != null),
    );
    final noteId = ref.watch(editorNoteIdProvider);
    final recording =
        hasPanel &&
        (ref.watch(editorPanelProvider) ||
            micIndicatorOf(
                  ref.watch(editorRecorderStatusProvider).value,
                  noteId,
                ) ==
                MicIndicator.thisNote);
    final hasInsert = InsertMenu.hasItems(
      ref.watch(editorImageImporterProvider),
      ref.watch(editorExtensionsProvider.select((e) => e.insertMenuItems)),
      textPen: ref.watch(
        editorExtensionsProvider.select((e) => e.textPen != null),
      ),
      mathPen: ref.watch(
        editorExtensionsProvider.select((e) => e.mathPen != null),
      ),
      recording: hasPanel,
    );
    final detached = ref.watch(
      editorDeviceStateProvider.select((s) => s.paletteDetached),
    );
    return Material(
      color: StyleTokens.of(context).toolbar,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final plan = planFor(
              constraints.maxWidth,
              hasInsert: hasInsert,
              mic: recording,
              detached: detached,
            );
            final row = Row(
              mainAxisSize: plan.scroll ? MainAxisSize.min : MainAxisSize.max,
              children: [
                IconButton(
                  key: backKey,
                  onPressed: onBack,
                  icon: const Icon(
                    Icons.arrow_back,
                    semanticLabel: EditorStrings.back,
                  ),
                ),
                if (plan.scroll)
                  const MenuHideButton()
                else
                  Expanded(
                    key: plan.title ? titleSlotKey : null,
                    child: _FlexSlot(title: plan.title ? title : null),
                  ),
                if (plan.search) const _NoteSearchButton(),
                const _PagePanelButton(),
                if (plan.trayPens > 0) PenTray(capacity: plan.trayPens),
                _ToolButtons(withObjectTools: !plan.fold),
                const _Divider(),
                if (plan.fold) ...[
                  OverflowToolsMenu(hasInsert: hasInsert, hasPanel: hasPanel),
                  const _Divider(),
                ] else ...[
                  if (hasInsert) const InsertMenu(),
                  if (recording) const MicButton(),
                  if (hasInsert || recording) const _Divider(),
                ],
                const UndoRedoButtons(),
                const _Divider(),
                EditorMoreMenu(
                  onOpenSettings: onOpenSettings,
                  showNoteInfo: !plan.title,
                  showNoteSearch: !plan.search,
                ),
                const SizedBox(width: 4),
              ],
            );
            if (!plan.scroll) return row;
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

/// (v2.15-ui) The flexible slot after [←]: [⌃], the title (when [title] is
/// set), [100%] and [☁] — each only when it fits, in the order [☁] (a sync
/// problem must show), [100%], [⌃], the title; never an overflow.
class _FlexSlot extends ConsumerWidget {
  const _FlexSlot({required this.title});

  final String? title;

  static const double _zoomWidth = 72;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badge = ref.watch(core.syncBadgeProvider).value;
    final badgeShown =
        badge != null &&
        badge.display != core.SyncDisplayState.off &&
        badge.display != core.SyncDisplayState.done;
    final viewport = ref.watch(editorViewportProvider);
    return ListenableBuilder(
      listenable: viewport,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          var room = constraints.maxWidth;
          // [☁] must show: 36 px wide where the full 48 does not fit.
          final badgeWidth = room >= 48 ? 48.0 : 36.0;
          final showBadge = badgeShown && room >= badgeWidth;
          if (showBadge) room -= badgeWidth;
          final showZoom = !ZoomChip.isFit(viewport.zoom) && room >= _zoomWidth;
          if (showZoom) room -= _zoomWidth;
          final t = title;
          final children = <Widget>[
            if (t != null)
              Expanded(child: _TitleSlot(title: t))
            else ...[
              if (room >= MenuHideButton.width) const MenuHideButton(),
              const Spacer(),
            ],
            if (showZoom) const ZoomChip(),
            if (showBadge)
              SizedBox(
                width: badgeWidth,
                child: OverflowBox(
                  maxWidth: 48,
                  child: const EditorSyncBadgeIcon(),
                ),
              ),
          ];
          return Row(children: children);
        },
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
                  Icon(
                    Icons.arrow_drop_down,
                    key: EditorToolbar.titleAffordanceKey,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

/// [올가미] and, with [withObjectTools], [도형] (`interests`) and [텍스트]
/// (`text_fields`). Tap: inactive tool → select it; the active shape / text
/// tool again or a long press (active or not) → its tool popup under the
/// button (v2, 6.13.1). (v2.15-ui) The pen and the eraser are in the pen
/// tray; 수식 펜 and 텍스트 펜 in [+].
class _ToolButtons extends ConsumerWidget {
  const _ToolButtons({required this.withObjectTools});

  final bool withObjectTools;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(editorToolProvider.select((s) => s.activeTool));
    final readOnly = ref.watch(editorReadOnlyProvider);
    final commands = ref.watch(editorCommandsProvider);
    final popups = ref.read(editorPopupProvider.notifier);
    final anchors = PopupHost.anchorsOf(context);

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
