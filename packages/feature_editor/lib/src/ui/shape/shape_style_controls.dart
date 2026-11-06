// lib/src/ui/shape/shape_style_controls.dart — m5-7/04-editor 6.9.1 (the
// shape tool popup) and 6.7.5 (a selected shape's '스타일') — E2-09 part 2.
// One set of controls for both: the tool popup edits
// editorToolOptionsProvider, the selection popup sends ONE UpdateObjects per
// finished adjustment.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../scope/editor_scope.dart';
import '../../state/color_palette.dart';
import '../../state/popup.dart';
import '../../tools/selection.dart';
import '../../tools/tool_controller.dart';
import '../../tools/tool_options.dart';
import '../color/color_swatch.dart';
import '../editor_strings.dart';
import '../popup_host.dart';

/// A change of one attribute of a shape style (applied to each selected
/// shape's own style, so a colour change keeps every shape's width).
typedef ShapeStyleEdit = core.ShapeStyle Function(core.ShapeStyle style);

/// The style rows of 6.9.1: 테두리 색 (a few basic colours, the recent
/// colours and the user palette; '펜 색 쓰기' when [onPenColor]), 굵기
/// (ShapeStyle.minWidth – maxWidth — the pen's range; applied when the
/// slider is let go), 선 종류 (LineDash), 채우기 (없음 + colours + 채우기
/// 투명도) — hidden when [lineOnly] — and 화살촉 (ArrowHeads) only when
/// [lineOnly]. Every finished adjustment calls [onEdit] once.
class ShapeStyleControls extends ConsumerStatefulWidget {
  const ShapeStyleControls({
    super.key,
    required this.style,
    required this.lineOnly,
    required this.onEdit,
    this.onPenColor,
  });

  /// The values shown.
  final core.ShapeStyle style;

  /// Every shape it edits is a line or an arrow.
  final bool lineOnly;
  final void Function(ShapeStyleEdit edit) onEdit;

  /// '펜 색 쓰기' (the tool popup only).
  final VoidCallback? onPenColor;

  static ValueKey<String> strokeKey(int argb) =>
      ValueKey('editor.shapeStyle.stroke.${_hex(argb)}');
  static ValueKey<String> fillKey(int argb) =>
      ValueKey('editor.shapeStyle.fill.${_hex(argb)}');
  static ValueKey<String> dashKey(core.LineDash dash) =>
      ValueKey('editor.shapeStyle.dash.${dash.name}');
  static ValueKey<String> arrowKey(core.ArrowHeads heads) =>
      ValueKey('editor.shapeStyle.arrow.${heads.name}');
  static const fillNoneKey = ValueKey('editor.shapeStyle.fill.none');
  static const widthKey = ValueKey('editor.shapeStyle.width');
  static const fillOpacityKey = ValueKey('editor.shapeStyle.fillOpacity');
  static const penColorKey = ValueKey('editor.shapeStyle.penColor');
  static const fillRowKey = ValueKey('editor.shapeStyle.fillRow');
  static const arrowRowKey = ValueKey('editor.shapeStyle.arrowRow');

  /// Offered before the recent colours (a shape needs colours before any
  /// stroke was drawn).
  static const List<int> basicColors = [
    0xFF1A1A1A,
    0xFFE53935,
    0xFF1E88E5,
    0xFF43A047,
    0xFFFDD835,
    0xFF8E24AA,
  ];

  static String _hex(int argb) =>
      (0xFF000000 + argb % 0x1000000).toRadixString(16).padLeft(8, '0');

  @override
  ConsumerState<ShapeStyleControls> createState() => _ShapeStyleControlsState();
}

class _ShapeStyleControlsState extends ConsumerState<ShapeStyleControls> {
  double? _width; // while the slider is held
  double? _fillOpacity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = ref.watch(editorColorPaletteProvider);
    final colors = <int>{
      for (final c in ShapeStyleControls.basicColors) c,
      for (final c in palette.recent) ColorPaletteState.opaque(c),
      for (final c in palette.palette) ColorPaletteState.opaque(c),
    }.toList();
    final style = widget.style;
    final label = theme.textTheme.labelLarge;
    Widget title(String text) => Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Text(text, style: label),
    );
    final width = (_width ?? style.strokeWidth)
        .clamp(core.ShapeStyle.minWidth, core.ShapeStyle.maxWidth)
        .toDouble();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        title(EditorStrings.shapeStrokeColor),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final c in colors)
              ColorSwatchButton(
                key: ShapeStyleControls.strokeKey(c),
                argb: c,
                selected: c == ColorPaletteState.opaque(style.strokeColorArgb),
                onTap: () =>
                    widget.onEdit((s) => s.copyWith(strokeColorArgb: c)),
              ),
            if (widget.onPenColor != null)
              TextButton(
                key: ShapeStyleControls.penColorKey,
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                onPressed: widget.onPenColor,
                child: const Text(EditorStrings.usePenColor),
              ),
          ],
        ),
        title('${EditorStrings.shapeWidth} ${width.toStringAsFixed(1)} pt'),
        Slider(
          key: ShapeStyleControls.widthKey,
          min: core.ShapeStyle.minWidth,
          max: core.ShapeStyle.maxWidth,
          value: width,
          onChanged: (v) => setState(() => _width = v),
          onChangeEnd: (v) {
            setState(() => _width = null);
            widget.onEdit((s) => s.copyWith(strokeWidth: v));
          },
        ),
        title(EditorStrings.shapeLineDash),
        Wrap(
          spacing: 8,
          children: [
            for (final dash in core.LineDash.values)
              ChoiceChip(
                key: ShapeStyleControls.dashKey(dash),
                label: Text(switch (dash) {
                  core.LineDash.solid => EditorStrings.lineSolid,
                  core.LineDash.dashed => EditorStrings.lineDashed,
                  core.LineDash.dotted => EditorStrings.lineDotted,
                }),
                selected: style.dash == dash,
                onSelected: (_) => widget.onEdit((s) => s.copyWith(dash: dash)),
              ),
          ],
        ),
        if (!widget.lineOnly) ...[
          title(EditorStrings.shapeFill),
          Wrap(
            key: ShapeStyleControls.fillRowKey,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                key: ShapeStyleControls.fillNoneKey,
                label: const Text(EditorStrings.none),
                selected: style.fillColorArgb == null,
                onSelected: (_) =>
                    widget.onEdit((s) => s.copyWith(clearFill: true)),
              ),
              for (final c in colors)
                ColorSwatchButton(
                  key: ShapeStyleControls.fillKey(c),
                  argb: c,
                  selected:
                      style.fillColorArgb != null &&
                      ColorPaletteState.opaque(style.fillColorArgb!) == c,
                  onTap: () =>
                      widget.onEdit((s) => s.copyWith(fillColorArgb: c)),
                ),
            ],
          ),
          if (style.fillColorArgb != null) ...[
            title(
              '${EditorStrings.shapeFillOpacity} '
              '${((_fillOpacity ?? style.fillOpacity) * 100).round()}%',
            ),
            Slider(
              key: ShapeStyleControls.fillOpacityKey,
              value: (_fillOpacity ?? style.fillOpacity)
                  .clamp(0.0, 1.0)
                  .toDouble(),
              onChanged: (v) => setState(() => _fillOpacity = v),
              onChangeEnd: (v) {
                setState(() => _fillOpacity = null);
                widget.onEdit((s) => s.copyWith(fillOpacity: v));
              },
            ),
          ],
        ],
        if (widget.lineOnly) ...[
          title(EditorStrings.shapeArrowHeads),
          Wrap(
            key: ShapeStyleControls.arrowRowKey,
            spacing: 8,
            children: [
              for (final heads in core.ArrowHeads.values)
                ChoiceChip(
                  key: ShapeStyleControls.arrowKey(heads),
                  label: Text(switch (heads) {
                    core.ArrowHeads.none => EditorStrings.none,
                    core.ArrowHeads.end => EditorStrings.arrowHeadEnd,
                    core.ArrowHeads.both => EditorStrings.arrowHeadBoth,
                  }),
                  selected: style.arrowHeads == heads,
                  onSelected: (_) =>
                      widget.onEdit((s) => s.copyWith(arrowHeads: heads)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

bool _isLine(core.ShapeKind kind) =>
    kind == core.ShapeKind.line || kind == core.ShapeKind.arrow;

/// The shape tool popup (ShapeToolPopup — 6.9.1): the 7 kinds (keys
/// `editor.shapePopup.kind.<ShapeKind.name>`, appendix C), the polygon's
/// sides (3–12) or the star's points (4–16) when that kind is chosen, then
/// [ShapeStyleControls] on the tool style ('펜 색 쓰기' = the current pen
/// colour). Every value goes to editorToolOptionsProvider (`editor.toolOptions`).
class ShapeToolPanel extends ConsumerWidget {
  const ShapeToolPanel({super.key});

  static const panelKey = ValueKey('editor.popup.shapeTool');
  static ValueKey<String> kindKey(core.ShapeKind kind) =>
      ValueKey('editor.shapePopup.kind.${kind.name}');
  static const countMinusKey = ValueKey('editor.shapePopup.count.minus');
  static const countPlusKey = ValueKey('editor.shapePopup.count.plus');

  static IconData iconOf(core.ShapeKind kind) => switch (kind) {
    core.ShapeKind.line => Icons.horizontal_rule,
    core.ShapeKind.arrow => Icons.arrow_right_alt,
    core.ShapeKind.rectangle => Icons.rectangle_outlined,
    core.ShapeKind.ellipse => Icons.circle_outlined,
    core.ShapeKind.triangle => Icons.change_history,
    core.ShapeKind.polygon => Icons.pentagon_outlined,
    core.ShapeKind.star => Icons.star_outline,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(editorToolOptionsProvider);
    final notifier = ref.read(editorToolOptionsProvider.notifier);
    final kind = options.shapeKind;
    final scheme = Theme.of(context).colorScheme;
    final counted =
        kind == core.ShapeKind.polygon || kind == core.ShapeKind.star;
    final count = kind == core.ShapeKind.star
        ? options.starPoints
        : options.polygonSides;
    void setCount(int value) => kind == core.ShapeKind.star
        ? notifier.setStarPoints(value)
        : notifier.setPolygonSides(value);
    return PopupPanelFrame(
      key: panelKey,
      title: EditorStrings.shapeTool,
      children: [
        Text(
          EditorStrings.shapeKind,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        Wrap(
          children: [
            for (final k in core.ShapeKind.values)
              IconButton(
                key: kindKey(k),
                tooltip: EditorStrings.shapeKindName(k),
                isSelected: k == kind,
                style: IconButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  backgroundColor: k == kind ? scheme.secondaryContainer : null,
                ),
                onPressed: () => notifier.setShapeKind(k),
                icon: Icon(iconOf(k)),
              ),
          ],
        ),
        if (counted)
          Row(
            children: [
              Text(
                kind == core.ShapeKind.star
                    ? EditorStrings.starPoints
                    : EditorStrings.polygonSides,
              ),
              const Spacer(),
              IconButton(
                key: countMinusKey,
                onPressed: () => setCount(count - 1),
                icon: const Icon(Icons.remove),
              ),
              Text('$count'),
              IconButton(
                key: countPlusKey,
                onPressed: () => setCount(count + 1),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ShapeStyleControls(
          style: options.shapeStyle,
          lineOnly: _isLine(kind),
          onEdit: (edit) =>
              notifier.setShapeStyle(edit(options.shapeStyle).normalized()),
          onPenColor: () {
            final pen = ref.read(editorToolProvider).currentPen.colorArgb;
            notifier.setShapeStyle(
              options.shapeStyle.copyWith(strokeColorArgb: pen).normalized(),
            );
          },
        ),
      ],
    );
  }
}

/// The selection menu's '스타일' popup (ShapeStylePopup — 6.7.5): one or
/// more selected shapes (shapes only). Every finished adjustment → ONE
/// UpdateObjects with each shape's own style changed by that edit
/// (normalized). Closes when the selection goes or is dragged.
class ShapeStylePanel extends ConsumerWidget {
  const ShapeStylePanel({super.key});

  static const panelKey = ValueKey('editor.popup.shapeStyle');

  /// The selected shapes when the selection holds shapes only (z order),
  /// else empty.
  static List<core.ShapeObject> shapesOf(
    core.PageContent? content,
    EditorSelection? selection,
  ) {
    if (content == null || selection == null) return const [];
    final shapes = <core.ShapeObject>[];
    for (final o in content.objects) {
      if (!selection.elementIds.contains(o.id)) continue;
      if (o is! core.ShapeObject) return const [];
      shapes.add(o);
    }
    return shapes.length == selection.elementIds.length ? shapes : const [];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(editorSelectionProvider, (_, next) {
      if (next == null || next.isDragging) {
        ref.read(editorPopupProvider.notifier).close();
      }
    });
    final selection = ref.watch(editorSelectionProvider);
    final session = ref.watch(editorSessionValueProvider);
    final pages = ref.watch(editorMountedPagesProvider);
    final mount = selection == null ? null : pages[selection.pageId];
    return ListenableBuilder(
      listenable: Listenable.merge([pages, ?mount?.contentChanges]),
      builder: (context, _) {
        final shapes = shapesOf(
          selection == null ? null : session.pageIfLoaded(selection.pageId),
          selection,
        );
        if (selection == null || shapes.isEmpty) {
          return const SizedBox.shrink();
        }
        return PopupPanelFrame(
          key: panelKey,
          title: EditorStrings.selectionStyle,
          children: [
            ShapeStyleControls(
              style: shapes.first.style,
              lineOnly: shapes.every((s) => _isLine(s.shapeKind)),
              onEdit: (edit) => ref.read(editorCommandsProvider).updateObjects(
                selection.pageId,
                [
                  for (final s in shapes)
                    s.copyWith(style: edit(s.style).normalized()),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
