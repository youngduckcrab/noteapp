// lib/src/geometry/stroke_outline.dart — INTERNAL (03-ink 4.5, 6.8 O7).
//
// The polygons come from OutlineGenerator (6.8). toPath / toVectorPath with
// smooth: true draw quadratic Béziers through the edge midpoints with the
// vertices as control points (O7): the curve stays inside the vertices'
// convex hull, so bounds (vertex bounds) still contain it (K-1).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'vector_path.dart';

/// Fill geometry of one stroke. All polygons share one orientation (positive shoelace area
/// in y-down coordinates) and must be filled together with PathFillType.nonZero.
final class StrokeOutline {
  StrokeOutline({
    required this.polygons,
    required this.bounds,
    this.dotCenter,
    this.dotRadius = 0,
  });

  /// each: x0,y0,x1,y1,... implicitly closed
  final List<Float32List> polygons;

  /// ⊆ InkStroke.bounds (K-1)
  final ui.Rect bounds;

  /// non-null → render as a circle
  final ui.Offset? dotCenter;
  final double dotRadius;

  bool get isDot => dotCenter != null;

  int get vertexCount {
    var n = isDot ? 1 : 0;
    for (final p in polygons) {
      n += p.length ~/ 2;
    }
    return n;
  }

  /// The polygons plus the smooth ui.Path [toPath] keeps (one quadratic =
  /// 2 points + 1 verb ≈ 17 bytes per vertex) — the L1 cache entry (6.13).
  int get approximateBytes {
    var n = 64 + _pathOverheadBytes + _pathBytesPerVertex * vertexCount;
    for (final p in polygons) {
      n += 32 + p.lengthInBytes;
    }
    return n;
  }

  static const int _pathOverheadBytes = 96;
  static const int _pathBytesPerVertex = 17;

  ui.Path? _smoothPath;
  ui.Path? _polygonPath;

  /// Fill path (PathFillType.nonZero). [smooth]: quadratic Béziers through
  /// the edge midpoints, `moveTo(mid(v_{m−1}, v_0))` then for every v_i
  /// `quadraticBezierTo(v_i, mid(v_i, v_{i+1}))` (6.8 O7); otherwise the
  /// polygon edges.
  ///
  /// Built once per outline and shared (a chunk re-record then only draws —
  /// building the path is most of the cost, T22 B8): never modify it.
  ui.Path toPath({bool smooth = true}) => smooth
      ? _smoothPath ??= _buildPath(smooth: true)
      : _polygonPath ??= _buildPath(smooth: false);

  ui.Path _buildPath({required bool smooth}) {
    final path = ui.Path()..fillType = ui.PathFillType.nonZero;
    final c = dotCenter;
    if (c != null) {
      path.addOval(ui.Rect.fromCircle(center: c, radius: dotRadius));
      return path;
    }
    for (final poly in polygons) {
      final m = poly.length ~/ 2;
      if (m < 3) continue;
      if (!smooth) {
        path.moveTo(poly[0], poly[1]);
        for (var i = 1; i < m; i++) {
          path.lineTo(poly[2 * i], poly[2 * i + 1]);
        }
        path.close();
        continue;
      }
      path.moveTo(
        (poly[2 * m - 2] + poly[0]) / 2,
        (poly[2 * m - 1] + poly[1]) / 2,
      );
      for (var i = 0; i < m; i++) {
        final j = i + 1 == m ? 0 : i + 1;
        path.quadraticBezierTo(
          poly[2 * i],
          poly[2 * i + 1],
          (poly[2 * i] + poly[2 * j]) / 2,
          (poly[2 * i + 1] + poly[2 * j + 1]) / 2,
        );
      }
      path.close();
    }
    return path;
  }

  /// The same geometry as [toPath] for PDF export (6.24): a quadratic
  /// (P0, C, P1) becomes the cubic (P0, P0 + ⅔(C − P0), P1 + ⅔(C − P1), P1);
  /// a dot is 4 cubics with k = 0.5523 · r.
  InkVectorPath toVectorPath({bool smooth = true}) {
    final c = dotCenter;
    if (c != null) {
      final r = dotRadius, k = 0.5523 * dotRadius;
      final x = c.dx, y = c.dy;
      return InkVectorPath(
        Uint8List.fromList([
          InkPathVerb.moveTo.index,
          InkPathVerb.cubicTo.index,
          InkPathVerb.cubicTo.index,
          InkPathVerb.cubicTo.index,
          InkPathVerb.cubicTo.index,
          InkPathVerb.close.index,
        ]),
        Float32List.fromList([
          x + r, y, //
          x + r, y + k, x + k, y + r, x, y + r,
          x - k, y + r, x - r, y + k, x - r, y,
          x - r, y - k, x - k, y - r, x, y - r,
          x + k, y - r, x + r, y - k, x + r, y,
        ]),
      );
    }
    // Sizes first: moveTo + (lineTo | cubicTo) per vertex + close.
    var verbCount = 0, coordCount = 0;
    for (final poly in polygons) {
      final m = poly.length ~/ 2;
      if (m < 3) continue;
      verbCount += m + 2 - (smooth ? 0 : 1);
      coordCount += smooth ? 2 + 6 * m : 2 * m;
    }
    final verbs = Uint8List(verbCount);
    final coords = Float32List(coordCount);
    var v = 0, o = 0;
    final lineTo = InkPathVerb.lineTo.index,
        cubicTo = InkPathVerb.cubicTo.index;
    for (final poly in polygons) {
      final m = poly.length ~/ 2;
      if (m < 3) continue;
      verbs[v++] = InkPathVerb.moveTo.index;
      if (!smooth) {
        coords.setRange(o, o + 2 * m, poly);
        o += 2 * m;
        verbs.fillRange(v, v + m - 1, lineTo);
        v += m - 1;
        verbs[v++] = InkPathVerb.close.index;
        continue;
      }
      var x0 = (poly[2 * m - 2] + poly[0]) / 2;
      var y0 = (poly[2 * m - 1] + poly[1]) / 2;
      coords[o++] = x0;
      coords[o++] = y0;
      for (var i = 0; i < m; i++) {
        final j = i + 1 == m ? 0 : i + 1;
        final cx = poly[2 * i], cy = poly[2 * i + 1];
        final x1 = (cx + poly[2 * j]) / 2, y1 = (cy + poly[2 * j + 1]) / 2;
        verbs[v++] = cubicTo;
        coords[o++] = x0 + 2 / 3 * (cx - x0);
        coords[o++] = y0 + 2 / 3 * (cy - y0);
        coords[o++] = x1 + 2 / 3 * (cx - x1);
        coords[o++] = y1 + 2 / 3 * (cy - y1);
        coords[o++] = x1;
        coords[o++] = y1;
        x0 = x1;
        y0 = y1;
      }
      verbs[v++] = InkPathVerb.close.index;
    }
    return InkVectorPath(verbs, coords);
  }
}
