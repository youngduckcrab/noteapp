// lib/src/model/ink_points.dart — 03-ink 4.1.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:note_core/note_core.dart' as core;

/// Zero-copy, read-only view over core.StrokePoints.rawData
/// (stride 6: [x, y, widthQ, tilt, azimuth, t]). Never writes to the buffer (K-2).
/// Values are CORE's quantized values, so what INK renders == what is stored.
final class InkPoints {
  /// Wraps [raw] without copying. raw.length must be a positive multiple of [stride].
  InkPoints.fromRaw(this.raw) {
    if (raw.isEmpty || raw.length % stride != 0) {
      throw ArgumentError.value(
        raw.length,
        'raw.length',
        'must be a positive multiple of $stride',
      );
    }
  }

  /// Same as InkPoints.fromRaw(points.rawData).
  factory InkPoints.of(core.StrokePoints points) =>
      InkPoints.fromRaw(points.rawData);

  static const int stride = core.StrokePoints.stride; // 6

  /// The CORE buffer itself — read only.
  final Float32List raw;

  int get length => raw.length ~/ stride;
  bool get isEmpty => raw.isEmpty;

  double x(int i) => raw[i * stride];
  double y(int i) => raw[i * stride + 1];

  /// Channel [2].
  double widthQ(int i) => raw[i * stride + 2];
  double tilt(int i) => raw[i * stride + 3];
  double azimuth(int i) => raw[i * stride + 4];

  /// ms since Stroke.createdAt.
  double t(int i) => raw[i * stride + 5];

  Offset offsetAt(int i) => Offset(x(i), y(i));

  core.StrokePoint operator [](int i) => core.StrokePoint(
    x(i),
    y(i),
    widthQ: widthQ(i),
    tilt: tilt(i),
    azimuth: azimuth(i),
    t: t(i),
  );

  /// All channels linearly interpolated at fractional index s ∈ [0, length - 1]; azimuth
  /// along the shortest arc. Used for partial-eraser cut points (6.20 P5).
  core.StrokePoint lerpAt(double s) {
    final last = length - 1;
    final c = s.isNaN ? 0.0 : s.clamp(0.0, last.toDouble()).toDouble();
    final i = c.floor();
    if (i >= last) return this[last];
    final u = c - i;
    if (u == 0) return this[i];
    double lerp(int channel) {
      final a = raw[i * stride + channel];
      final b = raw[(i + 1) * stride + channel];
      return a + (b - a) * u;
    }

    final a0 = azimuth(i);
    var da = azimuth(i + 1) - a0;
    while (da > math.pi) {
      da -= 2 * math.pi;
    }
    while (da < -math.pi) {
      da += 2 * math.pi;
    }
    var az = a0 + da * u;
    if (az > math.pi) az -= 2 * math.pi;
    if (az <= -math.pi) az += 2 * math.pi;
    return core.StrokePoint(
      lerp(0),
      lerp(1),
      widthQ: lerp(2),
      tilt: lerp(3),
      azimuth: az,
      t: lerp(5),
    );
  }

  /// Centerline length (pt).
  double arcLength() {
    var sum = 0.0;
    for (var i = 1; i < length; i++) {
      sum += _segment(i);
    }
    return sum;
  }

  /// Cumulative centerline lengths (result[0] == 0).
  Float64List cumulativeLengths() {
    final out = Float64List(length);
    for (var i = 1; i < length; i++) {
      out[i] = out[i - 1] + _segment(i);
    }
    return out;
  }

  double _segment(int i) {
    final dx = x(i) - x(i - 1);
    final dy = y(i) - y(i - 1);
    return math.sqrt(dx * dx + dy * dy);
  }
}
