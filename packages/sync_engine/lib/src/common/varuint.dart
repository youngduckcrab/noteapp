// Internal (not exported). Unsigned LEB128 exactly as CORE 6.2.4: 7 bits per byte, low
// group first, MSB = continuation, at most 5 bytes. Arithmetic only (no bit operations —
// web safe, contract 7.4.3).
import 'dart:typed_data';

abstract final class VarUint {
  static const int maxBytes = 5;

  /// 128^5 - 1: the largest value that fits in [maxBytes].
  static const int maxValue = 34359738367;

  /// Bytes [write] uses for [value].
  static int lengthOf(int value) {
    _check(value);
    var n = 1;
    var u = value;
    while (u >= 128) {
      u ~/= 128;
      n++;
    }
    return n;
  }

  /// Appends [value] to [out]. ArgumentError when negative or > [maxValue].
  static void write(BytesBuilder out, int value) {
    _check(value);
    var u = value;
    while (u >= 128) {
      out.addByte(u % 128 + 128);
      u ~/= 128;
    }
    out.addByte(u);
  }

  static Uint8List encode(int value) {
    final out = BytesBuilder(copy: false);
    write(out, value);
    return out.takeBytes();
  }

  /// Reads one value at [offset]; returns it with the offset after it. FormatException when
  /// the bytes end early or the value takes more than [maxBytes].
  static (int value, int next) read(Uint8List bytes, int offset) {
    var value = 0;
    var scale = 1;
    var i = offset;
    for (var n = 0; n < maxBytes; n++) {
      if (i >= bytes.length) {
        throw FormatException('varuint: bytes end early', bytes, i);
      }
      final b = bytes[i++];
      if (b < 128) return (value + b * scale, i);
      value += (b - 128) * scale;
      scale *= 128;
    }
    throw FormatException('varuint: longer than $maxBytes bytes', bytes, i);
  }

  static void _check(int value) {
    if (value < 0 || value > maxValue) {
      throw ArgumentError.value(value, 'value', 'varuint out of range');
    }
  }
}
