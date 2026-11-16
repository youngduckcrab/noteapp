// lib/src/ui/toolbar/editor_rail.dart — (v2.16-ui, m5-7/04-editor 24.3)
// 스튜디오's left rail: the pen tray standing vertically, the tools with their
// names, and the current pen's 6 colours and 3 widths, always in reach.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:ui_kit/ui_kit.dart';

import '../../scope/editor_scope.dart';
import '../../state/preset_bar.dart';
import '../../state/settings/editor_device_state.dart';
import '../../tools/tool_controller.dart';
import '../color/basic_colors_row.dart';
import '../editor_strings.dart';
import '../pen/pen_art_view.dart';
import '../pen/pen_tray.dart';
import '../pen/quick_pen_popup.dart' show InkDot, WidthChoice;
import 'editor_toolbar.dart';

/// [pen tray ↓] ─ [올가미] [도형] [텍스트] ─ 6 colours (2 × 3) ─ 3 widths.
///
/// [width] wide, the style's rail colour. The tray's capacity follows the
/// height ([capacityFor]: 8 pens in portrait, 5 in a 1280 × 800 landscape,
/// fewer on shorter windows); below 3 pens' room the rail scrolls. With the
/// palette detached the tray is in the floating palette and the rail keeps
/// the rest. The colours and widths act on the current pen (like the quick
/// pen's); a laser has no colour, so its colours are dimmed. On a
/// read-only note everything is disabled.
///
/// Keys: the tray's and tools' keys are the docked toolbar's
/// (EditorToolbar.penKey, eraserKey, lassoKey, shapeKey, textKey).
class EditorRail extends ConsumerWidget {
  const EditorRail({super.key});

  static const railKey = ValueKey('editor.rail');
  static const scrollKey = ValueKey('editor.rail.scroll');
  static ValueKey<String> colorKey(int index) =>
      ValueKey('editor.rail.color.$index');
  static ValueKey<String> widthKey(int index) =>
      ValueKey('editor.rail.width.$index');

  /// The rail's width (two 44-px colour dots side by side).
  static const double width = 88;

  /// The [kBasicColors] the rail shows: 검정, 남색, 파랑, 빨강, 초록, 주황.
  static const List<int> colorIndexes = [0, 2, 3, 6, 5, 7];

  /// The [penWidthChoices] the rail shows: 가늘게, 보통, 굵게.
  static const List<int> widthIndexes = [0, 2, 4];

  static const double _pad = 8;
  static const double _dividerHeight = 13;
  static const double _tool = 48;
  static const double _cell = 44;

  /// The height of everything but the tray.
  static const double restHeight =
      2 * _pad +
      2 * _dividerHeight +
      3 * _tool +
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
              final pens = capacityFor(
                constraints.maxHeight,
                shownFor: shownFor,
              );
              return SingleChildScrollView(
                key: scrollKey,
                padding: const EdgeInsets.symmetric(vertical: _pad),
                child: Column(
                  children: [
                    if (!detached) ...[
                      PenTray(capacity: pens, axis: Axis.vertical),
                      const _RailDivider(),
                    ],
                    const ToolbarToolButtons(
                      withObjectTools: true,
                      axis: Axis.vertical,
                      crossExtent: width,
                    ),
                    const _RailDivider(),
                    _Disabled(disabled: readOnly, child: const _RailColors()),
                    _Disabled(disabled: readOnly, child: const _RailWidths()),
                  ],
                ),
              );
            },
          ),
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
    final controller = ref.read(editorToolProvider.notifier);
    final ringed = nearestBasicColorIndex(pen.colorArgb);
    final laser = pen.tool == core.PenTool.laser;
    final dots = Wrap(
      children: [
        for (final (i, c) in EditorRail.colorIndexes.indexed)
          InkDot(
            key: EditorRail.colorKey(i),
            argb: kBasicColors[c],
            label: EditorStrings.basicColorNames[c],
            selected: !laser && c == ringed,
            onTap: () => controller.setColor(kBasicColors[c]),
          ),
      ],
    );
    return SizedBox(
      width: 2 * EditorRail._cell,
      child: laser ? _Disabled(disabled: true, child: dots) : dots,
    );
  }
}

/// The current pen's 가늘게 · 보통 · 굵게 (drawn at their real width).
class _RailWidths extends ConsumerWidget {
  const _RailWidths();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pen = ref.watch(editorToolProvider.select((s) => s.currentPen));
    final controller = ref.read(editorToolProvider.notifier);
    final choices = penWidthChoices(pen.tool);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          for (final (i, w) in EditorRail.widthIndexes.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: HoverName(
                name: EditorStrings.railWidthNames[i],
                child: WidthChoice(
                  key: EditorRail.widthKey(i),
                  style: pen.copyWith(width: choices[w]),
                  selected: (pen.width - choices[w]).abs() < 0.01,
                  height: EditorRail._cell - 2,
                  onTap: () => controller.setWidth(choices[w]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
