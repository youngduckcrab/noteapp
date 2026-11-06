// lib/src/image/image_header.dart — image headers read without decoding (m5-7/06-pdf 6.12.2,
// M-3; v2.1 review S-9). Internal, pure Dart, web-safe numbers (no 64-bit reads, arithmetic
// instead of bit operations on values that can pass 2^31).
//
// JPEG: the SOF marker (type, precision, size, component count), the EXIF orientation (APP1
// 'Exif\0\0' → TIFF IFD0 tag 0x0112), whether EXIF has a GPS IFD (0x8825), every APP1 segment
// (Exif and XMP — removed byte for byte on the fast path) and Adobe APP14 (+ its transform).
// PNG: IHDR (size, bit depth, colour type) and tRNS. GIF: the logical screen. WebP: VP8 / VP8L /
// VP8X sizes and alpha. HEIC/HEIF: recognised by the ftyp brand (no size — decoded by the
// platform).
import 'dart:typed_data';

enum ImageFormat { jpeg, png, gif, webp, heif, unknown }

final class ImageHeader {
  const ImageHeader({
    required this.format,
    this.width,
    this.height,
    this.orientation = 1,
    this.jpegSofType,
    this.jpegPrecision,
    this.jpegComponents,
    this.jpegAdobe = false,
    this.jpegAdobeTransform,
    this.jpegApp1 = const [],
    this.exifHasGps = false,
    this.pngColorType,
    this.pngBitDepth,
    this.pngHasTrns = false,
    this.webpHasAlpha = false,
    this.complete = false,
  });

  static const ImageHeader unknown = ImageHeader(format: ImageFormat.unknown);

  final ImageFormat format;

  /// The stored size (before the EXIF orientation); null when the header is cut or has none.
  final int? width, height;

  /// EXIF orientation 1..8 (1 when there is none or it is out of range).
  final int orientation;

  /// SOFn: n (0 baseline, 1 extended, 2 progressive, 3 lossless, 9+ arithmetic).
  final int? jpegSofType;
  final int? jpegPrecision;

  /// 1 gray, 3 YCbCr (or RGB), 4 CMYK / YCCK.
  final int? jpegComponents;

  /// Adobe APP14 present (CMYK / YCCK / RGB transforms — slow path, S-9).
  final bool jpegAdobe;
  final int? jpegAdobeTransform;

  /// Every APP1 segment (Exif, XMP, …) as [start, end) byte ranges, marker included.
  final List<({int start, int end})> jpegApp1;

  /// EXIF carries a GPS IFD pointer (location metadata).
  final bool exifHasGps;

  /// IHDR colour type: 0 gray, 2 RGB, 3 palette, 4 gray + alpha, 6 RGBA.
  final int? pngColorType;
  final int? pngBitDepth;
  final bool pngHasTrns;

  final bool webpHasAlpha;

  /// JPEG: ends with EOI (FF D9); PNG: ends with the IEND chunk. A cut file never takes the fast
  /// path (it is decoded and fails, or is re-encoded).
  final bool complete;

  /// The size as shown (EXIF 5..8 swap width and height).
  int? get orientedWidth => orientation >= 5 ? height : width;
  int? get orientedHeight => orientation >= 5 ? width : height;

  /// The long side as shown; null when unknown.
  int? get longSide {
    final w = width, h = height;
    if (w == null || h == null) return null;
    return w > h ? w : h;
  }

  /// The format can carry alpha here (PNG colour type 4/6 or tRNS, WebP with alpha, GIF).
  bool get mayHaveAlpha => switch (format) {
    ImageFormat.png => pngColorType == 4 || pngColorType == 6 || pngHasTrns,
    ImageFormat.webp => webpHasAlpha,
    ImageFormat.gif => true,
    _ => false,
  };

  /// Reads [bytes]; [ImageHeader.unknown] when the format is not recognised. A cut header
  /// keeps what was read (size null).
  static ImageHeader parse(Uint8List bytes) {
    if (_startsWith(bytes, const [0xFF, 0xD8, 0xFF])) return _jpeg(bytes);
    if (_startsWith(bytes, const [
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
    if (_startsWith(bytes, 'GIF87a'.codeUnits) ||
        _startsWith(bytes, 'GIF89a'.codeUnits)) {
      return bytes.length < 10
          ? const ImageHeader(format: ImageFormat.gif)
          : ImageHeader(
              format: ImageFormat.gif,
              width: _u16le(bytes, 6),
              height: _u16le(bytes, 8),
            );
    }
    if (bytes.length >= 12 &&
        _startsWith(bytes, 'RIFF'.codeUnits) &&
        _matches(bytes, 8, 'WEBP'.codeUnits)) {
      return _webp(bytes);
    }
    if (bytes.length >= 12 && _matches(bytes, 4, 'ftyp'.codeUnits)) {
      final brand = String.fromCharCodes(bytes.sublist(8, 12));
      if (const {
        'heic',
        'heix',
        'hevc',
        'hevx',
        'mif1',
        'msf1',
        'heis',
      }.contains(brand)) {
        return const ImageHeader(format: ImageFormat.heif);
      }
    }
    return unknown;
  }

  static ImageHeader _jpeg(Uint8List b) {
    int? sof, precision, components, width, height, adobeTransform;
    var adobe = false, gps = false;
    var orientation = 1;
    final app1 = <({int start, int end})>[];
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
      final start = p, dataStart = p + 4, end = p + 2 + length;
      if (end > b.length) break; // cut
      final isSof =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isSof && sof == null && length >= 8) {
        sof = marker - 0xC0;
        precision = b[dataStart];
        height = _u16be(b, dataStart + 1);
        width = _u16be(b, dataStart + 3);
        components = b[dataStart + 5];
      } else if (marker == 0xE1) {
        app1.add((start: start, end: end));
        if (_matches(b, dataStart, const [0x45, 0x78, 0x69, 0x66, 0, 0])) {
          final exif = _exif(b, dataStart + 6, end);
          if (exif.orientation != null) orientation = exif.orientation!;
          gps = gps || exif.gps;
        }
      } else if (marker == 0xEE && _matches(b, dataStart, 'Adobe'.codeUnits)) {
        adobe = true;
        if (dataStart + 11 < end) adobeTransform = b[dataStart + 11];
      }
      p = end;
    }
    return ImageHeader(
      format: ImageFormat.jpeg,
      width: width,
      height: height,
      orientation: orientation,
      jpegSofType: sof,
      jpegPrecision: precision,
      jpegComponents: components,
      jpegAdobe: adobe,
      jpegAdobeTransform: adobeTransform,
      jpegApp1: List.unmodifiable(app1),
      exifHasGps: gps,
      complete:
          b.length >= 4 && b[b.length - 2] == 0xFF && b[b.length - 1] == 0xD9,
    );
  }

  /// TIFF in an EXIF APP1: IFD0's orientation and GPS pointer.
  static ({int? orientation, bool gps}) _exif(Uint8List b, int tiff, int end) {
    if (tiff + 8 > end) return (orientation: null, gps: false);
    final little = b[tiff] == 0x49 && b[tiff + 1] == 0x49;
    final big = b[tiff] == 0x4D && b[tiff + 1] == 0x4D;
    if (!little && !big) return (orientation: null, gps: false);
    int u16(int at) => little ? _u16le(b, at) : _u16be(b, at);
    int u32(int at) => little ? _u32le(b, at) : _u32be(b, at);
    if (u16(tiff + 2) != 42) return (orientation: null, gps: false);
    final ifd = tiff + u32(tiff + 4);
    if (ifd + 2 > end) return (orientation: null, gps: false);
    final count = u16(ifd);
    int? orientation;
    var gps = false;
    for (var i = 0; i < count; i++) {
      final e = ifd + 2 + i * 12;
      if (e + 12 > end) break;
      final tag = u16(e);
      if (tag == 0x0112) {
        final v = u16(e + 8);
        orientation = v >= 1 && v <= 8 ? v : 1;
      } else if (tag == 0x8825) {
        gps = true;
      }
    }
    return (orientation: orientation, gps: gps);
  }

  static ImageHeader _png(Uint8List b) {
    if (b.length < 33 || !_matches(b, 12, 'IHDR'.codeUnits)) {
      return const ImageHeader(format: ImageFormat.png);
    }
    final width = _u32be(b, 16), height = _u32be(b, 20);
    final bitDepth = b[24], colorType = b[25];
    var trns = false;
    var p = 8;
    while (p + 8 <= b.length) {
      final length = _u32be(b, p);
      if (_matches(b, p + 4, 'tRNS'.codeUnits)) trns = true;
      if (_matches(b, p + 4, 'IDAT'.codeUnits)) break;
      p += 12 + length;
    }
    return ImageHeader(
      format: ImageFormat.png,
      width: width,
      height: height,
      pngColorType: colorType,
      pngBitDepth: bitDepth,
      pngHasTrns: trns,
      complete: _matches(b, b.length - 12, const [
        0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
      ]),
    );
  }

  static ImageHeader _webp(Uint8List b) {
    if (b.length < 30) return const ImageHeader(format: ImageFormat.webp);
    if (_matches(b, 12, 'VP8X'.codeUnits)) {
      final flags = b[20];
      return ImageHeader(
        format: ImageFormat.webp,
        width: _u24le(b, 24) + 1,
        height: _u24le(b, 27) + 1,
        webpHasAlpha: (flags ~/ 16) % 2 == 1, // bit 4
      );
    }
    if (_matches(b, 12, 'VP8L'.codeUnits) && b[20] == 0x2F) {
      // 14 bits width − 1, 14 bits height − 1, 1 bit alpha (little endian bit stream)
      final bits = _u32le(b, 21);
      final w = bits % 16384 + 1;
      final h = (bits ~/ 16384) % 16384 + 1;
      final alpha = (bits ~/ 268435456) % 2 == 1;
      return ImageHeader(
        format: ImageFormat.webp,
        width: w,
        height: h,
        webpHasAlpha: alpha,
      );
    }
    if (_matches(b, 12, 'VP8 '.codeUnits) &&
        _matches(b, 23, const [0x9D, 0x01, 0x2A])) {
      return ImageHeader(
        format: ImageFormat.webp,
        width: _u16le(b, 26) % 16384,
        height: _u16le(b, 28) % 16384,
      );
    }
    return const ImageHeader(format: ImageFormat.webp);
  }
}

/// [bytes] without its APP1 segments (Exif, XMP — location and other metadata), every other
/// byte unchanged (lossless, 6.12.2 fast path). The same bytes when there is no APP1.
Uint8List stripJpegApp1(Uint8List bytes, ImageHeader header) {
  final cut = header.jpegApp1;
  if (cut.isEmpty) return bytes;
  var removed = 0;
  for (final s in cut) {
    removed += s.end - s.start;
  }
  final out = Uint8List(bytes.length - removed);
  var from = 0, at = 0;
  for (final s in cut) {
    out.setRange(at, at + s.start - from, bytes, from);
    at += s.start - from;
    from = s.end;
  }
  out.setRange(at, out.length, bytes, from);
  return out;
}

bool _startsWith(Uint8List b, List<int> prefix) => _matches(b, 0, prefix);

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
