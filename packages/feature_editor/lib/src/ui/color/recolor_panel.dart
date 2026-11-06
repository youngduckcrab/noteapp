// lib/src/ui/color/recolor_panel.dart — m5-7/04-editor 6.7.2 (the recolor
// popup of the selection menu's '색 ●').
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../scope/editor_scope.dart';
import '../../state/color_palette.dart';
import '../../state/popup.dart';
import '../../tools/selection.dart';
import '../../tools/selection_menu_model.dart';
import '../editor_strings.dart';
import '../popup_host.dart';
import 'color_picker_panel.dart';
import 'color_swatch.dart';

/// The recolor popup (RecolorPopup — opened under the selection menu's
/// '색'): the recent colours row, the user palette row and '더 보기' (the
/// colour panel in the same popup, with [적용]). A colour tap →
/// EditorCommands.recolorSelection (one step — commitInkEdit(controller,
/// sel.recolor(argb))), the popup closes, the selection stays and the colour
/// goes to the recent colours. The selection's colour (its first
/// recolorable element) is ringed. The popup closes when the selection goes
/// away or is dragged.
class RecolorPanel extends ConsumerStatefulWidget {
  const RecolorPanel({super.key});

  static const panelKey = ValueKey('editor.popup.recolor');
  static const moreKey = ValueKey('editor.recolor.more');
  static const applyKey = ValueKey('editor.recolor.apply');

  /// Width of the popup (the colour panel needs the pen settings width).
  static const double width = 340;

  /// Key of the colour cell for [argb] (appendix C:
  /// `editor.recolor.swatch.<argb hex>` — 8 lower-case hex digits, opaque).
  static ValueKey<String> swatchKey(int argb) =>
      ValueKey('editor.recolor.swatch.${_hex(argb)}');

  static String _hex(int argb) =>
      (0xFF000000 + argb % 0x1000000).toRadixString(16).padLeft(8, '0');

  @override
  ConsumerState<RecolorPanel> createState() => _RecolorPanelState();
}

class _RecolorPanelState extends ConsumerState<RecolorPanel> {
  bool _expanded = false;
  int? _draft;

  void _pick(int argb) {
    ref.read(editorCommandsProvider).recolorSelection(argb);
    ref.read(editorPopupProvider.notifier).close();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(editorSelectionProvider, (_, next) {
      if (next == null || next.isDragging) {
        ref.read(editorPopupProvider.notifier).close();
      }
    });
    final selection = ref.watch(editorSelectionProvider);
    if (selection == null) return const SizedBox.shrink();
    final session = ref.watch(editorSessionValueProvider);
    final palette = ref.watch(editorColorPaletteProvider);
    final current = SelectionMenuModel.of(
      session.pageIfLoaded(selection.pageId),
      selection.elementIds,
    ).colorArgb;
    final theme = Theme.of(context);
    final used = <int>{};
    Widget swatch(int argb, {double diameter = 28}) {
      final c = ColorPaletteState.opaque(argb);
      // One cell per colour carries the appendix C key (a colour in both
      // rows: the recent one).
      final key = used.add(c)
          ? RecolorPanel.swatchKey(c)
          : ValueKey('editor.recolor.palette.${RecolorPanel._hex(c)}');
      return ColorSwatchButton(
        key: key,
        argb: c,
        diameter: diameter,
        selected: c == current,
        onTap: () => _pick(c),
      );
    }

    final draft = _draft ?? current ?? 0xFF000000;
    return PopupPanelFrame(
      key: RecolorPanel.panelKey,
      width: RecolorPanel.width,
      title: EditorStrings.selectionColor,
      children: [
        Text(EditorStrings.recentColors, style: theme.textTheme.labelLarge),
        if (palette.recent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              EditorStrings.noRecentColors,
              style: theme.textTheme.bodySmall,
            ),
          )
        else
          Wrap(children: [for (final c in palette.recent) swatch(c)]),
        const SizedBox(height: 8),
        if (palette.palette.isNotEmpty) ...[
          Text(EditorStrings.userPalette, style: theme.textTheme.labelLarge),
          Wrap(
            children: [
              for (final c in palette.palette) swatch(c, diameter: 30),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            key: RecolorPanel.moreKey,
            style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
            onPressed: () => setState(() => _expanded = !_expanded),
            child: const Text(EditorStrings.moreColors),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 4),
          ColorPickerPanel(
            colorArgb: draft,
            onColor: (c) => setState(() => _draft = c),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton(
              key: RecolorPanel.applyKey,
              style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
              onPressed: () => _pick(draft),
              child: const Text(EditorStrings.recolorApply),
            ),
          ),
        ],
      ],
    );
  }
}
