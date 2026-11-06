// The image import rules (m5-7/06-pdf 6.12.2, 6.12.3; 8.2 T35a — M-3, S-9) with the VM codec
// (package:image) and a counting codec: the fast paths (APP1 removed byte for byte, PNG as is),
// the slow path (EXIF baked, long side 2048, CMYK → RGB, alpha → PNG, PNG stays PNG), the
// quality steps 0.85 → 0.75 → 0.6 and the downscale rounds, tooLarge, decodeFailed and
// unsupportedFormat. Fixtures: see image_header_test.dart.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:media_io/src/errors.dart';
import 'package:media_io/src/image/image_codec.dart';
import 'package:media_io/src/image/image_codec_io.dart';
import 'package:media_io/src/image/image_header.dart';
import 'package:media_io/src/image/image_normalizer.dart';

Uint8List fixture(String name) =>
    File('test/support/fixtures/$name').readAsBytesSync();

img.Image gradient(int w, int h, {int channels = 3, bool hole = false}) {
  final image = img.Image(width: w, height: h, numChannels: channels);
  for (final p in image) {
    p
      ..r = p.x * 255 ~/ max(1, w - 1)
      ..g = p.y * 255 ~/ max(1, h - 1)
      ..b = 128;
    if (channels == 4) p.a = hole && p.x == 0 && p.y == 0 ? 0 : 255;
  }
  return image;
}

img.Image noise(int w, int h, {int seed = 7}) {
  final r = Random(seed);
  final image = img.Image(width: w, height: h);
  for (final p in image) {
    p
      ..r = r.nextInt(256)
      ..g = r.nextInt(256)
      ..b = r.nextInt(256);
  }
  return image;
}

Matcher throwsMedia(MediaErrorCode code) =>
    throwsA(isA<MediaIoException>().having((e) => e.code, 'code', code));

const vm = ImageNormalizer(codec: IoImageCodec(useIsolate: false));

void main() {
  group('fast path (6.12.2)', () {
    test('JPEG with EXIF (GPS) + XMP, orientation 1: APP1 removed, the pixels the same', () async {
      final bytes = fixture('img_exif_gps_xmp.jpg');
      final n = await vm.normalize(bytes);
      expect(n.path, NormalizePath.fastJpeg);
      expect(n.mimeType, 'image/jpeg');
      expect((n.width, n.height), (48, 32));
      final h = ImageHeader.parse(n.bytes);
      expect(h.jpegApp1, isEmpty);
      expect(h.exifHasGps, isFalse);
      expect(n.bytes.length, lessThan(bytes.length));
      final before = img.decodeJpg(bytes)!, after = img.decodeJpg(n.bytes)!;
      expect(after.width, before.width);
      expect(after.getBytes(), before.getBytes());
    });

    test('gray (1 component) and progressive JPEGs go as they are', () async {
      for (final name in ['img_gray.jpg', 'img_progressive.jpg']) {
        final bytes = fixture(name);
        final n = await vm.normalize(bytes);
        expect(n.path, NormalizePath.fastJpeg, reason: name);
        expect(n.bytes, bytes, reason: name);
      }
    });

    test('PNG (with alpha) ≤ 2048 and ≤ 8 MiB: the same bytes', () async {
      final bytes = img.encodePng(gradient(300, 200, channels: 4, hole: true));
      final n = await vm.normalize(bytes);
      expect(n.path, NormalizePath.fastPng);
      expect(n.mimeType, 'image/png');
      expect(n.bytes, same(bytes));
      expect((n.width, n.height), (300, 200));
    });
  });

  group('slow path (6.12.3)', () {
    test('4000 × 3000 JPEG → 2048 × 1536 JPEG (in an isolate)', () async {
      const normalizer = ImageNormalizer(codec: IoImageCodec());
      final n = await normalizer.normalize(
        img.encodeJpg(gradient(4000, 3000), quality: 90),
      );
      expect(n.path, NormalizePath.slow);
      expect(n.mimeType, 'image/jpeg');
      expect((n.width, n.height), (2048, 1536));
      final h = ImageHeader.parse(n.bytes);
      expect((h.width, h.height), (2048, 1536));
    });

    test('EXIF 6 → the turned size, orientation 1, no EXIF left', () async {
      final n = await vm.normalize(fixture('img_exif6.jpg'));
      expect(n.path, NormalizePath.slow);
      expect((n.width, n.height), (40, 60));
      final h = ImageHeader.parse(n.bytes);
      expect((h.width, h.height), (40, 60));
      expect(h.orientation, 1);
      expect(h.jpegApp1, isEmpty);
    });

    test(
      'package:image EXIF orientation 6 on a bigger photo → turned and fitted',
      () async {
        final photo = gradient(3000, 2000)..exif.imageIfd.orientation = 6;
        final n = await vm.normalize(img.encodeJpg(photo, quality: 80));
        expect((n.width, n.height), (1365, 2048));
      },
    );

    test(
      'CMYK (Adobe APP14) JPEG → slow path, RGB JPEG without APP14',
      () async {
        final n = await vm.normalize(fixture('img_cmyk_adobe.jpg'));
        expect(n.path, NormalizePath.slow);
        expect(n.mimeType, 'image/jpeg');
        final h = ImageHeader.parse(n.bytes);
        expect(h.jpegAdobe, isFalse);
        expect(h.jpegComponents, 3);
        expect((h.width, h.height), (48, 32));
      },
    );

    test('a long side over 2048 with alpha → PNG 2048 wide, the transparent pixel kept', () async {
      final n = await vm.normalize(
        img.encodePng(gradient(2500, 100, channels: 4, hole: true)),
      );
      expect(n.path, NormalizePath.slow);
      expect(n.mimeType, 'image/png');
      expect((n.width, n.height), (2048, 82));
      final out = img.decodePng(n.bytes)!;
      expect(out.getPixel(0, 0).a, lessThan(255));
    });

    test('an opaque big PNG stays PNG (screenshots), fitted to 2048', () async {
      final n = await vm.normalize(img.encodePng(gradient(3000, 1200)));
      expect(n.mimeType, 'image/png');
      expect((n.width, n.height), (2048, 819));
    });

    test(
      'a palette PNG with tRNS but every pixel opaque → still PNG',
      () async {
        final n = await vm.normalize(fixture('img_palette_trns.png'));
        expect(n.mimeType, 'image/png');
      },
    );

    test('an opaque GIF → JPEG; a WebP with alpha → PNG', () async {
      final gif = await vm.normalize(img.encodeGif(gradient(40, 20)));
      expect(gif.path, NormalizePath.slow);
      expect(gif.mimeType, 'image/jpeg');
      expect((gif.width, gif.height), (40, 20));
      final webp = await vm.normalize(fixture('img_alpha.webp'));
      expect(webp.mimeType, 'image/png');
      expect((webp.width, webp.height), (40, 30));
    });

    test('a 12 MB noise JPEG (≤ 2048) → re-encoded ≤ 8 MiB', () async {
      final bytes = img.encodeJpg(noise(2048, 1536), quality: 100);
      expect(bytes.length, greaterThan(12 * 1000 * 1000));
      final n = await vm.normalize(bytes);
      expect(n.path, NormalizePath.slow);
      expect(n.mimeType, 'image/jpeg');
      expect(n.bytes.length, lessThanOrEqualTo(8 * 1024 * 1024));
      expect((n.width, n.height), (2048, 1536));
    });

    test('the quality steps on the real codec: a tight limit needs a lower quality', () async {
      final bytes = img.encodeJpg(noise(800, 600), quality: 100);
      final counting = CountingCodec(const IoImageCodec(useIsolate: false));
      final q85 = (await (await counting.inner.decode(
        bytes,
        maxLongSide: 2048,
      ))!.encodeJpeg(0.85)).length;
      final n = await ImageNormalizer(
        codec: counting,
        maxBytes: q85 - 1,
      ).normalize(bytes);
      expect(counting.log.take(2), ['jpeg 0.85 800x600', 'jpeg 0.75 800x600']);
      expect(n.bytes.length, lessThan(q85));
    });
  });

  group('limits and failures', () {
    test(
      'JPEG steps 0.85 → 0.75 → 0.6, then × 0.85 at 0.6 six times → tooLarge',
      () async {
        final codec = FakeCodec(
          width: 2000,
          height: 1000,
          alpha: false,
          size: (_) => 2000,
        );
        await expectLater(
          ImageNormalizer(
            codec: codec,
            maxBytes: 1000,
          ).normalize(Uint8List.fromList([1, 2, 3])),
          throwsMedia(MediaErrorCode.tooLarge),
        );
        expect(codec.log, [
          'jpeg 0.85 2000x1000',
          'jpeg 0.75 2000x1000',
          'jpeg 0.6 2000x1000',
          'scale 0.85',
          'jpeg 0.6 1700x850',
          'scale 0.85',
          'jpeg 0.6 1445x723',
          'scale 0.85',
          'jpeg 0.6 1228x615',
          'scale 0.85',
          'jpeg 0.6 1044x523',
          'scale 0.85',
          'jpeg 0.6 887x445',
          'scale 0.85',
          'jpeg 0.6 754x378',
        ]);
        expect(codec.disposed, codec.made);
      },
    );

    test(
      'PNG: no quality steps — × 0.85 rounds; the first that fits wins',
      () async {
        final codec = FakeCodec(
          width: 2000,
          height: 1000,
          alpha: true,
          size: (w) => w > 1500 ? 2000 : 500,
        );
        final n = await ImageNormalizer(
          codec: codec,
          maxBytes: 1000,
        ).normalize(Uint8List(3));
        expect(codec.log, [
          'png 2000x1000',
          'scale 0.85',
          'png 1700x850',
          'scale 0.85',
          'png 1445x723',
        ]);
        expect(n.mimeType, 'image/png');
        expect((n.width, n.height), (1445, 723));
        expect(codec.disposed, codec.made);
      },
    );

    test('a JPEG fitting at 0.75 stops there', () async {
      var calls = 0;
      final codec = FakeCodec(
        width: 100,
        height: 100,
        alpha: false,
        size: (_) => ++calls == 1 ? 2000 : 100,
      );
      final n = await ImageNormalizer(
        codec: codec,
        maxBytes: 1000,
      ).normalize(Uint8List(3));
      expect(codec.log, ['jpeg 0.85 100x100', 'jpeg 0.75 100x100']);
      expect(n.bytes.length, 100);
    });

    test('a cut / broken JPEG → decodeFailed; bytes of no known format → unsupportedFormat', () async {
      final broken = Uint8List.fromList([
        0xFF,
        0xD8,
        0xFF,
        0xE0,
        0,
        4,
        1,
        2,
        ...List.filled(64, 0x33),
      ]);
      await expectLater(
        vm.normalize(broken),
        throwsMedia(MediaErrorCode.decodeFailed),
      );
      await expectLater(
        vm.normalize(Uint8List.fromList(List.filled(64, 0x42))),
        throwsMedia(MediaErrorCode.unsupportedFormat),
      );
      final cut = Uint8List.sublistView(img.encodePng(gradient(64, 64)), 0, 60);
      await expectLater(
        vm.normalize(cut),
        throwsMedia(MediaErrorCode.decodeFailed),
      );
    });

    test('a JPEG over 8 MiB or with a long side over 2048 does not take the fast path', () async {
      final codec = FakeCodec(
        width: 10,
        height: 10,
        alpha: false,
        size: (_) => 10,
      );
      final wide = img.encodeJpg(gradient(2100, 10));
      expect(
        (await ImageNormalizer(codec: codec).normalize(wide)).path,
        NormalizePath.slow,
      );
      final small = img.encodeJpg(gradient(10, 10));
      expect(
        (await ImageNormalizer(
          codec: codec,
          maxBytes: small.length - 1,
        ).normalize(small)).path,
        NormalizePath.slow,
      );
      expect(
        (await ImageNormalizer(codec: codec).normalize(small)).path,
        NormalizePath.fastJpeg,
      );
    });
  });
}

/// Logs what the normalizer asks of a real codec.
final class CountingCodec implements ImageCodec {
  CountingCodec(this.inner);
  final ImageCodec inner;
  final List<String> log = [];

  @override
  Future<DecodedImage?> decode(
    Uint8List bytes, {
    required int maxLongSide,
  }) async {
    final d = await inner.decode(bytes, maxLongSide: maxLongSide);
    return d == null ? null : _Counting(this, d);
  }
}

final class _Counting implements DecodedImage {
  _Counting(this.c, this.d);
  final CountingCodec c;
  final DecodedImage d;

  @override
  int get width => d.width;
  @override
  int get height => d.height;
  @override
  bool get hasAlpha => d.hasAlpha;

  @override
  Future<Uint8List> encodeJpeg(double quality) {
    c.log.add('jpeg $quality ${width}x$height');
    return d.encodeJpeg(quality);
  }

  @override
  Future<Uint8List> encodePng() {
    c.log.add('png ${width}x$height');
    return d.encodePng();
  }

  @override
  Future<DecodedImage> scaled(double factor) async {
    c.log.add('scale $factor');
    return _Counting(c, await d.scaled(factor));
  }

  @override
  void dispose() => d.dispose();
}

/// A codec that only reports sizes: every encode returns `size(width)` bytes.
final class FakeCodec implements ImageCodec {
  FakeCodec({
    required this.width,
    required this.height,
    required this.alpha,
    required this.size,
  });

  final int width, height;
  final bool alpha;
  final int Function(int width) size;
  final List<String> log = [];
  int made = 0, disposed = 0;

  @override
  Future<DecodedImage?> decode(
    Uint8List bytes, {
    required int maxLongSide,
  }) async {
    made++;
    return _FakeImage(this, width, height);
  }
}

final class _FakeImage implements DecodedImage {
  _FakeImage(this.c, this.width, this.height);
  final FakeCodec c;

  @override
  final int width, height;

  @override
  bool get hasAlpha => c.alpha;

  @override
  Future<Uint8List> encodeJpeg(double quality) async {
    c.log.add('jpeg $quality ${width}x$height');
    return Uint8List(c.size(width));
  }

  @override
  Future<Uint8List> encodePng() async {
    c.log.add('png ${width}x$height');
    return Uint8List(c.size(width));
  }

  @override
  Future<DecodedImage> scaled(double factor) async {
    c.log.add('scale $factor');
    c.made++;
    return _FakeImage(
      c,
      max(1, (width * factor).round()),
      max(1, (height * factor).round()),
    );
  }

  @override
  void dispose() => c.disposed++;
}
