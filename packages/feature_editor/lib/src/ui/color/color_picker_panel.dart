// lib/src/ui/color/color_picker_panel.dart — 04-editor 6.9.3 #4, 6.9.5.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../scope/editor_scope.dart';
import '../../tools/tool_controller.dart';
import '../editor_strings.dart';
import 'color_math.dart';
import 'hex_rgb_fields.dart';
import 'hsv_wheel.dart';
import 'hue_slider.dart';
import 'sv_square.dart';
import 'value_slider.dart';

/// Which picker the colour section shows.
enum ColorPickerMode { wheel, square }

/// The colour section of the pen settings panel: SegmentedButton[휠 | 사각] →
/// HsvWheel + ValueSlider or SvSquare + HueSlider, the HEX and R/G/B fields
/// and [스포이드]. Edits the current pen's colour (ToolController.setColor —
/// the opacity is separate, an 8-digit HEX sets it too).
///
/// The picker keeps an HSVColor as its source while it is used, so the hue
/// survives saturation 0 or value 0. When the colour changes elsewhere (a
/// preset, another pen type, the eyedropper) the HSV is computed again,
/// keeping the old hue when the new saturation or value is 0.
///
/// (v2, m5-7/04-editor 6.7.2) With [onColor] the panel edits [colorArgb]
/// instead of the pen's colour (the recolor popup's '더 보기'): every change
/// goes to [onColor] (opaque), the opacity part of an 8-digit HEX is
/// ignored and [스포이드] is not shown.
class ColorPickerPanel extends ConsumerStatefulWidget {
  const ColorPickerPanel({super.key, this.colorArgb, this.onColor})
    : assert(
        (colorArgb == null) == (onColor == null),
        'colorArgb and onColor go together',
      );

  /// The colour edited with [onColor] (null: the current pen's colour).
  final int? colorArgb;

  /// Receives the edited colour (null: ToolController.setColor).
  final ValueChanged<int>? onColor;

  static const wheelSegmentKey = ValueKey('editor.color.mode.wheel');
  static const squareSegmentKey = ValueKey('editor.color.mode.square');
  static const wheelKey = ValueKey('editor.color.wheel');
  static const valueSliderKey = ValueKey('editor.color.value');
  static const squareKey = ValueKey('editor.color.square');
  static const hueSliderKey = ValueKey('editor.color.hue');
  static const eyedropperKey = ValueKey('editor.color.eyedropper');

  @override
  ConsumerState<ColorPickerPanel> createState() => _ColorPickerPanelState();
}

class _ColorPickerPanelState extends ConsumerState<ColorPickerPanel> {
  HSVColor? _hsv;
  ColorPickerMode _mode = ColorPickerMode.wheel;

  HSVColor _syncFrom(int argb) {
    final held = _hsv;
    if (held != null && ColorMath.fromHsv(held) == ColorMath.opaque(argb)) {
      return held;
    }
    final next = ColorMath.toHsv(argb);
    return _hsv = held != null && (next.saturation == 0 || next.value == 0)
        ? next.withHue(held.hue)
        : next;
  }

  void _apply(HSVColor next) {
    setState(() => _hsv = next);
    _setColor(ColorMath.fromHsv(next));
  }

  void _setColor(int argb) {
    final onColor = widget.onColor;
    if (onColor != null) {
      onColor(ColorMath.opaque(argb));
    } else {
      ref.read(editorToolProvider.notifier).setColor(argb);
    }
  }

  @override
  Widget build(BuildContext context) {
    final int penArgb = ref.watch(
      editorToolProvider.select((s) => s.currentPen.colorArgb),
    );
    final argb = widget.colorArgb ?? penArgb;
    final hsv = _syncFrom(argb);
    final tools = ref.read(editorToolProvider.notifier);
    final penColour = widget.onColor == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedButton<ColorPickerMode>(
          segments: const [
            ButtonSegment(
              value: ColorPickerMode.wheel,
              label: Text(
                EditorStrings.colorWheel,
                key: ColorPickerPanel.wheelSegmentKey,
              ),
            ),
            ButtonSegment(
              value: ColorPickerMode.square,
              label: Text(
                EditorStrings.colorSquare,
                key: ColorPickerPanel.squareSegmentKey,
              ),
            ),
          ],
          selected: {_mode},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        const SizedBox(height: 12),
        if (_mode == ColorPickerMode.wheel) ...[
          Center(
            child: HsvWheel(
              key: ColorPickerPanel.wheelKey,
              hsv: hsv,
              onChanged: _apply,
            ),
          ),
          const SizedBox(height: 4),
          ValueSlider(
            key: ColorPickerPanel.valueSliderKey,
            hsv: hsv,
            onChanged: _apply,
          ),
        ] else ...[
          Center(
            child: SvSquare(
              key: ColorPickerPanel.squareKey,
              hsv: hsv,
              onChanged: _apply,
            ),
          ),
          const SizedBox(height: 4),
          HueSlider(
            key: ColorPickerPanel.hueSliderKey,
            hsv: hsv,
            onChanged: _apply,
          ),
        ],
        const SizedBox(height: 8),
        HexRgbFields(
          argb: argb,
          onColor: _setColor,
          onOpacity: penColour ? tools.setOpacity : (_) {},
        ),
        if (penColour) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: ColorPickerPanel.eyedropperKey,
              icon: const Icon(Icons.colorize),
              label: const Text(EditorStrings.eyedropper),
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              onPressed: () =>
                  ref.read(editorCommandsProvider).startEyedropper(),
            ),
          ),
        ],
      ],
    );
  }
}
