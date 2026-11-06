// lib/src/testing/synthetic_shapes.dart — body of
// package:ink_recognition/testing.dart SyntheticShapes (contract
// m5-7/00-overview 7.6, m5-7/05-library 4.3). Final since the 2차
// foundation step R2-B6: INFRA's V5b smoke test drives pointers along it
// right after the foundation stage.
//
// The guarantee 'GeometricShapeFitter with the default ShapeFitTuning always
// judges it a rectangle within 1 pt' is asserted since L2-06 for the whole
// size / pointsPerSide / viewScale range (synthetic_shapes_test);
// the R2-B6 test checks the path shape, closure and the ArgumentError rules.
import 'dart:ui' show Offset, Rect;

import '../shapes/shape_fit_tuning.dart';

/// (v2.1) Paths that GeometricShapeFitter with the default ShapeFitTuning always judges as the
/// named shape — app smoke tests drive pointers along it and hold (V5 '합성 멈춤').
abstract final class SyntheticShapes {
  /// Smallest pointsPerSide.
  static const int _minPointsPerSide = 4;

  /// Clockwise axis-aligned rectangle centreline in page pt: starts and ends
  /// at the middle of the top edge (a start at a corner would add a closing
  /// hook), [pointsPerSide] evenly spaced samples per side (corners
  /// included once), exactly closed — 4 × pointsPerSide + 1 points.
  ///
  /// The size rule is in pt at viewScale 1: [boundsPt] must be finite and
  /// both sides ≥ 2 × const ShapeFitTuning().minDiagonalLogicalPx (48 pt).
  /// At another viewScale v the CALLER enlarges the rect so that
  /// shortestSide × v ≥ 48. Out of range (a smaller or non-finite rect,
  /// pointsPerSide < 4) → ArgumentError.
  static List<Offset> rectanglePath(Rect boundsPt, {int pointsPerSide = 24}) {
    if (pointsPerSide < _minPointsPerSide) {
      throw ArgumentError.value(
        pointsPerSide,
        'pointsPerSide',
        'must be at least $_minPointsPerSide',
      );
    }
    if (!boundsPt.isFinite) {
      throw ArgumentError.value(boundsPt, 'boundsPt', 'must be finite');
    }
    final minSide = 2 * const ShapeFitTuning().minDiagonalLogicalPx;
    if (boundsPt.width < minSide || boundsPt.height < minSide) {
      throw ArgumentError.value(
        boundsPt,
        'boundsPt',
        'both sides must be at least $minSide pt (too small to snap)',
      );
    }
    final n = pointsPerSide;
    final l = boundsPt.left, t = boundsPt.top;
    final r = boundsPt.right, b = boundsPt.bottom;
    final mid = Offset((l + r) / 2, t);
    final topRight = Offset(r, t), bottomRight = Offset(r, b);
    final bottomLeft = Offset(l, b), topLeft = Offset(l, t);

    // The top side is split at its middle: ceil(n / 2) samples from the
    // middle to the top-right corner (corner excluded) and floor(n / 2) from
    // the top-left corner (included) back to the middle — n in all.
    final firstHalf = (n + 1) ~/ 2;
    final secondHalf = n - firstHalf;
    final path = <Offset>[
      ..._samples(mid, topRight, firstHalf),
      ..._samples(topRight, bottomRight, n),
      ..._samples(bottomRight, bottomLeft, n),
      ..._samples(bottomLeft, topLeft, n),
      ..._samples(topLeft, mid, secondHalf),
      mid,
    ];
    return path;
  }

  /// [count] samples from [from] (included) towards [to] (excluded), evenly
  /// spaced. `a + (b - a) × f` keeps a coordinate that does not change along
  /// the side exactly equal to the corner's.
  static Iterable<Offset> _samples(Offset from, Offset to, int count) sync* {
    for (var i = 0; i < count; i++) {
      final f = i / count;
      yield Offset(
        from.dx + (to.dx - from.dx) * f,
        from.dy + (to.dy - from.dy) * f,
      );
    }
  }
}
