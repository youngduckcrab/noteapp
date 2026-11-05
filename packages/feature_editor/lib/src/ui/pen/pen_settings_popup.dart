// lib/src/ui/pen/pen_settings_popup.dart — 04-editor 6.9.3.
//
// E-13 opens this panel from the toolbar (the active pen tapped again). E-14
// fills the colour part (#4 picker, #5 recent colours, #6 palette); the pen
// types, width, opacity, preview and advanced controls come with E-15.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../tools/tool_controller.dart';
import '../color/color_picker_panel.dart';
import '../color/recent_colors_row.dart';
import '../color/user_palette_grid.dart';
import '../editor_strings.dart';
import '../popup_host.dart';

/// Pen settings popup panel (6.9.3).
class PenSettingsPanel extends ConsumerWidget {
  const PenSettingsPanel({super.key});

  static const panelKey = ValueKey('editor.popup.penSettings');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tools = ref.watch(editorToolProvider);
    return PopupPanelFrame(
      key: panelKey,
      title: EditorStrings.penSettings,
      children: [
        Text(EditorStrings.penTypeName(tools.penType)),
        const SizedBox(height: 12),
        const ColorPickerPanel(),
        const SizedBox(height: 12),
        const RecentColorsRow(),
        const SizedBox(height: 8),
        const UserPaletteGrid(),
      ],
    );
  }
}
