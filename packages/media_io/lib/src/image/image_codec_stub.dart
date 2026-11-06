// lib/src/image/image_codec_stub.dart — image_codec_factory.dart where there is neither the web
// nor dart:io (m5-7/06-pdf 6.18; ws check R6 wants a stub default): no codec (nothing decodes —
// the slow path is decodeFailed), no clipboard. Internal.
import 'package:flutter/foundation.dart';

import '../errors.dart';
import 'image_codec.dart';

ImageCodec createPlatformImageCodec() => const _NoImageCodec();

bool clipboardImageReadable() => false;

Future<PickedImage?> readClipboardImage() => Future.error(
  const MediaIoException(
    MediaErrorCode.clipboardEmpty,
    detail: 'no clipboard source here',
  ),
);

final class _NoImageCodec implements ImageCodec {
  const _NoImageCodec();

  @override
  Future<DecodedImage?> decode(
    Uint8List bytes, {
    required int maxLongSide,
  }) async => null;
}
