// lib/src/ui/pen/pen_settings_popup.dart — 04-editor 6.9.3.
//
// E-13 opens this panel from the toolbar (the active pen tapped again).
// E-14: the colour part (#4 picker, #5 recent colours, #6 palette). E-15: pen
// types (#1), width + preview (#2), opacity (#3) and '고급' (#7). E-16:
// [프리셋으로 저장] (#8) → SavePresetPopup (replaces this popup).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/popup.dart';
import '../../tools/tool_controller.dart';
import '../color/color_picker_panel.dart';
import '../color/opacity_slider.dart';
import '../color/recent_colors_row.dart';
import '../color/user_palette_grid.dart';
import '../editor_strings.dart';
import '../popup_host.dart';
import 'pen_advanced_controls.dart';
import 'pen_preview.dart';
import 'pen_type_selector.dart';
import 'width_slider.dart';

/// Pen settings popup panel (6.9.3): 340 wide, scrolls past min(600, room).
class PenSettingsPanel extends ConsumerWidget {
  const PenSettingsPanel({super.key});

  static const panelKey = ValueKey('editor.popup.penSettings');
  static const advancedKey = ValueKey('editor.popup.penSettings.advanced');
  static const saveAsPresetKey = ValueKey(
    'editor.popup.penSettings.saveAsPreset',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pen = ref.watch(editorToolProvider.select((s) => s.currentPen));
    return PopupPanelFrame(
      key: panelKey,
      title: EditorStrings.penSettings,
      children: [
        const PenTypeSelector(),
        const SizedBox(height: 8),
        const WidthSlider(),
        PenPreview(style: pen),
        const SizedBox(height: 12),
        const OpacitySlider(),
        const SizedBox(height: 12),
        const ColorPickerPanel(),
        const SizedBox(height: 12),
        const RecentColorsRow(),
        const SizedBox(height: 8),
        const UserPaletteGrid(),
        const SizedBox(height: 4),
        Theme(
          // No divider lines around the expansion tile inside the panel.
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: const ExpansionTile(
            key: advancedKey,
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.only(bottom: 8),
            title: Text(EditorStrings.advanced),
            children: [PenAdvancedControls()],
          ),
        ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          key: saveAsPresetKey,
          onPressed: () => ref
              .read(editorPopupProvider.notifier)
              .open(const SavePresetPopup()),
          icon: const Icon(Icons.bookmark_add),
          label: const Text(EditorStrings.saveAsPreset),
        ),
      ],
    );
  }
}
