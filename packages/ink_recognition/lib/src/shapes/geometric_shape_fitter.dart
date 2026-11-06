// lib/src/shapes/geometric_shape_fitter.dart — contract m5-7/00-overview
// 7.2.11 (m5-7/05-library 4.2, 6.17).
//
// 2차 foundation step R2-B6: the contract surface only — fit() always
// returns null (every stroke stays a stroke), and recognitionOverrides()
// does not install it yet (contract 7.6.2 R2-B6: the shape fitter override is
// INK's NoShapeFitter). LIBRARY L2-06 (P-B) puts the 6.17 classifier and the
// CORE-geometry beautifier behind it.
import 'dart:ui' show Offset;

import 'package:ink_engine/ink_engine.dart' as ink;

import 'shape_fit_tuning.dart';

/// Geometric fitter (03-recognition 4.3 prototype) — implements INK's port.
final class GeometricShapeFitter implements ink.InkShapeFitter {
  const GeometricShapeFitter({this.tuning = const ShapeFitTuning()});

  final ShapeFitTuning tuning;

  /// R2-B6: never fits (L2-06 adds the classifier).
  @override
  ink.InkShapeFit? fit(List<Offset> points, {required double viewScale}) =>
      null;
}
