// lib/src/image/image_codec_io.dart — the VM · native image codec (m5-7/06-pdf 6.12.3). Internal.
// package:image in a background isolate (compute): decodeImage (first frame) → bakeOrientation →
// copyResize (long side ≤ 2048, average interpolation) → encodeJpg / encodePng with the EXIF
// dropped. What package:image cannot read (HEIC, …) goes through the engine's platform decoder
// (ImageDescriptor at the target size → RGBA) and the same steps. No dart:io.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'image_codec.dart';

final class IoImageCodec implements ImageCodec {
  const IoImageCodec({this.useIsolate = true});

  /// false: run on the calling isolate (tests that count work; small images).
  final bool useIsolate;

  Future<R> _run<M, R>(R Function(M) f, M message) =>
      useIsolate ? compute(f, message) : Future.value(f(message));

  @override
  Future<DecodedImage?> decode(
    Uint8List bytes, {
    required int maxLongSide,
  }) async {
    final decoded = await _run(_decodeAndFit, (bytes, maxLongSide));
    if (decoded != null) return _IoImage(this, decoded.image, decoded.alpha);
    final viaEngine = await _engineDecode(bytes, maxLongSide);
    if (viaEngine == null) return null;
    return _IoImage(this, viaEngine, _hasAlpha(viaEngine));
  }

  /// The engine's decoder (HEIC on iOS, …) at the target size, as RGBA.
  Future<img.Image?> _engineDecode(Uint8List bytes, int maxLongSide) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? frame;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final w = descriptor.width, h = descriptor.height;
      if (w <= 0 || h <= 0) return null;
      final scale = math.min(1.0, maxLongSide / math.max(w, h));
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (w * scale).round()),
        targetHeight: math.max(1, (h * scale).round()),
      );
      frame = (await codec.getNextFrame()).image;
      final data = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      return img.Image.fromBytes(
        width: frame.width,
        height: frame.height,
        bytes: data.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
    } on Object {
      return null;
    } finally {
      frame?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}

final class _IoImage implements DecodedImage {
  _IoImage(this._codec, this._image, this.hasAlpha);

  final IoImageCodec _codec;
  img.Image? _image;

  @override
  final bool hasAlpha;

  img.Image get _pixels =>
      _image ?? (throw StateError('The decoded image was disposed'));

  @override
  int get width => _pixels.width;

  @override
  int get height => _pixels.height;

  @override
  Future<Uint8List> encodeJpeg(double quality) =>
      _codec._run(_encodeJpg, (_pixels, (quality * 100).round().clamp(1, 100)));

  @override
  Future<Uint8List> encodePng() => _codec._run(_encodePng, _pixels);

  @override
  Future<DecodedImage> scaled(double factor) async {
    final out = await _codec._run(_scale, (_pixels, factor));
    return _IoImage(_codec, out, hasAlpha);
  }

  @override
  void dispose() => _image = null;
}

({img.Image image, bool alpha})? _decodeAndFit((Uint8List, int) message) {
  final (bytes, maxLongSide) = message;
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes, frame: 0);
  } on Object {
    decoded = null;
  }
  if (decoded == null) return null;
  var image = img.bakeOrientation(decoded);
  final long = math.max(image.width, image.height);
  if (long > maxLongSide) image = _fit(image, maxLongSide / long);
  image.exif = img.ExifData();
  return (image: image, alpha: _hasAlpha(image));
}

img.Image _fit(img.Image image, double factor) {
  final landscape = image.width >= image.height;
  final long = math.max(
    1,
    ((landscape ? image.width : image.height) * factor).round(),
  );
  return landscape
      ? img.copyResize(
          image,
          width: long,
          interpolation: img.Interpolation.average,
        )
      : img.copyResize(
          image,
          height: long,
          interpolation: img.Interpolation.average,
        );
}

img.Image _scale((img.Image, double) message) {
  final (image, factor) = message;
  final out = _fit(image, factor);
  out.exif = img.ExifData();
  return out;
}

Uint8List _encodeJpg((img.Image, int) message) {
  final (image, quality) = message;
  final rgb = image.numChannels >= 3 && !image.hasPalette
      ? image
      : image.convert(numChannels: 3);
  return img.encodeJpg(rgb, quality: quality, chroma: img.JpegChroma.yuv420);
}

Uint8List _encodePng(img.Image image) => img.encodePng(image);

bool _hasAlpha(img.Image image) {
  if (!image.hasAlpha &&
      !(image.hasPalette && image.palette!.numChannels == 4)) {
    return false;
  }
  for (final p in image) {
    if (p.a < p.maxChannelValue) return true;
  }
  return false;
}
