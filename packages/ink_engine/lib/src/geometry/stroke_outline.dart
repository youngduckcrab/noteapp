// lib/src/geometry/stroke_outline.dart — INTERNAL (03-ink 4.5).
//
// Foundation step B3: a simple outline (both sides of the centerline offset
// by the point radius, no caps / joins). The outline of 6.8 replaces the
// generator in INK T07; this type keeps its members.
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

  /// B3: straight edges ([smooth] is accepted and ignored).
  ui.Path toPath({bool smooth = true}) {
    final path = ui.Path()..fillType = ui.PathFillType.nonZero;
    final c = dotCenter;
    if (c != null) {
      path.addOval(ui.Rect.fromCircle(center: c, radius: dotRadius));
      return path;
    }
    for (final poly in polygons) {
      if (poly.length < 6) continue;
      path.moveTo(poly[0], poly[1]);
      for (var i = 2; i + 1 < poly.length; i += 2) {
        path.lineTo(poly[i], poly[i + 1]);
      }
      path.close();
    }
    return path;
  }

  InkVectorPath toVectorPath({bool smooth = true}) {
    final verbs = <int>[];
    final coords = <double>[];
    final c = dotCenter;
    if (c != null) {
      // circle = 4 cubic Béziers, k = 0.5523 (6.24)
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
        if (poly.length < 6) continue;
        verbs.add(InkPathVerb.moveTo.index);
        coords.addAll([poly[0], poly[1]]);
        for (var i = 2; i + 1 < poly.length; i += 2) {
          verbs.add(InkPathVerb.lineTo.index);
          coords.addAll([poly[i], poly[i + 1]]);
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
