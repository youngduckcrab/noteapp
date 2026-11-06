// lib/src/export/image_probe.dart — image headers read without decoding (m5-7/06-pdf 6.2.4).
// Internal (not in the barrel), pure Dart, web-safe numbers (no 64-bit reads, arithmetic instead
// of bit operations on values that can pass 2^31).
//
// The same job as media_io's image_header.dart, kept apart because pdf_io does not import
// media_io (3.5 I-1). Only what the export resolver needs: format, stored size, alpha
// possibility, JPEG SOF type / precision / component count, Adobe APP14 and the EXIF
// orientation.
import 'dart:typed_data';

import '../tuning.dart';

enum PdfImageFormat { jpeg, png, gif, webp, unknown }

final class PdfImageProbe {
  const PdfImageProbe({
    required this.format,
    this.width,
    this.height,
    this.orientation = 1,
    this.jpegSofType,
    this.jpegPrecision,
    this.jpegComponents,
    this.jpegAdobe = false,
    this.pngColorType,
    this.pngHasTrns = false,
    this.webpHasAlpha = false,
  });

  static const PdfImageProbe unknown = PdfImageProbe(
    format: PdfImageFormat.unknown,
  );

  final PdfImageFormat format;

  /// The stored size (before the EXIF orientation); null when the header is cut or has none.
  final int? width, height;

  /// EXIF orientation 1..8 (1 when there is none or it is out of range).
  final int orientation;

  /// JPEG SOFn: n (0 baseline, 1 extended, 2 progressive, 3 lossless, 9+ arithmetic).
  final int? jpegSofType;
  final int? jpegPrecision;

  /// 1 gray, 3 YCbCr, 4 CMYK / YCCK.
  final int? jpegComponents;

  /// Adobe APP14 present (CMYK / YCCK / RGB transforms — slow path, S-9).
  final bool jpegAdobe;

  /// PNG IHDR colour type: 0 gray, 2 RGB, 3 palette, 4 gray + alpha, 6 RGBA.
  final int? pngColorType;
  final bool pngHasTrns;
  final bool webpHasAlpha;

  bool get hasSize => (width ?? 0) > 0 && (height ?? 0) > 0;

  /// The size as shown (EXIF 5..8 swap width and height) — what the engine decodes to.
  int? get orientedWidth => orientation >= 5 ? height : width;
  int? get orientedHeight => orientation >= 5 ? width : height;

  /// The format can carry alpha (PNG colour type 4 / 6 or tRNS, WebP with alpha, GIF). False →
  /// the decoded RGBA is opaque and is not scanned.
  bool get mayHaveAlpha => switch (format) {
    PdfImageFormat.png => pngColorType == 4 || pngColorType == 6 || pngHasTrns,
    PdfImageFormat.webp => webpHasAlpha,
    PdfImageFormat.gif => true,
    // unknown formats: scan the pixels
    PdfImageFormat.unknown => true,
    PdfImageFormat.jpeg => false,
  };

  /// 6.2.4 JPEG fast path (bytes as stored, no pixels held): SOF0 · 1 · 2, 8 bit, 1 (gray) or 3
  /// (YCbCr) components without Adobe APP14 (S-9), no EXIF rotation, ≤ exportJpegInlineMaxBytes.
  bool jpegFastPath(int byteLength) =>
      format == PdfImageFormat.jpeg &&
      hasSize &&
      (jpegSofType == 0 || jpegSofType == 1 || jpegSofType == 2) &&
      jpegPrecision == 8 &&
      (jpegComponents == 1 || jpegComponents == 3) &&
      !jpegAdobe &&
      orientation == 1 &&
      byteLength <= PdfTuning.exportJpegInlineMaxBytes;

  /// Reads [bytes]; [unknown] when the format is not recognised. A cut header keeps what was
  /// read (size null).
  static PdfImageProbe parse(Uint8List bytes) {
    if (_matches(bytes, 0, const [0xFF, 0xD8, 0xFF])) return _jpeg(bytes);
    if (_matches(bytes, 0, const [
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ])) {
      return _png(bytes);
    }
    if (_matches(bytes, 0, 'GIF87a'.codeUnits) ||
        _matches(bytes, 0, 'GIF89a'.codeUnits)) {
      return bytes.length < 10
          ? const PdfImageProbe(format: PdfImageFormat.gif)
          : PdfImageProbe(
              format: PdfImageFormat.gif,
              width: _u16le(bytes, 6),
              height: _u16le(bytes, 8),
            );
    }
    if (bytes.length >= 12 &&
        _matches(bytes, 0, 'RIFF'.codeUnits) &&
        _matches(bytes, 8, 'WEBP'.codeUnits)) {
      return _webp(bytes);
    }
    return unknown;
  }

  static PdfImageProbe _jpeg(Uint8List b) {
    int? sof, precision, components, width, height;
    var adobe = false;
    var orientation = 1;
    var p = 2;
    while (p + 4 <= b.length) {
      if (b[p] != 0xFF) break; // lost sync
      final marker = b[p + 1];
      if (marker == 0xFF) {
        p++; // fill byte
        continue;
      }
      if (marker == 0xD8 ||
          marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        p += 2; // standalone
        continue;
      }
      if (marker == 0xD9 || marker == 0xDA) break; // EOI / SOS: the headers end
      final length = _u16be(b, p + 2);
      if (length < 2) break;
      final data = p + 4, end = p + 2 + length;
      if (end > b.length) break; // cut
      final isSof =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isSof && sof == null && length >= 8) {
        sof = marker - 0xC0;
        precision = b[data];
        height = _u16be(b, data + 1);
        width = _u16be(b, data + 3);
        components = b[data + 5];
      } else if (marker == 0xE1 &&
          _matches(b, data, const [0x45, 0x78, 0x69, 0x66, 0, 0])) {
        orientation = _exifOrientation(b, data + 6, end) ?? orientation;
      } else if (marker == 0xEE && _matches(b, data, 'Adobe'.codeUnits)) {
        adobe = true;
      }
      p = end;
    }
    return PdfImageProbe(
      format: PdfImageFormat.jpeg,
      width: width,
      height: height,
      orientation: orientation,
      jpegSofType: sof,
      jpegPrecision: precision,
      jpegComponents: components,
      jpegAdobe: adobe,
    );
  }

  /// TIFF in an EXIF APP1: IFD0's orientation tag (0x0112).
  static int? _exifOrientation(Uint8List b, int tiff, int end) {
    if (tiff + 8 > end) return null;
    final little = b[tiff] == 0x49 && b[tiff + 1] == 0x49;
    final big = b[tiff] == 0x4D && b[tiff + 1] == 0x4D;
    if (!little && !big) return null;
    int u16(int at) => little ? _u16le(b, at) : _u16be(b, at);
    int u32(int at) => little ? _u32le(b, at) : _u32be(b, at);
    if (u16(tiff + 2) != 42) return null;
    final ifd = tiff + u32(tiff + 4);
    if (ifd + 2 > end) return null;
    final count = u16(ifd);
    for (var i = 0; i < count; i++) {
      final e = ifd + 2 + i * 12;
      if (e + 12 > end) break;
      if (u16(e) == 0x0112) {
        final v = u16(e + 8);
        return v >= 1 && v <= 8 ? v : 1;
      }
    }
    return null;
  }

  static PdfImageProbe _png(Uint8List b) {
    if (b.length < 33 || !_matches(b, 12, 'IHDR'.codeUnits)) {
      return const PdfImageProbe(format: PdfImageFormat.png);
    }
    final width = _u32be(b, 16), height = _u32be(b, 20);
    final colorType = b[25];
    var trns = false;
    var p = 8;
    while (p + 8 <= b.length) {
      final length = _u32be(b, p);
      if (_matches(b, p + 4, 'tRNS'.codeUnits)) trns = true;
      if (_matches(b, p + 4, 'IDAT'.codeUnits)) break;
      p += 12 + length;
    }
    return PdfImageProbe(
      format: PdfImageFormat.png,
      width: width,
      height: height,
      pngColorType: colorType,
      pngHasTrns: trns,
    );
  }

  static PdfImageProbe _webp(Uint8List b) {
    if (b.length < 30) return const PdfImageProbe(format: PdfImageFormat.webp);
    if (_matches(b, 12, 'VP8X'.codeUnits)) {
      return PdfImageProbe(
        format: PdfImageFormat.webp,
        width: _u24le(b, 24) + 1,
        height: _u24le(b, 27) + 1,
        webpHasAlpha: (b[20] ~/ 16) % 2 == 1, // flags bit 4
      );
    }
    if (_matches(b, 12, 'VP8L'.codeUnits) && b[20] == 0x2F) {
      // 14 bits width − 1, 14 bits height − 1, 1 bit alpha (little endian bit stream)
      final bits = _u32le(b, 21);
      return PdfImageProbe(
        format: PdfImageFormat.webp,
        width: bits % 16384 + 1,
        height: (bits ~/ 16384) % 16384 + 1,
        webpHasAlpha: (bits ~/ 268435456) % 2 == 1,
      );
    }
    if (_matches(b, 12, 'VP8 '.codeUnits) &&
        _matches(b, 23, const [0x9D, 0x01, 0x2A])) {
      return PdfImageProbe(
        format: PdfImageFormat.webp,
        width: _u16le(b, 26) % 16384,
        height: _u16le(b, 28) % 16384,
      );
    }
    return const PdfImageProbe(format: PdfImageFormat.webp);
  }

  @override
  String toString() =>
      'PdfImageProbe(${format.name}, ${width}x$height, orientation $orientation'
      '${format == PdfImageFormat.jpeg ? ', SOF$jpegSofType/$jpegPrecision bit/'
                '$jpegComponents comp${jpegAdobe ? ', Adobe' : ''}' : ''})';
}

bool _matches(Uint8List b, int at, List<int> what) {
  if (at < 0 || at + what.length > b.length) return false;
  for (var i = 0; i < what.length; i++) {
    if (b[at + i] != what[i]) return false;
  }
  return true;
}

int _u16be(Uint8List b, int at) =>
    at + 2 > b.length ? 0 : b[at] * 256 + b[at + 1];

int _u16le(Uint8List b, int at) =>
    at + 2 > b.length ? 0 : b[at + 1] * 256 + b[at];

int _u24le(Uint8List b, int at) =>
    at + 3 > b.length ? 0 : b[at + 2] * 65536 + b[at + 1] * 256 + b[at];

int _u32be(Uint8List b, int at) => at + 4 > b.length
    ? 0
    : b[at] * 16777216 + b[at + 1] * 65536 + b[at + 2] * 256 + b[at + 3];

int _u32le(Uint8List b, int at) => at + 4 > b.length
    ? 0
    : b[at + 3] * 16777216 + b[at + 2] * 65536 + b[at + 1] * 256 + b[at];
