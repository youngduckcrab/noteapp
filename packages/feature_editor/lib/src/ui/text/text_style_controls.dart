// lib/src/ui/text/text_style_controls.dart — m5-7/04-editor 6.11.4 (the
// format bar of a text edit session), 6.7.5 (a selected text box's '서식')
// and the text tool popup (TextToolPopup — 8.2 E2-10) — E2-10 part 2.
//
// One set of controls for the three: [−] size [+] (6 – 144, the presets
// 10 · 12 · 14 · 16 · 20 · 24 · 32 · 48 under the size), colour (5 recent
// colours + '더 보기' — a picker without the HEX field), B, the three
// alignments and the background (none or a colour). Nothing here takes the
// focus (ExcludeFocus): a focus loss ends an edit session (6.11.5).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../scope/editor_scope.dart';
import '../../state/color_palette.dart';
import '../../state/popup.dart';
import '../../tools/object_resize.dart';
import '../../tools/selection.dart';
import '../../tools/tool_options.dart';
import '../color/color_swatch.dart';
import '../color/hue_slider.dart';
import '../color/sv_square.dart';
import '../editor_strings.dart';
import '../popup_host.dart';

/// The text style rows (6.11.4). Every change calls [onChanged] once with
/// the whole new style (normalized); the colour picker of '더 보기' applies
/// on its [적용] only. [axis] lays the groups out in one row (the format
/// bar — scrolls sideways when narrow) or one group per row (popups).
class TextStyleControls extends ConsumerStatefulWidget {
  const TextStyleControls({
    super.key,
    required this.style,
    required this.onChanged,
    this.axis = Axis.horizontal,
  });

  final core.TextBoxStyle style;
  final ValueChanged<core.TextBoxStyle> onChanged;
  final Axis axis;

  static const sizeDownKey = ValueKey('editor.textFormat.sizeDown');
  static const sizeUpKey = ValueKey('editor.textFormat.sizeUp');
  static const sizeKey = ValueKey('editor.textFormat.size');
  static const presetsKey = ValueKey('editor.textFormat.presets');
  static ValueKey<String> presetKey(int size) =>
      ValueKey('editor.textFormat.preset.$size');
  static ValueKey<String> colorKey(int argb) =>
      ValueKey('editor.textFormat.color.${_hex(argb)}');
  static const moreColorsKey = ValueKey('editor.textFormat.moreColors');
  static const pickerKey = ValueKey('editor.textFormat.picker');
  static const pickerApplyKey = ValueKey('editor.textFormat.picker.apply');
  static const boldKey = ValueKey('editor.textFormat.bold');
  static ValueKey<String> alignKey(core.TextAlignKind align) =>
      ValueKey('editor.textFormat.align.${align.name}');
  static const backgroundNoneKey = ValueKey(
    'editor.textFormat.background.none',
  );
  static ValueKey<String> backgroundKey(int argb) =>
      ValueKey('editor.textFormat.background.${_hex(argb)}');

  /// 6.11.4 presets (pt).
  static const List<int> presets = [10, 12, 14, 16, 20, 24, 32, 48];

  /// The colours shown: the recent ones first, then these, 5 in all.
  static const List<int> basicColors = [
    0xFF1A1A1A,
    0xFFE53935,
    0xFF1E88E5,
    0xFF43A047,
    0xFF8E24AA,
  ];

  /// How many colours the row shows (6.11.4 '최근 색 5').
  static const int colorCount = 5;

  /// The background choices besides none: light marker tones.
  static const List<int> backgrounds = [0xFFFFF59D, 0xFFC8E6C9, 0xFFBBDEFB];

  /// [−] / [+]: one pt down / up, clamped to 6 – 144.
  static double stepped(double size, int direction) =>
      (size.round() + direction)
          .clamp(core.TextBoxStyle.minFontSize, core.TextBoxStyle.maxFontSize)
          .toDouble();

  /// The colours of the row: [recent] first, then [basicColors], no repeats.
  static List<int> colorsFrom(List<int> recent) {
    final out = <int>[];
    for (final c in [...recent, ...basicColors]) {
      if (out.length == colorCount) break;
      if (!out.contains(c)) out.add(c);
    }
    return out;
  }

  static String _hex(int argb) =>
      (0xFF000000 + argb % 0x1000000).toRadixString(16).padLeft(8, '0');

  @override
  ConsumerState<TextStyleControls> createState() => _TextStyleControlsState();
}

class _TextStyleControlsState extends ConsumerState<TextStyleControls> {
  bool _presets = false;
  HSVColor? _picking;

  void _set(core.TextBoxStyle style) => widget.onChanged(style.normalized());

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final recent = ref.watch(
      editorColorPaletteProvider.select((s) => s.recent),
    );
    final scheme = Theme.of(context).colorScheme;
    final size = style.fontSizePt.round();
    final groups = <Widget>[
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: TextStyleControls.sizeDownKey,
            onPressed: size <= core.TextBoxStyle.minFontSize
                ? null
                : () => _set(
                    style.copyWith(
                      fontSizePt: TextStyleControls.stepped(
                        style.fontSizePt,
                        -1,
                      ),
                    ),
                  ),
            icon: const Icon(
              Icons.remove,
              semanticLabel: EditorStrings.fontSizeDown,
            ),
          ),
          TextButton(
            key: TextStyleControls.sizeKey,
            onPressed: () => setState(() => _presets = !_presets),
            child: Text(
              '$size',
              semanticsLabel: '${EditorStrings.fontSize} $size',
            ),
          ),
          IconButton(
            key: TextStyleControls.sizeUpKey,
            onPressed: size >= core.TextBoxStyle.maxFontSize
                ? null
                : () => _set(
                    style.copyWith(
                      fontSizePt: TextStyleControls.stepped(
                        style.fontSizePt,
                        1,
                      ),
                    ),
                  ),
            icon: const Icon(
              Icons.add,
              semanticLabel: EditorStrings.fontSizeUp,
            ),
          ),
        ],
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in TextStyleControls.colorsFrom(recent))
            ColorSwatchButton(
              key: TextStyleControls.colorKey(c),
              argb: c,
              diameter: 24,
              selected: c == style.colorArgb,
              onTap: () => _set(style.copyWith(colorArgb: c)),
            ),
          IconButton(
            key: TextStyleControls.moreColorsKey,
            isSelected: _picking != null,
            onPressed: () => setState(
              () => _picking = _picking == null
                  ? HSVColor.fromColor(Color(style.colorArgb))
                  : null,
            ),
            icon: const Icon(
              Icons.palette_outlined,
              semanticLabel: EditorStrings.moreColors,
            ),
          ),
        ],
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: TextStyleControls.boldKey,
            isSelected: style.bold,
            onPressed: () => _set(style.copyWith(bold: !style.bold)),
            icon: const Icon(
              Icons.format_bold,
              semanticLabel: EditorStrings.bold,
            ),
          ),
          for (final (align, icon, label) in const [
            (
              core.TextAlignKind.start,
              Icons.format_align_left,
              EditorStrings.alignLeft,
            ),
            (
              core.TextAlignKind.center,
              Icons.format_align_center,
              EditorStrings.alignCenter,
            ),
            (
              core.TextAlignKind.end,
              Icons.format_align_right,
              EditorStrings.alignRight,
            ),
          ])
            IconButton(
              key: TextStyleControls.alignKey(align),
              isSelected: style.align == align,
              onPressed: () => _set(style.copyWith(align: align)),
              icon: Icon(icon, semanticLabel: label),
            ),
        ],
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: TextStyleControls.backgroundNoneKey,
            isSelected: style.backgroundArgb == null,
            onPressed: () => _set(style.copyWith(clearBackground: true)),
            icon: const Icon(
              Icons.format_color_reset_outlined,
              semanticLabel:
                  '${EditorStrings.textBackground} ${EditorStrings.none}',
            ),
          ),
          for (final c in TextStyleControls.backgrounds)
            Semantics(
              label: EditorStrings.textBackground,
              child: ColorSwatchButton(
                key: TextStyleControls.backgroundKey(c),
                argb: c,
                diameter: 24,
                selected: c == style.backgroundArgb,
                onTap: () => _set(style.copyWith(backgroundArgb: c)),
              ),
            ),
        ],
      ),
    ];
    final picking = _picking;
    return ExcludeFocus(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.axis == Axis.horizontal)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < groups.length; i++) ...[
                    if (i > 0)
                      SizedBox(
                        height: 28,
                        child: VerticalDivider(
                          width: 12,
                          color: scheme.outlineVariant,
                        ),
                      ),
                    groups[i],
                  ],
                ],
              ),
            )
          else
            ...groups,
          if (_presets)
            Wrap(
              key: TextStyleControls.presetsKey,
              children: [
                for (final p in TextStyleControls.presets)
                  TextButton(
                    key: TextStyleControls.presetKey(p),
                    onPressed: () {
                      setState(() => _presets = false);
                      _set(style.copyWith(fontSizePt: p.toDouble()));
                    },
                    child: Text(
                      '$p',
                      style: size == p
                          ? TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          if (picking != null)
            Padding(
              key: TextStyleControls.pickerKey,
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SvSquare(
                    hsv: picking,
                    size: const Size(220, 140),
                    onChanged: (hsv) => setState(() => _picking = hsv),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 220,
                    child: HueSlider(
                      hsv: picking,
                      onChanged: (hsv) => setState(() => _picking = hsv),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      key: TextStyleControls.pickerApplyKey,
                      onPressed: () {
                        final argb = picking.toColor().toARGB32();
                        setState(() => _picking = null);
                        _set(style.copyWith(colorArgb: argb));
                      },
                      child: const Text(EditorStrings.recolorApply),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The format bar of an edit session (6.11.4 — key editor.textFormatBar):
/// the session's style, a change → TextEditNotifier.updateStyle (draft only
/// — the command comes at the end) and ToolOptions.textStyle (the next box
/// starts with it — 6.2.4). In the editor's tap group (TextFieldTapRegion),
/// so pressing it keeps the session.
class TextFormatBar extends StatelessWidget {
  const TextFormatBar({
    super.key,
    required this.style,
    required this.onChanged,
    this.elevation = 3,
  });

  static const barKey = ValueKey('editor.textFormatBar');

  final core.TextBoxStyle style;
  final ValueChanged<core.TextBoxStyle> onChanged;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextFieldTapRegion(
      child: Material(
        key: barKey,
        elevation: elevation,
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: TextStyleControls(style: style, onChanged: onChanged),
        ),
      ),
    );
  }
}

/// Places the format bar 8 px above [anchor] (screen px — the box's frame
/// bounds), or 8 px below it when there is no room above; kept inside the
/// area with an 8 px margin.
class FormatBarLayout extends SingleChildLayoutDelegate {
  const FormatBarLayout(this.anchor);

  final Rect anchor;

  static const double gap = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(
          math.max(0, constraints.maxWidth - 2 * gap),
          math.max(0, constraints.maxHeight - 2 * gap),
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxX = math.max(gap, size.width - childSize.width - gap);
    final x = anchor.left.clamp(gap, maxX).toDouble();
    final above = anchor.top - gap - childSize.height;
    final y = above >= gap
        ? above
        : math.min(
            anchor.bottom + gap,
            math.max(gap, size.height - childSize.height - gap),
          );
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(FormatBarLayout oldDelegate) =>
      oldDelegate.anchor != anchor;
}

/// The text tool popup (TextToolPopup): ToolOptions.textStyle — the style
/// of the next new box.
class TextToolPanel extends ConsumerWidget {
  const TextToolPanel({super.key});

  static const panelKey = ValueKey('editor.popup.textTool');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(
      editorToolOptionsProvider.select((o) => o.textStyle),
    );
    return PopupPanelFrame(
      key: panelKey,
      title: EditorStrings.textTool,
      children: [
        TextStyleControls(
          style: style,
          axis: Axis.vertical,
          onChanged: ref.read(editorToolOptionsProvider.notifier).setTextStyle,
        ),
      ],
    );
  }
}

/// The selection menu's '서식' (TextFormatPopup — 6.7.5): a single selected
/// text box outside an edit session. Every change → ONE UpdateObjects with
/// the new style and the height measured again (the top edge kept —
/// ObjectResize.withMeasuredHeight), and ToolOptions.textStyle (6.2.4).
/// Closes when the selection goes or is dragged.
class TextFormatPanel extends ConsumerWidget {
  const TextFormatPanel({super.key});

  static const panelKey = ValueKey('editor.popup.textFormat');

  /// [box] restyled, its height measured for the new style (measureSync, or
  /// the measure Future before the glyphs are in).
  static Future<core.TextBoxObject> restyled(
    core.TextBoxObject box,
    core.TextBoxStyle style,
  ) async {
    final next = box.copyWith(style: style);
    final width = next.frame.rect.width;
    final sync = ink.InkTextLayout.measureSync(
      next.text,
      style,
      widthPt: width,
    );
    if (sync != null) return ObjectResize.withMeasuredHeight(next, sync.height);
    try {
      final size = await ink.InkTextLayout.measure(
        next.text,
        style,
        widthPt: width,
      ).timeout(const Duration(seconds: 2));
      return ObjectResize.withMeasuredHeight(next, size.height);
    } on Object {
      return next; // 6.21: the old height
    }
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
        final ids = selection?.elementIds ?? const <String>{};
        final object = selection == null || ids.length != 1
            ? null
            : session.pageIfLoaded(selection.pageId)?.objectById(ids.single);
        if (selection == null || object is! core.TextBoxObject) {
          return const SizedBox.shrink();
        }
        return PopupPanelFrame(
          key: panelKey,
          title: EditorStrings.selectionFormat,
          children: [
            TextStyleControls(
              style: object.style,
              axis: Axis.vertical,
              onChanged: (style) {
                ref
                    .read(editorToolOptionsProvider.notifier)
                    .setTextStyle(style);
                final commands = ref.read(editorCommandsProvider);
                unawaited(
                  restyled(object, style).then(
                    (box) => commands.updateObjects(selection.pageId, [box]),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
