// m5-7/03-ink 8.2 T35 (6.11.1, review S-4): the pixel size of PNG / JPEG bytes
// from the header only — PNG IHDR, baseline / progressive JPEG, a JPEG with an
// Exif segment before the SOF, segments that are not a SOF (DHT, JPG, DAC) and
// fill bytes skipped; cut-short or foreign bytes → null.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/src/image/image_header.dart';
import 'package:ink_engine/testing.dart';

import '../../support/jpeg_samples.dart';

Uint8List _b(List<int> bytes) => Uint8List.fromList(bytes);

/// A JPEG made of [segments] (marker byte, payload) between SOI and EOI.
Uint8List _jpeg(List<(int, List<int>)> segments, {int fill = 0}) => _b([
  0xFF, 0xD8, //
  for (final (marker, payload) in segments) ...[
    for (var i = 0; i < fill; i++) 0xFF,
    0xFF,
    marker,
    (payload.length + 2) >> 8,
    (payload.length + 2) & 0xFF,
    ...payload,
  ],
  0xFF, 0xD9,
]);

/// A SOF payload: precision 8, [h] × [w], one component.
List<int> _sof(int w, int h) => [
  8,
  h >> 8,
  h & 0xFF,
  w >> 8,
  w & 0xFF,
  1,
  1,
  0x11,
  0,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PNG IHDR', () async {
    final png = await testPngBytes(width: 37, height: 21);
    expect(readImagePixelSize(png), (width: 37, height: 21));
    final big = await testPngBytes(width: 1600, height: 1200);
    expect(readImagePixelSize(big), (width: 1600, height: 1200));
  });

  test('JPEG: baseline, progressive, an Exif segment before the SOF', () {
    expect(readImagePixelSize(base64Decode(jpegBaseline7x5)), (
      width: 7,
      height: 5,
    ));
    expect(readImagePixelSize(base64Decode(jpegProgressive9x4)), (
      width: 9,
      height: 4,
    ));
    expect(readImagePixelSize(base64Decode(jpegExif6x8)), (
      width: 6,
      height: 8,
    ));
  });

  test('JPEG: DHT / JPG / DAC are not a SOF; fill bytes; every SOFn', () {
    // segments whose bytes would read as a size if they were taken for a SOF
    final decoys = [
      (0xC4, _sof(1, 1)), // DHT
      (0xC8, _sof(2, 2)), // JPG
      (0xCC, _sof(3, 3)), // DAC
      (0xE0, [0x4A, 0x46, 0x49, 0x46, 0]), // APP0
    ];
    for (final sof in [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC9, 0xCA, 0xCF]) {
      final bytes = _jpeg([...decoys, (sof, _sof(640, 480))]);
      expect(readImagePixelSize(bytes), (
        width: 640,
        height: 480,
      ), reason: 'SOF ${sof.toRadixString(16)}');
    }
    expect(
      readImagePixelSize(_jpeg([...decoys, (0xC0, _sof(300, 200))], fill: 3)),
      (width: 300, height: 200),
    );
  });

  test('cut short, foreign or empty bytes → null', () async {
    final png = await testPngBytes(width: 8, height: 8);
    expect(readImagePixelSize(Uint8List.sublistView(png, 0, 20)), isNull);
    final jpeg = base64Decode(jpegExif6x8);
    final sofAt = _indexOfMarker(jpeg, 0xC0);
    expect(readImagePixelSize(Uint8List.sublistView(jpeg, 0, sofAt)), isNull);
    expect(
      readImagePixelSize(Uint8List.sublistView(jpeg, 0, sofAt + 5)),
      isNull,
    );
    expect(readImagePixelSize(Uint8List(0)), isNull);
    expect(
      readImagePixelSize(_b([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])),
      isNull,
    );
    // SOS before any SOF, a corrupt marker run, a zero size
    expect(
      readImagePixelSize(
        _jpeg([
          (0xDA, [0, 0]),
        ]),
      ),
      isNull,
    );
    expect(readImagePixelSize(_b([0xFF, 0xD8, 0x12, 0x34])), isNull);
    expect(readImagePixelSize(_jpeg([(0xC0, _sof(0, 10))])), isNull);
  });
}

int _indexOfMarker(Uint8List b, int marker) {
  for (var i = 0; i + 1 < b.length; i++) {
    if (b[i] == 0xFF && b[i + 1] == marker) return i;
  }
  throw StateError('no marker');
}
