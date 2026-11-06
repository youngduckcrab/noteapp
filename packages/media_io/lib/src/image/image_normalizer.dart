// lib/src/image/image_normalizer.dart — the image import rules (m5-7/06-pdf 6.12.2, 6.12.3; M-3,
// contract 7.2.6 ImageImportLimits). Internal; pure rules over the codec port.
//
// Fast path (no re-encoding): JPEG SOF0/1/2, 8-bit, 1 or 3 components, no Adobe APP14, long side
// ≤ 2048, ≤ 8 MiB, EXIF orientation none / 1 → the same JPEG with every APP1 (Exif, XMP)
// removed byte for byte; PNG long side ≤ 2048, ≤ 8 MiB → as is. Both only when the file is
// complete (JPEG EOI / PNG IEND at the end).
// Slow path: decode (EXIF orientation baked, long side ≤ 2048) → PNG when some pixel has alpha
// or the source was PNG, else JPEG 0.85 → over 8 MiB: JPEG 0.75, 0.6; still over (or PNG): the
// long side × 0.85 and again, at most 6 times → tooLarge. Not decodable → decodeFailed (a known
// image format) / unsupportedFormat (not an image format we know).
import 'dart:typed_data';

import 'package:note_core/note_core.dart' as core;

import '../errors.dart';
import '../tuning.dart';
import 'image_codec.dart';
import 'image_header.dart';

/// How [ImageNormalizer.normalize] produced its result.
enum NormalizePath { fastJpeg, fastPng, slow }

final class NormalizedImage {
  const NormalizedImage({
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.path,
  });

  final Uint8List bytes;

  /// 'image/jpeg' or 'image/png' (core.ImageImportLimits.storedMimeTypes).
  final String mimeType;
  final int width, height;
  final NormalizePath path;
}

final class ImageNormalizer {
  const ImageNormalizer({
    required this.codec,
    this.maxBytes = core.ImageImportLimits.maxBytes,
    this.maxLongSide = core.ImageImportLimits.maxLongSidePx,
  });

  final ImageCodec codec;
  final int maxBytes;
  final int maxLongSide;

  /// Most downscale rounds on the slow path (6.12.3).
  static const int maxDownscales = 6;

  /// Throws [MediaIoException] (decodeFailed, unsupportedFormat, tooLarge).
  Future<NormalizedImage> normalize(Uint8List bytes) async {
    final header = ImageHeader.parse(bytes);
    final fast = _fastPath(bytes, header);
    if (fast != null) return fast;

    final decoded = await codec.decode(bytes, maxLongSide: maxLongSide);
    if (decoded == null) {
      throw MediaIoException(
        header.format == ImageFormat.unknown
            ? MediaErrorCode.unsupportedFormat
            : MediaErrorCode.decodeFailed,
        detail: header.format.name,
      );
    }
    final png = decoded.hasAlpha || header.format == ImageFormat.png;
    var image = decoded;
    try {
      for (var round = 0; round <= maxDownscales; round++) {
        if (round > 0) {
          final next = await image.scaled(MediaTuning.downscaleStep);
          image.dispose();
          image = next;
        }
        if (png) {
          final out = await image.encodePng();
          if (out.length <= maxBytes) return _slow(out, 'image/png', image);
        } else {
          // every quality at the full size, then the lowest one per downscale round
          final qualities = round == 0
              ? MediaTuning.jpegQualities
              : [MediaTuning.jpegQualities.last];
          for (final q in qualities) {
            final out = await image.encodeJpeg(q);
            if (out.length <= maxBytes) return _slow(out, 'image/jpeg', image);
          }
        }
      }
    } finally {
      image.dispose();
    }
    throw MediaIoException(
      MediaErrorCode.tooLarge,
      detail: 'over $maxBytes bytes after $maxDownscales downscales',
    );
  }

  NormalizedImage _slow(Uint8List out, String mime, DecodedImage image) =>
      NormalizedImage(
        bytes: out,
        mimeType: mime,
        width: image.width,
        height: image.height,
        path: NormalizePath.slow,
      );

  NormalizedImage? _fastPath(Uint8List bytes, ImageHeader h) {
    final w = h.width, hgt = h.height, long = h.longSide;
    if (w == null || hgt == null || long == null || w <= 0 || hgt <= 0) {
      return null;
    }
    if (long > maxLongSide || bytes.length > maxBytes || !h.complete) {
      return null;
    }
    switch (h.format) {
      case ImageFormat.jpeg:
        final sof = h.jpegSofType;
        // baseline, extended, progressive only
        if (sof == null || sof > 2) return null;
        if (h.jpegPrecision != 8) return null;
        if (h.jpegComponents != 1 && h.jpegComponents != 3) return null;
        if (h.jpegAdobe) return null; // CMYK / YCCK / RGB transforms (S-9)
        if (h.orientation != 1) return null;
        return NormalizedImage(
          bytes: stripJpegApp1(bytes, h),
          mimeType: 'image/jpeg',
          width: w,
          height: hgt,
          path: NormalizePath.fastJpeg,
        );
      case ImageFormat.png:
        return NormalizedImage(
          bytes: bytes,
          mimeType: 'image/png',
          width: w,
          height: hgt,
          path: NormalizePath.fastPng,
        );
      default:
        return null;
    }
  }
}
