// lib/src/shapes/shape_fit_tuning.dart — contract m5-7/00-overview 7.2.11
// (m5-7/05-library 4.4.5, 6.17). Final since the 2차 foundation step R2-B6.
//
// Every threshold of GeometricShapeFitter in one place (03-recognition R4).
// Re-tuning with real-device samples (U18) changes only these defaults — the
// commit that does it also runs unit/synthetic_shapes_test.dart
// (LIBRARY-F2).
import 'package:meta/meta.dart';

/// every threshold in one place (03-recognition R4)
@immutable
final class ShapeFitTuning {
  const ShapeFitTuning({
    this.resampleCount = 64,
    this.smoothRadius = 2,
    this.minDiagonalLogicalPx = 24,
    this.lineMinStraightness = 0.85,
    this.lineMaxDeviation = 0.065,
    this.closedMaxGap = 0.2,
    this.minTurnDeg = 270,
    this.maxTurnDeg = 540,
    this.ellipseMaxError = 0.075,
    this.circleMinAxisRatio = 0.86,
    this.rdpEpsilon = 0.055,
    this.cornerMinTurnDeg = 28,
    this.minEdgeFraction = 0.08,
    this.rightAngleToleranceDeg = 16,
    this.polygonMaxError = 0.03,
    this.ellipseOverPolygonFactor = 0.8,
    this.weakCornerTriangleDeg = 55,
    this.weakCornerQuadDeg = 45,
    this.weakCornerErrorFactor = 1.6,
    this.axisSnapDeg = 8,
    this.minScore = 0.0,
    this.holdTailLogicalPx = 6,
    this.holdTailMaxFraction = 0.1,
    this.maxAbsTurnDeg = 660,
    this.roundedCornerMaxEdge = 0.15,
  });

  final int resampleCount, smoothRadius;

  /// diag(pt) × viewScale below this → null (dots, ticks)
  final double minDiagonalLogicalPx;
  final double lineMinStraightness,
      lineMaxDeviation,
      closedMaxGap,
      minTurnDeg,
      maxTurnDeg,
      ellipseMaxError,
      circleMinAxisRatio,
      rdpEpsilon,
      cornerMinTurnDeg,
      minEdgeFraction,
      rightAngleToleranceDeg,
      polygonMaxError,
      ellipseOverPolygonFactor,
      weakCornerTriangleDeg,
      weakCornerQuadDeg,
      weakCornerErrorFactor,
      axisSnapDeg,
      minScore;

  /// (6.17.5) the hold tail: trailing samples within this many logical px
  /// (÷ viewScale → pt) of where the pen rests are cut (at most
  /// holdTailMaxFraction × the bounds diagonal)
  final double holdTailLogicalPx, holdTailMaxFraction;

  /// (6.17.5) the closed loop's Σ|turn| above this → no shape (a scribble
  /// that happens to wind once)
  final double maxAbsTurnDeg;

  /// (6.17.5) a 4-corner outline whose edge is at most this share of the
  /// perimeter may be a triangle with that corner rounded
  final double roundedCornerMaxEdge;

  ShapeFitTuning copyWith({
    int? resampleCount,
    int? smoothRadius,
    double? minDiagonalLogicalPx,
    double? lineMinStraightness,
    double? lineMaxDeviation,
    double? closedMaxGap,
    double? minTurnDeg,
    double? maxTurnDeg,
    double? ellipseMaxError,
    double? circleMinAxisRatio,
    double? rdpEpsilon,
    double? cornerMinTurnDeg,
    double? minEdgeFraction,
    double? rightAngleToleranceDeg,
    double? polygonMaxError,
    double? ellipseOverPolygonFactor,
    double? weakCornerTriangleDeg,
    double? weakCornerQuadDeg,
    double? weakCornerErrorFactor,
    double? axisSnapDeg,
    double? minScore,
    double? holdTailLogicalPx,
    double? holdTailMaxFraction,
    double? maxAbsTurnDeg,
    double? roundedCornerMaxEdge,
  }) => ShapeFitTuning(
    resampleCount: resampleCount ?? this.resampleCount,
    smoothRadius: smoothRadius ?? this.smoothRadius,
    minDiagonalLogicalPx: minDiagonalLogicalPx ?? this.minDiagonalLogicalPx,
    lineMinStraightness: lineMinStraightness ?? this.lineMinStraightness,
    lineMaxDeviation: lineMaxDeviation ?? this.lineMaxDeviation,
    closedMaxGap: closedMaxGap ?? this.closedMaxGap,
    minTurnDeg: minTurnDeg ?? this.minTurnDeg,
    maxTurnDeg: maxTurnDeg ?? this.maxTurnDeg,
    ellipseMaxError: ellipseMaxError ?? this.ellipseMaxError,
    circleMinAxisRatio: circleMinAxisRatio ?? this.circleMinAxisRatio,
    rdpEpsilon: rdpEpsilon ?? this.rdpEpsilon,
    cornerMinTurnDeg: cornerMinTurnDeg ?? this.cornerMinTurnDeg,
    minEdgeFraction: minEdgeFraction ?? this.minEdgeFraction,
    rightAngleToleranceDeg:
        rightAngleToleranceDeg ?? this.rightAngleToleranceDeg,
    polygonMaxError: polygonMaxError ?? this.polygonMaxError,
    ellipseOverPolygonFactor:
        ellipseOverPolygonFactor ?? this.ellipseOverPolygonFactor,
    weakCornerTriangleDeg: weakCornerTriangleDeg ?? this.weakCornerTriangleDeg,
    weakCornerQuadDeg: weakCornerQuadDeg ?? this.weakCornerQuadDeg,
    weakCornerErrorFactor: weakCornerErrorFactor ?? this.weakCornerErrorFactor,
    axisSnapDeg: axisSnapDeg ?? this.axisSnapDeg,
    minScore: minScore ?? this.minScore,
    holdTailLogicalPx: holdTailLogicalPx ?? this.holdTailLogicalPx,
    holdTailMaxFraction: holdTailMaxFraction ?? this.holdTailMaxFraction,
    maxAbsTurnDeg: maxAbsTurnDeg ?? this.maxAbsTurnDeg,
    roundedCornerMaxEdge: roundedCornerMaxEdge ?? this.roundedCornerMaxEdge,
  );

  List<Object> get _fields => [
    resampleCount,
    smoothRadius,
    minDiagonalLogicalPx,
    lineMinStraightness,
    lineMaxDeviation,
    closedMaxGap,
    minTurnDeg,
    maxTurnDeg,
    ellipseMaxError,
    circleMinAxisRatio,
    rdpEpsilon,
    cornerMinTurnDeg,
    minEdgeFraction,
    rightAngleToleranceDeg,
    polygonMaxError,
    ellipseOverPolygonFactor,
    weakCornerTriangleDeg,
    weakCornerQuadDeg,
    weakCornerErrorFactor,
    axisSnapDeg,
    minScore,
    holdTailLogicalPx,
    holdTailMaxFraction,
    maxAbsTurnDeg,
    roundedCornerMaxEdge,
  ];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ShapeFitTuning) return false;
    final a = _fields, b = other._fields;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_fields);

  @override
  String toString() => 'ShapeFitTuning(${_fields.join(', ')})';
}
