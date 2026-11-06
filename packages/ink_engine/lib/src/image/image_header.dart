// lib/src/image/image_header.dart — INTERNAL (m5-7/03-ink 6.11.1, review S-4).
//
// The pixel size of stored image bytes without decoding them: PNG IHDR (the
// first chunk after the 8-byte signature) and JPEG SOFn (markers FFC0..FFCF
// except C4 DHT, C8 JPG, CC DAC — baseline, progressive, ...). Pure Dart on the
// bytes (web safe — ui.ImageDescriptor.width is not supported on the web). An
// image background has no pixel size in the model, so its bucket is chosen
// from this and the original resolution is never decoded. null = not PNG /
// JPEG or cut short (the caller decodes with targetWidth only).
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// INTERNAL: (width, height) in px of PNG / JPEG [bytes]; null when unreadable.
@internal
({int width, int height})? readImagePixelSize(Uint8List bytes) {
  try {
    if (_isPng(bytes)) return _png(bytes);
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return _jpeg(bytes);
    }
  } on RangeError {
    return null;
  }
  return null;
}

const List<int> _pngSignature = [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
];

bool _isPng(Uint8List b) {
  if (b.length < 8) return false;
  for (var i = 0; i < 8; i++) {
    if (b[i] != _pngSignature[i]) return false;
  }
  return true;
}

int _u16(Uint8List b, int i) => b[i] * 0x100 + b[i + 1];

int _u32(Uint8List b, int i) =>
    b[i] * 0x1000000 + b[i + 1] * 0x10000 + b[i + 2] * 0x100 + b[i + 3];

({int width, int height})? _png(Uint8List b) {
  // length (4) · 'IHDR' (4) · width (4) · height (4)
  if (b.length < 24) return null;
  if (b[12] != 0x49 || b[13] != 0x48 || b[14] != 0x44 || b[15] != 0x52) {
    return null;
  }
  final w = _u32(b, 16), h = _u32(b, 20);
  return w > 0 && h > 0 ? (width: w, height: h) : null;
}

({int width, int height})? _jpeg(Uint8List b) {
  var i = 2;
  while (i < b.length) {
    if (b[i] != 0xFF) return null; // not at a marker: corrupt
    // fill bytes
    while (i < b.length && b[i] == 0xFF) {
      i++;
    }
    if (i >= b.length) return null;
    final marker = b[i++];
    // markers without a length
    if (marker == 0xD8 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      continue;
    }
    if (marker == 0xD9 || marker == 0xDA) return null; // EOI / SOS before a SOF
    if (i + 2 > b.length) return null;
    final length = _u16(b, i);
    if (length < 2) return null;
    final isSof =
        marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isSof) {
      // length (2) · precision (1) · height (2) · width (2)
      if (i + 7 > b.length) return null;
      final h = _u16(b, i + 3), w = _u16(b, i + 5);
      return w > 0 && h > 0 ? (width: w, height: h) : null;
    }
    i += length;
  }
  return null;
}
