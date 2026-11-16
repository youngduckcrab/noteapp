// lib/src/ui/color/color_palette_popup.dart — m5-7/04-editor 6.4.1
// (EditorAction.colorPalette, E2-05).
import 'package:material_ui/material_ui.dart';

import '../editor_strings.dart';
import '../pen/quick_pen_popup.dart';
import '../popup_host.dart';
import 'basic_colors_row.dart';
import 'recent_colors_row.dart';
import 'user_palette_grid.dart';

/// The colour palette popup (300 wide): (v2.14-ui) the 12 built-in colours,
/// the 12 recent colours and the user palette (tap only). A tap sets the
/// current pen's colour.
class ColorPalettePanel extends StatelessWidget {
  const ColorPalettePanel({super.key});

  static const panelKey = ValueKey('editor.popup.colorPalette');

  @override
  Widget build(BuildContext context) => const PopupPanelFrame(
    key: panelKey,
    width: QuickPenPanel.width,
    title: EditorStrings.actionColorPalette,
    children: [
      BasicColorsRow(),
      SizedBox(height: 8),
      RecentColorsRow(),
      SizedBox(height: 8),
      UserPaletteGrid(editable: false),
    ],
  );
}
