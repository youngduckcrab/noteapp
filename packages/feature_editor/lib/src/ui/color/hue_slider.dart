// lib/src/ui/color/hue_slider.dart — 04-editor 6.9.5 (under the square).
import 'package:material_ui/material_ui.dart';

import '../editor_strings.dart';
import 'color_drag_area.dart';

/// Hue 0–360 of [hsv] over the rainbow track.
class HueSlider extends StatelessWidget {
  const HueSlider({super.key, required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) => GradientTrackSlider(
    value: hsv.hue / 360,
    colors: PickerSpectrum.hueStops,
    semanticLabel: EditorStrings.colorHue,
    semanticValue: '${hsv.hue.round()}°',
    onChanged: (t) => onChanged(hsv.withHue(t * 360)),
  );
}
