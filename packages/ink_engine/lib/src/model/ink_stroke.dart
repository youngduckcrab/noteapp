// lib/src/model/ink_stroke.dart — 03-ink 4.1.
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

import '../interop/core_interop.dart' as interop;
import '../pen/pen_profile.dart';
import '../pen/style_ink.dart';
import '../tuning.dart';
import 'ink_layer.dart';
import 'ink_points.dart';

final Expando<InkStroke> _cache = Expando<InkStroke>('InkStroke');

/// Render-side view of ONE committed or pending core.Stroke. Created only through
/// InkStroke.of, which caches per core.Stroke instance (Expando): the same instance
/// always gives the same InkStroke (diff by identity, K-4). Equality = identical(source).
@immutable
final class InkStroke {
  InkStroke._(this.source);

  factory InkStroke.of(core.Stroke stroke) =>
      _cache[stroke] ??= InkStroke._(stroke);

  final core.Stroke source;

  /// source.id
  String get id => source.id;

  /// source.style (normalized by CORE)
  core.StrokeStyle get style => source.style;

  /// style.profile — P1 tools → ballpoint profile
  PenProfile get profile => source.style.profile;

  /// InkPoints.of(source.points), no copy
  InkPoints get points => _points;
  late final InkPoints _points = InkPoints.of(source.points);

  /// source.bounds as a Rect — the CORE value (7.2.3). INK never recomputes it;
  /// every rendered pixel lies inside (K-1, 6.7).
  Rect get bounds => _bounds;
  late final Rect _bounds = interop.rectOf(source.bounds);

  /// profile.layer
  InkLayer get layer => profile.layer;

  /// One point or zero-length centerline.
  bool get isDot => _isDot;
  late final bool _isDot = _computeIsDot();

  bool _computeIsDot() {
    final p = source.points;
    if (p.length <= 1) return true;
    final x0 = p.x(0), y0 = p.y(0);
    for (var i = 1; i < p.length; i++) {
      if (p.x(i) != x0 || p.y(i) != y0) return false;
    }
    return true;
  }

  /// max(InkTuning.minRadiusPt, 2 * style.width * points.widthQ(i));
  /// highlighter: style.width / 2 (widthQ ignored, square caps).
  double radiusAt(int i) {
    if (profile.layer == InkLayer.highlighter) return style.width / 2;
    return math.max(
      InkTuning.minRadiusPt,
      2 * style.width * source.points.widthQ(i),
    );
  }

  double get maxRadius {
    if (profile.layer == InkLayer.highlighter) return style.width / 2;
    return math.max(
      InkTuning.minRadiusPt,
      2 * style.width * source.points.maxWidthQ,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is InkStroke && identical(other.source, source);

  @override
  int get hashCode => identityHashCode(source);

  @override
  String toString() => 'InkStroke(${source.id})';
}
