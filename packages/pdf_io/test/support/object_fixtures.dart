// test/support/object_fixtures.dart — (v2.1, PDF-M3) the big export samples (m5-7/06-pdf
// 4.3.1). VM only (dart:io ZLibEncoder) — web tests use PdfObjectFixtures from
// package:pdf_io/testing.dart.
import 'dart:io';
import 'dart:typed_data';

import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/testing.dart';

/// A page-size text box, 500 × 700 pt (300 dpi would be 2083 × 2917 ≈ 6.1 Mpx — capped to
/// ≈ 249 dpi). [text] defaults to a line with a character NoteSans does not cover (U+1F600), so
/// the resolver takes the raster path.
core.TextBoxObject pageSizeTextBox({
  String id = 'text-page',
  String text = '쪽 크기 상자 \u{1F600}',
  int? backgroundArgb,
}) => core.TextBoxObject(
  id: id,
  pageId: 'p1',
  frame: const core.ElementFrame(core.PageRect(40, 60, 540, 760)),
  text: text,
  style: core.TextBoxStyle(backgroundArgb: backgroundArgb),
  createdAt: 1,
);

/// A big formula frame, 700 × 700 pt (300 dpi would be 2917² ≈ 8.5 Mpx — capped to ≈ 211 dpi).
core.MathObject bigMathObject({String id = 'math-big'}) => core.MathObject(
  id: id,
  pageId: 'p1',
  frame: const core.ElementFrame(core.PageRect(20, 20, 720, 720)),
  latex: r'\sum_{k=1}^{n} k^2',
  style: const core.MathStyle(),
  createdAt: 1,
);

/// A solid 6000 × 4000 RGB PNG (a synced original — 96 MB of pixels, about 100 KB of file).
Uint8List bigPng6000x4000() =>
    pngFromRows(6000, 4000, (y, row) => row.fillRange(0, row.length, 200));

/// A 2048 × 2048 RGB PNG of at least [minBytes] (default 6 MiB): the top rows are noise (they do
/// not compress), the rest is one colour.
Uint8List noisePng2048({int minBytes = 6 * 1024 * 1024}) {
  const w = 2048, h = 2048;
  final noisyRows = (minBytes + w * 3 - 1) ~/ (w * 3);
  final rng = _XorShift(7);
  return pngFromRows(w, h, (y, row) {
    if (y < noisyRows) {
      rng.fill(row);
    } else {
      row.fillRange(0, row.length, 90);
    }
  });
}

/// A gray noise PNG of at least [minBytes] (default 20 MiB — outside M-3).
Uint8List noisePngOver({int minBytes = 20 * 1024 * 1024}) {
  const w = 4096;
  final h = (minBytes + w - 1) ~/ w + 8;
  final rng = _XorShift(11);
  return pngFromRows(w, h, (y, row) => rng.fill(row), channels: 1);
}

/// PNG from rows ([fill] writes one row of [width] × [channels] bytes), zlib level 1, filter 0.
/// channels: 1 gray, 3 RGB, 4 RGBA.
Uint8List pngFromRows(
  int width,
  int height,
  void Function(int y, Uint8List row) fill, {
  int channels = 3,
}) {
  final colorType = switch (channels) {
    1 => 0,
    3 => 2,
    4 => 6,
    _ => throw ArgumentError.value(channels, 'channels'),
  };
  final idat = BytesBuilder(copy: false);
  final sink = ZLibEncoder(level: 1).startChunkedConversion(_BytesSink(idat));
  final row = Uint8List(width * channels);
  for (var y = 0; y < height; y++) {
    fill(y, row);
    sink.add(const [0]);
    sink.add(Uint8List.fromList(row));
  }
  sink.close();
  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, colorType);
  final out = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add(_chunk('IHDR', ihdr.buffer.asUint8List()))
    ..add(_chunk('IDAT', idat.takeBytes()))
    ..add(_chunk('IEND', Uint8List(0)));
  return out.takeBytes();
}

/// [jpeg] with COM segments after SOI until it is longer than [minBytes] (a valid JPEG — the
/// decoders skip comments).
Uint8List paddedJpeg(Uint8List jpeg, int minBytes) {
  const segment = 65533; // payload of one COM segment (length field 65535)
  final count = (minBytes - jpeg.length) ~/ segment + 1;
  final out = BytesBuilder(copy: false)..add(jpeg.sublist(0, 2));
  final com = Uint8List(4 + segment)
    ..[0] = 0xFF
    ..[1] = 0xFE
    ..[2] = 0xFF
    ..[3] = 0xFF;
  for (var i = 0; i < count; i++) {
    out.add(com);
  }
  out.add(jpeg.sublist(2));
  return out.takeBytes();
}

/// PdfObjectFixtures.png re-exported for VM tests that import only this file.
Uint8List smallPng({int width = 64, int height = 48, bool alpha = false}) =>
    PdfObjectFixtures.png(width: width, height: height, alpha: alpha);

Uint8List _chunk(String type, Uint8List data) {
  final head = ByteData(8)..setUint32(0, data.length);
  final typeBytes = type.codeUnits;
  for (var i = 0; i < 4; i++) {
    head.setUint8(4 + i, typeBytes[i]);
  }
  final crcInput = Uint8List(4 + data.length)
    ..setRange(0, 4, typeBytes)
    ..setRange(4, 4 + data.length, data);
  final tail = ByteData(4)..setUint32(0, _crc32(crcInput));
  return (BytesBuilder(copy: false)
        ..add(head.buffer.asUint8List())
        ..add(data)
        ..add(tail.buffer.asUint8List()))
      .takeBytes();
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = c.isOdd ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(Uint8List bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

final class _BytesSink implements Sink<List<int>> {
  _BytesSink(this.builder);
  final BytesBuilder builder;

  @override
  void add(List<int> data) => builder.add(data);

  @override
  void close() {}
}

final class _XorShift {
  _XorShift(this._s);
  int _s;

  void fill(Uint8List row) {
    for (var i = 0; i < row.length; i++) {
      _s ^= (_s << 13) & 0xFFFFFFFF;
      _s ^= _s >> 17;
      _s ^= (_s << 5) & 0xFFFFFFFF;
      row[i] = _s & 0xFF;
    }
  }
}
