// lib/src/ui/toolbar/editor_rail.dart — (v2.16-ui, m5-7/04-editor 24.3)
// 스튜디오's left rail: the pen tray standing vertically, the tools with their
// names, and the current pen's 6 colours and 3 widths, always in reach.
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:ui_kit/ui_kit.dart';

import '../../di/editor_extensions.dart';
import '../../scope/editor_scope.dart';
import '../../state/popup.dart';
import '../../state/preset_bar.dart';
import '../../state/settings/editor_device_state.dart';
import '../../tools/tool_controller.dart';
import '../../tools/tool_state.dart';
import '../color/basic_colors_row.dart';
import '../editor_strings.dart';
import '../pen/pen_art_view.dart';
import '../pen/pen_tray.dart';
import '../pen/quick_pen_popup.dart' show InkDot;
import 'editor_toolbar.dart';
import 'insert_menu.dart';

/// [pen tray ↓] ([모든 펜]) ─ [올가미] [삽입] / [도형] [텍스트] ─ … ─
/// 6 colours (2 × 3) ─ 3 widths.
///
/// [width] wide, the style's rail colour. The tray's capacity follows the
/// height ([capacityFor]: 8 pens in portrait, 5 in a 1280 × 800 landscape,
/// fewer on shorter windows); below 3 pens' room the rail scrolls. With
/// room to spare a [모든 펜] button under the tray opens the pen picker, and
/// the colours and widths sit at the rail's foot (near the writing hand);
/// on a short rail everything packs from the top and scrolls. With the
/// palette detached the tray is in the floating palette and the rail keeps
/// the rest.
///
/// The colours and widths act on the current pen (like the quick pen's)
/// and pick the pen when another tool is in hand, so a tap always shows
/// what it did; a selection is recoloured from its own menu ('색'). Only
/// the colour the pen's ink is exactly gets the ring. A laser has no
/// colour, so its colours are dimmed. On a read-only note everything is
/// disabled.
///
/// Keys: the tray's and tools' keys are the docked toolbar's
/// (EditorToolbar.penKey, eraserKey, lassoKey, shapeKey, textKey; [삽입]
/// InsertMenu.buttonKey).
class EditorRail extends ConsumerWidget {
  const EditorRail({super.key});

  static const railKey = ValueKey('editor.rail');
  static const scrollKey = ValueKey('editor.rail.scroll');
  static const allPensKey = ValueKey('editor.rail.allPens');
  static ValueKey<String> colorKey(int index) =>
      ValueKey('editor.rail.color.$index');
  static ValueKey<String> widthKey(int index) =>
      ValueKey('editor.rail.width.$index');

  /// The rail's width (two 48-px tools side by side).
  static const double width = 96;

  /// The [kBasicColors] the rail shows: 검정, 남색, 파랑, 빨강, 초록, 주황.
  static const List<int> colorIndexes = [0, 2, 3, 6, 5, 7];

  /// The [penWidthChoices] the rail shows: 가늘게, 보통, 굵게.
  static const List<int> widthIndexes = [0, 2, 4];

  static const double _pad = 8;
  static const double _dividerHeight = 13;
  static const double _tool = 48;
  static const double _cell = 44;

  /// [모든 펜]: 36 tall and 4 above it.
  static const double allPensHeight = 40;

  /// The height of everything but the tray (and [모든 펜]).
  static const double restHeight =
      2 * _pad +
      2 * _dividerHeight +
      2 * _tool /* two tool rows */ +
      3 * _cell /* colours */ +
      3 * _cell /* widths */;

  /// The most pens the tray shows in a rail [height] tall: the first of 8,
  /// 5, 4 that fits, else 3 (and the rail scrolls). [shownFor] is how many
  /// slots the tray takes at a capacity (fewer pinned pens, or one more for
  /// '지금 펜' — trayPensOf); null = the capacity.
  static int capacityFor(
    double height, {
    int Function(int capacity)? shownFor,
  }) {
    for (final pens in const [8, 5, 4]) {
      final slots = shownFor?.call(pens) ?? pens;
      if (restHeight + PenTray.heightFor(slots) <= height) return pens;
    }
    return 3;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = StyleTokens.of(context);
    final detached = ref.watch(
      editorDeviceStateProvider.select((s) => s.paletteDetached),
    );
    final readOnly = ref.watch(editorReadOnlyProvider);
    final presets = ref.watch(editorTrayPresetsProvider).value ?? const [];
    final current = ref.watch(editorToolProvider.select((s) => s.currentPen));
    int shownFor(int capacity) =>
        trayPensOf(presets, current, capacity).pens.length;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: EditorStrings.railToolbar,
      child: Material(
        key: railKey,
        color: tokens.rail,
        child: SizedBox(
          width: width,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = constraints.maxHeight;
              final pens = capacityFor(height, shownFor: shownFor);
              final allPens =
                  !detached &&
                  restHeight +
                          PenTray.heightFor(shownFor(pens)) +
                          allPensHeight <=
                      height;
              final top = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!detached) ...[
                    PenTray(capacity: pens, axis: Axis.vertical),
                    if (allPens) const _AllPensButton(),
                    const _RailDivider(),
                  ],
                  const ToolbarToolButtons(
                    withObjectTools: true,
                    axis: Axis.vertical,
                    crossExtent: width,
                    // Its menu opens right of the rail (and its divider).
                    insert: InsertMenu(
                      key: EditorToolbar.insertSlotKey,
                      besideGap: 13,
                    ),
                  ),
                  const _RailDivider(),
                ],
              );
              final foot = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Disabled(disabled: readOnly, child: const _RailColors()),
                  _Disabled(disabled: readOnly, child: const _RailWidths()),
                ],
              );
              // The colours and widths stand at the foot while the rail
              // has room; a short rail scrolls the whole column.
              return CustomScrollView(
                key: scrollKey,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.only(top: _pad),
                    sliver: SliverToBoxAdapter(child: top),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: _pad),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: foot,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// [모든 펜] under the tray (a tall rail): opens the pen picker beside it.
class _AllPensButton extends ConsumerWidget {
  const _AllPensButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readOnly = ref.watch(editorReadOnlyProvider);
    final tokens = StyleTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SizedBox(
        width: PenTray.railWidth,
        height: EditorRail.allPensHeight - 4,
        child: OutlinedButton(
          key: EditorRail.allPensKey,
          onPressed: readOnly
              ? null
              : () => ref
                    .read(editorPopupProvider.notifier)
                    .open(const PenSettingsPopup()),
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            foregroundColor: tokens.textPrimary,
            side: BorderSide(color: tokens.hairline),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radiusSmall + 2),
            ),
            textStyle: Theme.of(context).textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          child: const Text(EditorStrings.railAllPens),
        ),
      ),
    );
  }
}

class _RailDivider extends StatelessWidget {
  const _RailDivider();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: EditorRail._dividerHeight,
    child: Center(
      child: Container(
        width: EditorRail.width - 28,
        height: 1,
        color: StyleTokens.of(context).hairline,
      ),
    ),
  );
}

class _Disabled extends StatelessWidget {
  const _Disabled({required this.disabled, required this.child});

  final bool disabled;
  final Widget child;

  @override
  Widget build(BuildContext context) => disabled
      ? IgnorePointer(
          child: ExcludeSemantics(child: Opacity(opacity: 0.38, child: child)),
        )
      : child;
}

/// The current pen's 6 colours, two a row; the one its ink reads as is
/// ringed.
class _RailColors extends ConsumerWidget {
  const _RailColors();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pen = ref.watch(editorToolProvider.select((s) => s.currentPen));
    final pick = _pickPen(ref);
    final controller = ref.read(editorToolProvider.notifier);
    // (review) Only an exact match is ringed: a custom ink is none of
    // these six.
    final rgb = pen.colorArgb & 0xFFFFFF;
    final laser = pen.tool == core.PenTool.laser;
    final dots = Wrap(
      children: [
        for (final (i, c) in EditorRail.colorIndexes.indexed)
          InkDot(
            key: EditorRail.colorKey(i),
            argb: kBasicColors[c],
            label: EditorStrings.basicColorNames[c],
            selected: !laser && rgb == kBasicColors[c] & 0xFFFFFF,
            onTap: () {
              controller.setColor(kBasicColors[c]);
              pick();
            },
          ),
      ],
    );
    return SizedBox(
      width: 2 * EditorRail._cell,
      child: laser ? _Disabled(disabled: true, child: dots) : dots,
    );
  }
}

/// The current pen's 가늘게 · 보통 · 굵게: (owner review) each width drawn in
/// the pen's real ink on a paper-light strip (like the tray's ink strips),
/// so a 형광펜's yellow or a black pen on the dark rail still reads; the
/// chosen one in the accent's soft well with its outline. At least 1.5 px
/// so 가늘게 still shows.
class _RailWidths extends ConsumerWidget {
  const _RailWidths();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pen = ref.watch(editorToolProvider.select((s) => s.currentPen));
    final pick = _pickPen(ref);
    final controller = ref.read(editorToolProvider.notifier);
    final choices = penWidthChoices(pen.tool);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
      child: Column(
        children: [
          for (final (i, w) in EditorRail.widthIndexes.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: HoverName(
                name: EditorStrings.railWidthNames[i],
                child: _RailWidth(
                  key: EditorRail.widthKey(i),
                  style: pen.copyWith(width: math.max(1.5, choices[w])),
                  realWidth: choices[w],
                  selected: (pen.width - choices[w]).abs() < 0.01,
                  onTap: () {
                    controller.setWidth(choices[w]);
                    pick();
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RailWidth extends StatelessWidget {
  const _RailWidth({
    super.key,
    required this.style,
    required this.realWidth,
    required this.selected,
    required this.onTap,
  });

  final core.StrokeStyle style;
  final double realWidth;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = StyleTokens.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: EditorStrings.widthChoice(realWidth),
      excludeSemantics: true,
      child: Material(
        color: selected ? tokens.accentSoft : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: selected
              ? BorderSide(color: tokens.accent, width: 2)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: EditorRail._cell - 2,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.inkSwatch,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: tokens.hairline),
                ),
                child: SizedBox(
                  width: 62,
                  height: 26,
                  child: Center(
                    child: InkStroke(
                      style: style.copyWith(
                        width: style.width.clamp(1.5, 14.0),
                      ),
                      size: const Size(48, 18),
                      shape: ink.PenPreviewShape.line,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Picks the pen after a rail colour or width when another tool (eraser,
/// lasso, shape, text) is in hand — the tap shows what it changed.
VoidCallback _pickPen(WidgetRef ref) {
  final active = ref.watch(editorToolProvider.select((s) => s.activeTool));
  final hasMathPen = ref.watch(
    editorExtensionsProvider.select((e) => e.mathPen != null),
  );
  final hasTextPen = ref.watch(
    editorExtensionsProvider.select((e) => e.textPen != null),
  );
  return () {
    if (penToolActive(active, hasMathPen: hasMathPen, hasTextPen: hasTextPen)) {
      return;
    }
    ref.read(editorCommandsProvider).selectTool(EditorTool.pen);
  };
}
