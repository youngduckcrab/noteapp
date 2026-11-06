// Image headers without decoding (m5-7/06-pdf 6.12.2; 8.2 T35a): JPEG SOF type / precision /
// components, EXIF orientation and GPS, APP1 ranges and their lossless removal, Adobe APP14;
// PNG IHDR and tRNS; GIF; WebP VP8 / VP8L; cut and unknown bytes.
//
// Samples: package:image encodes made here, and small files in test/support/fixtures/ made with
// Pillow 12.3 (48×32 / 60×40 / 24×16 / 40×30 gradients): img_gray.jpg (mode L), img_progressive.jpg
// (progressive=True), img_cmyk_adobe.jpg (mode CMYK — Pillow writes Adobe APP14),
// img_exif6.jpg (EXIF orientation 6), img_exif_gps_xmp.jpg (EXIF orientation 1 + GPS IFD +
// an XMP APP1), img_palette_trns.png (P mode, transparency 0), img_lossy.webp (VP8),
// img_alpha.webp (lossless RGBA — VP8L).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:media_io/src/image/image_header.dart';

Uint8List fixture(String name) =>
    File('test/support/fixtures/$name').readAsBytesSync();

img.Image gradient(int w, int h, {int channels = 3}) {
  final image = img.Image(width: w, height: h, numChannels: channels);
  for (final p in image) {
    p
      ..r = p.x * 255 ~/ (w - 1)
      ..g = p.y * 255 ~/ (h - 1)
      ..b = 128;
    if (channels == 4) p.a = p.x == 0 ? 0 : 255;
  }
  return image;
}

void main() {
  group('JPEG', () {
    test('baseline (package:image): SOF0, 8-bit, 3 components, size, orientation 1', () {
      final h = ImageHeader.parse(img.encodeJpg(gradient(320, 200)));
      expect(h.format, ImageFormat.jpeg);
      expect(h.jpegSofType, 0);
      expect(h.jpegPrecision, 8);
      expect(h.jpegComponents, 3);
      expect((h.width, h.height), (320, 200));
      expect(h.orientation, 1);
      expect(h.jpegAdobe, isFalse);
      expect(h.jpegApp1, isEmpty);
      expect(h.longSide, 320);
      expect(h.mayHaveAlpha, isFalse);
      expect(h.complete, isTrue);
    });

    test('gray (mode L): 1 component', () {
      final h = ImageHeader.parse(fixture('img_gray.jpg'));
      expect(h.jpegComponents, 1);
      expect((h.width, h.height), (48, 32));
      expect(h.jpegSofType, 0);
    });

    test('progressive: SOF2', () {
      final h = ImageHeader.parse(fixture('img_progressive.jpg'));
      expect(h.jpegSofType, 2);
      expect(h.jpegComponents, 3);
    });

    test('CMYK: Adobe APP14, 4 components', () {
      final h = ImageHeader.parse(fixture('img_cmyk_adobe.jpg'));
      expect(h.jpegAdobe, isTrue);
      expect(h.jpegComponents, 4);
      expect(h.jpegAdobeTransform, isNotNull);
    });

    test('EXIF orientation 6: the shown size swaps', () {
      final h = ImageHeader.parse(fixture('img_exif6.jpg'));
      expect(h.orientation, 6);
      expect((h.width, h.height), (60, 40));
      expect((h.orientedWidth, h.orientedHeight), (40, 60));
      expect(h.jpegApp1, hasLength(1));
      expect(h.exifHasGps, isFalse);
    });

    test('EXIF with GPS + XMP: two APP1 ranges; stripping them keeps every other byte', () {
      final bytes = fixture('img_exif_gps_xmp.jpg');
      final h = ImageHeader.parse(bytes);
      expect(h.orientation, 1);
      expect(h.exifHasGps, isTrue);
      expect(h.jpegApp1, hasLength(2));
      final stripped = stripJpegApp1(bytes, h);
      var removed = 0;
      for (final s in h.jpegApp1) {
        expect(bytes[s.start], 0xFF);
        expect(bytes[s.start + 1], 0xE1);
        removed += s.end - s.start;
      }
      expect(stripped.length, bytes.length - removed);
      final again = ImageHeader.parse(stripped);
      expect(again.jpegApp1, isEmpty);
      expect(again.exifHasGps, isFalse);
      expect((again.width, again.height), (48, 32));
      expect(String.fromCharCodes(stripped).contains('Exif'), isFalse);
      expect(String.fromCharCodes(stripped).contains('xmpmeta'), isFalse);
      // the bytes before the first APP1 and after the last are the same
      expect(
        stripped.sublist(0, h.jpegApp1.first.start),
        bytes.sublist(0, h.jpegApp1.first.start),
      );
      final tail = bytes.length - h.jpegApp1.last.end;
      expect(
        stripped.sublist(stripped.length - tail),
        bytes.sublist(h.jpegApp1.last.end),
      );
      // no APP1 → the same object
      expect(stripJpegApp1(stripped, again), same(stripped));
    });

    test('package:image EXIF orientation is read (big-endian / little-endian TIFF)', () {
      final image = gradient(30, 20)..exif.imageIfd.orientation = 8;
      final h = ImageHeader.parse(img.encodeJpg(image));
      expect(h.orientation, 8);
      expect((h.orientedWidth, h.orientedHeight), (20, 30));
    });

    test(
      'cut before SOF: format known, size null; cut right after SOI: same',
      () {
        final bytes = fixture('img_exif_gps_xmp.jpg');
        final h = ImageHeader.parse(Uint8List.sublistView(bytes, 0, 40));
        expect(h.format, ImageFormat.jpeg);
        expect(h.width, isNull);
        expect(h.longSide, isNull);
        expect(
          ImageHeader.parse(Uint8List.fromList([0xFF, 0xD8, 0xFF])).width,
          isNull,
        );
      },
    );
  });

  group('PNG', () {
    test('RGB: colour type 2, no alpha', () {
      final h = ImageHeader.parse(img.encodePng(gradient(64, 80)));
      expect(h.format, ImageFormat.png);
      expect((h.width, h.height), (64, 80));
      expect(h.complete, isTrue);
      expect(h.pngColorType, 2);
      expect(h.pngBitDepth, 8);
      expect(h.mayHaveAlpha, isFalse);
    });

    test('RGBA: colour type 6, may have alpha', () {
      final h = ImageHeader.parse(img.encodePng(gradient(16, 8, channels: 4)));
      expect(h.pngColorType, 6);
      expect(h.mayHaveAlpha, isTrue);
    });

    test('palette + tRNS: may have alpha', () {
      final h = ImageHeader.parse(fixture('img_palette_trns.png'));
      expect(h.pngColorType, 3);
      expect(h.pngHasTrns, isTrue);
      expect(h.mayHaveAlpha, isTrue);
      expect((h.width, h.height), (24, 16));
    });

    test('cut after IHDR: size known, not complete', () {
      final bytes = img.encodePng(gradient(64, 64));
      final h = ImageHeader.parse(Uint8List.sublistView(bytes, 0, 60));
      expect((h.width, h.height), (64, 64));
      expect(h.complete, isFalse);
    });

    test('cut IHDR → format only', () {
      final bytes = img.encodePng(gradient(4, 4));
      final h = ImageHeader.parse(Uint8List.sublistView(bytes, 0, 20));
      expect(h.format, ImageFormat.png);
      expect(h.width, isNull);
    });
  });

  group('GIF · WebP · others', () {
    test('GIF: logical screen size', () {
      final h = ImageHeader.parse(img.encodeGif(gradient(33, 17)));
      expect(h.format, ImageFormat.gif);
      expect((h.width, h.height), (33, 17));
    });

    test('WebP lossy (VP8) and lossless with alpha (VP8L)', () {
      final lossy = ImageHeader.parse(fixture('img_lossy.webp'));
      expect(lossy.format, ImageFormat.webp);
      expect((lossy.width, lossy.height), (40, 30));
      expect(lossy.webpHasAlpha, isFalse);
      final alpha = ImageHeader.parse(fixture('img_alpha.webp'));
      expect((alpha.width, alpha.height), (40, 30));
      expect(alpha.webpHasAlpha, isTrue);
    });

    test('HEIF brand → heif (size from the platform decoder)', () {
      final bytes = Uint8List.fromList([
        0,
        0,
        0,
        24,
        ...'ftypheic'.codeUnits,
        0,
        0,
        0,
        0,
        ...'mif1heic'.codeUnits,
      ]);
      expect(ImageHeader.parse(bytes).format, ImageFormat.heif);
    });

    test('unknown and empty bytes', () {
      expect(ImageHeader.parse(Uint8List(0)).format, ImageFormat.unknown);
      expect(
        ImageHeader.parse(Uint8List.fromList('hello world!'.codeUnits)).format,
        ImageFormat.unknown,
      );
    });
  });
}
