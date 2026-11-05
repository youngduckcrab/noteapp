// lib/src/tools/selection_hit_test.dart — 04-editor 6.6.5.
//
// Hit testing of the selection frame only; the transform math is
// ink.SelectionGeometry (contract 7.2.15, INK 4.7).
import 'dart:ui' show Offset, Rect, Size;

import 'package:ink_engine/ink_engine.dart' as ink;

abstract final class SelectionHitTest {
  static const double handleVisualRadius = 6; // px
  static const double handleHitRadius = 22; // px
  static const double bodyInflate = 8; // px

  /// M1 shows the 4 corner handles only (keepAspect resize).
  static const List<ink.SelectionHandle> cornerHandles = [
    ink.SelectionHandle.topLeft,
    ink.SelectionHandle.topRight,
    ink.SelectionHandle.bottomRight,
    ink.SelectionHandle.bottomLeft,
  ];

  /// The screen position of corner [handle] of [boundsOnScreen].
  static Offset handlePosition(
    Rect boundsOnScreen,
    ink.SelectionHandle handle,
  ) => switch (handle) {
    ink.SelectionHandle.topLeft => boundsOnScreen.topLeft,
    ink.SelectionHandle.top => boundsOnScreen.topCenter,
    ink.SelectionHandle.topRight => boundsOnScreen.topRight,
    ink.SelectionHandle.right => boundsOnScreen.centerRight,
    ink.SelectionHandle.bottomRight => boundsOnScreen.bottomRight,
    ink.SelectionHandle.bottom => boundsOnScreen.bottomCenter,
    ink.SelectionHandle.bottomLeft => boundsOnScreen.bottomLeft,
    ink.SelectionHandle.left => boundsOnScreen.centerLeft,
  };

  /// The corner handle within [handleHitRadius] px of [p] (the nearest one
  /// when several are — a small selection), or null.
  static ink.SelectionHandle? hitHandle(Rect boundsOnScreen, Offset p) {
    ink.SelectionHandle? best;
    var bestDistance = double.infinity;
    for (final handle in cornerHandles) {
      final d = (handlePosition(boundsOnScreen, handle) - p).distance;
      if (d <= handleHitRadius && d < bestDistance) {
        best = handle;
        bestDistance = d;
      }
    }
    return best;
  }

  /// [p] lies inside [boundsOnScreen] inflated by [bodyInflate] px.
  static bool hitBody(Rect boundsOnScreen, Offset p) =>
      boundsOnScreen.inflate(bodyInflate).contains(p);

  /// Clamps a page-pt move so the moved bounds' centre stays inside the page.
  static Offset clampTranslation(Rect bounds, Offset delta, Size pageSize) {
    final centre = bounds.center;
    final moved = centre + delta;
    final clamped = Offset(
      moved.dx.clamp(0.0, pageSize.width).toDouble(),
      moved.dy.clamp(0.0, pageSize.height).toDouble(),
    );
    return clamped - centre;
  }
}
