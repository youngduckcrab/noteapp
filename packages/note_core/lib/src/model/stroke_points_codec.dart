// lib/src/model/stroke_points_codec.dart — contract 00-overview 7.2.3 / CORE 4.2.2, 6.2.4.
part of 'stroke_points.dart';

/// Binary format v1 = CORE 6.2.4 with ONE change: flags bit0 means "hasWidthQ" (was
/// hasPressure). Writers always set bit0. A reader seeing bit0 == 0 returns kNominalWidthQ.
abstract final class StrokePointsCodec {
  static Uint8List encode(StrokePoints points) {
    final n = points.length;
    final w = _ByteWriter();
    w.byte(1); // format version (kStrokePointsFormatVersion)
    w.byte(1 + (points.hasTilt ? 2 : 0) + (points.hasAzimuth ? 4 : 0));
    w.varuint(n);
    final data = points._data;
    void channel(int offset, int Function(double) quantize) {
      var prev = 0;
      for (var i = 0; i < n; i++) {
        final q = quantize(data[i * StrokePoints.stride + offset]);
        w.varuint(_zigzag(i == 0 ? q : q - prev));
        prev = q;
      }
    }

    channel(0, _Quant.xy);
    channel(1, _Quant.xy);
    channel(2, _Quant.widthQ);
    if (points.hasTilt) channel(3, _Quant.tilt);
    if (points.hasAzimuth) channel(4, _Quant.azimuth);
    channel(5, _Quant.t);
    return w.takeBytes();
  }

  /// Throws FormatException.
  static StrokePoints decode(Uint8List bytes) {
    final r = _ByteReader(bytes);
    final version = r.byte();
    if (version != 1) {
      throw FormatException('Unknown stroke points format version $version');
    }
    final flags = r.byte();
    if (flags >= 8) {
      throw FormatException('Reserved stroke points flag bits set: $flags');
    }
    final hasWidthQ = flags % 2 == 1;
    final hasTilt = (flags ~/ 2) % 2 == 1;
    final hasAzimuth = (flags ~/ 4) % 2 == 1;
    final n = r.varuint();
    if (n == 0 || n > StrokePoints.maxLength) {
      throw FormatException('Invalid stroke point count $n');
    }
    const s = StrokePoints.stride;
    final data = Float32List(n * s);
    void channel(int offset, int min, int max, double scale) {
      var v = 0;
      for (var i = 0; i < n; i++) {
        final d = _unzigzag(r.varuint());
        v = i == 0 ? d : v + d;
        if (v < min || v > max) {
          throw FormatException(
            'Stroke point channel $offset out of range: $v',
          );
        }
        data[i * s + offset] = v / scale;
      }
    }

    channel(0, -_Quant.maxXYq, _Quant.maxXYq, _Quant.xyScale);
    channel(1, -_Quant.maxXYq, _Quant.maxXYq, _Quant.xyScale);
    if (hasWidthQ) {
      channel(2, 0, _Quant.maxWidthQq, _Quant.widthQScale);
    } else {
      for (var i = 0; i < n; i++) {
        data[i * s + 2] = kNominalWidthQ;
      }
    }
    if (hasTilt) channel(3, 0, _Quant.maxTiltq, _Quant.angleScale);
    if (hasAzimuth) {
      channel(4, -_Quant.maxAzimuthq, _Quant.maxAzimuthq, _Quant.angleScale);
    }
    channel(5, 0, _Quant.maxTq, _Quant.tScale);
    if (!r.isAtEnd) {
      throw FormatException(
        '${r.remaining} trailing bytes after stroke points',
      );
    }
    return StrokePoints._(data, hasTilt, hasAzimuth);
  }

  static String encodeBase64(StrokePoints points) =>
      base64.encode(encode(points));

  static StrokePoints decodeBase64(String text) {
    final Uint8List bytes;
    try {
      bytes = base64.decode(text);
    } on FormatException catch (e) {
      throw FormatException('Invalid base64 stroke points: ${e.message}');
    }
    return decode(bytes);
  }

  // zigzag(n) : n >= 0 ? 2n : -2n - 1 (arithmetic, no bit ops — web safe)
  static int _zigzag(int v) => v >= 0 ? 2 * v : -2 * v - 1;
  // unzigzag(u) : u.isEven ? u ~/ 2 : -((u + 1) ~/ 2)
  static int _unzigzag(int u) => u.isEven ? u ~/ 2 : -((u + 1) ~/ 2);
}

final class _ByteWriter {
  final List<int> _buf = [];

  void byte(int v) => _buf.add(v);

  // LEB128, 7 bits per byte, low group first, MSB = continuation
  void varuint(int v) {
    var u = v;
    while (u >= 128) {
      _buf.add(u % 128 + 128);
      u ~/= 128;
    }
    _buf.add(u);
  }

  Uint8List takeBytes() => Uint8List.fromList(_buf);
}

final class _ByteReader {
  _ByteReader(this._bytes);
  final Uint8List _bytes;
  int _pos = 0;

  bool get isAtEnd => _pos == _bytes.length;
  int get remaining => _bytes.length - _pos;

  int byte() {
    if (_pos >= _bytes.length) {
      throw const FormatException('Stroke points data is truncated');
    }
    return _bytes[_pos++];
  }

  /// Max 5 bytes.
  int varuint() {
    var result = 0;
    var factor = 1;
    for (var i = 0; i < 5; i++) {
      final b = byte();
      if (b < 128) return result + b * factor;
      result += (b - 128) * factor;
      factor *= 128;
    }
    throw const FormatException('varuint longer than 5 bytes');
  }
}
