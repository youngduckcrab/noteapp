// lib/src/ui/pen/quick_pen_popup.dart — 04-editor 6.9.1 (long press on the
// pen button), 6.9.3 '빠른 팝업'. E-13 opens it; E-15 fills it. (v2.15-ui, UI
// stage 4 — m5-7/04-editor 23.2) The quick pen of the pen tray: 8 colours, 5
// real-width strokes, 순서 바꾸기 · 트레이에서 빼기 · 펜 고르기.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:ui_kit/ui_kit.dart';

import '../../state/popup.dart';
import '../../tools/tool_controller.dart';
import '../color/basic_colors_row.dart';
import '../editor_strings.dart';
import '../presets/save_preset_dialog.dart' show runPresetWrite;
import 'pen_art_view.dart';

/// Quick pen popup panel ([width] wide): the pen's name and stroke, the
/// first [colorsShown] built-in colours (kBasicColors), the five widths of
/// [penWidthChoices] drawn at their real width, then '순서 바꾸기' (the preset
/// manager), '트레이에서 빼기' (only for the tray pen it was opened on —
/// [presetId]; unpins it) and '펜 고르기 ›' (the pen picker). It edits the
/// current pen (ToolController.setColor / setWidth).
class QuickPenPanel extends ConsumerWidget {
  const QuickPenPanel({super.key, this.presetId});

  /// The tray pen the quick pen was opened on.
  final String? presetId;

  static const panelKey = ValueKey('editor.popup.quickPen');
  static const reorderKey = ValueKey('editor.quickPen.reorder');
  static const unpinKey = ValueKey('editor.quickPen.unpin');
  static const pickerKey = ValueKey('editor.quickPen.picker');
  static ValueKey<String> colorKey(int index) =>
      ValueKey('editor.quickPen.color.$index');
  static ValueKey<String> widthKey(int index) =>
      ValueKey('editor.quickPen.width.$index');

  static const double width = 400;
  static const int colorsShown = 8;

  /// The [kBasicColors] indexes the quick pen shows: the first
  /// [colorsShown]; when the pen's colour reads as a later one (a yellow
  /// highlighter, a pink pen) that one takes the last place, so the current
  /// colour is always there and ringed.
  static List<int> quickColorsFor(int? ringed) => [
    for (var i = 0; i < colorsShown - 1; i++) i,
    if (ringed != null && ringed >= colorsShown - 1)
      ringed
    else
      colorsShown - 1,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pen = ref.watch(editorToolProvider.select((s) => s.currentPen));
    final controller = ref.read(editorToolProvider.notifier);
    final popups = ref.read(editorPopupProvider.notifier);
    final tokens = StyleTokens.of(context);
    final theme = Theme.of(context);
    final colours = pen.tool != core.PenTool.laser;
    final widths = penWidthChoices(pen.tool);
    final ringed = nearestBasicColorIndex(pen.colorArgb);
    final shown = quickColorsFor(ringed);
    final radius = BorderRadius.circular(tokens.radiusLarge);
    // The shadow is cast OUTSIDE the panel: inside the clipped Material it
    // tinted the whole panel grey.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: tokens.shadows(2),
      ),
      child: Material(
        key: panelKey,
        color: tokens.popover,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: tokens.popoverSide,
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      EditorStrings.penTypeName(pen.tool),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: tokens.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        EditorStrings.quickPenHint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.textTertiary,
                        ),
                      ),
                    ),
                    InkSwatchBox(
                      style: pen,
                      size: const Size(84, 24),
                      shape: ink.PenPreviewShape.line,
                    ),
                  ],
                ),
                if (colours) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 2,
                    runSpacing: 2,
                    children: [
                      for (final (i, c) in shown.indexed)
                        InkDot(
                          key: colorKey(i),
                          argb: kBasicColors[c],
                          label: EditorStrings.basicColorNames[c],
                          selected: c == ringed,
                          onTap: () => controller.setColor(kBasicColors[c]),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (var i = 0; i < widths.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(
                        child: WidthChoice(
                          key: widthKey(i),
                          style: pen.copyWith(width: widths[i]),
                          selected: pen.width == widths[i],
                          onTap: () => controller.setWidth(widths[i]),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Divider(height: 1, color: tokens.hairline),
                Row(
                  children: [
                    TextButton(
                      key: reorderKey,
                      onPressed: () => popups.open(const PresetManagerPopup()),
                      child: const Text(EditorStrings.quickPenReorder),
                    ),
                    if (presetId != null)
                      TextButton(
                        key: unpinKey,
                        onPressed: () => _unpin(context, ref),
                        child: const Text(EditorStrings.quickPenUnpin),
                      ),
                    const Spacer(),
                    TextButton(
                      key: pickerKey,
                      onPressed: () => popups.open(const PenSettingsPopup()),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(EditorStrings.quickPenOpenPicker),
                          AppIcon(AppIconKind.chevronRight, size: 18),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _unpin(BuildContext context, WidgetRef ref) {
    final id = presetId;
    final all = ref.read(core.penPresetsProvider).value ?? const [];
    final preset = all.where((p) => p.id == id).firstOrNull;
    final repo = ref.read(core.penPresetRepositoryProvider);
    if (preset != null) {
      // Started (and its messenger taken) before the popup closes; '뺐어요'
      // shows once the write is done.
      runPresetWrite(
        context,
        'unpinning a preset',
        () => repo.updatePreset(preset.copyWith(pinned: false)),
        onDone: (messenger) => messenger
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text(EditorStrings.unpinnedFromTray)),
          ),
      );
    }
    ref.read(editorPopupProvider.notifier).close();
  }
}

/// The real stroke of [style] on a paper-light swatch (ink is document
/// data: it stays readable in a dark style).
class InkSwatchBox extends StatelessWidget {
  const InkSwatchBox({
    super.key,
    required this.style,
    required this.size,
    this.shape = ink.PenPreviewShape.sCurve,
    this.padding = 4,
  });

  final core.StrokeStyle style;
  final Size size;
  final ink.PenPreviewShape shape;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final tokens = StyleTokens.of(context);
    return Container(
      width: size.width,
      height: size.height,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: tokens.inkSwatch,
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
      ),
      child: InkStroke(
        style: style,
        size: Size(size.width - 2 * padding, size.height - 2 * padding),
        shape: shape,
      ),
    );
  }
}

/// A colour dot (30 px in a 44 px target): the ink colour with a white
/// inner ring; an accent ring when [selected].
class InkDot extends StatelessWidget {
  const InkDot({
    super.key,
    required this.argb,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final int argb;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = StyleTokens.of(context);
    final colour = Color(argb | 0xFF000000);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colour,
                border: Border.all(color: tokens.inkSwatch, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: selected ? tokens.accent : tokens.hairline,
                    spreadRadius: selected ? 2 : 1,
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

/// One width choice: the pen's real stroke at that width on a paper-light
/// tile; an accent border when [selected].
class WidthChoice extends StatelessWidget {
  const WidthChoice({
    super.key,
    required this.style,
    required this.selected,
    required this.onTap,
    this.height = 44,
  });

  final core.StrokeStyle style;
  final bool selected;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = StyleTokens.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: EditorStrings.widthChoice(style.width),
      excludeSemantics: true,
      child: Material(
        color: tokens.inkSwatch,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: selected ? tokens.accent : tokens.hairline,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Center(
              child: InkStroke(
                style: style.copyWith(width: style.width.clamp(0.5, 14.0)),
                size: const Size(38, 18),
                shape: ink.PenPreviewShape.line,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
