// lib/src/tools/shape_drafts.dart — m5-7/04-editor 6.9.2 (E2-09): the shape
// tool's geometry from a drag — pure, unit-tested. CORE's templates
// (ShapeGeometry.line / rectangle / ellipse / triangle / regularPolygon /
// star) do the geometry; this only picks the box and the snapping.
import 'dart:math' as math;

import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import 'tool_options.dart';

/// How a drag snaps (6.9.2): [normal] = the thresholds (15° within ±3° for
/// a line, |w / h − 1| ≤ 0.06 for the equal-sided kinds); [always] (Shift on
/// a hardware keyboard) = the thresholds at infinity — every line on a 15°
/// step, every box square; [off] (Alt) = no snapping.
enum ShapeSnap { normal, always, off }

abstract final class ShapeDrafts {
  /// |w / h − 1| at most this → a square / circle / regular polygon / star
  /// with the long side (p0 fixed).
  static const double ratioThreshold = 0.06;

  /// The geometry of [kind] dragged from [p0] to [p1] (page pt) with the
  /// tool's [options] (polygon sides, star points):
  ///
  /// | kind | geometry (r = the box of p0, p1) | snapping |
  /// |---|---|---|
  /// | line · arrow | ShapeGeometry.line(p0, p1) | the angle from p0 (snapAngle, 15°, ±3°), the length kept |
  /// | rectangle | rectangle(r) | square (ratio) |
  /// | ellipse | ellipse(r) | circle (ratio) |
  /// | triangle | triangle(r) | none |
  /// | polygon | regularPolygon(r, sides) | ratio |
  /// | star | star(r, points: starPoints) | ratio |
  static core.ShapeGeometry geometry(
    core.ShapeKind kind,
    core.PagePoint p0,
    core.PagePoint p1,
    ToolOptions options, {
    ShapeSnap snap = ShapeSnap.normal,
  }) {
    switch (kind) {
      case core.ShapeKind.line:
      case core.ShapeKind.arrow:
        return core.ShapeGeometry.line(p0, _snappedEnd(p0, p1, snap));
      case core.ShapeKind.rectangle:
        return core.ShapeGeometry.rectangle(_box(p0, p1, snap));
      case core.ShapeKind.ellipse:
        return core.ShapeGeometry.ellipse(_box(p0, p1, snap));
      case core.ShapeKind.triangle:
        return core.ShapeGeometry.triangle(_box(p0, p1, ShapeSnap.off));
      case core.ShapeKind.polygon:
        return core.ShapeGeometry.regularPolygon(
          _box(p0, p1, snap),
          options.polygonSides,
        );
      case core.ShapeKind.star:
        return core.ShapeGeometry.star(
          _box(p0, p1, snap),
          points: options.starPoints,
        );
    }
  }

  /// The style of a new shape of [kind]: the tool's style normalized; an
  /// arrow without heads gets one at the end (6.9.2 — a line keeps its own).
  static core.ShapeStyle styleFor(core.ShapeKind kind, ToolOptions options) {
    final style = options.shapeStyle.normalized();
    if (kind == core.ShapeKind.arrow &&
        style.arrowHeads == core.ArrowHeads.none) {
      return style.copyWith(arrowHeads: core.ArrowHeads.end);
    }
    return style;
  }

  static core.PagePoint _snappedEnd(
    core.PagePoint p0,
    core.PagePoint p1,
    ShapeSnap snap,
  ) {
    if (snap == ShapeSnap.off) return p1;
    final dx = p1.x - p0.x, dy = p1.y - p0.y;
    final length = math.sqrt(dx * dx + dy * dy);
    if (!(length > 0)) return p1;
    final angle = math.atan2(dy, dx);
    final snapped = snap == ShapeSnap.always
        ? ink.SelectionGeometry.snapAngle(angle, threshold: double.infinity)
        : ink.SelectionGeometry.snapAngle(angle);
    if (snapped == angle) return p1;
    return core.PagePoint(
      p0.x + math.cos(snapped) * length,
      p0.y + math.sin(snapped) * length,
    );
  }

  /// The box of [p0], [p1]; squared from p0 toward p1 (the long side) when
  /// [snap] says so.
  static core.PageRect _box(
    core.PagePoint p0,
    core.PagePoint p1,
    ShapeSnap snap,
  ) {
    final dx = p1.x - p0.x, dy = p1.y - p0.y;
    final w = dx.abs(), h = dy.abs();
    final square = switch (snap) {
      ShapeSnap.off => false,
      ShapeSnap.always => w > 0 || h > 0,
      ShapeSnap.normal => h > 0 && (w / h - 1).abs() <= ratioThreshold,
    };
    if (!square) return core.PageRect.fromPoints(p0.x, p0.y, p1.x, p1.y);
    final side = math.max(w, h);
    final sx = dx < 0 ? -1.0 : 1.0, sy = dy < 0 ? -1.0 : 1.0;
    return core.PageRect.fromPoints(
      p0.x,
      p0.y,
      p0.x + sx * side,
      p0.y + sy * side,
    );
  }
}
