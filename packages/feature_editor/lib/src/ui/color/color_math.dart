// lib/src/ui/color/color_math.dart — 04-editor 6.9.5.
//
// Web-safe arithmetic only (contract 7.4.3): ARGB values stay below 2^32 and
// channels are taken with ~/ and %, never with bit operations.
import 'package:flutter/painting.dart' show Color, HSVColor;

abstract final class ColorMath {
  static const int _alphaUnit = 0x1000000; // 2^24
  static const int _rgbRange = 0x1000000;

  /// Accepts "#RGB", "#RRGGBB", "#AARRGGBB" (with or without '#', any case,
  /// surrounding spaces). Returns ARGB (alpha FF for 3/6 digits) or null.
  static int? parseHex(String input) {
    var s = input.trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length != 3 && s.length != 6 && s.length != 8) return null;
    final digits = <int>[];
    for (final unit in s.codeUnits) {
      final d = _hexDigit(unit);
      if (d == null) return null;
      digits.add(d);
    }
    switch (digits.length) {
      case 3:
        return 0xFF000000 +
            (digits[0] * 17) * 0x10000 +
            (digits[1] * 17) * 0x100 +
            digits[2] * 17;
      case 6:
        return 0xFF000000 + _number(digits);
      default:
        return _number(digits);
    }
  }

  /// "#1A2B3C" (upper case); "#801A2B3C" with [includeAlpha].
  static String toHex(int argb, {bool includeAlpha = false}) {
    final c = argb % 0x100000000;
    final a = c ~/ _alphaUnit;
    final rgb = c % _rgbRange;
    final body = rgb.toRadixString(16).padLeft(6, '0').toUpperCase();
    if (!includeAlpha) return '#$body';
    return '#${a.toRadixString(16).padLeft(2, '0').toUpperCase()}$body';
  }

  /// Hue 0..360, saturation and value 0..1 of the RGB part; alpha 1.
  static HSVColor toHsv(int argb) => HSVColor.fromColor(Color(opaque(argb)));

  /// alpha FF.
  static int fromHsv(HSVColor hsv) =>
      opaque(hsv.withAlpha(1).toColor().toARGB32());

  static ({int r, int g, int b}) toRgb(int argb) {
    final rgb = argb % _rgbRange;
    return (r: rgb ~/ 0x10000, g: (rgb ~/ 0x100) % 0x100, b: rgb % 0x100);
  }

  /// Each channel clamped to 0..255; alpha FF.
  static int fromRgb(int r, int g, int b) =>
      0xFF000000 +
      r.clamp(0, 255) * 0x10000 +
      g.clamp(0, 255) * 0x100 +
      b.clamp(0, 255);

  /// 0xFF000000 | rgb (written without bit operations).
  static int opaque(int argb) => 0xFF000000 + argb % _rgbRange;

  /// The alpha byte of [argb] as 0..1.
  static double alphaOf(int argb) => (argb % 0x100000000) ~/ _alphaUnit / 255;

  static int _number(List<int> digits) {
    var n = 0;
    for (final d in digits) {
      n = n * 16 + d;
    }
    return n;
  }

  static int? _hexDigit(int unit) {
    if (unit >= 0x30 && unit <= 0x39) return unit - 0x30; // 0-9
    if (unit >= 0x41 && unit <= 0x46) return unit - 0x41 + 10; // A-F
    if (unit >= 0x61 && unit <= 0x66) return unit - 0x61 + 10; // a-f
    return null;
  }
}
