// lib/src/ui/color/color_swatch.dart — 04-editor 6.9.3 #5–#6 (one colour
// circle of the recent colours and the palette).
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import 'color_math.dart';

/// A [diameter] colour circle in a 44 × 44 touch target (contract 7.4.8);
/// [selected] draws a primary ring. Semantics label = [label], else the HEX
/// value. (v2.14-ui review) In dark mode the ring of an unselected swatch is
/// `outline`, not `outlineVariant`, so dark inks (검정, 남색) stay visible on
/// the dark popup.
class ColorSwatchButton extends StatelessWidget {
  const ColorSwatchButton({
    super.key,
    required this.argb,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
    this.diameter = 28,
    this.label,
  });

  static const double cellSize = 44;

  final int argb;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final double diameter;

  /// The spoken name (the basic colours' Korean names); null → HEX.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label ?? ColorMath.toHex(argb),
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
                  color: selected
                      ? scheme.primary
                      : StyleTokens.of(context).swatchRing(
                          Color(ColorMath.opaque(argb)),
                          StyleTokens.of(context).panel,
                        ),
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
