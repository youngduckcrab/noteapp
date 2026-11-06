// lib/src/tools/selection_hit_test.dart — 04-editor 6.6.5; (v2) m5-7/04-editor
// 6.6.4 (rotated frames, the rotate handle, the 8 handle directions) — E2-06.
//
// Hit testing of the selection frame only; the transform math is
// ink.SelectionGeometry (contract 7.2.15, INK 4.7).
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:ink_engine/ink_engine.dart' as ink;

abstract final class SelectionHitTest {
  static const double handleVisualRadius = 6; // px
  static const double handleHitRadius = 22; // px
  static const double bodyInflate = 8; // px

  /// (v2, 6.6.4) The rotate handle's centre: this far (px) outside the
  /// middle of the frame's top edge, along the edge's outward normal.
  static const double rotateHandleOffset = 28;

  /// (v2) Half the side of an edge handle's square (px — drawn from E2-08).
  static const double edgeHandleHalfSide = 5;

  /// M1 shows the 4 corner handles only (keepAspect resize).
  static const List<ink.SelectionHandle> cornerHandles = [
    ink.SelectionHandle.topLeft,
    ink.SelectionHandle.topRight,
    ink.SelectionHandle.bottomRight,
    ink.SelectionHandle.bottomLeft,
  ];

  /// (v2) The 4 edge handles (middles of the sides).
  static const List<ink.SelectionHandle> edgeHandles = [
    ink.SelectionHandle.top,
    ink.SelectionHandle.right,
    ink.SelectionHandle.bottom,
    ink.SelectionHandle.left,
  ];

  /// (v2) All 8 directions, clockwise from top-left.
  static const List<ink.SelectionHandle> allHandles = [
    ink.SelectionHandle.topLeft,
    ink.SelectionHandle.top,
    ink.SelectionHandle.topRight,
    ink.SelectionHandle.right,
    ink.SelectionHandle.bottomRight,
    ink.SelectionHandle.bottom,
    ink.SelectionHandle.bottomLeft,
    ink.SelectionHandle.left,
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
  static ink.SelectionHandle? hitHandle(Rect boundsOnScreen, Offset p) =>
      hitFrameHandle(
        SelectionQuad.fromRect(boundsOnScreen),
        p,
        rotatable: false,
      )?.resize;

  /// [p] lies inside [boundsOnScreen] inflated by [bodyInflate] px.
  static bool hitBody(Rect boundsOnScreen, Offset p) =>
      boundsOnScreen.inflate(bodyInflate).contains(p);

  /// (v2) The handle of [quad] within [handleHitRadius] px of [p] — one of
  /// [handles] or, when [rotatable], the rotate handle — the nearest one when
  /// several are (a small frame); null when none is.
  static FrameHandle? hitFrameHandle(
    SelectionQuad quad,
    Offset p, {
    Iterable<ink.SelectionHandle> handles = cornerHandles,
    bool rotatable = true,
  }) {
    FrameHandle? best;
    var bestDistance = double.infinity;
    void consider(FrameHandle handle, Offset at) {
      final d = (at - p).distance;
      if (d <= handleHitRadius && d < bestDistance) {
        best = handle;
        bestDistance = d;
      }
    }

    for (final handle in handles) {
      consider(FrameHandle.resize(handle), quad.handlePosition(handle));
    }
    if (rotatable) {
      consider(const FrameHandle.rotate(), quad.rotateHandlePosition);
    }
    return best;
  }

  /// (v2) [p] lies inside [quad] inflated by [bodyInflate] px (in the quad's
  /// own axes — a rotated frame's body is rotated too).
  static bool hitQuadBody(SelectionQuad quad, Offset p) =>
      quad.containsInflated(p, bodyInflate);

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

/// (v2, 6.6.4) A handle of the selection frame: one of INK's 8 resize
/// handles ([resize]) or the rotate handle ([isRotate]).
@immutable
final class FrameHandle {
  const FrameHandle.resize(ink.SelectionHandle this.resize);
  const FrameHandle.rotate() : resize = null;

  /// null = the rotate handle.
  final ink.SelectionHandle? resize;

  bool get isRotate => resize == null;

  @override
  bool operator ==(Object other) =>
      other is FrameHandle && other.resize == resize;

  @override
  int get hashCode => resize.hashCode;

  @override
  String toString() =>
      isRotate ? 'FrameHandle.rotate' : 'FrameHandle.${resize!.name}';
}

/// (v2, 6.6.4) The selection frame as a — possibly rotated — rectangle on
/// screen: its corners clockwise from the (unrotated) top-left. An axis-aligned
/// frame is [SelectionQuad.fromRect]; a rotated object frame or a frame under
/// a rotation preview has its corners turned.
@immutable
final class SelectionQuad {
  const SelectionQuad(
    this.topLeft,
    this.topRight,
    this.bottomRight,
    this.bottomLeft,
  );

  factory SelectionQuad.fromRect(Rect r) =>
      SelectionQuad(r.topLeft, r.topRight, r.bottomRight, r.bottomLeft);

  /// [corners] = tl, tr, br, bl.
  factory SelectionQuad.fromCorners(List<Offset> corners) {
    if (corners.length != 4) {
      throw ArgumentError.value(corners, 'corners', 'needs 4 points');
    }
    return SelectionQuad(corners[0], corners[1], corners[2], corners[3]);
  }

  final Offset topLeft, topRight, bottomRight, bottomLeft;

  List<Offset> get corners => [topLeft, topRight, bottomRight, bottomLeft];

  Offset get center => (topLeft + bottomRight) / 2;

  /// The direction of the top edge (screen radians, clockwise positive —
  /// y points down); 0 for an axis-aligned frame.
  double get angle => math.atan2(_u.dy, _u.dx);

  /// The unit vector along the top edge (tl → tr); a frame without width
  /// takes the bottom edge, then the x axis.
  Offset get _u {
    for (final d in [topRight - topLeft, bottomRight - bottomLeft]) {
      final length = d.distance;
      if (length > 1e-9) return d / length;
    }
    return const Offset(1, 0);
  }

  /// The unit vector along the left edge (tl → bl) — the top edge turned by
  /// +90° (down on screen) when the frame has no height.
  Offset get _v {
    final d = bottomLeft - topLeft;
    final length = d.distance;
    if (length > 1e-9) return d / length;
    final u = _u;
    return Offset(-u.dy, u.dx);
  }

  double get width => (topRight - topLeft).distance;
  double get height => (bottomLeft - topLeft).distance;

  /// The screen position of [handle]: a corner, or the middle of a side.
  Offset handlePosition(ink.SelectionHandle handle) => switch (handle) {
    ink.SelectionHandle.topLeft => topLeft,
    ink.SelectionHandle.top => (topLeft + topRight) / 2,
    ink.SelectionHandle.topRight => topRight,
    ink.SelectionHandle.right => (topRight + bottomRight) / 2,
    ink.SelectionHandle.bottomRight => bottomRight,
    ink.SelectionHandle.bottom => (bottomRight + bottomLeft) / 2,
    ink.SelectionHandle.bottomLeft => bottomLeft,
    ink.SelectionHandle.left => (bottomLeft + topLeft) / 2,
  };

  /// Where the rotate handle's line meets the frame (the top edge's middle).
  Offset get rotateHandleBase => handlePosition(ink.SelectionHandle.top);

  /// The rotate handle's centre: [SelectionHitTest.rotateHandleOffset] px
  /// outside the top edge's middle, along its outward normal (−v).
  Offset get rotateHandlePosition =>
      rotateHandleBase - _v * SelectionHitTest.rotateHandleOffset;

  /// [p] inside the frame inflated by [inflate] px, in the frame's axes.
  bool containsInflated(Offset p, double inflate) {
    final d = p - topLeft;
    final u = _u, v = _v;
    final x = d.dx * u.dx + d.dy * u.dy;
    final y = d.dx * v.dx + d.dy * v.dy;
    return x >= -inflate &&
        x <= width + inflate &&
        y >= -inflate &&
        y <= height + inflate;
  }

  /// The axis-aligned box of the corners.
  Rect get bounds {
    final xs = [topLeft.dx, topRight.dx, bottomRight.dx, bottomLeft.dx];
    final ys = [topLeft.dy, topRight.dy, bottomRight.dy, bottomLeft.dy];
    return Rect.fromLTRB(
      xs.reduce(math.min),
      ys.reduce(math.min),
      xs.reduce(math.max),
      ys.reduce(math.max),
    );
  }

  SelectionQuad shift(Offset by) => SelectionQuad(
    topLeft + by,
    topRight + by,
    bottomRight + by,
    bottomLeft + by,
  );

  @override
  bool operator ==(Object other) =>
      other is SelectionQuad &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft);

  @override
  String toString() =>
      'SelectionQuad($topLeft, $topRight, $bottomRight, $bottomLeft)';
}
