// lib/src/image/image_codec.dart — the image codec port of the slow path (m5-7/06-pdf 6.12.3).
// Internal. Bodies: image_codec_io.dart (VM · native — package:image in an isolate, the engine
// decoder for what package:image cannot read) and image_codec_browser.dart (createImageBitmap +
// canvas, and the web clipboard read — PDF T35b), chosen by image_codec_factory.dart.
import 'package:flutter/foundation.dart';

/// What a picker or the clipboard gave (6.12.1).
@immutable
final class PickedImage {
  const PickedImage(this.bytes, {this.name});

  final Uint8List bytes;

  /// The chosen file's name (its extension becomes the stored format's — 6.12.5); null for
  /// the camera / the clipboard.
  final String? name;
}

abstract interface class ImageCodec {
  /// The first frame of [bytes] with its EXIF orientation baked in, scaled down (never up) so
  /// its long side is at most [maxLongSide]. `null` when it cannot be decoded.
  Future<DecodedImage?> decode(Uint8List bytes, {required int maxLongSide});
}

/// A decoded image held by a codec (pixels stay on the codec's side).
abstract interface class DecodedImage {
  int get width;
  int get height;

  /// Some pixel has alpha < 255 (6.12.3 '알파 판정').
  bool get hasAlpha;

  /// JPEG at [quality] (0..1), no metadata.
  Future<Uint8List> encodeJpeg(double quality);

  /// PNG, no metadata.
  Future<Uint8List> encodePng();

  /// A copy whose long side is × [factor] (at least 1 px each way).
  Future<DecodedImage> scaled(double factor);

  /// Lets the pixels go.
  void dispose();
}
