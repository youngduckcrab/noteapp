// lib/src/edit/selection_geometry.dart — 03-ink 4.7, numeric contract 6.22.
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:note_core/note_core.dart' as core;

import '../interop/core_interop.dart' as interop;
import '../model/ink_stroke.dart';
import '../tuning.dart';

enum SelectionHandle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
}

/// THE implementation of selection-transform math in the app (7.2.0, INK-S4). EDITOR only
/// hit-tests its handles and calls these functions. Numeric contract (6.22):
///  * scale per axis clamped to [InkTuning.scaleMin 0.05, InkTuning.scaleMax 20];
///  * resulting box short side >= InkTuning.selectionMinSizePt (4 pt); never flips;
///  * stroke width after the transform = clamp(width * m.uniformScale, 0.1, 30)
///    (== core.Stroke.transformed, scaleWidth: true; limits = core.StrokeStyle.minWidth/maxWidth);
///  * the final geometry is CORE's Stroke.transformed; INK previews match it within 0.01 pt.
abstract final class SelectionGeometry {
  /// Union of the CORE bounds of [strokes]; Rect.zero when empty.
  static Rect boundsOf(Iterable<InkStroke> strokes) {
    Rect? out;
    for (final s in strokes) {
      out = out == null ? s.bounds : out.expandToInclude(s.bounds);
    }
    return out ?? Rect.zero;
  }

  /// Transform for dragging [handle] by [delta] (page pt). The opposite handle stays fixed.
  /// Corner handles keep aspect when [keepAspect]; edge handles scale one axis.
  static core.Affine2 resize({
    required Rect bounds,
    required SelectionHandle handle,
    required Offset delta,
    bool keepAspect = true,
  }) {
    // -1: the left / top edge moves, +1: the right / bottom edge moves, 0: fixed axis.
    final (hx, hy) = switch (handle) {
      SelectionHandle.topLeft => (-1, -1),
      SelectionHandle.top => (0, -1),
      SelectionHandle.topRight => (1, -1),
      SelectionHandle.right => (1, 0),
      SelectionHandle.bottomRight => (1, 1),
      SelectionHandle.bottom => (0, 1),
      SelectionHandle.bottomLeft => (-1, 1),
      SelectionHandle.left => (-1, 0),
    };
    final w = bounds.width, h = bounds.height;
    final anchorX = hx < 0 ? bounds.right : bounds.left;
    final anchorY = hy < 0 ? bounds.bottom : bounds.top;
    var sx = 1.0, sy = 1.0;
    final isCorner = hx != 0 && hy != 0;
    if (isCorner && keepAspect) {
      // Project the dragged size vector onto the original diagonal.
      final dx = hx * w, dy = hy * h;
      final len2 = dx * dx + dy * dy;
      if (len2 > 0) {
        final vx = dx + delta.dx, vy = dy + delta.dy;
        var s = (vx * dx + vy * dy) / len2;
        s = _clampScale(s, w);
        s = _clampScale(s, h);
        sx = s;
        sy = s;
      }
    } else {
      if (hx != 0 && w > 0) sx = _clampScale((w + hx * delta.dx) / w, w);
      if (hy != 0 && h > 0) sy = _clampScale((h + hy * delta.dy) / h, h);
    }
    return core.Affine2.scaling(sx, sy, originX: anchorX, originY: anchorY);
  }

  /// Clamp to [scaleMin, scaleMax], never flip, and never shrink the side
  /// below selectionMinSizePt (a side already shorter cannot shrink further).
  static double _clampScale(double s, double side) {
    var v = s.isNaN ? 1.0 : s;
    if (side > 0) {
      final minBySize = math.min(1.0, InkTuning.selectionMinSizePt / side);
      v = math.max(v, minBySize);
    }
    return v.clamp(InkTuning.scaleMin, InkTuning.scaleMax).toDouble();
  }

  static core.Affine2 move(Offset delta) =>
      core.Affine2.translation(delta.dx, delta.dy);

  /// Rotation around bounds.center.
  static core.Affine2 rotate({required Rect bounds, required double radians}) =>
      core.Affine2.rotation(
        radians,
        originX: bounds.center.dx,
        originY: bounds.center.dy,
      );

  /// Snaps to multiples of [step] when within [threshold].
  static double snapAngle(
    double radians, {
    double step = math.pi / 12,
    double threshold = 3 * math.pi / 180,
  }) {
    if (!(step > 0)) return radians;
    final snapped = (radians / step).roundToDouble() * step;
    return (radians - snapped).abs() <= threshold ? snapped : radians;
  }

  /// Axis-aligned box of [bounds] after [m] (selection frame preview).
  static Rect transformedBounds(Rect bounds, core.Affine2 m) =>
      interop.rectOf(m.applyToRect(interop.pageRectOf(bounds)));

  /// The 4 corners of [bounds] after [m], clockwise from top-left (rotated frame).
  static List<Offset> transformedCorners(Rect bounds, core.Affine2 m) => [
    interop.applyAffine(m, bounds.topLeft),
    interop.applyAffine(m, bounds.topRight),
    interop.applyAffine(m, bounds.bottomRight),
    interop.applyAffine(m, bounds.bottomLeft),
  ];

  /// Width a stroke will have after [m]: clamp(width * m.uniformScale, 0.1, 30).
  static double transformedWidth(double width, core.Affine2 m) =>
      (width * m.uniformScale)
          .clamp(core.StrokeStyle.minWidth, core.StrokeStyle.maxWidth)
          .toDouble();
}
