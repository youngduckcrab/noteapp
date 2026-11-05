// lib/src/geometry/vector_path.dart — public (PDF uses it, contract 7.2.16, 03-ink 4.5).
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

enum InkPathVerb { moveTo, lineTo, cubicTo, close }

/// Renderer-neutral path for PDF export. Coordinates in page pt, y down.
final class InkVectorPath {
  InkVectorPath(this.verbs, this.coords);

  /// InkPathVerb.index per verb
  final Uint8List verbs;

  /// moveTo/lineTo: 2 values, cubicTo: 6, close: 0
  final Float32List coords;

  /// Bounds of every coordinate (control points included); Rect.zero when empty.
  ui.Rect get bounds {
    if (coords.length < 2) return ui.Rect.zero;
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (var i = 0; i + 1 < coords.length; i += 2) {
      minX = math.min(minX, coords[i]);
      maxX = math.max(maxX, coords[i]);
      minY = math.min(minY, coords[i + 1]);
      maxY = math.max(maxY, coords[i + 1]);
    }
    return ui.Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// The path with PathFillType.nonZero (the fill rule of every ink outline).
  ui.Path toUiPath() {
    final path = ui.Path()..fillType = ui.PathFillType.nonZero;
    var c = 0;
    for (final v in verbs) {
      switch (InkPathVerb.values[v]) {
        case InkPathVerb.moveTo:
          path.moveTo(coords[c], coords[c + 1]);
          c += 2;
        case InkPathVerb.lineTo:
          path.lineTo(coords[c], coords[c + 1]);
          c += 2;
        case InkPathVerb.cubicTo:
          path.cubicTo(
            coords[c],
            coords[c + 1],
            coords[c + 2],
            coords[c + 3],
            coords[c + 4],
            coords[c + 5],
          );
          c += 6;
        case InkPathVerb.close:
          path.close();
      }
    }
    return path;
  }
}
