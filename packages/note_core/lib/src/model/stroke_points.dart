// lib/src/model/stroke_points.dart — contract 00-overview 7.2.3 / CORE 4.2.2, 6.2.4.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../common/geometry.dart';

part 'stroke_points_codec.dart';

const double kMaxWidthFactor = 4.0; // f in (0, 4]; widthQ = f / kMaxWidthFactor
const double kNominalWidthQ = 0.25; // f = 1.0 → rendered radius = width / 2

@immutable
final class StrokePoint {
  const StrokePoint(
    this.x,
    this.y, {
    this.widthQ = kNominalWidthQ,
    this.tilt = 0,
    this.azimuth = 0,
    this.t = 0,
  });

  final double x, y; // pt, page coordinates, clamped to [-32000, 32000]
  final double widthQ; // [0, 1], quantized 0.001
  final double tilt; // rad [0, pi/2], 0 = perpendicular (web: |signed tilt|)
  final double azimuth; // rad (-pi, pi], 0 when unknown (always 0 on web)
  // ms since Stroke.createdAt, [0, 500000]; fragments keep t (no rebase)
  final double t;

  @override
  bool operator ==(Object other) =>
      other is StrokePoint &&
      other.x == x &&
      other.y == y &&
      other.widthQ == widthQ &&
      other.tilt == tilt &&
      other.azimuth == azimuth &&
      other.t == t;

  @override
  int get hashCode => Object.hash(x, y, widthQ, tilt, azimuth, t);

  @override
  String toString() =>
      'StrokePoint($x, $y, widthQ: $widthQ, tilt: $tilt, azimuth: $azimuth, t: $t)';
}

/// Quantization of the point channels (CORE 6.2.4). Shared with the codec part.
abstract final class _Quant {
  static const double xyScale = 100; // 0.01 pt
  static const double widthQScale = 1000; // 0.001
  static const double angleScale = 1000; // 0.001 rad
  static const double tScale = 10; // 0.1 ms

  static const double maxXY = 32000;
  static const double maxT = 500000;
  static const double maxTilt = math.pi / 2;

  static const int maxXYq = 3200000;
  static const int maxWidthQq = 1000;
  static const int maxTiltq = 1571;
  static const int maxAzimuthq = 3142;
  static const int maxTq = 5000000;

  static double _finite(double v, double fallback) => v.isNaN ? fallback : v;

  static int xy(double v) =>
      (_finite(v, 0).clamp(-maxXY, maxXY) * xyScale).round();
  static int widthQ(double v) =>
      (_finite(v, kNominalWidthQ).clamp(0.0, 1.0) * widthQScale).round();
  static int tilt(double v) =>
      (_finite(v, 0).clamp(0.0, maxTilt) * angleScale).round();
  static int azimuth(double v) =>
      (normalizeAngle(_finite(v, 0)) * angleScale).round();
  static int t(double v) => (_finite(v, 0).clamp(0.0, maxT) * tScale).round();

  /// (-pi, pi]
  static double normalizeAngle(double a) {
    if (a.isInfinite) return 0;
    var r = a % (2 * math.pi); // [0, 2pi)
    if (r > math.pi) r -= 2 * math.pi;
    return r;
  }
}

@immutable
final class StrokePoints {
  StrokePoints._(this._data, this.hasTilt, this.hasAzimuth)
    : length = _data.length ~/ stride {
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    var maxQ = 0.0;
    for (var o = 0; o < _data.length; o += stride) {
      final x = _data[o], y = _data[o + 1], q = _data[o + 2];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      if (q > maxQ) maxQ = q;
    }
    pointBounds = PageRect(minX, minY, maxX, maxY);
    maxWidthQ = maxQ;
  }

  /// Values are quantized on build so in-memory values == decoded values (CORE 6.2.4).
  factory StrokePoints.fromList(
    List<StrokePoint> points, {
    bool hasTilt = false,
    bool hasAzimuth = false,
  }) {
    _checkLength(points.length);
    final b = StrokePointsBuilder(
      hasTilt: hasTilt,
      hasAzimuth: hasAzimuth,
      initialCapacity: points.length,
    );
    points.forEach(b.addPoint);
    return b.build();
  }

  /// Copies interleaved [data] (stride 6: x, y, widthQ, tilt, azimuth, t) and quantizes.
  /// INK hands finished strokes to CORE with this; INK then renders the quantized result.
  factory StrokePoints.fromInterleaved(
    Float32List data, {
    bool hasTilt = false,
    bool hasAzimuth = false,
  }) {
    if (data.length % stride != 0) {
      throw ArgumentError.value(
        data.length,
        'data.length',
        'must be a multiple of $stride',
      );
    }
    _checkLength(data.length ~/ stride);
    final b = StrokePointsBuilder(
      hasTilt: hasTilt,
      hasAzimuth: hasAzimuth,
      initialCapacity: data.length ~/ stride,
    );
    for (var o = 0; o < data.length; o += stride) {
      b.add(
        data[o],
        data[o + 1],
        widthQ: data[o + 2],
        tilt: data[o + 3],
        azimuth: data[o + 4],
        t: data[o + 5],
      );
    }
    return b.build();
  }

  static void _checkLength(int n) {
    if (n == 0) throw ArgumentError('A stroke needs at least one point');
    if (n > maxLength) {
      throw ArgumentError.value(n, 'length', 'exceeds $maxLength points');
    }
  }

  static const int stride = 6;
  static const int maxLength = 100000;

  final Float32List _data;
  final int length;
  bool get isEmpty => length == 0;
  final bool hasTilt;
  final bool hasAzimuth;

  double x(int i) => _data[i * stride];
  double y(int i) => _data[i * stride + 1];
  double widthQ(int i) => _data[i * stride + 2];
  double tilt(int i) => _data[i * stride + 3]; // 0 when !hasTilt
  double azimuth(int i) => _data[i * stride + 4]; // 0 when !hasAzimuth
  double t(int i) => _data[i * stride + 5];

  StrokePoint operator [](int i) {
    RangeError.checkValidIndex(i, this, 'index', length);
    final o = i * stride;
    return StrokePoint(
      _data[o],
      _data[o + 1],
      widthQ: _data[o + 2],
      tilt: _data[o + 3],
      azimuth: _data[o + 4],
      t: _data[o + 5],
    );
  }

  Iterable<StrokePoint> get points sync* {
    for (var i = 0; i < length; i++) {
      yield this[i];
    }
  }

  /// Centerline only, cached.
  late final PageRect pointBounds;

  /// Cached.
  late final double maxWidthQ;

  StrokePoints sublist(int start, [int? end]) {
    final e = RangeError.checkValidRange(start, end, length);
    _checkLength(e - start);
    return StrokePoints._(
      _data.sublist(start * stride, e * stride),
      hasTilt,
      hasAzimuth,
    );
  }

  /// azimuth += m.rotation, re-quantized
  StrokePoints transformed(Affine2 m) {
    final rotation = m.rotation;
    final out = Float32List(_data.length);
    for (var o = 0; o < _data.length; o += stride) {
      final (nx, ny) = m.apply(_data[o], _data[o + 1]);
      out[o] = _Quant.xy(nx) / _Quant.xyScale;
      out[o + 1] = _Quant.xy(ny) / _Quant.xyScale;
      out[o + 2] = _data[o + 2];
      out[o + 3] = _data[o + 3];
      out[o + 4] = hasAzimuth
          ? _Quant.azimuth(_data[o + 4] + rotation) / _Quant.angleScale
          : 0;
      out[o + 5] = _data[o + 5];
    }
    return StrokePoints._(out, hasTilt, hasAzimuth);
  }

  /// Read-only interleaved view, stride 6 [x, y, widthQ, tilt, azimuth, t]. Never mutate.
  /// INK wraps it without copying (InkPoints.fromRaw).
  Float32List get rawData {
    var view = _data;
    // Debug and test runs hand out an unmodifiable view so accidental writes
    // fail fast (CORE 6.2.4); release builds pay nothing.
    assert(() {
      view = _data.asUnmodifiableView();
      return true;
    }());
    return view;
  }

  bool contentEquals(StrokePoints other) {
    if (identical(this, other)) return true;
    if (other.length != length ||
        other.hasTilt != hasTilt ||
        other.hasAzimuth != hasAzimuth) {
      return false;
    }
    final a = _data, b = other._data;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is StrokePoints && contentEquals(other);

  @override
  int get hashCode {
    final last = (length - 1) * stride;
    return Object.hash(
      length,
      hasTilt,
      hasAzimuth,
      _data[0],
      _data[1],
      _data[5],
      _data[last],
      _data[last + 1],
      _data[last + 5],
    );
  }

  @override
  String toString() =>
      'StrokePoints($length points, tilt: $hasTilt, azimuth: $hasAzimuth)';
}

/// Mutable builder (INK may also build a Float32List itself and call fromInterleaved).
final class StrokePointsBuilder {
  StrokePointsBuilder({
    this.hasTilt = false,
    this.hasAzimuth = false,
    int initialCapacity = 256,
  }) : _data = Float32List(
         math.max(1, math.min(initialCapacity, StrokePoints.maxLength)) *
             StrokePoints.stride,
       );

  final bool hasTilt, hasAzimuth;
  Float32List _data;
  int _length = 0;
  bool _full = false;

  /// Values are clamped (x, y: ±32000, widthQ 0..1, tilt 0..pi/2, azimuth (-pi, pi], t 0..500000).
  /// Calls beyond StrokePoints.maxLength are ignored and [isFull] becomes true.
  void add(
    double x,
    double y, {
    double widthQ = kNominalWidthQ,
    double tilt = 0,
    double azimuth = 0,
    required double t,
  }) {
    if (_length >= StrokePoints.maxLength) {
      _full = true;
      return;
    }
    const s = StrokePoints.stride;
    if ((_length + 1) * s > _data.length) {
      final grown = Float32List(
        math.min(_data.length * 2, StrokePoints.maxLength * s),
      )..setRange(0, _length * s, _data);
      _data = grown;
    }
    final o = _length * s;
    _data[o] = _Quant.xy(x) / _Quant.xyScale;
    _data[o + 1] = _Quant.xy(y) / _Quant.xyScale;
    _data[o + 2] = _Quant.widthQ(widthQ) / _Quant.widthQScale;
    _data[o + 3] = hasTilt ? _Quant.tilt(tilt) / _Quant.angleScale : 0;
    _data[o + 4] = hasAzimuth ? _Quant.azimuth(azimuth) / _Quant.angleScale : 0;
    _data[o + 5] = _Quant.t(t) / _Quant.tScale;
    _length++;
    if (_length >= StrokePoints.maxLength) _full = true;
  }

  void addPoint(StrokePoint p) =>
      add(p.x, p.y, widthQ: p.widthQ, tilt: p.tilt, azimuth: p.azimuth, t: p.t);

  int get length => _length;
  bool get isFull => _full;

  void removeLast([int count = 1]) {
    if (count < 0 || count > _length) {
      throw RangeError.range(count, 0, _length, 'count');
    }
    _length -= count;
    if (count > 0) _full = false;
  }

  /// Throws StateError if empty.
  StrokePoints build() {
    if (_length == 0) throw StateError('StrokePointsBuilder is empty');
    return StrokePoints._(
      Float32List.fromList(
        Float32List.sublistView(_data, 0, _length * StrokePoints.stride),
      ),
      hasTilt,
      hasAzimuth,
    );
  }
}
