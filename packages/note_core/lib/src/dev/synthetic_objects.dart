// Internal: deterministic page objects for seedSyntheticNote(objectsPerPage:) (dev_tools.dart —
// CORE CP-9, approved P-C) and the small PNG its image objects show. Web-safe: no dart:io,
// integer math within 32 bits.
import 'dart:typed_data';

import '../common/geometry.dart';
import '../common/ids.dart';
import '../model/object_styles.dart';
import '../model/page_size.dart';
import '../model/shape_geometry.dart';
import '../model/stroke.dart';

/// One cycle of the object mix: 10 shapes (the kinds in turn), 5 text boxes, 1 math, 1 image —
/// INK's object page (bench B14: 200 shapes, 100 text boxes, 20 math, 20 images) is 340.
const int kSyntheticObjectCycle = 17;

/// Pixel size of [syntheticPng] (image objects keep this 4:3 aspect).
const int kSyntheticPngWidth = 64, kSyntheticPngHeight = 48;

/// [count] objects in a grid over [size] (10 pt margin), in the [kSyntheticObjectCycle] mix,
/// with ids from [ids] and createdAt = [createdAt] + index. Image objects reference
/// [imageAssetId] (bytes = [syntheticPng]); it must be given when [count] reaches an image
/// slot (index 16, 33, …).
List<PageObject> syntheticObjects({
  required PageId pageId,
  required IdGenerator ids,
  required int count,
  required PageSize size,
  AssetId? imageAssetId,
  int seed = 1,
  EpochMillis createdAt = 0,
}) {
  if (count <= 0) return const [];
  const margin = 10.0;
  final width = size.width - 2 * margin, height = size.height - 2 * margin;
  var columns = 1;
  while (columns * columns * height < count * width) {
    columns++;
  }
  final rows = (count + columns - 1) ~/ columns;
  final cellW = width / columns, cellH = height / rows;
  final pad = (cellW < cellH ? cellW : cellH) * 0.1;
  return [
    for (var i = 0; i < count; i++)
      _object(
        i,
        pageId: pageId,
        id: ids.newId(),
        cell: PageRect(
          margin + (i % columns) * cellW + pad,
          margin + (i ~/ columns) * cellH + pad,
          margin + (i % columns + 1) * cellW - pad,
          margin + (i ~/ columns + 1) * cellH - pad,
        ),
        imageAssetId: imageAssetId,
        seed: seed,
        createdAt: createdAt + i,
      ),
  ];
}

PageObject _object(
  int i, {
  required PageId pageId,
  required ElementId id,
  required PageRect cell,
  required AssetId? imageAssetId,
  required int seed,
  required EpochMillis createdAt,
}) {
  final slot = i % kSyntheticObjectCycle;
  final n = i + 1;
  if (slot < 10) {
    final kind =
        ShapeKind.values[(i ~/ kSyntheticObjectCycle * 10 + slot) %
            ShapeKind.values.length];
    return ShapeObject(
      id: id,
      pageId: pageId,
      shapeKind: kind,
      geometry: switch (kind) {
        ShapeKind.line || ShapeKind.arrow => ShapeGeometry.line(
          PagePoint(cell.left, cell.top),
          PagePoint(cell.right, cell.bottom),
        ),
        ShapeKind.rectangle => ShapeGeometry.rectangle(cell),
        ShapeKind.ellipse => ShapeGeometry.ellipse(cell),
        ShapeKind.triangle => ShapeGeometry.triangle(cell),
        ShapeKind.polygon => ShapeGeometry.regularPolygon(cell, 5 + n % 4),
        ShapeKind.star => ShapeGeometry.star(cell),
      },
      style: ShapeStyle(
        strokeColorArgb: 0xFF1A1A1A + (n * 0x0F0713 & 0x7F7F7F),
        strokeWidth: 1 + n % 4,
        fillColorArgb: slot.isEven ? null : 0xFFFFE08A,
        fillOpacity: 0.5,
        arrowHeads: kind == ShapeKind.arrow ? ArrowHeads.end : ArrowHeads.none,
      ),
      createdAt: createdAt,
    );
  }
  if (slot < 15) {
    return TextBoxObject(
      id: id,
      pageId: pageId,
      frame: ElementFrame(cell),
      text: '합성 메모 $n · synthetic note $seed',
      style: const TextBoxStyle(),
      createdAt: createdAt,
    );
  }
  if (slot == 15) {
    return MathObject(
      id: id,
      pageId: pageId,
      frame: ElementFrame(cell),
      latex: '\\frac{a_{$n}}{b} + \\sqrt{x^{2} + $seed}',
      style: const MathStyle(),
      createdAt: createdAt,
    );
  }
  final assetId = imageAssetId ?? (throw ArgumentError.notNull('imageAssetId'));
  // The largest 4:3 rect centred in the cell.
  final w = cell.width * kSyntheticPngHeight <= cell.height * kSyntheticPngWidth
      ? cell.width
      : cell.height * kSyntheticPngWidth / kSyntheticPngHeight;
  final h = w * kSyntheticPngHeight / kSyntheticPngWidth;
  final left = cell.left + (cell.width - w) / 2;
  final top = cell.top + (cell.height - h) / 2;
  return ImageObject(
    id: id,
    pageId: pageId,
    frame: ElementFrame(PageRect(left, top, left + w, top + h)),
    assetId: assetId,
    pixelWidth: kSyntheticPngWidth,
    pixelHeight: kSyntheticPngHeight,
    createdAt: createdAt,
  );
}

/// A [kSyntheticPngWidth] × [kSyntheticPngHeight] 8-bit RGB PNG (a gradient that depends on
/// [seed]): zlib stream of one stored deflate block, CRC-32 per chunk. Same bytes for the same
/// seed on every platform (so AssetStore.put stores it once per store).
Uint8List syntheticPng({int seed = 1}) {
  const w = kSyntheticPngWidth, h = kSyntheticPngHeight;
  final raw = Uint8List((1 + 3 * w) * h);
  var o = 0;
  for (var y = 0; y < h; y++) {
    raw[o++] = 0; // filter: none
    for (var x = 0; x < w; x++) {
      raw[o++] = (x * 4 + seed * 37) & 0xFF;
      raw[o++] = (y * 5 + seed * 11) & 0xFF;
      raw[o++] = ((x + y) * 2 + 128) & 0xFF;
    }
  }
  final zlib = BytesBuilder(copy: false)
    ..add(const [0x78, 0x01]) // deflate, 32 KiB window, no dictionary
    ..add([
      0x01, // BFINAL, stored; LEN and NLEN little-endian (raw.length < 65536)
      raw.length & 0xFF,
      raw.length >> 8,
      (0xFFFF - raw.length) & 0xFF,
      (0xFFFF - raw.length) >> 8,
    ])
    ..add(raw)
    ..add(_u32(adler32(raw)));
  final header = ByteData(13)
    ..setUint32(0, w)
    ..setUint32(4, h)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 2); // colour type: RGB (compression, filter, interlace 0)
  return (BytesBuilder(copy: false)
        ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        ..add(_chunk('IHDR', header.buffer.asUint8List()))
        ..add(_chunk('IDAT', zlib.takeBytes()))
        ..add(_chunk('IEND', Uint8List(0))))
      .takeBytes();
}

Uint8List _chunk(String type, Uint8List data) {
  final typeBytes = Uint8List.fromList(type.codeUnits);
  return (BytesBuilder(copy: false)
        ..add(_u32(data.length))
        ..add(typeBytes)
        ..add(data)
        ..add(_u32(crc32([...typeBytes, ...data]))))
      .takeBytes();
}

Uint8List _u32(int v) =>
    (ByteData(4)..setUint32(0, v & 0xFFFFFFFF)).buffer.asUint8List();

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
  }
  return c;
}, growable: false);

/// CRC-32 (ISO-HDLC, the PNG / zlib one): crc32('123456789'.codeUnits) == 0xCBF43926.
int crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >>> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// Adler-32 of [bytes] (the zlib trailer).
int adler32(List<int> bytes) {
  var a = 1, b = 0;
  for (final x in bytes) {
    a = (a + x) % 65521;
    b = (b + a) % 65521;
  }
  return (b << 16 | a) & 0xFFFFFFFF;
}
