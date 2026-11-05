// lib/src/ui/pen/quick_pen_popup.dart — 04-editor 6.9.1 (long press on the
// pen button), 6.9.3 '빠른 팝업'. E-13 opens it; E-15 fills it.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../tools/tool_controller.dart';
import '../color/opacity_slider.dart';
import '../color/recent_colors_row.dart';
import '../color/user_palette_grid.dart';
import '../editor_strings.dart';
import '../popup_host.dart';
import 'pen_preview.dart';
import 'width_slider.dart';

/// Quick pen popup panel (300 wide): the width row + preview (the same
/// PenPreviewPainter call as the settings panel), opacity, the 12 recent
/// colours and the first [paletteShown] palette colours (tap only).
class QuickPenPanel extends ConsumerWidget {
  const QuickPenPanel({super.key});

  static const panelKey = ValueKey('editor.popup.quickPen');
  static const double width = 300;
  static const int paletteShown = 16;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tools = ref.watch(editorToolProvider);
    return PopupPanelFrame(
      key: panelKey,
      width: width,
      title:
          '${EditorStrings.quickPen} · ${EditorStrings.penTypeName(tools.penType)}',
      children: [
        const WidthSlider(),
        PenPreview(style: tools.currentPen),
        const SizedBox(height: 12),
        const OpacitySlider(),
        const SizedBox(height: 12),
        const RecentColorsRow(),
        const SizedBox(height: 8),
        const UserPaletteGrid(limit: paletteShown, editable: false),
      ],
    );
  }
}
