// lib/src/shapes/geometric_shape_fitter.dart — contract m5-7/00-overview
// 7.2.11 (m5-7/05-library 4.2, 6.17).
//
// INK calls fit(points, viewScale:) when the pen has held still for 500 ms;
// a non-null answer becomes the preview, and pen-up adds the shape
// (InkEdit addShape — 7.2.9). LIBRARY only judges: pure Dart on every
// platform (the web too).
//
// L2-06: the 6.17.1 classifier (shape_classifier.dart) and the 6.17.2
// beautifier (shape_beautify.dart). fit never throws: fewer than 4 points, a
// non-finite coordinate, a bounds diagonal × viewScale under
// minDiagonalLogicalPx (dots, ticks, small letters) or a score under
// minScore → null (the stroke stays ink).
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:ink_engine/ink_engine.dart' as ink;

import '../common/report_error.dart';
import 'shape_beautify.dart';
import 'shape_classifier.dart';
import 'shape_fit_tuning.dart';

/// Geometric fitter (03-recognition 4.3 prototype) — implements INK's port.
final class GeometricShapeFitter implements ink.InkShapeFitter {
  const GeometricShapeFitter({this.tuning = const ShapeFitTuning()});

  final ShapeFitTuning tuning;

  @override
  ink.InkShapeFit? fit(List<Offset> points, {required double viewScale}) {
    if (points.length < 4 || !viewScale.isFinite || !(viewScale > 0)) {
      return null;
    }
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in points) {
      if (!p.dx.isFinite || !p.dy.isFinite) return null;
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx);
      maxY = math.max(maxY, p.dy);
    }
    final diagonal = Offset(maxX - minX, maxY - minY).distance;
    if (diagonal * viewScale < tuning.minDiagonalLogicalPx) return null;
    try {
      // 6.17.5: the ~500 ms the pen rested before INK asked.
      final stroke = trimHoldTail(
        points,
        math.min(
          tuning.holdTailLogicalPx / viewScale,
          tuning.holdTailMaxFraction * diagonal,
        ),
      );
      final c = classifyShape(stroke, tuning: tuning);
      if (c == null) return null;
      final fit = beautifyShape(c, stroke, tuning);
      return fit.score < tuning.minScore ? null : fit;
    } catch (e, s) {
      // Not expected for finite input — the stroke stays ink (6.17.2: fit
      // never throws).
      reportRecognitionError(e, s, 'fitting a shape');
      return null;
    }
  }
}
