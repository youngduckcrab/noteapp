// lib/src/image/image_codec_browser.dart — the web image codec and clipboard read (m5-7/06-pdf
// 6.12.3, 6.12.4). Internal; behind image_codec_factory.dart.
//
// Decode: createImageBitmap(Blob, {imageOrientation: 'from-image'}) — the browser decodes HEIC /
// WebP / GIF (first frame) and applies the EXIF orientation — then draws it at the target size
// (long side ≤ maxLongSide, never up) on an OffscreenCanvas (a <canvas> where there is none).
// Alpha: some pixel of the drawn image has alpha < 255. Encode: convertToBlob / toBlob as
// image/jpeg (quality) or image/png — no metadata either way.
// Clipboard: navigator.clipboard.read() is CALLED before readClipboardImage returns (the user's
// tap — Safari reads the clipboard only right after one, 7.2.10 v2.1); the first item with
// image/png, image/jpeg, image/webp or image/gif gives the bytes. None → clipboardEmpty;
// NotAllowedError → clipboardDenied ('붙여넣기를 허용한 뒤 다시 눌러 주세요').
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../errors.dart';
import 'image_codec.dart';

ImageCodec createPlatformImageCodec() => const BrowserImageCodec();

/// The image types taken from a clipboard item, in this order (6.12.4).
const List<String> clipboardImageTypes = [
  'image/png',
  'image/jpeg',
  'image/webp',
  'image/gif',
];

bool clipboardImageReadable() {
  try {
    final navigator = web.window.navigator as JSObject;
    if (!navigator.has('clipboard')) return false;
    final clipboard = navigator.getProperty<JSObject?>('clipboard'.toJS);
    return clipboard != null &&
        clipboard.has('read') &&
        globalContext.has('ClipboardItem') &&
        globalContext.getProperty<JSAny?>('ClipboardItem'.toJS) != null;
  } on Object {
    return false;
  }
}

Future<PickedImage?> readClipboardImage() {
  final JSPromise<web.ClipboardItems> items;
  try {
    // called here, synchronously — not after an await
    items = web.window.navigator.clipboard.read();
  } on Object catch (e) {
    return Future.error(_clipboardError(e));
  }
  return _readItems(items);
}

Future<PickedImage?> _readItems(JSPromise<web.ClipboardItems> pending) async {
  final List<web.ClipboardItem> items;
  try {
    items = (await pending.toDart).toDart;
  } on Object catch (e) {
    throw _clipboardError(e);
  }
  for (final item in items) {
    final types = [for (final t in item.types.toDart) t.toDart];
    for (final type in clipboardImageTypes) {
      if (!types.contains(type)) continue;
      try {
        final blob = await item.getType(type).toDart;
        final bytes = (await blob.arrayBuffer().toDart).toDart.asUint8List();
        if (bytes.isEmpty) continue;
        return PickedImage(bytes);
      } on Object catch (e) {
        throw _clipboardError(e);
      }
    }
  }
  throw const MediaIoException(MediaErrorCode.clipboardEmpty);
}

/// The DOMException name of [e] when it is one ('NotAllowedError' …), else its text.
String _errorName(Object e) {
  try {
    final name = (e as JSObject).getProperty<JSAny?>('name'.toJS);
    if (name != null && name.isA<JSString>()) return (name as JSString).toDart;
  } on Object {
    // not a JS object
  }
  return e.toString();
}

MediaIoException _clipboardError(Object e) {
  final name = _errorName(e);
  return MediaIoException(
    name.contains('NotAllowedError') || name.contains('SecurityError')
        ? MediaErrorCode.clipboardDenied
        : MediaErrorCode.clipboardEmpty,
    detail: 'clipboard read',
    cause: name,
  );
}

final class BrowserImageCodec implements ImageCodec {
  const BrowserImageCodec();

  @override
  Future<DecodedImage?> decode(
    Uint8List bytes, {
    required int maxLongSide,
  }) async {
    final blob = web.Blob(<JSAny>[bytes.toJS].toJS);
    final web.ImageBitmap bitmap;
    try {
      bitmap = await _bitmapOf(blob);
    } on Object {
      return null; // not an image the browser can decode
    }
    try {
      final w = bitmap.width, h = bitmap.height;
      if (w <= 0 || h <= 0) return null;
      final scale = math.min(1.0, maxLongSide / math.max(w, h));
      final tw = math.max(1, (w * scale).round());
      final th = math.max(1, (h * scale).round());
      final surface = _Surface.create(tw, th)..draw(bitmap);
      return _BrowserImage(surface, hasAlpha: surface.hasAlpha());
    } finally {
      bitmap.close();
    }
  }

  static Future<web.ImageBitmap> _bitmapOf(web.Blob blob) async {
    try {
      return await web.window
          .createImageBitmap(
            blob,
            web.ImageBitmapOptions(imageOrientation: 'from-image'),
          )
          .toDart;
    } on Object catch (e) {
      // an engine without the 'from-image' value applies the orientation by default
      if (!_errorName(e).contains('TypeError')) rethrow;
      return web.window.createImageBitmap(blob).toDart;
    }
  }
}

final class _BrowserImage implements DecodedImage {
  _BrowserImage(this._surface, {required this.hasAlpha});

  final _Surface _surface;

  @override
  final bool hasAlpha;

  @override
  int get width => _surface.width;

  @override
  int get height => _surface.height;

  @override
  Future<Uint8List> encodeJpeg(double quality) =>
      _surface.encode('image/jpeg', quality);

  @override
  Future<Uint8List> encodePng() => _surface.encode('image/png', null);

  @override
  Future<DecodedImage> scaled(double factor) async {
    final w = math.max(1, (width * factor).round());
    final h = math.max(1, (height * factor).round());
    final next = _Surface.create(w, h)..draw(_surface.source);
    return _BrowserImage(next, hasAlpha: hasAlpha);
  }

  @override
  void dispose() => _surface.release();
}

/// An OffscreenCanvas, or a <canvas> where there is none.
final class _Surface {
  _Surface._(this.width, this.height, this._offscreen, this._element);

  factory _Surface.create(int width, int height) {
    if (globalContext.has('OffscreenCanvas')) {
      return _Surface._(
        width,
        height,
        web.OffscreenCanvas(width, height),
        null,
      );
    }
    final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement
      ..width = width
      ..height = height;
    return _Surface._(width, height, null, canvas);
  }

  final int width, height;
  final web.OffscreenCanvas? _offscreen;
  final web.HTMLCanvasElement? _element;

  /// What another surface draws from.
  JSObject get source => (_offscreen ?? _element)!;

  JSObject get _context2d {
    final JSObject? ctx = _offscreen != null
        ? _offscreen.getContext('2d')
        : _element!.getContext('2d');
    if (ctx == null) throw StateError('no 2d canvas context');
    return ctx;
  }

  /// Draws [image] scaled to the whole surface (high quality smoothing).
  void draw(JSObject image) {
    final ctx = _context2d
      ..setProperty('imageSmoothingEnabled'.toJS, true.toJS)
      ..setProperty('imageSmoothingQuality'.toJS, 'high'.toJS);
    ctx.callMethodVarArgs<JSAny?>('drawImage'.toJS, [
      image,
      0.toJS,
      0.toJS,
      width.toJS,
      height.toJS,
    ]);
  }

  /// Some pixel has alpha < 255.
  bool hasAlpha() {
    final data = _context2d.callMethodVarArgs<web.ImageData>(
      'getImageData'.toJS,
      [0.toJS, 0.toJS, width.toJS, height.toJS],
    );
    final px = data.data.toDart;
    for (var i = 3; i < px.length; i += 4) {
      if (px[i] < 255) return true;
    }
    return false;
  }

  Future<Uint8List> encode(String type, double? quality) async {
    final web.Blob blob;
    if (_offscreen case final canvas?) {
      blob = await canvas
          .convertToBlob(
            quality == null
                ? web.ImageEncodeOptions(type: type)
                : web.ImageEncodeOptions(type: type, quality: quality),
          )
          .toDart;
    } else {
      final done = Completer<web.Blob>();
      void onBlob(web.Blob? b) => b == null
          ? done.completeError(StateError('canvas.toBlob gave nothing'))
          : done.complete(b);
      final canvas = _element!;
      if (quality == null) {
        canvas.toBlob(onBlob.toJS, type);
      } else {
        canvas.toBlob(onBlob.toJS, type, quality.toJS);
      }
      blob = await done.future;
    }
    return (await blob.arrayBuffer().toDart).toDart.asUint8List();
  }

  /// Lets the pixels go (a 0 × 0 canvas holds none).
  void release() {
    if (_offscreen case final c?) {
      c
        ..width = 0
        ..height = 0;
    }
    if (_element case final c?) {
      c
        ..width = 0
        ..height = 0;
    }
  }
}
