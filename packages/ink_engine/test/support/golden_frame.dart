// Golden capture frame (03-ink 9.2): images under test/goldens/images/, at
// most 400 × 400 px, opaque. A page drawn at a fractional size (A4 × scale)
// would leave a partly covered last row / column (alpha < 255), so the
// capture is cropped to whole pixels: the child is laid out at its own size
// and the RepaintBoundary is that size floored.
import 'package:flutter/widgets.dart';

/// Largest golden image side in px (9.2).
const double kMaxGoldenSidePx = 400;

/// [child] at its own (possibly fractional) [size] inside a top-left
/// RepaintBoundary of `size` floored to whole pixels — the boundary the
/// golden matcher captures.
Widget goldenFrame(Size size, Widget child) {
  final w = size.width.floorToDouble(), h = size.height.floorToDouble();
  assert(w <= kMaxGoldenSidePx && h <= kMaxGoldenSidePx, 'golden too large');
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        child: SizedBox(
          width: w,
          height: h,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 0,
            minHeight: 0,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: child,
          ),
        ),
      ),
    ),
  );
}
