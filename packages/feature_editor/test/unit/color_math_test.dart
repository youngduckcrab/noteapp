// E-14: ColorMath (04-editor 6.9.5) — HEX parsing (9 valid forms, 6 kinds
// of error), HEX output, RGB channels, opaque, and the HSV round trip within
// 1/255.
import 'dart:math' as math;

import 'package:feature_editor/src/ui/color/color_math.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseHex accepts', () {
    const cases = <String, int>{
      '#1A2B3C': 0xFF1A2B3C, // #RRGGBB
      '1a2b3c': 0xFF1A2B3C, // without '#', lower case
      '#AbC': 0xFFAABBCC, // #RGB, mixed case
      'abc': 0xFFAABBCC, // RGB without '#'
      '#801A2B3C': 0x801A2B3C, // #AARRGGBB keeps the alpha
      'ff00ff00': 0xFF00FF00, // AARRGGBB without '#'
      '  #1a2B3c  ': 0xFF1A2B3C, // surrounding spaces
      '#000': 0xFF000000,
      '\t00000000\n': 0x00000000, // fully transparent, other white space
    };
    for (final MapEntry(key: input, value: expected) in cases.entries) {
      test('"${input.replaceAll('\t', r'\t').replaceAll('\n', r'\n')}"', () {
        expect(ColorMath.parseHex(input), expected);
      });
    }
  });

  group('parseHex rejects', () {
    const cases = <String, String>{
      'empty': '',
      'only #': '#',
      'wrong length (2, 4, 5, 7, 9)': '#12|#1234|#12345|#1234567|#123456789',
      'not a hex digit': '#GG0000|#12345z|0x123456',
      'space inside': '#12 3456|1 2 3',
      'two #': '##123456|#123#456',
    };
    for (final MapEntry(key: name, value: inputs) in cases.entries) {
      test(name, () {
        for (final input in inputs.split('|')) {
          expect(ColorMath.parseHex(input), isNull, reason: '"$input"');
        }
      });
    }
  });

  test('toHex writes #RRGGBB upper case, #AARRGGBB with includeAlpha', () {
    expect(ColorMath.toHex(0xFF1A2B3C), '#1A2B3C');
    expect(ColorMath.toHex(0x801A2B3C), '#1A2B3C');
    expect(ColorMath.toHex(0x801A2B3C, includeAlpha: true), '#801A2B3C');
    expect(ColorMath.toHex(0xFF00000F), '#00000F');
    expect(ColorMath.toHex(0x0000000F, includeAlpha: true), '#0000000F');
    // HEX → value → HEX.
    for (final hex in ['#000000', '#FFFFFF', '#3366CC', '#ABCDEF']) {
      expect(ColorMath.toHex(ColorMath.parseHex(hex)!), hex);
    }
  });

  test('toRgb / fromRgb (channels clamped to 0..255, alpha FF)', () {
    expect(ColorMath.toRgb(0x801A2B3C), (r: 0x1A, g: 0x2B, b: 0x3C));
    expect(ColorMath.fromRgb(0x1A, 0x2B, 0x3C), 0xFF1A2B3C);
    expect(ColorMath.fromRgb(300, -5, 128), 0xFFFF0080);
  });

  test('opaque sets alpha FF and keeps the RGB part; alphaOf reads AA', () {
    expect(ColorMath.opaque(0x001A2B3C), 0xFF1A2B3C);
    expect(ColorMath.opaque(0x801A2B3C), 0xFF1A2B3C);
    expect(ColorMath.opaque(0xFF1A2B3C), 0xFF1A2B3C);
    expect(ColorMath.alphaOf(0x80000000), closeTo(128 / 255, 1e-12));
    expect(ColorMath.alphaOf(0xFF123456), 1);
    expect(ColorMath.alphaOf(0x00123456), 0);
  });

  test('RGB → HSV → RGB: every channel within 1/255 (a 16-step grid plus '
      'random colours)', () {
    final colors = <int>[
      for (var r = 0; r <= 255; r += 17)
        for (var g = 0; g <= 255; g += 17)
          for (var b = 0; b <= 255; b += 17) ColorMath.fromRgb(r, g, b),
    ];
    final random = math.Random(14);
    for (var i = 0; i < 2000; i++) {
      colors.add(
        ColorMath.fromRgb(
          random.nextInt(256),
          random.nextInt(256),
          random.nextInt(256),
        ),
      );
    }
    for (final c in colors) {
      final back = ColorMath.fromHsv(ColorMath.toHsv(c));
      final a = ColorMath.toRgb(c);
      final b = ColorMath.toRgb(back);
      expect((a.r - b.r).abs(), lessThanOrEqualTo(1), reason: '$c');
      expect((a.g - b.g).abs(), lessThanOrEqualTo(1), reason: '$c');
      expect((a.b - b.b).abs(), lessThanOrEqualTo(1), reason: '$c');
      expect(back ~/ 0x1000000, 0xFF); // alpha FF
    }
  });

  test('HSV → RGB → HSV: value and chroma within 1/255, hue kept where it '
      'is defined', () {
    for (var h = 0.0; h < 360; h += 7.5) {
      for (var s = 0.2; s <= 1.0001; s += 0.2) {
        for (var v = 0.2; v <= 1.0001; v += 0.2) {
          final hsv = HSVColor.fromAHSV(1, h, math.min(s, 1), math.min(v, 1));
          final back = ColorMath.toHsv(ColorMath.fromHsv(hsv));
          expect((back.value - hsv.value).abs(), lessThanOrEqualTo(1 / 255));
          expect(
            (back.saturation * back.value - hsv.saturation * hsv.value).abs(),
            lessThanOrEqualTo(1 / 255),
            reason: 'chroma of $hsv',
          );
          // The hue is quantised by the chroma (8-bit channels): check it
          // where the chroma is at least 0.2 (51 steps → < 1° error).
          if (hsv.saturation * hsv.value >= 0.2) {
            final dh = (back.hue - hsv.hue).abs();
            expect(math.min(dh, 360 - dh), lessThan(1), reason: 'hue of $hsv');
          }
        }
      }
    }
  });

  test('toHsv ignores the alpha; fromHsv is opaque', () {
    expect(ColorMath.toHsv(0x00FF0000).alpha, 1);
    expect(ColorMath.toHsv(0x00FF0000).hue, 0);
    expect(ColorMath.fromHsv(HSVColor.fromAHSV(0.2, 120, 1, 1)), 0xFF00FF00);
  });
}
