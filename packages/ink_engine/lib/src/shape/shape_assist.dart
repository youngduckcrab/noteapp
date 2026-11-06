// lib/src/shape/shape_assist.dart — contract 7.2.9 (m5-7/03-ink 4.4, 4.5). Final (T24).
//
// The port of automatic shape correction: INK detects the hold (m5-7 T39 —
// shape/hold_detector.dart, render/sessions.dart; 6.18), the fitter decides.
import 'dart:ui' show Offset;

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

enum ShapeAssist { off, holdToSnap }

/// (v2.0) Shape recognition port. INK detects the hold; the fitter decides.
abstract interface class InkShapeFitter {
  /// Centerline points of the stroke so far (page pt). null = not a shape (keep the stroke).
  InkShapeFit? fit(List<Offset> points, {required double viewScale});
}

@immutable
final class InkShapeFit {
  const InkShapeFit({
    required this.kind,
    required this.geometry,
    required this.score,
  });
  final core.ShapeKind kind;
  final core.ShapeGeometry geometry;

  /// [0, 1]
  final double score;

  @override
  bool operator ==(Object other) =>
      other is InkShapeFit &&
      other.kind == kind &&
      other.geometry == geometry &&
      other.score == score;

  @override
  int get hashCode => Object.hash(kind, geometry, score);

  @override
  String toString() => 'InkShapeFit(${kind.name}, score $score)';
}

/// Never fits: every stroke stays a stroke.
final class NoShapeFitter implements InkShapeFitter {
  const NoShapeFitter();

  @override
  InkShapeFit? fit(List<Offset> points, {required double viewScale}) => null;
}
