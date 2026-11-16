// lib/src/tools/object_resize.dart — m5-7/04-editor 6.6.5 (single object
// handles — pure math, unit-tested). (v2, E2-06) cornerScale first: the
// corner handles of a single object are drawn on its — possibly rotated —
// frame (6.6.4), so their drag needs it now. (E2-08) the edge, vertex and
// text width drags: resize, moveVertex, resizeTextWidth (+ the text height
// re-measure withMeasuredHeight) — ObjectEditInteraction previews and
// commits them (UpdateObjects).
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

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

  /// (math resize fix) The uniform scale range a corner drag of [object] may
  /// take: a formula's font size stays in [MathStyle.minFontSize,
  /// MathStyle.maxFontSize] (6–144 pt — CORE clamps it there, so a bigger
  /// frame would only stretch the formula's raster); a size already outside
  /// does not move further out. Everything else: unbounded.
  static ({double min, double max}) scaleRangeOf(core.PageObject object) {
    if (object is! core.MathObject) {
      return (min: 0, max: double.infinity);
    }
    final f = object.style.fontSizePt;
    if (!(f > 0) || !f.isFinite) return (min: 1, max: 1);
    return (
      min: math.min(1.0, core.MathStyle.minFontSize / f),
      max: math.max(1.0, core.MathStyle.maxFontSize / f),
    );
  }

  /// (math resize fix) [scaleRangeOf] of every object of a selection: the
  /// tightest range (each contains 1, so the result does).
  static ({double min, double max}) scaleRangeOfAll(
    Iterable<core.PageObject> objects,
  ) {
    var lo = 0.0, hi = double.infinity;
    for (final o in objects) {
      final r = scaleRangeOf(o);
      lo = math.max(lo, r.min);
      hi = math.min(hi, r.max);
    }
    return (min: lo, max: hi);
  }

  /// (math resize fix) A selection resize [t] (SelectionGeometry.resize from
  /// [handle] of [bounds] — a scale about the opposite corner / edge) with its
  /// uniform scale (Affine2.uniformScale, what CORE scales a formula's font
  /// by) clamped into [range] ([scaleRangeOfAll]), about the same anchor: the
  /// whole selection stops where its first formula's font size stops, so the
  /// formula does not stop about its own centre while the rest grows on.
  static core.Affine2 clampGroupResize(
    core.Affine2 t, {
    required Rect bounds,
    required ink.SelectionHandle handle,
    required ({double min, double max}) range,
  }) {
    final u = t.uniformScale;
    if (!(u > 0) || !u.isFinite) return t;
    final clamped = u.clamp(range.min, range.max).toDouble();
    if (clamped == u) return t;
    final (hx, hy) = switch (handle) {
      ink.SelectionHandle.topLeft => (-1, -1),
      ink.SelectionHandle.top => (0, -1),
      ink.SelectionHandle.topRight => (1, -1),
      ink.SelectionHandle.right => (1, 0),
      ink.SelectionHandle.bottomRight => (1, 1),
      ink.SelectionHandle.bottom => (0, 1),
      ink.SelectionHandle.bottomLeft => (-1, 1),
      ink.SelectionHandle.left => (-1, 0),
    };
    final ax = hx < 0 ? bounds.right : bounds.left;
    final ay = hy < 0 ? bounds.bottom : bounds.top;
    // u = sqrt(sx · sy): a corner scales both (sx = sy), an edge one axis
    final k = clamped / u;
    final double sx, sy;
    if (hx != 0 && hy != 0) {
      (sx, sy) = (t.a * k, t.d * k);
    } else if (hx != 0) {
      (sx, sy) = (t.a * k * k, t.d);
    } else {
      (sx, sy) = (t.a, t.d * k * k);
    }
    return core.Affine2.scaling(sx, sy, originX: ax, originY: ay);
  }

  /// (수정 1회차, 검토 S-2 → EDITOR-M5) Corner handle (keep aspect) of a
  /// single — possibly rotated — object. delta is projected on the diagonal
  /// from the opposite corner o to the dragged corner c (a dot product, so
  /// the frame's rotation needs no undoing): s = (|c − o| + proj) / |c − o|,
  /// clamped so no side goes below the minimum ([minWidth] × [minHeight] pt
  /// — [minimumOf]; a side already shorter does not shrink) or above
  /// ElementFrame.maxSide, and (math resize fix) into [minScale, maxScale]
  /// ([scaleRangeOf]). Returns T(o) · S(s) · T(−o) — a uniform scale
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
    double minScale = 0,
    double maxScale = double.infinity,
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
    var upper = longest > 0
        ? math.max(1.0, core.ElementFrame.maxSide / longest)
        : 1.0;
    lower = math.max(lower, math.min(1.0, minScale));
    upper = math.min(upper, math.max(1.0, maxScale));
    s = s.clamp(lower, upper).toDouble();
    if (s == 1) return core.Affine2.identity;
    return core.Affine2.scaling(s, s, originX: o.x, originY: o.y);
  }

  /// (E2-08, 6.6.5) Edge handle drag of a single object in its frame-local
  /// axes (the rotation undone, then redone): the side opposite [handle]
  /// stays put. A polyline shape (frame rotation 0 — page axes) has its
  /// points scaled on that axis only (x' = anchor + (x − anchor)·s — a turned
  /// rectangle becomes a parallelogram, accepted); an ellipse gets a new
  /// local `rect` with its rotation kept; an image (aspect unlocked) a new
  /// frame; a text box its width ([resizeTextWidth] — left / right only).
  /// [keepAspect] scales the other side by the same ratio about the dragged
  /// axis (an edge) or projects on the diagonal (a corner — like
  /// [cornerScale]); a corner without it moves both sides freely. The sides
  /// stop at the minimum ([minimumOf] — a side already shorter does not
  /// shrink) and at ElementFrame.maxSide. Returns the edited copy (same id),
  /// or null when [handle] does not apply: an unknown object, a math object's
  /// edge, a text box's top / bottom edge, a flat polyline axis.
  static core.PageObject? resize(
    core.PageObject object,
    ink.SelectionHandle handle,
    Offset deltaPagePt, {
    required bool keepAspect,
  }) {
    final (hx, hy) = _directions(handle);
    final corner = hx != 0 && hy != 0;
    final min = minimumOf(object);
    switch (object) {
      case core.UnknownObject():
        return null;
      case core.MathObject():
        if (!corner) return null;
        final range = scaleRangeOf(object);
        return object.transformed(
          cornerScale(
            object.frame,
            handle,
            deltaPagePt,
            minWidth: min.width,
            minHeight: min.height,
            minScale: range.min,
            maxScale: range.max,
          ),
        );
      case core.TextBoxObject():
        if (corner) {
          return object.transformed(
            cornerScale(
              object.frame,
              handle,
              deltaPagePt,
              minWidth: min.width,
              minHeight: min.height,
            ),
          );
        }
        if (hx == 0) return null;
        return resizeTextWidth(object, handle, deltaPagePt);
      case core.ImageObject():
        return object.copyWith(
          frame: _resizedFrame(
            object.frame,
            hx,
            hy,
            deltaPagePt,
            minWidth: min.width,
            minHeight: min.height,
            keepAspect: keepAspect,
          ),
        );
      case core.ShapeObject(:final geometry):
        switch (geometry) {
          case core.EllipseGeometry(:final ellipseFrame):
            return object.copyWith(
              geometry: core.EllipseGeometry(
                _resizedFrame(
                  ellipseFrame,
                  hx,
                  hy,
                  deltaPagePt,
                  minWidth: min.width,
                  minHeight: min.height,
                  keepAspect: keepAspect,
                ),
              ),
            );
          case core.PolylineGeometry(:final points, :final closed):
            final box = geometry.frame.rect;
            final w = box.right - box.left, h = box.bottom - box.top;
            if ((hx != 0 && !(w > 0)) || (hy != 0 && !(h > 0))) return null;
            if (keepAspect && (!(w > 0) || !(h > 0))) return null;
            final next = _resizedFrame(
              core.ElementFrame(box),
              hx,
              hy,
              deltaPagePt,
              minWidth: min.width,
              minHeight: min.height,
              keepAspect: keepAspect,
            ).rect;
            final sx = w > 0 ? (next.right - next.left) / w : 1.0;
            final sy = h > 0 ? (next.bottom - next.top) / h : 1.0;
            return object.copyWith(
              geometry: core.PolylineGeometry([
                for (final p in points)
                  core.PagePoint(
                    next.left + (p.x - box.left) * sx,
                    next.top + (p.y - box.top) * sy,
                  ),
              ], closed: closed),
            );
        }
    }
  }

  /// (E2-08, 6.6.5) Moves vertex [index] of a PolylineGeometry shape by
  /// [deltaPagePt]. [snapAngle]: a line / an arrow (two points) has the
  /// angle from the other end point snapped by
  /// ink.SelectionGeometry.snapAngle (15° steps within ±3°, the length kept);
  /// a polygon, a triangle, a rectangle or a star never snaps. shapeKind is
  /// kept (contract 7.2.2 'UI meaning only'). Another geometry or an index
  /// out of range → [shape] unchanged.
  static core.ShapeObject moveVertex(
    core.ShapeObject shape,
    int index,
    Offset deltaPagePt, {
    bool snapAngle = true,
  }) {
    final geometry = shape.geometry;
    if (geometry is! core.PolylineGeometry) return shape;
    final points = geometry.points;
    if (index < 0 || index >= points.length) return shape;
    final p = points[index];
    var x = p.x + deltaPagePt.dx, y = p.y + deltaPagePt.dy;
    if (snapAngle && isEndpointShape(shape)) {
      final other = points[1 - index];
      final dx = x - other.x, dy = y - other.y;
      final length = math.sqrt(dx * dx + dy * dy);
      if (length > 0) {
        final angle = math.atan2(dy, dx);
        final snapped = ink.SelectionGeometry.snapAngle(angle);
        if (snapped != angle) {
          x = other.x + math.cos(snapped) * length;
          y = other.y + math.sin(snapped) * length;
        }
      }
    }
    return shape.copyWith(
      geometry: core.PolylineGeometry([
        for (var i = 0; i < points.length; i++)
          i == index ? core.PagePoint(x, y) : points[i],
      ], closed: geometry.closed),
    );
  }

  /// (E2-08, 6.6.5) Text box width handle ([side] left or right): the frame
  /// width follows the drag along the box's own x axis (the rotation undone),
  /// at least [minTextWidthPt] (a box already narrower does not shrink) and at
  /// most ElementFrame.maxSide; the other side stays put, the height and the
  /// rotation are kept — the caller re-measures the height
  /// ([withMeasuredHeight]). Another handle → [box] unchanged.
  static core.TextBoxObject resizeTextWidth(
    core.TextBoxObject box,
    ink.SelectionHandle side,
    Offset deltaPagePt,
  ) {
    final hx = switch (side) {
      ink.SelectionHandle.left => -1,
      ink.SelectionHandle.right => 1,
      _ => 0,
    };
    if (hx == 0) return box;
    return box.copyWith(
      frame: _resizedFrame(
        box.frame,
        hx,
        0,
        deltaPagePt,
        minWidth: minTextWidthPt,
        minHeight: minSidePt,
        keepAspect: false,
      ),
    );
  }

  /// (E2-08) [box] with the laid-out height [measuredPt] (at least one line:
  /// fontSizePt × lineHeight) and its — possibly rotated — top edge kept (the
  /// centre moves along the box's own y axis). Rotation 0: the rect's top
  /// stays, like the edit session's height.
  static core.TextBoxObject withMeasuredHeight(
    core.TextBoxObject box,
    double measuredPt,
  ) {
    final frame = box.frame;
    final r = frame.rect;
    final oneLine = box.style.fontSizePt * box.style.lineHeight;
    final height = math.min(
      core.ElementFrame.maxSide,
      measuredPt > oneLine ? measuredPt : oneLine,
    );
    final h = r.bottom - r.top;
    if (height == h) return box;
    final grow = (height - h) / 2;
    final theta = frame.rotation;
    final c = frame.center;
    final cx = c.x - math.sin(theta) * grow;
    final cy = c.y + math.cos(theta) * grow;
    final w = r.right - r.left;
    return box.copyWith(
      frame: core.ElementFrame(
        core.PageRect(cx - w / 2, cy - height / 2, cx + w / 2, cy + height / 2),
        rotation: theta,
      ),
    );
  }

  /// (E2-08) A line or an arrow with two points: its handles are the two end
  /// points (always vertex handles, no box, no rotation — 6.6.4).
  static bool isEndpointShape(core.ShapeObject shape) {
    final geometry = shape.geometry;
    return (shape.shapeKind == core.ShapeKind.line ||
            shape.shapeKind == core.ShapeKind.arrow) &&
        geometry is core.PolylineGeometry &&
        geometry.points.length == 2;
  }

  /// (−1 | 0 | 1, −1 | 0 | 1): which local side of the frame [handle] moves
  /// (−1 left / top, 1 right / bottom, 0 that axis stays).
  static (int, int) _directions(ink.SelectionHandle handle) => switch (handle) {
    ink.SelectionHandle.topLeft => (-1, -1),
    ink.SelectionHandle.top => (0, -1),
    ink.SelectionHandle.topRight => (1, -1),
    ink.SelectionHandle.right => (1, 0),
    ink.SelectionHandle.bottomRight => (1, 1),
    ink.SelectionHandle.bottom => (0, 1),
    ink.SelectionHandle.bottomLeft => (-1, 1),
    ink.SelectionHandle.left => (-1, 0),
  };

  /// [side] after a drag to [wanted]: at least [minimum] (a side already
  /// shorter stays), at most ElementFrame.maxSide.
  static double _clampSide(double wanted, double side, double minimum) {
    final lower = math.min(side, minimum);
    final upper = math.max(side, core.ElementFrame.maxSide);
    if (wanted.isNaN) return side;
    return wanted.clamp(lower, upper).toDouble();
  }

  /// [frame] with the sides [hx] / [hy] (see [_directions]) moved by
  /// [delta] in the frame's own axes; the opposite sides stay put, the
  /// rotation is kept.
  static core.ElementFrame _resizedFrame(
    core.ElementFrame frame,
    int hx,
    int hy,
    Offset delta, {
    required double minWidth,
    required double minHeight,
    required bool keepAspect,
  }) {
    final theta = frame.rotation;
    final cos = math.cos(theta), sin = math.sin(theta);
    // local axes: u = (cos, sin) (the box's x), v = (−sin, cos) (its y)
    final lx = delta.dx * cos + delta.dy * sin;
    final ly = -delta.dx * sin + delta.dy * cos;
    final r = frame.rect;
    final w = r.right - r.left, h = r.bottom - r.top;
    var newW = hx == 0 ? w : _clampSide(w + hx * lx, w, minWidth);
    var newH = hy == 0 ? h : _clampSide(h + hy * ly, h, minHeight);
    if (keepAspect && w > 0 && h > 0) {
      final double k;
      if (hx != 0 && hy != 0) {
        // the projection on the diagonal (cornerScale's rule)
        final dx = hx * w, dy = hy * h;
        final len2 = dx * dx + dy * dy;
        k = len2 == 0 ? 1 : ((dx + lx) * dx + (dy + ly) * dy) / len2;
      } else {
        k = hx != 0 ? newW / w : newH / h;
      }
      var s = k.isNaN ? 1.0 : k;
      s = math.max(
        s,
        math.max(math.min(1.0, minWidth / w), math.min(1.0, minHeight / h)),
      );
      s = math.min(
        s,
        math.max(1.0, core.ElementFrame.maxSide / math.max(w, h)),
      );
      newW = w * s;
      newH = h * s;
    }
    // the centre follows the moved sides (an axis without a dragged side
    // grows symmetrically — keepAspect on an edge)
    final gx = hx * (newW - w) / 2, gy = hy * (newH - h) / 2;
    final c = frame.center;
    final cx = c.x + cos * gx - sin * gy;
    final cy = c.y + sin * gx + cos * gy;
    return core.ElementFrame(
      core.PageRect(cx - newW / 2, cy - newH / 2, cx + newW / 2, cy + newH / 2),
      rotation: theta,
    );
  }
}
