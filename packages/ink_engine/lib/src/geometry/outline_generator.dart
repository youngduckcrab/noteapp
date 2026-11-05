// lib/src/geometry/outline_generator.dart — INTERNAL (03-ink 4.5).
//
// Foundation step B3: simple offset outline (see stroke_outline.dart). The
// perfect-freehand style generator of 6.8 replaces it in INK T07.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:meta/meta.dart';

import '../model/ink_layer.dart';
import '../model/ink_points.dart';
import '../model/ink_stroke.dart';
import '../pen/pen_profile.dart';
import '../tuning.dart';
import 'stroke_outline.dart';

@immutable
final class OutlineOptions {
  const OutlineOptions({
    this.sharpCornerCos = InkTuning.sharpCornerCos,
    this.capChordPt = InkTuning.capChordPt,
    this.maxCapSegments = InkTuning.maxCapSegments,
    this.simplifyTolerance = InkTuning.outlineSimplifyPt,
  });
  final double sharpCornerCos, capChordPt, simplifyTolerance;
  final int maxCapSegments;

  @override
  bool operator ==(Object other) =>
      other is OutlineOptions &&
      other.sharpCornerCos == sharpCornerCos &&
      other.capChordPt == capChordPt &&
      other.simplifyTolerance == simplifyTolerance &&
      other.maxCapSegments == maxCapSegments;

  @override
  int get hashCode => Object.hash(
    sharpCornerCos,
    capChordPt,
    simplifyTolerance,
    maxCapSegments,
  );
}

abstract final class OutlineGenerator {
  static StrokeOutline outline(
    InkStroke stroke, {
    OutlineOptions options = const OutlineOptions(),
  }) => outlineOf(
    stroke.points,
    width: stroke.style.width,
    profile: stroke.profile,
    options: options,
  );

  /// Same from raw parts (live builder, previews of transformed copies).
  static StrokeOutline outlineOf(
    InkPoints points, {
    required double width,
    required PenProfile profile,
    OutlineOptions options = const OutlineOptions(),
  }) {
    final n = points.length;
    double radius(int i) => profile.layer == InkLayer.highlighter
        ? width / 2
        : math.max(InkTuning.minRadiusPt, 2 * width * points.widthQ(i));

    var isDot = true;
    for (var i = 1; i < n; i++) {
      if (points.x(i) != points.x(0) || points.y(i) != points.y(0)) {
        isDot = false;
        break;
      }
    }
    if (isDot) {
      var r = 0.0;
      for (var i = 0; i < n; i++) {
        r = math.max(r, radius(i));
      }
      final c = points.offsetAt(0);
      return StrokeOutline(
        polygons: const [],
        bounds: ui.Rect.fromCircle(center: c, radius: r),
        dotCenter: c,
        dotRadius: r,
      );
    }

    final left = <double>[];
    final right = <double>[];
    var nx = 0.0, ny = -1.0;
    for (var i = 0; i < n; i++) {
      final a = i == 0 ? 0 : i - 1;
      final b = i == n - 1 ? n - 1 : i + 1;
      final dx = points.x(b) - points.x(a);
      final dy = points.y(b) - points.y(a);
      final len = math.sqrt(dx * dx + dy * dy);
      if (len > 1e-9) {
        nx = -dy / len;
        ny = dx / len;
      }
      final r = radius(i);
      left.addAll([points.x(i) + nx * r, points.y(i) + ny * r]);
      right.addAll([points.x(i) - nx * r, points.y(i) - ny * r]);
    }
    final poly = Float32List(left.length + right.length);
    poly.setRange(0, left.length, left);
    for (var i = 0; i < right.length; i += 2) {
      final src = right.length - 2 - i;
      poly[left.length + i] = right[src];
      poly[left.length + i + 1] = right[src + 1];
    }
    _orientPositive(poly);
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (var i = 0; i + 1 < poly.length; i += 2) {
      minX = math.min(minX, poly[i]);
      maxX = math.max(maxX, poly[i]);
      minY = math.min(minY, poly[i + 1]);
      maxY = math.max(maxY, poly[i + 1]);
    }
    return StrokeOutline(
      polygons: [poly],
      bounds: ui.Rect.fromLTRB(minX, minY, maxX, maxY),
    );
  }

  /// Centerline x,y pairs for strokedPolyline pens (highlighter).
  static Float32List polyline(InkPoints points) {
    final out = Float32List(points.length * 2);
    for (var i = 0; i < points.length; i++) {
      out[2 * i] = points.x(i);
      out[2 * i + 1] = points.y(i);
    }
    return out;
  }

  static void _orientPositive(Float32List poly) {
    var area = 0.0;
    final m = poly.length ~/ 2;
    for (var i = 0; i < m; i++) {
      final j = (i + 1) % m;
      area += poly[2 * i] * poly[2 * j + 1] - poly[2 * j] * poly[2 * i + 1];
    }
    if (area >= 0) return;
    for (var i = 0, j = m - 1; i < j; i++, j--) {
      final x = poly[2 * i], y = poly[2 * i + 1];
      poly[2 * i] = poly[2 * j];
      poly[2 * i + 1] = poly[2 * j + 1];
      poly[2 * j] = x;
      poly[2 * j + 1] = y;
    }
  }
}
