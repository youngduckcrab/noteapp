// lib/src/object/shape_path.dart — INTERNAL (m5-7/03-ink 6.9, T33).
//
// The geometry of one ShapeObject, built once per instance (Expando — 6.8.1):
// - centerline (6.9.1): a polyline as given (closed → back to the first
//   point), an ellipse sampled when it is dashed / dotted (6.9.2:
//   clamp(⌈perimeter / 2 pt⌉, 32, 256) segments) — a solid ellipse is the
//   exact oval, rotated about its center;
// - arrow heads (6.9.3, line / arrow kinds, open polylines): filled triangles
//   E, E − L(cos α·d − sin α·n), E − L(cos α·d + sin α·n) with L =
//   style.arrowHeadLength, α = InkTuning.arrowHeadHalfAngleDeg; d = the
//   direction of the last segment of non-zero length (none → no heads); the
//   line stops at the base midpoint B = E − L·cos α·d (or, when the last
//   segment is shorter, at the same distance back along the line);
// - line style (6.9.2): solid = the centerline stroked once (round cap and
//   join, no self-overlap darkening); dashed [4, 3] × w and dotted [0, 2] × w
//   through the shared splitter (geometry/dash.dart) — capsules in one stroked
//   path, dots in one filled path;
// - fill: closed polylines (≥ 3 points) and ellipses with fillColorArgb, drawn
//   before the outline; open polylines are never filled.
// Drawing (paintShape): the colors' alpha is ignored, the *Opacity fields
// apply (5.2); an arrow with strokeOpacity < 1 draws its line and heads opaque
// inside one saveLayer so the overlap is not painted twice (S-10).
// K-6 (6.9.4): every centerline point is a vertex or lies on the outline of
// the frame, the stroke reaches w / 2 from it, the heads lie within L of an
// end point — all inside bounds = frame.bounds.inflate(0.75·w + L).
// Vector geometry (6.9.5): shapeOutlineOf gives the fill polygons and the
// outline polygons (the round-1 fill outline generator with the constant
// radius w / 2 on every centerline / dash piece, dots as inscribed polygons,
// the heads) — all with the positive O7 orientation, so one nonzero path
// paints the line and the heads once (S-10).
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:note_core/note_core.dart' as core;

import '../geometry/dash.dart';
import '../geometry/outline_generator.dart';
import '../interop/core_interop.dart' as interop;
import '../model/ink_points.dart';
import '../pen/pen_profile.dart';
import '../render/stroke_painter.dart' show inkColor;
import '../tuning.dart';

/// The dash pattern of a LineDash, in multiples of the stroke width (6.9.2).
List<double> shapeDashPattern(core.LineDash dash) => switch (dash) {
  core.LineDash.solid => const [],
  core.LineDash.dashed => const [4, 3],
  core.LineDash.dotted => const [0, 2],
};

/// The drawable geometry of one ShapeObject (see the file comment).
final class ShapeRenderGeometry {
  ShapeRenderGeometry._({
    required this.width,
    required this.centerline,
    required this.closed,
    required this.oval,
    required this.fill,
    required this.capsules,
    required this.dots,
    required this.heads,
  });

  /// The validated stroke width (pt).
  final double width;

  /// The (trimmed) centerline; for a solid ellipse: empty ([oval] instead).
  final List<ui.Offset> centerline;

  /// [centerline] is a closed loop (its last point is its first).
  final bool closed;

  /// A solid ellipse: the exact oval path (rotated).
  final ui.Path? oval;

  /// The fill area (closed polyline or ellipse with a fill color); null = no fill.
  final ui.Path? fill;

  /// Dashed: the capsule centerlines (≥ 2 points each); solid / dotted: empty.
  final List<List<ui.Offset>> capsules;

  /// Dotted (and dashes too short for a capsule): dot centers of radius width / 2.
  final List<ui.Offset> dots;

  /// Arrow head triangles (apex first).
  final List<List<ui.Offset>> heads;

  /// The stroke as one path to stroke with a round cap and join: the solid centerline, the
  /// oval, or the dash capsules as subpaths (nonzero union — painted once).
  late final ui.Path? strokePath = _strokePath();

  /// The dots as one filled path of circles; null when there are none.
  late final ui.Path? dotPath = dots.isEmpty
      ? null
      : (ui.Path()
          ..fillType = ui.PathFillType.nonZero
          ..addCircles(dots, width / 2));

  /// The heads as one filled path; null when there are none.
  late final ui.Path? headPath = heads.isEmpty ? null : _polygonsPath(heads);

  ui.Path? _strokePath() {
    final o = oval;
    if (o != null) return o;
    if (capsules.isNotEmpty) {
      final p = ui.Path();
      for (final c in capsules) {
        _addPolyline(p, c, close: false);
      }
      return p;
    }
    if (dots.isNotEmpty || centerline.length < 2) return null;
    return _addPolyline(ui.Path(), centerline, close: closed);
  }
}

extension on ui.Path {
  /// Adds a circle of [radius] around every point.
  void addCircles(List<ui.Offset> centers, double radius) {
    for (final c in centers) {
      addOval(ui.Rect.fromCircle(center: c, radius: radius));
    }
  }
}

ui.Path _addPolyline(ui.Path p, List<ui.Offset> pts, {required bool close}) {
  p.moveTo(pts.first.dx, pts.first.dy);
  for (var i = 1; i < pts.length; i++) {
    p.lineTo(pts[i].dx, pts[i].dy);
  }
  if (close) p.close();
  return p;
}

ui.Path _polygonsPath(List<List<ui.Offset>> polygons) {
  final p = ui.Path()..fillType = ui.PathFillType.nonZero;
  for (final poly in polygons) {
    if (poly.length >= 3) p.addPolygon(poly, true);
  }
  return p;
}

final Expando<ShapeRenderGeometry> _geometries = Expando('ShapeGeometry');

/// The geometry of [o] (cached per instance).
ShapeRenderGeometry shapeGeometryOf(core.ShapeObject o) =>
    _geometries[o] ??= _build(o);

double _validWidth(double w) => w.isFinite
    ? w.clamp(core.ShapeStyle.minWidth, core.ShapeStyle.maxWidth).toDouble()
    : 2.0;

/// A stored opacity as drawn: clamped to [0, 1], not finite → 1 (5.2).
double shapeOpacity(double o) =>
    o.isFinite ? o.clamp(0.0, 1.0).toDouble() : 1.0;

bool _hasHeads(core.ShapeObject o) =>
    o.style.arrowHeads != core.ArrowHeads.none &&
    (o.shapeKind == core.ShapeKind.line || o.shapeKind == core.ShapeKind.arrow);

/// The ellipse of [frame] sampled with [segments] segments, closed (last = first), from
/// the rotated frame's right-middle point (parameter 0).
List<ui.Offset> _ellipsePoints(core.ElementFrame frame, int segments) {
  final r = frame.rect;
  final c = frame.center;
  final a = r.width / 2, b = r.height / 2;
  final rot = frame.rotation.isFinite ? frame.rotation : 0.0;
  final cr = math.cos(rot), sr = math.sin(rot);
  return [
    for (var k = 0; k <= segments; k++)
      () {
        if (k == segments) {
          return ui.Offset(c.x + a * cr, c.y + a * sr);
        }
        final t = 2 * math.pi * k / segments;
        final x = a * math.cos(t), y = b * math.sin(t);
        return ui.Offset(c.x + x * cr - y * sr, c.y + x * sr + y * cr);
      }(),
  ];
}

ui.Path _ovalPath(core.ElementFrame frame) {
  final r = frame.rect;
  final c = frame.center;
  final rot = frame.rotation.isFinite ? frame.rotation : 0.0;
  final oval = ui.Path()
    ..addOval(
      ui.Rect.fromCenter(
        center: ui.Offset.zero,
        width: r.width,
        height: r.height,
      ),
    );
  final cr = math.cos(rot), sr = math.sin(rot);
  // column-major 4×4: rotate by rot, then translate to the center
  final m = Float64List(16)
    ..[0] = cr
    ..[1] = sr
    ..[4] = -sr
    ..[5] = cr
    ..[10] = 1
    ..[12] = c.x
    ..[13] = c.y
    ..[15] = 1;
  return oval.transform(m);
}

/// One arrow head at end [e] of a line coming from [from] (≠ e): the triangle and the
/// distance back from [e] to the base midpoint.
(List<ui.Offset>, double) _head(ui.Offset e, ui.Offset from, double l) {
  final v = e - from;
  final d = v / v.distance;
  final n = ui.Offset(-d.dy, d.dx);
  const alpha = InkTuning.arrowHeadHalfAngleDeg * math.pi / 180;
  final ca = math.cos(alpha), sa = math.sin(alpha);
  return ([e, e - (d * ca - n * sa) * l, e - (d * ca + n * sa) * l], l * ca);
}

/// The last point before index [end] (walking back) that differs from points[end].
int? _distinctBefore(List<ui.Offset> pts, int end, int step) {
  for (var i = end - step; i >= 0 && i < pts.length; i -= step) {
    if ((pts[i] - pts[end]).distance > 1e-9) return i;
  }
  return null;
}

ShapeRenderGeometry _build(core.ShapeObject o) {
  final style = o.style;
  final w = _validWidth(style.strokeWidth);
  final dash = style.dash;
  final pattern = [for (final v in shapeDashPattern(dash)) v * w];
  ui.Path? oval;
  ui.Path? fill;
  var closed = false;
  var line = <ui.Offset>[];
  final heads = <List<ui.Offset>>[];
  switch (o.geometry) {
    case core.PolylineGeometry(:final points, closed: final isClosed):
      final pts = [
        for (final p in points)
          if (p.x.isFinite && p.y.isFinite) ui.Offset(p.x, p.y),
      ];
      closed = isClosed && pts.length > 2;
      if (closed) {
        if (style.fillColorArgb != null) {
          fill = _polygonsPath([pts]);
        }
        line = [...pts, pts.first];
      } else {
        line = pts;
      }
      if (!closed && _hasHeads(o) && pts.length >= 2) {
        line = _withHeads(pts, style, heads);
      }
    case core.EllipseGeometry(:final ellipseFrame):
      final r = ellipseFrame.rect;
      final ok =
          r.width.isFinite &&
          r.height.isFinite &&
          ellipseFrame.center.x.isFinite &&
          ellipseFrame.center.y.isFinite;
      if (ok) {
        if (style.fillColorArgb != null) fill = _ovalPath(ellipseFrame);
        if (dash == core.LineDash.solid) {
          oval = _ovalPath(ellipseFrame);
        } else {
          line = _ellipsePoints(
            ellipseFrame,
            ellipseDashSegments(r.width / 2, r.height / 2),
          );
          closed = true;
        }
      }
  }
  final capsules = <List<ui.Offset>>[];
  final dots = <ui.Offset>[];
  if (oval == null && pattern.isNotEmpty && line.isNotEmpty) {
    for (final piece in dashPieces(
      PolylineMeasure(line),
      pattern,
      radius: w / 2,
    )) {
      if (piece.length == 1) {
        dots.add(piece.single);
      } else {
        capsules.add(piece);
      }
    }
  } else if (oval == null && line.length == 1) {
    dots.add(line.single);
  }
  return ShapeRenderGeometry._(
    width: w,
    centerline: List.unmodifiable(line),
    closed: closed,
    oval: oval,
    fill: fill,
    capsules: capsules,
    dots: dots,
    heads: heads,
  );
}

/// 6.9.3: adds the heads of [style] at the end (and the start for `both`) of the open
/// polyline [pts] to [heads] and returns the line trimmed to the base midpoints.
List<ui.Offset> _withHeads(
  List<ui.Offset> pts,
  core.ShapeStyle style,
  List<List<ui.Offset>> heads,
) {
  final l = style.arrowHeadLength;
  if (!(l > 0) || !l.isFinite) return pts;
  final last = pts.length - 1;
  final beforeEnd = _distinctBefore(pts, last, 1);
  if (beforeEnd == null) return pts; // every segment has length 0: no head
  final both = style.arrowHeads == core.ArrowHeads.both;
  // drop the repeats of the end points: the heads use the real segments
  var line = pts.sublist(0, beforeEnd + 1)..add(pts[last]);
  if (both) {
    final afterStart = _distinctBefore(line, 0, -1)!;
    line = [line.first, ...line.sublist(afterStart)];
  }
  final measure = PolylineMeasure(line);
  final total = measure.length;
  var from = 0.0, to = total;
  final (endHead, endBack) = _head(line.last, line[line.length - 2], l);
  heads.add(endHead);
  final lastSegment = (line.last - line[line.length - 2]).distance;
  ui.Offset? exactEnd;
  if (lastSegment >= endBack) {
    final d = (line.last - line[line.length - 2]) / lastSegment;
    exactEnd = line.last - d * endBack;
  }
  to = total - endBack;
  ui.Offset? exactStart;
  if (both) {
    final (startHead, startBack) = _head(line.first, line[1], l);
    heads.add(startHead);
    final firstSegment = (line[1] - line.first).distance;
    if (firstSegment >= startBack) {
      final d = (line.first - line[1]) / firstSegment;
      exactStart = line.first - d * startBack;
    }
    from = startBack;
  }
  if (to <= from) return const []; // the heads cover the whole line
  final trimmed = measure.between(from, to);
  // the exact base midpoints B = E − L·cos α·d on a long enough end segment
  if (exactEnd != null) trimmed[trimmed.length - 1] = exactEnd;
  if (exactStart != null) trimmed[0] = exactStart;
  return trimmed;
}

/// Paints [o] in page pt (6.9). Throws only on an unexpected engine error (the caller
/// catches — 4.0).
void paintShape(ui.Canvas canvas, core.ShapeObject o) {
  final g = shapeGeometryOf(o);
  final style = o.style;
  final fillArgb = style.fillColorArgb;
  final fill = g.fill;
  if (fill != null && fillArgb != null) {
    canvas.drawPath(
      fill,
      ui.Paint()
        ..style = ui.PaintingStyle.fill
        ..isAntiAlias = true
        ..color = inkColor(fillArgb, shapeOpacity(style.fillOpacity)),
    );
  }
  final opacity = shapeOpacity(style.strokeOpacity);
  final stroke = g.strokePath, dots = g.dotPath, heads = g.headPath;
  if (stroke == null && dots == null && heads == null) return;
  // S-10: line + heads (+ dots) overlap — one layer, the opacity applied once
  final layered = opacity < 1 && heads != null;
  if (layered) {
    canvas.saveLayer(
      interop.rectOf(o.bounds),
      ui.Paint()..color = ui.Color.fromARGB((opacity * 255).round(), 0, 0, 0),
    );
  }
  final color = inkColor(style.strokeColorArgb, layered ? 1 : opacity);
  if (stroke != null) {
    canvas.drawPath(
      stroke,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = g.width
        ..strokeCap = ui.StrokeCap.round
        ..strokeJoin = ui.StrokeJoin.round
        ..isAntiAlias = true
        ..color = color,
    );
  }
  final solidPaint = ui.Paint()
    ..style = ui.PaintingStyle.fill
    ..isAntiAlias = true
    ..color = color;
  if (dots != null) canvas.drawPath(dots, solidPaint);
  if (heads != null) canvas.drawPath(heads, solidPaint);
  if (layered) canvas.restore();
}

/// 6.9.5: the vector geometry of a shape — fill polygons and outline polygons (each x,y
/// pairs, implicitly closed, positive O7 orientation: one nonzero path each).
typedef ShapeOutline = ({List<Float32List> fill, List<Float32List> stroke});

/// The vector geometry of [o] (6.9.5).
ShapeOutline shapeOutlineOf(core.ShapeObject o) {
  final fill = <Float32List>[];
  // the fill: the closed polyline as given, the ellipse sampled finely
  if (o.style.fillColorArgb != null) {
    switch (o.geometry) {
      case core.PolylineGeometry(:final points, :final closed)
          when closed && points.length > 2:
        fill.add(_oriented([for (final p in points) ui.Offset(p.x, p.y)]));
      case core.EllipseGeometry(:final ellipseFrame):
        final pts = _ellipsePoints(ellipseFrame, 256)..removeLast();
        fill.add(_oriented(pts));
      case core.PolylineGeometry():
        break;
    }
  }
  final parts = shapeOutlinePartsOf(o);
  return (
    fill: fill,
    stroke: [
      ...parts.pieces,
      for (final c in parts.dots) _circlePolygon(c, parts.dotRadius),
      ...parts.heads,
    ],
  );
}

/// (T42) The outline of [o] in parts: [pieces] = the outline polygons of the solid
/// centerline (a solid ellipse sampled — ellipseDashSegments) or of every dash piece,
/// [heads] = the arrow head triangles (both positive O7 orientation), [dots] = the dot
/// centers of radius [dotRadius] = width / 2. shapeOutlineOf lists them as polygons
/// (pieces, dots as inscribed polygons, heads); the vector export draws the dots as
/// exact circles (4 cubics) instead.
typedef ShapeOutlineParts = ({
  List<Float32List> pieces,
  List<Float32List> heads,
  List<ui.Offset> dots,
  double dotRadius,
});

/// See [ShapeOutlineParts].
ShapeOutlineParts shapeOutlinePartsOf(core.ShapeObject o) {
  final g = shapeGeometryOf(o);
  List<ui.Offset> line = g.centerline;
  if (g.oval != null) {
    final frame = (o.geometry as core.EllipseGeometry).ellipseFrame;
    line = _ellipsePoints(
      frame,
      ellipseDashSegments(frame.rect.width / 2, frame.rect.height / 2),
    );
  }
  final runs = g.capsules.isNotEmpty
      ? g.capsules
      : (g.dots.isEmpty && line.length >= 2
            ? [line]
            : const <List<ui.Offset>>[]);
  return (
    pieces: [for (final run in runs) ..._roundOutline(run, g.width)],
    heads: [for (final h in g.heads) _oriented(h)],
    dots: g.dots,
    dotRadius: g.width / 2,
  );
}

const _roundOutlineSpec = OutlineSpec(
  method: InkRenderMethod.filledOutline,
  cap: InkCap.round,
  constantRadius: true,
);

/// (T42) Shape outlines split the centerline at every corner sharper than 10° (O3 with
/// cos 10° instead of the stroke threshold): each run gets its own round caps, so the
/// inner side of a corner keeps the full half width and the caps meet as the round join
/// the screen strokes (the stroke threshold keeps 90° corners in one run, whose inner side
/// points sit r·cos 45° from the edges — 15 % thinner rectangle sides in the PDF).
const _shapeOutlineOptions = OutlineOptions(sharpCornerCos: 0.9848);

/// The round-1 fill outline (O1–O8) of [pts] with the constant radius [width] / 2,
/// split at every corner sharper than 10° ([_shapeOutlineOptions]).
List<Float32List> _roundOutline(List<ui.Offset> pts, double width) {
  final raw = Float32List(pts.length * InkPoints.stride);
  for (var i = 0; i < pts.length; i++) {
    raw[i * InkPoints.stride] = pts[i].dx;
    raw[i * InkPoints.stride + 1] = pts[i].dy;
  }
  final outline = OutlineGenerator.outlineFor(
    InkPoints.fromRaw(raw),
    width: width,
    spec: _roundOutlineSpec,
    options: _shapeOutlineOptions,
  );
  final dot = outline.dotCenter;
  if (dot != null) return [_circlePolygon(dot, outline.dotRadius)];
  return outline.polygons;
}

/// A regular polygon inscribed in the circle (inside the disk — K-6), positive orientation.
Float32List _circlePolygon(ui.Offset c, double r) {
  final n = (math.pi * r / InkTuning.capChordPt).ceil().clamp(8, 64);
  return _oriented([
    for (var k = 0; k < n; k++)
      ui.Offset(
        c.dx + r * math.cos(2 * math.pi * k / n),
        c.dy + r * math.sin(2 * math.pi * k / n),
      ),
  ]);
}

/// Shoelace area of x,y pairs (implicitly closed); positive = the 6.8 O7 orientation.
double shoelaceArea(Float32List poly) {
  var area = 0.0;
  final m = poly.length ~/ 2;
  for (var i = 0; i < m; i++) {
    final j = i + 1 == m ? 0 : i + 1;
    area += poly[2 * i] * poly[2 * j + 1] - poly[2 * j] * poly[2 * i + 1];
  }
  return area / 2;
}

/// [pts] as x,y pairs with a positive shoelace area (y down — 6.8 O7).
Float32List _oriented(List<ui.Offset> pts) {
  final out = Float32List(pts.length * 2);
  for (var i = 0; i < pts.length; i++) {
    out[2 * i] = pts[i].dx;
    out[2 * i + 1] = pts[i].dy;
  }
  if (shoelaceArea(out) < 0) {
    final m = pts.length;
    for (var i = 0; i < m ~/ 2; i++) {
      final j = m - 1 - i;
      final x = out[2 * i], y = out[2 * i + 1];
      out[2 * i] = out[2 * j];
      out[2 * i + 1] = out[2 * j + 1];
      out[2 * j] = x;
      out[2 * j + 1] = y;
    }
  }
  return out;
}
