// lib/src/ui/color/basic_colors_row.dart — (v2.14-ui, UI stage 1 —
// m5-7/04-editor 'UI 정리 1단계') 기본 색 12개: there from the first run, above
// the recent colours, so a common colour is one tap (it took the wheel and
// 5+ steps before). Built in, never stored: the saved recent colours and the
// user palette (editor.colors) are untouched.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../tools/tool_controller.dart';
import '../editor_strings.dart';
import 'color_swatch.dart';

/// The 12 built-in colours (opaque ARGB), in this order: black, dark grey,
/// navy, blue, teal, green, red, orange, yellow, purple, pink, brown.
const List<int> kBasicColors = [
  0xFF000000, // black
  0xFF5F6368, // dark grey
  0xFF1A237E, // navy
  0xFF1E88E5, // blue
  0xFF00897B, // teal
  0xFF43A047, // green
  0xFFE53935, // red
  0xFFFB8C00, // orange
  0xFFFDD835, // yellow
  0xFF8E24AA, // purple
  0xFFEC407A, // pink
  0xFF6D4C41, // brown
];

/// '기본 색' + the [kBasicColors] swatches (28 px circles in 44 px cells,
/// wrapping). Tap → the current pen's colour (like a recent colour).
class BasicColorsRow extends ConsumerWidget {
  const BasicColorsRow({super.key});

  static ValueKey<String> swatchKey(int index) =>
      ValueKey('editor.color.basic.$index');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(
      editorToolProvider.select((s) => s.currentPen.colorArgb),
    );
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(EditorStrings.basicColors, style: theme.textTheme.labelLarge),
        Wrap(
          children: [
            for (var i = 0; i < kBasicColors.length; i++)
              ColorSwatchButton(
                key: swatchKey(i),
                argb: kBasicColors[i],
                selected: kBasicColors[i] == current,
                onTap: () => ref
                    .read(editorToolProvider.notifier)
                    .setColor(kBasicColors[i]),
              ),
          ],
        ),
      ],
    );
  }
}
