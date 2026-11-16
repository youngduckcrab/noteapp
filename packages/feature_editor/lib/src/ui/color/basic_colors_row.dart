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
/// 검정 is the default ink (#1A1A1A — core.PenStyle defaults, the shape and
/// text colour rows), so the first-run pen shows it selected.
const List<int> kBasicColors = [
  0xFF1A1A1A, // black (the default ink)
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

/// (v2.15-ui review) The [kBasicColors] index [argb] reads as: the exact
/// colour, else the nearest by hue and lightness (the stock pens' navy
/// #1B2A6B → 남색, highlighter #FFE600 → 노랑, pencil #3C3C3C → 진회색);
/// null for a light grey or white (no built-in colour is near it).
int? nearestBasicColorIndex(int argb) {
  final rgb = argb & 0xFFFFFF;
  for (var i = 0; i < kBasicColors.length; i++) {
    if (kBasicColors[i] & 0xFFFFFF == rgb) return i;
  }
  final hsl = HSLColor.fromColor(Color(rgb | 0xFF000000));
  final h = hsl.hue;
  final l = hsl.lightness;
  if (hsl.saturation < .15 || l < .12) {
    if (l < .2) return 0; // 검정
    if (l < .6) return 1; // 진회색
    return null;
  }
  if (l > .94) return null;
  if (h >= 10 && h < 45 && l < .42) return 11; // 갈색
  if (h < 10 || h >= 345) return 6; // 빨강
  if (h < 45) return 7; // 주황
  if (h < 70) return 8; // 노랑
  if (h < 160) return 5; // 초록
  if (h < 195) return 4; // 청록
  if (h < 250) return l < .33 ? 2 : 3; // 남색 / 파랑
  if (h < 300) return 9; // 보라
  return 10; // 분홍
}

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
                label: EditorStrings.basicColorNames[i],
                // RGB only: setColor keeps the pen's opacity.
                selected: i == nearestBasicColorIndex(current),
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
