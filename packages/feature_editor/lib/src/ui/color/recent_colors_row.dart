// lib/src/ui/color/recent_colors_row.dart — 04-editor 6.9.3 #5 (최근 색 12개).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/color_palette.dart';
import '../../tools/tool_controller.dart';
import '../editor_strings.dart';
import 'color_swatch.dart';

/// The recent colours (28 px circles, newest first — a stroke commit puts
/// its colour in front). Tap → the current pen's colour.
class RecentColorsRow extends ConsumerWidget {
  const RecentColorsRow({super.key});

  static ValueKey<String> swatchKey(int index) =>
      ValueKey('editor.color.recent.$index');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(
      editorColorPaletteProvider.select((s) => s.recent),
    );
    final current = ref.watch(
      editorToolProvider.select((s) => s.currentPen.colorArgb),
    );
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(EditorStrings.recentColors, style: theme.textTheme.labelLarge),
        if (recent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              EditorStrings.noRecentColors,
              style: theme.textTheme.bodySmall,
            ),
          )
        else
          Wrap(
            children: [
              for (var i = 0; i < recent.length; i++)
                ColorSwatchButton(
                  key: swatchKey(i),
                  argb: recent[i],
                  selected: recent[i] == current,
                  onTap: () =>
                      ref.read(editorToolProvider.notifier).setColor(recent[i]),
                ),
            ],
          ),
      ],
    );
  }
}
