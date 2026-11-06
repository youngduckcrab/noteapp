// lib/src/image/image_codec_factory.dart (conditional export, m5-7/06-pdf 6.12.3, 6.12.4, 6.18) —
// declares:
//
//   /// Web: createImageBitmap + canvas (image_codec_browser.dart). VM · native: package:image +
//   /// the engine decoder (image_codec_io.dart — no dart:io, but a platform file by its suffix,
//   /// so ws check R6 wants a stub default: image_codec_stub.dart, which decodes nothing).
//   ImageCodec createPlatformImageCodec();
//   /// Web: navigator.clipboard.read and ClipboardItem exist. Else false.
//   bool clipboardImageReadable();
//   /// Web: calls navigator.clipboard.read() BEFORE returning (inside the user's tap — 7.2.10
//   /// v2.1), then the first image item's bytes; no image → clipboardEmpty, refused →
//   /// clipboardDenied (MediaIoException). Else an error (never offered).
//   Future<PickedImage?> readClipboardImage();
export 'image_codec_stub.dart'
    if (dart.library.js_interop) 'image_codec_browser.dart'
    if (dart.library.io) 'image_codec_io.dart';
