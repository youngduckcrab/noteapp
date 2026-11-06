// lib/src/tools/object_resize.dart — m5-7/04-editor 6.6.5 (single object
// handles — pure math, unit-tested). (v2, E2-06) cornerScale first: the
// corner handles of a single object are drawn on its — possibly rotated —
// frame (6.6.4), so their drag needs it now. The edge, vertex and text width
// drags (resize, moveVertex, resizeTextWidth) come with E2-08.
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

abstract final class ObjectResize {
  /// The smallest side a handle drag leaves (pt).
  static const double minSidePt = 4;

  /// The narrowest text box (pt).
  static const double minTextWidthPt = 40;

  /// The smallest image side (pt).
  static const double minImageSidePt = 16;

  /// (min width, min height) of [object] in its own frame axes: text 40 pt
  /// wide (4 pt high), image 16 pt, everything else 4 pt.
  static ({double width, double height}) minimumOf(core.PageObject object) =>
      switch (object) {
        core.TextBoxObject() => (width: minTextWidthPt, height: minSidePt),
        core.ImageObject() => (width: minImageSidePt, height: minImageSidePt),
        _ => (width: minSidePt, height: minSidePt),
      };

  /// (수정 1회차, 검토 S-2 → EDITOR-M5) Corner handle (keep aspect) of a
  /// single — possibly rotated — object. delta is projected on the diagonal
  /// from the opposite corner o to the dragged corner c (a dot product, so
  /// the frame's rotation needs no undoing): s = (|c − o| + proj) / |c − o|,
  /// clamped so no side goes below the minimum ([minWidth] × [minHeight] pt
  /// — [minimumOf]; a side already shorter does not shrink) or above
  /// ElementFrame.maxSide. Returns T(o) · S(s) · T(−o) — a uniform scale
  /// about the ROTATED opposite corner (frame.corners[(i + 2) % 4]), so the
  /// rotation is unchanged and o stays put. Fed to
  /// InkSelection.setPreviewTransform → commitTransform → TransformElements
  /// (PageObject.transformed). An edge [corner] gives the identity.
  static core.Affine2 cornerScale(
    core.ElementFrame frame,
    ink.SelectionHandle corner,
    Offset deltaPagePt, {
    double minWidth = minSidePt,
    double minHeight = minSidePt,
  }) {
    final i = switch (corner) {
      ink.SelectionHandle.topLeft => 0,
      ink.SelectionHandle.topRight => 1,
      ink.SelectionHandle.bottomRight => 2,
      ink.SelectionHandle.bottomLeft => 3,
      _ => -1,
    };
    if (i < 0) return core.Affine2.identity;
    final corners = frame.corners;
    final c = corners[i], o = corners[(i + 2) % 4];
    final dx = c.x - o.x, dy = c.y - o.y;
    final length = math.sqrt(dx * dx + dy * dy);
    if (!(length > 0)) return core.Affine2.identity;
    final proj = (deltaPagePt.dx * dx + deltaPagePt.dy * dy) / length;
    var s = (length + proj) / length;
    if (s.isNaN) s = 1;
    final w = frame.rect.right - frame.rect.left;
    final h = frame.rect.bottom - frame.rect.top;
    var lower = 0.0;
    if (w > 0) lower = math.max(lower, math.min(1.0, minWidth / w));
    if (h > 0) lower = math.max(lower, math.min(1.0, minHeight / h));
    final longest = math.max(w, h);
    final upper = longest > 0
        ? math.max(1.0, core.ElementFrame.maxSide / longest)
        : 1.0;
    s = s.clamp(lower, upper).toDouble();
    if (s == 1) return core.Affine2.identity;
    return core.Affine2.scaling(s, s, originX: o.x, originY: o.y);
  }
}
