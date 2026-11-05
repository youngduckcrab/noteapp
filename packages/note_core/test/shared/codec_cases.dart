// Shared body of the stroke point codec tests (CORE 6.2.4), run on the VM
// (test/model/stroke_points_codec_test.dart) and in Chrome
// (test/web/codec_browser_test.dart).
import 'dart:convert';
import 'dart:typed_data';

import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

Uint8List _hex(String s) =>
    Uint8List.fromList([for (final b in s.split(' ')) int.parse(b, radix: 16)]);

String _toHex(Uint8List b) =>
    b.map((v) => v.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

void defineCodecTests() {
  final g1 = StrokePoints.fromList(const [
    StrokePoint(10, 20, widthQ: 0.25, t: 0),
    StrokePoint(10.5, 20.25, widthQ: 0.275, t: 4.2),
    StrokePoint(11.25, 20.25, widthQ: 0.3, t: 8.3),
  ]);
  const g1Hex = '01 01 03 D0 0F 64 96 01 A0 1F 32 00 F4 03 32 32 00 54 52';

  test('G1 bytes and base64', () {
    expect(_toHex(StrokePointsCodec.encode(g1)), g1Hex);
    expect(StrokePointsCodec.encodeBase64(g1), 'AQED0A9klgGgHzIA9AMyMgBUUg==');
    expect(
      StrokePointsCodec.decodeBase64('AQED0A9klgGgHzIA9AMyMgBUUg==')
          .contentEquals(g1),
      isTrue,
    );
  });

  test('G2: flags 0 (no widthQ) decodes to 0.25 and re-encodes with bit0', () {
    final p = StrokePointsCodec.decode(
      _hex('01 00 02 C7 01 03 02 01 00 CE 02'),
    );
    expect(p.length, 2);
    expect(p.widthQ(0), 0.25);
    expect(p.widthQ(1), 0.25);
    expect(p.x(1), closeTo(-1.02, 1e-6));
    expect(p.t(1), closeTo(16.7, 1e-5));
    expect(
      _toHex(StrokePointsCodec.encode(p)),
      '01 01 02 C7 01 03 02 01 F4 03 00 00 CE 02',
    );
  });

  test('G3: tilt and azimuth channels', () {
    final p = StrokePoints.fromList(
      const [
        StrokePoint(0, 0, widthQ: 0.25, tilt: 0.5, azimuth: -1, t: 0),
        StrokePoint(1, -1, widthQ: 0.262, tilt: 0.52, azimuth: -0.99, t: 8.3),
      ],
      hasTilt: true,
      hasAzimuth: true,
    );
    expect(
      _toHex(StrokePointsCodec.encode(p)),
      '01 07 02 00 C8 01 00 C7 01 F4 03 18 E8 07 28 CF 0F 14 00 A6 01',
    );
  });

  test('round trip and re-encode are identical', () {
    final ids = SequentialIdGenerator();
    for (var seed = 0; seed < 20; seed++) {
      final s = StrokeFixtures.synthetic(
        pageId: 'p',
        ids: ids,
        seed: seed,
        hasTilt: seed.isEven,
      );
      final bytes = StrokePointsCodec.encode(s.points);
      final back = StrokePointsCodec.decode(bytes);
      expect(back.contentEquals(s.points), isTrue);
      expect(StrokePointsCodec.encode(back), bytes);
    }
  });

  test('decode errors', () {
    final good = StrokePointsCodec.encode(g1);
    Uint8List edit(void Function(List<int> b) f) {
      final b = good.toList();
      f(b);
      return Uint8List.fromList(b);
    }

    final cases = <String, Uint8List>{
      'unknown version': edit((b) => b[0] = 2),
      'reserved flag bit': edit((b) => b[1] = 0x09),
      'zero points': _hex('01 01 00'),
      'too many points': Uint8List.fromList([
        1,
        1,
        ...[0xA1, 0x8D, 0x06],
      ]), // 100001
      'truncated': Uint8List.sublistView(good, 0, good.length - 1),
      'trailing bytes': Uint8List.fromList([...good, 0]),
      'varuint longer than 5 bytes': _hex('01 01 01 80 80 80 80 80 01'),
      'channel out of range': _hex('01 01 01 00 00 E2 0F 00'), // widthQ 1009
    };
    for (final e in cases.entries) {
      expect(
        () => StrokePointsCodec.decode(e.value),
        throwsFormatException,
        reason: e.key,
      );
    }
    expect(() => StrokePointsCodec.decodeBase64('***'), throwsFormatException);
  });

  test('size budget (120 Hz synthetic handwriting)', () {
    final ids = SequentialIdGenerator();
    var all = 0;
    var basic = 0;
    var points = 0;
    for (var seed = 0; seed < 200; seed++) {
      final withTilt = StrokeFixtures.synthetic(
        pageId: 'p',
        ids: ids,
        seed: seed,
      );
      final plain = StrokeFixtures.synthetic(
        pageId: 'p',
        ids: ids,
        seed: seed,
        hasTilt: false,
      );
      all += StrokePointsCodec.encode(withTilt.points).length;
      basic += StrokePointsCodec.encode(plain.points).length;
      points += withTilt.points.length;
    }
    expect(all / points, lessThanOrEqualTo(9.0));
    expect(basic / points, lessThanOrEqualTo(7.0));
    expect(base64.encode([1]), isNotEmpty);
  });
}
