// lib/src/ui/color/color_swatch.dart — 04-editor 6.9.3 #5–#6 (one colour
// circle of the recent colours and the palette).
import 'package:material_ui/material_ui.dart';

import 'color_math.dart';

/// A [diameter] colour circle in a 44 × 44 touch target (contract 7.4.8);
/// [selected] draws a primary ring. Semantics label = the HEX value.
class ColorSwatchButton extends StatelessWidget {
  const ColorSwatchButton({
    super.key,
    required this.argb,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
    this.diameter = 28,
  });

  static const double cellSize = 44;

  final int argb;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: ColorMath.toHex(argb),
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: cellSize,
        child: InkResponse(
          onTap: onTap,
          onLongPress: onLongPress,
          radius: cellSize / 2,
          child: Center(
            child: Container(
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                color: Color(ColorMath.opaque(argb)),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? scheme.primary : scheme.outlineVariant,
                  width: selected ? 3 : 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
