// lib/src/ui/pickers/swatch_button.dart — 05-library 6.12: one color choice
// of the paper / cover / folder color pickers. The swatch color is a palette
// value (PaperColors, CoverPalette, FolderPalette — the palette exceptions of
// contract 7.4.11); everything else comes from the color scheme.
import 'package:material_ui/material_ui.dart';

import '../layout/library_metrics.dart';

/// A 44 × 44 tap target around a [swatchSize] swatch filled with [color]:
/// circle or rounded rectangle, 1 px outlineVariant edge (white stays
/// visible), and a 2 px primary ring around it when [selected]. [label] is
/// the tooltip and the semantics label.
class SwatchButton extends StatelessWidget {
  const SwatchButton({
    super.key,
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
    this.circle = true,
    this.swatchSize = const Size(28, 28),
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool circle;
  final Size swatchSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const ring = 2.0, gap = 2.0;
    final outer = Size(
      swatchSize.width + 2 * (ring + gap),
      swatchSize.height + 2 * (ring + gap),
    );
    final targetWidth = outer.width < LibraryMetrics.minTapTarget
        ? LibraryMetrics.minTapTarget
        : outer.width;
    final targetHeight = outer.height < LibraryMetrics.minTapTarget
        ? LibraryMetrics.minTapTarget
        : outer.height;
    ShapeBorder shape(double grow, BorderSide side) => circle
        ? CircleBorder(side: side)
        : RoundedRectangleBorder(
            side: side,
            borderRadius: BorderRadius.circular(4 + grow),
          );
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: InkResponse(
          onTap: onTap,
          radius: targetWidth / 2,
          child: SizedBox(
            width: targetWidth,
            height: targetHeight,
            child: Center(
              child: Container(
                width: outer.width,
                height: outer.height,
                padding: const EdgeInsets.all(gap),
                decoration: ShapeDecoration(
                  shape: shape(
                    ring + gap,
                    selected
                        ? BorderSide(color: scheme.primary, width: ring)
                        : BorderSide.none,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(ring),
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: color,
                      shape: shape(0, BorderSide(color: scheme.outlineVariant)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
