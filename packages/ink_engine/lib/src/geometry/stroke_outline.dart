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

  int get approximateBytes {
    var n = 64;
    for (final p in polygons) {
      n += 32 + p.lengthInBytes;
    }
    return n;
  }

  /// Fill path (PathFillType.nonZero). [smooth]: quadratic Béziers through
  /// the edge midpoints, `moveTo(mid(v_{m−1}, v_0))` then for every v_i
  /// `quadraticBezierTo(v_i, mid(v_i, v_{i+1}))` (6.8 O7); otherwise the
  /// polygon edges.
  ui.Path toPath({bool smooth = true}) {
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
    final verbs = <int>[];
    final coords = <double>[];
    final c = dotCenter;
    if (c != null) {
      final r = dotRadius, k = 0.5523 * dotRadius;
      final x = c.dx, y = c.dy;
      verbs.add(InkPathVerb.moveTo.index);
      coords.addAll([x + r, y]);
      void cubic(List<double> v) {
        verbs.add(InkPathVerb.cubicTo.index);
        coords.addAll(v);
      }

      cubic([x + r, y + k, x + k, y + r, x, y + r]);
      cubic([x - k, y + r, x - r, y + k, x - r, y]);
      cubic([x - r, y - k, x - k, y - r, x, y - r]);
      cubic([x + k, y - r, x + r, y - k, x + r, y]);
      verbs.add(InkPathVerb.close.index);
    } else {
      for (final poly in polygons) {
        final m = poly.length ~/ 2;
        if (m < 3) continue;
        verbs.add(InkPathVerb.moveTo.index);
        if (!smooth) {
          coords.addAll([poly[0], poly[1]]);
          for (var i = 1; i < m; i++) {
            verbs.add(InkPathVerb.lineTo.index);
            coords.addAll([poly[2 * i], poly[2 * i + 1]]);
          }
          verbs.add(InkPathVerb.close.index);
          continue;
        }
        var x0 = (poly[2 * m - 2] + poly[0]) / 2;
        var y0 = (poly[2 * m - 1] + poly[1]) / 2;
        coords.addAll([x0, y0]);
        for (var i = 0; i < m; i++) {
          final j = i + 1 == m ? 0 : i + 1;
          final cx = poly[2 * i], cy = poly[2 * i + 1];
          final x1 = (cx + poly[2 * j]) / 2, y1 = (cy + poly[2 * j + 1]) / 2;
          verbs.add(InkPathVerb.cubicTo.index);
          coords.addAll([
            x0 + 2 / 3 * (cx - x0),
            y0 + 2 / 3 * (cy - y0),
            x1 + 2 / 3 * (cx - x1),
            y1 + 2 / 3 * (cy - y1),
            x1,
            y1,
          ]);
          x0 = x1;
          y0 = y1;
        }
        verbs.add(InkPathVerb.close.index);
      }
    }
    return InkVectorPath(
      Uint8List.fromList(verbs),
      Float32List.fromList(coords),
    );
  }
}
