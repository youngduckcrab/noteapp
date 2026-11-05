// lib/src/ui/color/opacity_slider.dart — 04-editor 6.9.3 #3 (투명도 5–100%).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../tools/tool_controller.dart';
import '../editor_strings.dart';
import 'color_drag_area.dart';

/// The current pen's opacity: "투명도 60%" over a checkerboard with a
/// transparent → opaque gradient of the pen colour. The track spans
/// core.StrokeStyle.minOpacity (left end) to 1 (right end); ToolController
/// rounds to 0.01.
class OpacitySlider extends ConsumerWidget {
  const OpacitySlider({super.key});

  static const sliderKey = ValueKey('editor.pen.opacity');

  static const double min = core.StrokeStyle.minOpacity;

  /// Opacity at slider position [t] (0..1) and back.
  static double opacityAt(double t) => min + (1 - min) * t.clamp(0.0, 1.0);
  static double positionOf(double opacity) =>
      ((opacity - min) / (1 - min)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pen = ref.watch(editorToolProvider.select((s) => s.currentPen));
    final scheme = Theme.of(context).colorScheme;
    final color = Color(pen.colorArgb);
    final percent = (pen.opacity * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          EditorStrings.opacityLabel(percent),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        GradientTrackSlider(
          key: sliderKey,
          value: positionOf(pen.opacity),
          colors: [
            color.withValues(alpha: min),
            color,
          ],
          background: CheckerboardPainter(
            light: scheme.surface,
            dark: scheme.surfaceContainerHighest,
          ),
          semanticLabel: EditorStrings.opacity,
          semanticValue: '$percent%',
          onChanged: (t) =>
              ref.read(editorToolProvider.notifier).setOpacity(opacityAt(t)),
        ),
      ],
    );
  }
}

/// 7 px checker squares in two theme colours (the opacity track's backdrop).
class CheckerboardPainter extends CustomPainter {
  CheckerboardPainter({required this.light, required this.dark});

  final Color light;
  final Color dark;

  static const double cell = 7;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = light);
    final paint = Paint()..color = dark;
    var row = 0;
    for (var y = 0.0; y < size.height; y += cell, row++) {
      var col = 0;
      for (var x = 0.0; x < size.width; x += cell, col++) {
        if ((row + col).isOdd) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(CheckerboardPainter old) =>
      old.light != light || old.dark != dark;
}
