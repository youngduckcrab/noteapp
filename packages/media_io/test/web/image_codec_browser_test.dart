// The web image codec and the clipboard source in Chrome (m5-7/06-pdf 6.12.3, 6.12.4, 4.2.4 —
// 8.2 T35b): createImageBitmap + canvas downscale, JPEG / PNG results and their size, the alpha
// test, EXIF orientation applied by the browser, the normalizer's slow path on this codec;
// supportedImageSources() on the web and the clipboard source only when navigator.clipboard.read
// and ClipboardItem exist; navigator.clipboard.read() called before the pick Future is awaited
// (recorded on the JS side), its image bytes, no image → clipboardEmpty, NotAllowedError →
// clipboardDenied.
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:media_io/media_io.dart';
import 'package:media_io/src/errors.dart';
import 'package:media_io/src/image/image_codec_browser.dart';
import 'package:media_io/src/image/image_header.dart';
import 'package:media_io/src/image/image_normalizer.dart';
import 'package:media_io/src/image/image_picker_port.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:web/web.dart' as web;

Uint8List opaquePng(int w, int h) {
  final image = img.Image(width: w, height: h)
    ..clear(img.ColorRgb8(40, 120, 200));
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List alphaPng(int w, int h) {
  final image = img.Image(width: w, height: h, numChannels: 4)
    ..clear(img.ColorRgba8(200, 30, 30, 255));
  image.setPixel(1, 1, img.ColorRgba8(0, 0, 0, 0));
  return Uint8List.fromList(img.encodePng(image));
}

Matcher sizeOf(int w, int h) => isA<ImageHeader>()
    .having((x) => x.width, 'width', w)
    .having((x) => x.height, 'height', h);

/// Replaces navigator.clipboard.read with [read] for one test (an own property shadows the
/// prototype's method; deleting it restores the real one).
void fakeClipboardRead(JSPromise<JSAny?> Function() read) {
  final clipboard = web.window.navigator.clipboard as JSObject;
  clipboard.setProperty('read'.toJS, read.toJS);
  addTearDown(() => clipboard.delete('read'.toJS));
}

JSPromise<JSAny?> resolved(JSAny? value) => JSPromise<JSAny?>(
  ((JSFunction resolve, JSFunction reject) {
    resolve.callAsFunction(null, value);
  }).toJS,
);

JSPromise<JSAny?> rejected(JSAny error) => JSPromise<JSAny?>(
  ((JSFunction resolve, JSFunction reject) {
    reject.callAsFunction(null, error);
  }).toJS,
);

web.ClipboardItem itemOf(String type, Uint8List bytes) => web.ClipboardItem(
  JSObject()..setProperty(
    type.toJS,
    web.Blob(<JSAny>[bytes.toJS].toJS, web.BlobPropertyBag(type: type)),
  ),
);

void main() {
  group('BrowserImageCodec (6.12.3)', () {
    const codec = BrowserImageCodec();

    test('downscale on the canvas: long side 2048, JPEG / PNG of that size, no alpha', () async {
      final decoded = await codec.decode(
        opaquePng(2600, 900),
        maxLongSide: 2048,
      );
      expect(decoded, isNotNull);
      expect(decoded!.width, 2048);
      expect(decoded.height, 709); // 900 × 2048 / 2600 = 708.9
      expect(decoded.hasAlpha, isFalse);
      final jpeg = await decoded.encodeJpeg(0.85);
      expect(jpeg.sublist(0, 2), [0xFF, 0xD8]);
      expect(ImageHeader.parse(jpeg), sizeOf(2048, 709));
      final png = await decoded.encodePng();
      expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      expect(ImageHeader.parse(png), sizeOf(2048, 709));
      final half = await decoded.scaled(0.5);
      expect((half.width, half.height), (1024, 355));
      half.dispose();
      decoded.dispose();
    });

    test('never scales up; a transparent pixel is alpha', () async {
      final decoded = await codec.decode(alphaPng(100, 80), maxLongSide: 2048);
      expect((decoded!.width, decoded.height), (100, 80));
      expect(decoded.hasAlpha, isTrue);
      expect(ImageHeader.parse(await decoded.encodePng()), sizeOf(100, 80));
      decoded.dispose();
    });

    test('the browser applies the EXIF orientation (6 → turned)', () async {
      final image = img.Image(width: 40, height: 20)
        ..clear(img.ColorRgb8(0, 0, 0));
      image.exif.imageIfd.orientation = 6;
      final jpeg = Uint8List.fromList(img.encodeJpg(image));
      final decoded = await codec.decode(jpeg, maxLongSide: 2048);
      expect((decoded!.width, decoded.height), (20, 40));
      decoded.dispose();
    });

    test('bytes the browser cannot decode → null', () async {
      expect(
        await codec.decode(
          Uint8List.fromList(List.filled(64, 3)),
          maxLongSide: 2048,
        ),
        isNull,
      );
    });

    test(
      'the normalizer slow path on this codec: a big PNG stays PNG',
      () async {
        final n = await const ImageNormalizer(codec: BrowserImageCodec())
            .normalize(opaquePng(2600, 900));
        expect(n.path, NormalizePath.slow);
        expect(n.mimeType, 'image/png');
        expect((n.width, n.height), (2048, 709));
      },
    );
  });

  group('sources and the clipboard (4.2.4, 6.12.4)', () {
    test('web: photos, camera, files + clipboard (Chrome has both APIs)', () {
      expect(clipboardImageReadable(), isTrue);
      expect(supportedImageSources(), {
        core.ImageImportSource.photos,
        core.ImageImportSource.camera,
        core.ImageImportSource.files,
        core.ImageImportSource.clipboard,
      });
    });

    test('no ClipboardItem → no clipboard source', () {
      final saved = globalContext.getProperty<JSAny?>('ClipboardItem'.toJS);
      globalContext.setProperty('ClipboardItem'.toJS, null);
      addTearDown(() => globalContext.setProperty('ClipboardItem'.toJS, saved));
      expect(clipboardImageReadable(), isFalse);
      expect(
        supportedImageSources(),
        isNot(contains(core.ImageImportSource.clipboard)),
      );
    });

    test('navigator.clipboard.read() is called before the pick is awaited; the image bytes', () async {
      final png = alphaPng(12, 9);
      var calls = 0;
      fakeClipboardRead(() {
        calls++;
        return resolved(<JSAny>[itemOf('image/png', png)].toJS);
      });
      final pick = PluginImagePickerPort().pick(
        core.ImageImportSource.clipboard,
      );
      expect(calls, 1); // inside the same synchronous run (the user's tap)
      final picked = await pick;
      expect(picked!.bytes, png);
      expect(picked.name, isNull);
    });

    test('a clipboard without an image → clipboardEmpty', () async {
      fakeClipboardRead(
        () => resolved(
          <JSAny>[itemOf('text/plain', Uint8List.fromList('hello'.codeUnits))]
              .toJS,
        ),
      );
      await expectLater(
        readClipboardImage(),
        throwsA(
          isA<MediaIoException>().having(
            (e) => e.code,
            'code',
            MediaErrorCode.clipboardEmpty,
          ),
        ),
      );
    });

    test('NotAllowedError → clipboardDenied', () async {
      fakeClipboardRead(
        () => rejected(web.DOMException('read refused', 'NotAllowedError')),
      );
      await expectLater(
        readClipboardImage(),
        throwsA(
          isA<MediaIoException>().having(
            (e) => e.code,
            'code',
            MediaErrorCode.clipboardDenied,
          ),
        ),
      );
    });
  });
}
