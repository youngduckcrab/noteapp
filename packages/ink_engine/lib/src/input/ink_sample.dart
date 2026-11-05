// lib/src/input/ink_sample.dart — 03-ink 4.3.
import 'dart:ui' show Offset;

import 'package:meta/meta.dart';

enum InkPointerKind { stylus, invertedStylus, touch, mouse, trackpad, unknown }

/// One normalized input sample in page coordinates.
@immutable
final class InkSample {
  const InkSample({
    required this.position,
    required this.timeUs,
    required this.kind,
    this.pressure,
    this.pressureMin = 0.0,
    this.pressureMax = 1.0,
    this.tilt = 0.0,
    this.orientation = 0.0,
  });

  /// page pt (EDITOR converts)
  final Offset position;

  /// PointerEvent.timeStamp.inMicroseconds
  final int timeUs;
  final InkPointerKind kind;

  /// raw; null = not reported (up / cancel / mouse)
  final double? pressure;
  final double pressureMin;
  final double pressureMax;

  /// normalized to [0, pi/2]
  final double tilt;

  /// (-pi, pi]; 0 when the platform does not report it (web)
  final double orientation;

  /// (pressure - min) / (max - min) clamped to [0, 1]; null if pressure == null or max - min < 1e-6.
  double? get normalizedPressure {
    final p = pressure;
    if (p == null || p.isNaN) return null;
    final range = pressureMax - pressureMin;
    if (!(range >= 1e-6)) return null;
    return ((p - pressureMin) / range).clamp(0.0, 1.0).toDouble();
  }

  InkSample copyWith({
    Offset? position,
    int? timeUs,
    InkPointerKind? kind,
    double? pressure,
    double? pressureMin,
    double? pressureMax,
    double? tilt,
    double? orientation,
  }) => InkSample(
    position: position ?? this.position,
    timeUs: timeUs ?? this.timeUs,
    kind: kind ?? this.kind,
    pressure: pressure ?? this.pressure,
    pressureMin: pressureMin ?? this.pressureMin,
    pressureMax: pressureMax ?? this.pressureMax,
    tilt: tilt ?? this.tilt,
    orientation: orientation ?? this.orientation,
  );

  @override
  bool operator ==(Object other) =>
      other is InkSample &&
      other.position == position &&
      other.timeUs == timeUs &&
      other.kind == kind &&
      other.pressure == pressure &&
      other.pressureMin == pressureMin &&
      other.pressureMax == pressureMax &&
      other.tilt == tilt &&
      other.orientation == orientation;

  @override
  int get hashCode => Object.hash(
    position,
    timeUs,
    kind,
    pressure,
    pressureMin,
    pressureMax,
    tilt,
    orientation,
  );

  @override
  String toString() =>
      'InkSample(${kind.name} $position @${timeUs}us p=$pressure)';
}
