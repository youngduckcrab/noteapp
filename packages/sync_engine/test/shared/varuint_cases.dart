// varuint cases shared by the VM test (common/varuint_test.dart) and Chrome
// (web/pure_logic_browser_test.dart, T3): arithmetic LEB128 must give the same
// bytes on both platforms (CORE 6.2.4).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/src/common/varuint.dart';

/// CORE 6.2.4 golden G1 (19 bytes): version, flags, then 13 varuints.
final Uint8List kCoreG1 = Uint8List.fromList([
  0x01, 0x01, 0x03, 0xD0, 0x0F, 0x64, 0x96, 0x01, 0xA0, 0x1F, 0x32, 0x00, //
  0xF4, 0x03, 0x32, 0x32, 0x00, 0x54, 0x52,
]);

void varuintCases() {
  test('reads the varuints of CORE golden G1 byte for byte', () {
    final values = <int>[];
    var offset = 2;
    while (offset < kCoreG1.length) {
      final (value, next) = VarUint.read(kCoreG1, offset);
      values.add(value);
      offset = next;
    }
    expect(offset, kCoreG1.length);
    expect(values, [3, 2000, 100, 150, 4000, 50, 0, 500, 50, 50, 0, 84, 82]);
    final out = BytesBuilder();
    out.add(kCoreG1.sublist(0, 2));
    for (final v in values) {
      VarUint.write(out, v);
    }
    expect(out.takeBytes(), kCoreG1);
  });

  test('encodes like CORE: low group first, MSB = continuation', () {
    expect(VarUint.encode(0), [0x00]);
    expect(VarUint.encode(127), [0x7F]);
    expect(VarUint.encode(128), [0x80, 0x01]);
    expect(VarUint.encode(229), [0xE5, 0x01]); // chunk golden header length
    expect(VarUint.encode(2000), [0xD0, 0x0F]);
    expect(VarUint.encode(16383), [0xFF, 0x7F]);
    expect(VarUint.encode(16384), [0x80, 0x80, 0x01]);
    expect(VarUint.encode(1000000), [0xC0, 0x84, 0x3D]);
    expect(VarUint.encode(VarUint.maxValue), [0xFF, 0xFF, 0xFF, 0xFF, 0x7F]);
  });

  test('lengthOf matches the encoded length', () {
    for (final v in [0, 1, 127, 128, 16383, 16384, 2097151, 2097152]) {
      expect(VarUint.lengthOf(v), VarUint.encode(v).length, reason: '$v');
    }
    expect(VarUint.lengthOf(VarUint.maxValue), 5);
  });

  test('round-trips values up to 5 bytes', () {
    for (final v in [0, 5, 300, 70000, 1048576, 268435455, VarUint.maxValue]) {
      final (value, next) = VarUint.read(VarUint.encode(v), 0);
      expect(value, v);
      expect(next, VarUint.lengthOf(v));
    }
  });

  test('rejects values out of range', () {
    expect(() => VarUint.encode(-1), throwsArgumentError);
    expect(() => VarUint.encode(VarUint.maxValue + 1), throwsArgumentError);
  });

  test('decode errors are FormatException', () {
    expect(
      () => VarUint.read(Uint8List.fromList([0x80]), 0),
      throwsFormatException,
    );
    expect(() => VarUint.read(Uint8List(0), 0), throwsFormatException);
    expect(
      () => VarUint.read(
        Uint8List.fromList([0x80, 0x80, 0x80, 0x80, 0x80, 0x01]),
        0,
      ),
      throwsFormatException,
    );
  });
}
