// lib/src/ui/pen/quick_pen_popup.dart — 04-editor 6.9.1 (long press on the
// pen button). E-13 opens it; its content comes with E-15.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../tools/tool_controller.dart';
import '../editor_strings.dart';
import '../popup_host.dart';

/// Quick pen popup panel.
class QuickPenPanel extends ConsumerWidget {
  const QuickPenPanel({super.key});

  static const panelKey = ValueKey('editor.popup.quickPen');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tools = ref.watch(editorToolProvider);
    return PopupPanelFrame(
      key: panelKey,
      title: EditorStrings.quickPen,
      children: [Text(EditorStrings.penTypeName(tools.penType))],
    );
  }
}
