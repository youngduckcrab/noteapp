// lib/src/ui/color/value_slider.dart — 04-editor 6.9.5 (under the wheel).
import 'package:material_ui/material_ui.dart';

import '../editor_strings.dart';
import 'color_drag_area.dart';
import 'color_math.dart';

/// Value (brightness) 0–1 of [hsv]: black → the colour at full value.
class ValueSlider extends StatelessWidget {
  const ValueSlider({super.key, required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) => GradientTrackSlider(
    value: hsv.value,
    colors: [PickerSpectrum.black, Color(ColorMath.fromHsv(hsv.withValue(1)))],
    semanticLabel: EditorStrings.colorValue,
    semanticValue: '${(hsv.value * 100).round()}%',
    onChanged: (t) => onChanged(hsv.withValue(t)),
  );
}
