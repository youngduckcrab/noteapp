// lib/src/ui/toolbar/editor_toolbar.dart — 04-editor 6.9.1; (v2) the mic
// button in front of the undo button (m5-7/04-editor 6.13.1, 6.15.4 — E2-16),
// the insert menu [+] in front of it (6.13.1 — E2-12). (E2-13) Toolbar v2
// (6.13.1): the shape and text buttons after the lasso, [⋯도구] on narrow
// screens. (v2.15-ui — 23.4) The pen tray instead of the pen and eraser
// buttons; what gives way at each width is [EditorToolbar.planFor].
import 'dart:math' as math;

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
import '../../state/preset_bar.dart';
import '../../state/settings/editor_device_state.dart';
import '../../tools/tool_controller.dart';
import '../../tools/tool_state.dart';
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
import 'tool_glyph.dart';
import 'undo_redo_buttons.dart';
import 'zoom_chip.dart';

/// (UI stage 2 + 5) Whether the toolbar's page button shows '2 / 4'
/// ([ToolbarPlan.pageCount]); PageIndicator shows the count over the page
/// when it does not. Written by [EditorToolbar] after a layout that changes
/// it; true until the first toolbar layout.
class EditorToolbarPageCountNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(editorNoteIdProvider);
    return true;
  }

  void set(bool shown) {
    if (state != shown) state = shown;
  }
}

final editorToolbarPageCountProvider =
    NotifierProvider<EditorToolbarPageCountNotifier, bool>(
      EditorToolbarPageCountNotifier.new,
      dependencies: [editorNoteIdProvider],
      name: 'editorToolbarPageCountProvider',
    );

/// (v2.16-ui — 04-editor 24) Which bar [EditorToolbar] draws.
enum EditorToolbarVariant {
  /// 크래프트: the full-width toolbar (04-editor 22–23).
  docked,

  /// 미니멀: the same row in a rounded pill as wide as it needs (at most 5
  /// pens), floating over the page; narrower screens drop parts by
  /// [EditorToolbar.planFor] like the docked one.
  floating,

  /// 스튜디오 with its rail: ←, title, [🎤], undo / redo, [📄 2 / 4],
  /// [🔍], [⋯] — the pens and tools (and [삽입]) are in the rail
  /// (EditorRail).
  slim,
}

/// The toolbar's layout at one width (v2.15-ui, m5-7/04-editor 23.4).
@immutable
class ToolbarPlan {
  const ToolbarPlan({
    required this.trayPens,
    required this.title,
    required this.search,
    required this.fold,
    required this.scroll,
    this.pageCount = false,
  });

  /// Pens the tray shows (0: the tray is in the floating palette).
  final int trayPens;
  final bool title;
  final bool search;

  /// [도형] [텍스트] [+] (and a recording [🎤]) are in [⋯도구].
  final bool fold;

  /// The row scrolls sideways.
  final bool scroll;

  /// (UI stage 2) The page button shows '2 / 4' after its icon.
  final bool pageCount;

  @override
  String toString() =>
      'ToolbarPlan(pens: $trayPens, title: $title, search: $search, '
      'fold: $fold, scroll: $scroll, pageCount: $pageCount)';
}

/// [←] title [100%] [☁] [pen tray: pens · eraser] [올가미] [도형] [텍스트] │
/// [+] [🎤] │ [↶] [↷] │ [📄 2 / 4] [🔍] [⋯] — [heightOf]
/// (StyleTokens.toolbarHeight: 64 크래프트, 52 미니멀, 60 스튜디오; at least
/// [minHeight]).
///
/// (UI stage 2, 04-editor 22) ui_kit line icons, the small names under
/// 올가미 · 도형 · 텍스트 · 삽입 (StyleTokens.toolLabels), the page button with
/// the page count, [📄] [🔍] [⋯] together at the right end; no [⌃] in the
/// row ('집중 모드' is in [⋯]).
///
/// (v2.15-ui, UI stages 3–5 — m5-7/04-editor 23) The pen tray (PenTray) takes
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
/// title is hidden). [📄] toggles the page panel (E-17). On a read-only note
/// the tools are disabled (6.9.1). [+] only when the image slot or
/// EditorExtensions offer something (InsertMenu.hasItems).
///
/// (v2.16-ui — 04-editor 24) [variant]: the docked bar, 미니멀's floating
/// pill, or 스튜디오's slim bar beside its rail.
class EditorToolbar extends ConsumerWidget {
  const EditorToolbar({
    super.key,
    required this.onBack,
    this.onOpenSettings,
    this.variant = EditorToolbarVariant.docked,
  });

  final VoidCallback onBack;
  final VoidCallback? onOpenSettings;

  /// (v2.16-ui) Which bar.
  final EditorToolbarVariant variant;

  /// (v2.16-ui) The floating pill and its slim-bar row.
  static const pillKey = ValueKey('editor.toolbar.pill');
  static const slimKey = ValueKey('editor.toolbar.slim');

  /// (v2.16-ui) The pill's inner padding at each end.
  static const double pillPadding = 6;

  /// (v2.16-ui) The most pens the floating pill shows (the 미니멀 mockup's
  /// five strokes; the docked bar goes to 8).
  static const int pillMaxPens = 5;

  /// (v2.16-ui) The room the pill gives the title when it can grow.
  static const double pillTitleRoom = 200;

  /// (v2.16-ui) The slim bar's height (the 52 px of v1).
  static const double slimHeight = minHeight;

  /// (v2.15-ui review) The least toolbar height (the 52 px of v1).
  static const double minHeight = 52;

  /// (v2.15-ui review) The toolbar's height in [context]'s style: the
  /// style's toolbarHeight hint, so the pen tray's pens stand tall (about
  /// 42 px of each drawing shows) and a lifted pen stays inside the bar.
  static double heightOf(BuildContext context) =>
      math.max(minHeight, StyleTokens.of(context).toolbarHeight);

  /// (04-editor 19.1) The least the title keeps (test/widget/
  /// toolbar_width_test.dart). (UI stage 2) [⌃] left the row.
  static const double titleLeastWidth = 48;

  /// (UI stage 2) From this width the page button shows '2 / 4' after its
  /// icon (below it the icon alone, and PageIndicator shows the count over
  /// the page).
  static const double pageCountMinWidth = 760;

  /// (UI stage 2) What the '2 / 4' adds to the page button: its padding
  /// (2 × 6), the gap (4) and the count (at most 40), less the 26 px the
  /// icon-only button has around its 22-px glyph.
  static const double pageCountExtra = 30;

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
    bool pageCount = false,
  }) {
    var w = _button /* ← */ + _button /* 📄 */ + 4 /* end */;
    if (pageCount) w += pageCountExtra;
    w += fold ? 2 * _button : 3 * _button; // 올가미 (+ 도형 텍스트 | ⋯도구)
    w += _divider;
    // (v2.15-ui review) Folded: │ after [⋯도구] too.
    if (fold) w += _divider;
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
  ///
  /// [shownFor] is how many slots the tray takes at a capacity (trayPensOf:
  /// fewer pinned pens, or one more for '지금 펜' when the current pen is none
  /// of them); null = the capacity.
  ///
  /// (v2.16-ui review) [flexRoom]: what the flexible slot keeps without the
  /// title ([flexLeast]; 미니멀's pill passes 0 while there is no [☁] to
  /// show — no blank stretch after [←], the room goes to the pens).
  static ToolbarPlan planFor(
    double width, {
    required bool hasInsert,
    required bool mic,
    bool detached = false,
    int Function(int capacity)? shownFor,
    int maxPens = 8,
    double flexRoom = flexLeast,
  }) {
    double tray(int pens) =>
        detached ? 0 : PenTray.widthFor(shownFor?.call(pens) ?? pens);
    final pensAt = detached ? 0 : 1; // 0 pens when detached
    // (UI stage 2 + 5) The '2 / 4' only from [pageCountMinWidth], and only
    // where it fits after 5 pens (below that PageIndicator shows the count
    // over the page — editorToolbarPageCountProvider).
    final countFits = width >= pageCountMinWidth;
    final room =
        width - fixedWidth(hasInsert: hasInsert, mic: mic, fold: false);
    final options = <(int, bool, bool, bool)>[
      (8, true, true, true),
      (5, true, true, true),
      (5, true, false, true),
      (5, true, false, false),
      (5, false, false, true),
      (5, false, false, false),
      (3, false, false, true),
      (3, false, false, false),
    ];
    for (final (pens, search, title, count) in options) {
      if (count && !countFits) continue;
      if (pens > maxPens) continue;
      // The flexible slot keeps at least [flexLeast] (a narrow [☁]).
      final need =
          tray(pens) +
          (search ? _button : 0) +
          (title ? titleMinRoom : flexRoom) +
          (count ? pageCountExtra : 0);
      if (room >= need) {
        return ToolbarPlan(
          trayPens: pens * pensAt,
          title: title,
          search: search,
          fold: false,
          scroll: false,
          pageCount: count,
        );
      }
    }
    final folded = fixedWidth(hasInsert: hasInsert, mic: mic, fold: true);
    return ToolbarPlan(
      trayPens: 3 * pensAt,
      title: false,
      search: false,
      fold: true,
      // (v2.15-ui review) Room for a narrow [☁] too, or the row scrolls
      // (where [☁] and [100%] follow [←]).
      scroll: width < folded + tray(3) + flexRoom,
      pageCount: false,
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

  /// (owner review) The folder · last-edit line under the title.
  static const titleSubtitleKey = ValueKey('editor.toolbar.titleSubtitle');

  /// (v2.14-ui) The whole title slot (the title's [titleKey] is the tappable
  /// part; the rest of the slot is blank toolbar).
  static const titleSlotKey = ValueKey('editor.toolbar.titleSlot');
  static const pagePanelKey = ValueKey('editor.toolbar.pagePanel');

  /// The flexible slot after [←] (title, [100%], [☁]) and the [+] slot:
  /// stable keys so a plan change keeps the widgets after them.
  static const flexSlotKey = ValueKey('editor.toolbar.flexSlot');
  static const insertSlotKey = ValueKey('editor.toolbar.insertSlot');

  /// (UI stage 2) The '2 / 4' on [pagePanelKey].
  static const pageCountKey = ValueKey('editor.toolbar.pageCount');

  /// (v2.13-search) [🔍] '노트에서 찾기' (where [planFor] keeps it; else the
  /// more menu's first item).
  static const noteSearchKey = ValueKey('editor.toolbar.noteSearch');

  /// (v2) Appendix C.
  static const shapeKey = OverflowToolsMenu.shapeKey;
  static const textKey = OverflowToolsMenu.textKey;
  static const overflowToolsKey = OverflowToolsMenu.buttonKey;

  /// (v2) The sideways scroll.
  static const scrollKey = ValueKey('editor.toolbar.scroll');

  /// (v2.16-ui) The pill's width when it has all the room it wants: every
  /// part, [pillMaxPens] pens, [🔍], the page count and [pillTitleRoom].
  static double pillIdealWidth({
    required bool hasInsert,
    required bool mic,
    required double tray,
  }) =>
      fixedWidth(hasInsert: hasInsert, mic: mic, fold: false) +
      tray +
      _button +
      pageCountExtra +
      pillTitleRoom +
      2 * pillPadding;

  /// (v2.16-ui) Writes whether this bar shows '2 / 4' (PageIndicator shows
  /// the count over the page when it does not).
  static void _reportPageCount(
    BuildContext context,
    WidgetRef ref,
    bool shown,
  ) {
    if (ref.read(editorToolbarPageCountProvider) == shown) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        ref.read(editorToolbarPageCountProvider.notifier).set(shown);
      }
    });
  }

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
    // (v2.15-ui review) A read-only note (in the trash, a v1 copy) keeps
    // [🎤]: [+] is disabled there, and its recordings must stay playable.
    final readOnly = ref.watch(editorReadOnlyProvider);
    final mic = recording || (readOnly && hasPanel);
    final presets = ref.watch(editorTrayPresetsProvider).value ?? const [];
    final current = ref.watch(editorToolProvider.select((s) => s.currentPen));
    int shownFor(int capacity) =>
        trayPensOf(presets, current, capacity).pens.length;
    final tokens = StyleTokens.of(context);
    if (variant == EditorToolbarVariant.slim) {
      return _buildSlim(context, ref, tokens, title, mic);
    }
    final floating = variant == EditorToolbarVariant.floating;
    // (v2.16-ui review) The pill keeps room after [←] only for a [☁] that
    // has something to say.
    final flexRoom = !floating
        ? flexLeast
        : _syncBadgeShown(ref.watch(core.syncBadgeProvider).value)
        ? flexLeast
        : 0.0;
    return Material(
      type: floating ? MaterialType.transparency : MaterialType.canvas,
      color: floating ? null : tokens.toolbar,
      // (UI stage 2) The line icons in the text colour (the mockups' ink),
      // the accent while selected, dimmed while disabled.
      child: IconButtonTheme(
        data: IconButtonThemeData(style: toolbarIconButtonStyle(tokens)),
        child: SizedBox(
          height: heightOf(context),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // (v2.16-ui) The pill is as wide as it needs, at most the
              // room; the row inside it plans for its inner width.
              var pillWidth = floating
                  ? math.min(
                      constraints.maxWidth,
                      pillIdealWidth(
                        hasInsert: hasInsert,
                        mic: mic,
                        tray: detached
                            ? 0
                            : PenTray.widthFor(shownFor(pillMaxPens)),
                      ),
                    )
                  : constraints.maxWidth;
              final plan = planFor(
                floating ? pillWidth - 2 * pillPadding : constraints.maxWidth,
                hasInsert: hasInsert,
                mic: mic,
                detached: detached,
                shownFor: shownFor,
                maxPens: floating ? pillMaxPens : 8,
                flexRoom: flexRoom,
              );
              // (v2.16-ui) Without the title the pill hugs its buttons (no
              // blank stretch after [←]).
              if (floating && !plan.title && !plan.scroll) {
                pillWidth = math.min(
                  pillWidth,
                  fixedWidth(hasInsert: hasInsert, mic: mic, fold: plan.fold) +
                      (plan.trayPens > 0
                          ? PenTray.widthFor(shownFor(plan.trayPens))
                          : 0) +
                      (plan.search ? _button : 0) +
                      (plan.pageCount ? pageCountExtra : 0) +
                      flexRoom +
                      2 * pillPadding,
                );
              }
              // PageIndicator shows the count where this row does not.
              _reportPageCount(context, ref, plan.pageCount);
              final row = Row(
                mainAxisSize: plan.scroll ? MainAxisSize.min : MainAxisSize.max,
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
                  // (UI stage 2, proposal 1) No [⌃] here any more: '집중
                  // 모드' is in [⋯] only.
                  if (plan.scroll)
                    // (v2.15-ui review) The row scrolls: [100%] and [☁]
                    // stay in it (a sync problem must show).
                    const _ScrollFlexItems()
                  else
                    // One key whether or not the title shows, so the
                    // children after it (an open [+] menu) are kept when
                    // the plan changes.
                    Expanded(
                      key: flexSlotKey,
                      child: plan.title
                          ? KeyedSubtree(
                              key: titleSlotKey,
                              child: _FlexSlot(title: title),
                            )
                          : const _FlexSlot(title: null),
                    ),
                  if (plan.trayPens > 0) PenTray(capacity: plan.trayPens),
                  ToolbarToolButtons(withObjectTools: !plan.fold),
                  const _Divider(),
                  if (plan.fold) ...[
                    OverflowToolsMenu(hasInsert: hasInsert, hasPanel: hasPanel),
                    const _Divider(),
                  ] else ...[
                    if (hasInsert) const InsertMenu(key: insertSlotKey),
                    if (mic) const MicButton(),
                    if (hasInsert || mic) const _Divider(),
                  ],
                  const UndoRedoButtons(),
                  const _Divider(),
                  _PagePanelButton(showCount: plan.pageCount),
                  if (plan.search) const _NoteSearchButton(),
                  EditorMoreMenu(
                    onOpenSettings: onOpenSettings,
                    showNoteInfo: !plan.title,
                    showNoteSearch: !plan.search,
                  ),
                  if (!floating) const SizedBox(width: 4),
                ],
              );
              final Widget content = !plan.scroll
                  ? row
                  : SingleChildScrollView(
                      key: scrollKey,
                      scrollDirection: Axis.horizontal,
                      child: row,
                    );
              if (!floating) return content;
              return Align(
                alignment: Alignment.topCenter,
                child: _Pill(width: pillWidth, child: content),
              );
            },
          ),
        ),
      ),
    );
  }
}

extension on EditorToolbar {
  /// (v2.16-ui) 스튜디오's slim bar: [←] title │ [🎤] │ [↶] [↷] │
  /// [📄 2 / 4] [🔍] [⋯]; the title (and its folder · date line) only when
  /// it gets [EditorToolbar.titleMinRoom], else the flexible slot keeps
  /// [☁] / [100%].
  Widget _buildSlim(
    BuildContext context,
    WidgetRef ref,
    StyleTokens tokens,
    String title,
    bool mic,
  ) {
    return Material(
      key: EditorToolbar.slimKey,
      color: tokens.toolbar,
      child: IconButtonTheme(
        data: IconButtonThemeData(style: toolbarIconButtonStyle(tokens)),
        child: SizedBox(
          height: EditorToolbar.slimHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const b = EditorToolbar._button;
              const d = EditorToolbar._divider;
              // (review) [삽입] stands in the rail with the other tools.
              final fixed =
                  b /* ← */ +
                  (mic ? b + d : 0) +
                  2 * b +
                  d /* ↶ ↷ │ */ +
                  b +
                  EditorToolbar.pageCountExtra /* 📄 2 / 4 */ +
                  b /* 🔍 */ +
                  b /* ⋯ */ +
                  4;
              final room = constraints.maxWidth - fixed;
              final showTitle = room >= EditorToolbar.titleMinRoom;
              final search = room >= EditorToolbar.flexLeast;
              final count = room >= EditorToolbar.flexLeast + b;
              EditorToolbar._reportPageCount(context, ref, count);
              return Row(
                children: [
                  HoverName(
                    name: EditorStrings.back,
                    child: IconButton(
                      key: EditorToolbar.backKey,
                      onPressed: onBack,
                      icon: const ToolGlyph(
                        AppIconKind.back,
                        semanticLabel: EditorStrings.back,
                      ),
                    ),
                  ),
                  Expanded(
                    key: EditorToolbar.flexSlotKey,
                    child: showTitle
                        ? KeyedSubtree(
                            key: EditorToolbar.titleSlotKey,
                            child: _FlexSlot(title: title),
                          )
                        : const _FlexSlot(title: null),
                  ),
                  if (mic) ...[const MicButton(), const _Divider()],
                  const UndoRedoButtons(),
                  const _Divider(),
                  _PagePanelButton(showCount: count),
                  if (search) const _NoteSearchButton(),
                  EditorMoreMenu(
                    onOpenSettings: onOpenSettings,
                    showNoteInfo: !showTitle,
                    showNoteSearch: !search,
                  ),
                  const SizedBox(width: 4),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// (v2.16-ui) 미니멀's floating pill: the toolbar colour, rounded, the
/// style's floating shadow (a soft outline in dark, where a shadow barely
/// shows).
class _Pill extends StatelessWidget {
  const _Pill({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = StyleTokens.of(context);
    final radius = BorderRadius.circular(18);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: tokens.shadows(2),
      ),
      child: Material(
        key: EditorToolbar.pillKey,
        color: tokens.toolbar,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: tokens.isDark
              ? BorderSide(color: tokens.outline.withValues(alpha: 0.35))
              : BorderSide(color: tokens.hairline.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          height: EditorToolbar.heightOf(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: EditorToolbar.pillPadding,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// (UI stage 2) The toolbar's icon buttons: [StyleTokens.textPrimary]
/// (the mockups' ink), [StyleTokens.accent] while selected (the open page
/// panel or search), 38 % while disabled.
ButtonStyle toolbarIconButtonStyle(StyleTokens tokens) => ButtonStyle(
  foregroundColor: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.disabled)
        ? tokens.textPrimary.withValues(alpha: 0.38)
        : states.contains(WidgetState.selected)
        ? tokens.accent
        : tokens.textPrimary,
  ),
);

/// (v2.15-ui) The flexible slot after [←]: the title (when [title] is set),
/// [100%] and [☁] — each only when it fits, in the order [☁] (a sync
/// problem must show), [100%], the title; never an overflow.
/// Whether [badge] has something to say ([☁] shows: not off, not done).
bool _syncBadgeShown(core.SyncBadge? badge) =>
    badge != null &&
    badge.display != core.SyncDisplayState.off &&
    badge.display != core.SyncDisplayState.done;

class _FlexSlot extends ConsumerWidget {
  const _FlexSlot({required this.title});

  final String? title;

  /// (v2.15-ui review) The most [100%] takes ('110%' measures ~80 px; it
  /// was planned as 72 and overflowed next to [☁]); it is clipped to this.
  static const double _zoomWidth = 88;

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
            else
              const Spacer(),
            if (showZoom)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _zoomWidth),
                child: const ClipRect(child: ZoomChip()),
              ),
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

/// (v2.15-ui review) [100%] and [☁] in a scrolling row (each only while it
/// has something to say, like in [_FlexSlot]).
class _ScrollFlexItems extends ConsumerWidget {
  const _ScrollFlexItems();

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
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!ZoomChip.isFit(viewport.zoom)) const ZoomChip(),
          if (badgeShown) const EditorSyncBadgeIcon(),
        ],
      ),
    );
  }
}

/// The title. (v2.14-ui) A tap on it opens 노트 정보
/// (NoteInfoDialog); the ink area is the text's width, at most the slot.
class _TitleSlot extends ConsumerWidget {
  const _TitleSlot({required this.title});

  final String title;

  /// The folder and the day of the last edit, under the title (크래프트 /
  /// 스튜디오 — the 미니멀 bar is one line); null while unknown.
  static String? _subtitleOf(WidgetRef ref) {
    final session = ref.watch(editorSessionValueProvider);
    final note =
        ref.watch(core.noteProvider(session.noteId)).value ?? session.note;
    final folderId = note.folderId;
    final folder = folderId == null
        ? null
        : ref.watch(core.folderTreeProvider).value?.byId(folderId);
    final at = DateTime.fromMillisecondsSinceEpoch(note.updatedAt);
    return [
      if (folder != null) folder.name,
      EditorStrings.titleEditedOn(at.month, at.day),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = StyleTokens.of(context);
    final theme = Theme.of(context);
    final subtitle = tokens.style == AppStyle.calm ? null : _subtitleOf(ref);
    final titleText = Text(
      title,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.2,
      ),
    );
    return Align(
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                // (v2.16-ui) A one-line title (미니멀) stays centred in its
                // 44 px.
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: titleText),
                      const SizedBox(width: 2),
                      AppIcon(
                        AppIconKind.chevronDown,
                        key: EditorToolbar.titleAffordanceKey,
                        size: 18,
                        color: tokens.textSecondary,
                      ),
                    ],
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      key: EditorToolbar.titleSubtitleKey,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      textScaler: MediaQuery.textScalerOf(context)
                          .clamp(maxScaleFactor: 1.2),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                        height: 1.25,
                      ),
                    ),
                ],
              ),
            ),
          ),
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

/// [올가미] and, with [withObjectTools], [도형] (`interests`) and [텍스트]
/// (`text_fields`). Tap: inactive tool → select it; the active shape / text
/// tool again or a long press (active or not) → its tool popup under the
/// button (v2, 6.13.1). (v2.15-ui) The pen and the eraser are in the pen
/// tray; 수식 펜 and 텍스트 펜 in [+].
///
/// (v2.16-ui) With [axis] vertical (스튜디오's rail) they stand two a row
/// (with [insert]) and their popups open to the right of the rail
/// (PopupAnchorBox).
class ToolbarToolButtons extends ConsumerWidget {
  const ToolbarToolButtons({
    super.key,
    required this.withObjectTools,
    this.axis = Axis.horizontal,
    this.gap = 0,
    this.crossExtent,
    this.insert,
  });

  final bool withObjectTools;
  final Axis axis;

  /// (v2.16-ui) In the rail: the rows are this wide (the rail's width), so
  /// a popup placed beside them clears the rail.
  final double? crossExtent;

  /// (v2.16-ui review) In the rail: [삽입] beside [올가미].
  final Widget? insert;

  /// Space between the buttons.
  final double gap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(editorToolProvider.select((s) => s.activeTool));
    final readOnly = ref.watch(editorReadOnlyProvider);
    final commands = ref.watch(editorCommandsProvider);
    final popups = ref.read(editorPopupProvider.notifier);
    final anchors = PopupHost.anchorsOf(context);
    final vertical = axis == Axis.vertical;
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

    final lasso = ToolButton(
      key: EditorToolbar.lassoKey,
      glyph: AppIconKind.lasso,
      caption: EditorStrings.lasso,
      label: EditorStrings.lasso,
      active: active == EditorTool.lasso,
      onTap: tap(EditorTool.lasso, null),
    );
    final shape = ToolButton(
      key: EditorToolbar.shapeKey,
      glyph: AppIconKind.shape,
      caption: EditorStrings.shapeTool,
      label: EditorStrings.shapeTool,
      active: active == EditorTool.shape,
      onTap: tap(EditorTool.shape, const ShapeToolPopup(anchored: true)),
      onLongPress: () => popups.open(const ShapeToolPopup(anchored: true)),
    );
    final text = ToolButton(
      key: EditorToolbar.textKey,
      glyph: AppIconKind.text,
      caption: EditorStrings.textTool,
      label: EditorStrings.textTool,
      active: active == EditorTool.text,
      onTap: tap(EditorTool.text, const TextToolPopup(anchored: true)),
      onLongPress: () => popups.open(const TextToolPopup(anchored: true)),
    );

    if (vertical) {
      // (v2.16-ui review) The rail: two tools a row (올가미 [삽입] /
      // 도형 텍스트), [crossExtent] wide. The 도형 · 텍스트 row is the anchor
      // of both their popups (PopupAnchorBox under shapeBox and textBox),
      // so a popup beside it clears the whole rail.
      final width = crossExtent;
      Widget pair(List<Widget> two) => SizedBox(
        width: width,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: two),
      );
      final ins = insert;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          pair([lasso, if (ins != null) ins else const SizedBox(width: 48)]),
          if (withObjectTools) ...[
            if (gap > 0) SizedBox(height: gap),
            PopupAnchorBox(
              key: anchors.shapeBox,
              beside: true,
              child: PopupAnchorBox(
                key: anchors.textBox,
                beside: true,
                child: pair([shape, text]),
              ),
            ),
          ],
        ],
      );
    }

    final buttons = <Widget>[
      lasso,
      if (withObjectTools) ...[
        CompositedTransformTarget(link: anchors.shape, child: shape),
        CompositedTransformTarget(link: anchors.text, child: text),
      ],
    ];
    final spaced = <Widget>[
      for (final (i, b) in buttons.indexed) ...[
        if (i > 0 && gap > 0) SizedBox(width: gap),
        b,
      ],
    ];
    return Row(mainAxisSize: MainAxisSize.min, children: spaced);
  }
}

/// [📄 2 / 4] (UI stage 2 — the page panel button and the page count in
/// one, 04-editor 22): opens / closes the page panel (selected while
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
    // Only with the count: the current page and the page count (not the
    // viewport, which notifies on every scroll frame).
    String? label;
    if (showCount) {
      final count = ref.watch(editorPageCountProvider);
      final index = ref.watch(editorCurrentPageIndexProvider);
      if (count > 0) {
        label = EditorStrings.pageIndicator(
          index.clamp(0, count - 1) + 1,
          count,
        );
      }
    }
    // The title's face (titleSmall of the app font), tabular digits.
    final countStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      color: IconTheme.of(context).color,
    );
    return HoverName(
      name: EditorStrings.pagePanel,
      child: IconButton(
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
                    constraints: const BoxConstraints(maxWidth: countMaxWidth),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        key: EditorToolbar.pageCountKey,
                        maxLines: 1,
                        style: countStyle,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
