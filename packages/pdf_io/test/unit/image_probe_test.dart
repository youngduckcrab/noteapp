// PDF T25a — image headers (m5-7/06-pdf 6.2.4 image_probe.dart): the fixed JPEG samples (S-3),
// PNG alpha / palette, cut bytes, GIF / WebP sizes and the JPEG fast path rule.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/src/export/image_probe.dart';
import 'package:pdf_io/src/tuning.dart';
import 'package:pdf_io/testing.dart';

import '../support/object_fixtures.dart';

void main() {
  group('JPEG samples (S-3)', () {
    test('baseline: SOF0, 8 bit, 3 components, fast path', () {
      final bytes = PdfObjectFixtures.jpegBaseline64x48;
      final p = PdfImageProbe.parse(bytes);
      expect(p.format, PdfImageFormat.jpeg);
      expect((p.width, p.height), (64, 48));
      expect(
        (p.jpegSofType, p.jpegPrecision, p.jpegComponents, p.jpegAdobe),
        (0, 8, 3, false),
      );
      expect(p.orientation, 1);
      expect(p.mayHaveAlpha, isFalse);
      expect(p.jpegFastPath(bytes.length), isTrue);
    });

    test('progressive: SOF2, fast path', () {
      final bytes = PdfObjectFixtures.jpegProgressive64x48;
      final p = PdfImageProbe.parse(bytes);
      expect(
        (p.width, p.height, p.jpegSofType, p.jpegComponents),
        (64, 48, 2, 3),
      );
      expect(p.jpegFastPath(bytes.length), isTrue);
    });

    test('gray: SOF0, 1 component, fast path', () {
      final bytes = PdfObjectFixtures.jpegGray64x48;
      final p = PdfImageProbe.parse(bytes);
      expect(
        (p.width, p.height, p.jpegSofType, p.jpegComponents),
        (64, 48, 0, 1),
      );
      expect(p.jpegFastPath(bytes.length), isTrue);
    });

    test('EXIF 6: stored 64 × 48, shown 48 × 64, slow path', () {
      final bytes = PdfObjectFixtures.jpegExif6_64x48;
      final p = PdfImageProbe.parse(bytes);
      expect(p.orientation, 6);
      expect((p.width, p.height), (64, 48));
      expect((p.orientedWidth, p.orientedHeight), (48, 64));
      expect(p.jpegFastPath(bytes.length), isFalse);
    });

    test('Adobe CMYK: APP14, 4 components, slow path (S-9)', () {
      final bytes = PdfObjectFixtures.jpegAdobeCmyk64x48;
      final p = PdfImageProbe.parse(bytes);
      expect(p.jpegAdobe, isTrue);
      expect(p.jpegComponents, 4);
      expect((p.width, p.height), (64, 48));
      expect(p.jpegFastPath(bytes.length), isFalse);
    });

    test('over exportJpegInlineMaxBytes → slow path', () {
      final big = paddedJpeg(
        PdfObjectFixtures.jpegBaseline64x48,
        PdfTuning.exportJpegInlineMaxBytes,
      );
      expect(big.length, greaterThan(PdfTuning.exportJpegInlineMaxBytes));
      final p = PdfImageProbe.parse(big);
      expect((p.width, p.height, p.jpegSofType), (64, 48, 0));
      expect(p.jpegFastPath(big.length), isFalse);
      expect(p.jpegFastPath(PdfTuning.exportJpegInlineMaxBytes), isTrue);
    });

    test('other SOF types and precisions are not the fast path', () {
      final base = PdfObjectFixtures.jpegBaseline64x48;
      final sof = _indexOfMarker(base, 0xC0);
      for (final (marker, precision) in [
        (0xC1, 8), // extended — still fast
        (0xC3, 8), // lossless
        (0xC9, 8), // arithmetic
        (0xC0, 12), // 12 bit
      ]) {
        final b = Uint8List.fromList(base)
          ..[sof + 1] = marker
          ..[sof + 4] = precision;
        final p = PdfImageProbe.parse(b);
        expect(p.jpegSofType, marker - 0xC0);
        expect(p.jpegPrecision, precision);
        expect(
          p.jpegFastPath(b.length),
          marker == 0xC1 && precision == 8,
          reason: 'SOF${marker - 0xC0} / $precision bit',
        );
      }
    });

    test('cut before SOF → no size, not the fast path', () {
      final base = PdfObjectFixtures.jpegBaseline64x48;
      final cut = base.sublist(0, _indexOfMarker(base, 0xC0) + 3);
      final p = PdfImageProbe.parse(cut);
      expect(p.format, PdfImageFormat.jpeg);
      expect(p.hasSize, isFalse);
      expect(p.jpegFastPath(cut.length), isFalse);
    });
  });

  group('PNG', () {
    test('RGB: colour type 2, no alpha', () {
      final p = PdfImageProbe.parse(PdfObjectFixtures.png());
      expect(p.format, PdfImageFormat.png);
      expect((p.width, p.height, p.pngColorType), (64, 48, 2));
      expect(p.mayHaveAlpha, isFalse);
      expect(p.jpegFastPath(100), isFalse);
    });

    test('RGBA: colour type 6 may have alpha', () {
      final p = PdfImageProbe.parse(
        PdfObjectFixtures.png(width: 7, height: 3, alpha: true),
      );
      expect((p.width, p.height, p.pngColorType), (7, 3, 6));
      expect(p.mayHaveAlpha, isTrue);
    });

    test('palette with and without tRNS', () {
      final plain = _pngHeader(5, 4, colorType: 3, chunks: ['PLTE']);
      final trns = _pngHeader(5, 4, colorType: 3, chunks: ['PLTE', 'tRNS']);
      final p1 = PdfImageProbe.parse(plain), p2 = PdfImageProbe.parse(trns);
      expect(
        (p1.pngColorType, p1.pngHasTrns, p1.mayHaveAlpha),
        (3, false, false),
      );
      expect(
        (p2.pngColorType, p2.pngHasTrns, p2.mayHaveAlpha),
        (3, true, true),
      );
      expect((p2.width, p2.height), (5, 4));
    });

    test('cut inside IHDR → no size', () {
      final cut = PdfObjectFixtures.png().sublist(0, 20);
      final p = PdfImageProbe.parse(cut);
      expect(p.format, PdfImageFormat.png);
      expect(p.hasSize, isFalse);
    });

    test('big sizes read without 64-bit math', () {
      final p = PdfImageProbe.parse(_pngHeader(60000, 40000, colorType: 2));
      expect((p.width, p.height), (60000, 40000));
    });
  });

  test('GIF and WebP sizes, unknown bytes', () {
    final gif = Uint8List.fromList([
      ...'GIF89a'.codeUnits,
      0x2C, 0x01, 0x90, 0x00, 0, 0, 0, //
    ]);
    final g = PdfImageProbe.parse(gif);
    expect((g.format, g.width, g.height), (PdfImageFormat.gif, 300, 144));
    expect(g.mayHaveAlpha, isTrue);

    final vp8x = Uint8List(30)
      ..setRange(0, 4, 'RIFF'.codeUnits)
      ..setRange(8, 12, 'WEBP'.codeUnits)
      ..setRange(12, 16, 'VP8X'.codeUnits)
      ..[20] =
          0x10 // alpha flag
      ..[24] =
          0x3F // width − 1 = 0x013F → 320
      ..[25] = 0x01
      ..[27] =
          0xEF // height − 1 = 0xEF → 240
      ..[28] = 0x00;
    final w = PdfImageProbe.parse(vp8x);
    expect(
      (w.format, w.width, w.height, w.webpHasAlpha),
      (PdfImageFormat.webp, 320, 240, true),
    );

    final u = PdfImageProbe.parse(Uint8List.fromList([1, 2, 3, 4, 5]));
    expect(u.format, PdfImageFormat.unknown);
    expect(u.hasSize, isFalse);
    expect(u.mayHaveAlpha, isTrue, reason: 'unknown formats are scanned');
    expect(PdfImageProbe.parse(Uint8List(0)).format, PdfImageFormat.unknown);
  });
}

int _indexOfMarker(Uint8List b, int marker) {
  for (var i = 0; i + 1 < b.length; i++) {
    if (b[i] == 0xFF && b[i + 1] == marker) return i;
  }
  throw StateError('marker ${marker.toRadixString(16)} not found');
}

/// Signature + IHDR + empty [chunks] (+ IDAT) — headers only (not decodable).
Uint8List _pngHeader(
  int width,
  int height, {
  required int colorType,
  List<String> chunks = const [],
}) {
  final b = BytesBuilder()
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, colorType);
  void chunk(String type, Uint8List data) {
    b
      ..add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List())
      ..add(type.codeUnits)
      ..add(data)
      ..add(const [0, 0, 0, 0]); // CRC not checked by the probe
  }

  chunk('IHDR', ihdr.buffer.asUint8List());
  for (final c in chunks) {
    chunk(c, Uint8List(3));
  }
  chunk('IDAT', Uint8List(0));
  return b.takeBytes();
}
