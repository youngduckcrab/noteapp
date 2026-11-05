// A fixed page of vectors and its encoded ops (06-pdf 6.11.5; T12). The compose backends
// (T13 native, T14 web worker) interpret exactly these bytes, so the expected values below
// must only change together with the format. Shared by unit/compose_encoder_test (VM) and
// web/pure_logic_browser_test (dart2js gives the same bytes).
import 'dart:typed_data';
import 'dart:ui';

import 'package:pdf_io/pdf_io.dart';

/// Ivory paper fill + one template line object (underlay); a multiply highlighter line, a
/// cubic fill at 85 % and an even-odd fill with a half-transparent color (ink).
PdfPageVectors composeFixtureVectors() => PdfPageVectors(
  underlay: [
    PdfFillItem(
      path: PdfVectorPath.rect(const Rect.fromLTWH(0, 0, 200, 100)),
      colorArgb: 0xFFFBF7EC,
    ),
    PdfStrokeItem(
      path: PdfVectorPath(
        Uint8List.fromList(const [0, 1, 0, 1]),
        Float32List.fromList(const [0, 25, 200, 25, 0, 50, 200, 50]),
      ),
      colorArgb: 0xFFC8D2DC,
      width: 0.5,
      cap: PdfLineCap.butt,
      join: PdfLineJoin.miter,
    ),
  ],
  ink: [
    PdfStrokeItem(
      path: PdfVectorPath(
        Uint8List.fromList(const [0, 1]),
        Float32List.fromList(const [10, 30, 90.5, 30]),
      ),
      colorArgb: 0xFFFFE600,
      opacity: 0.35,
      blend: PdfBlend.multiply,
      width: 12,
    ),
    PdfFillItem(
      path: PdfVectorPath(
        Uint8List.fromList(const [0, 2, 1, 3]),
        Float32List.fromList(const [20, 60, 30, 50, 40, 70, 50.25, 60, 20, 80]),
      ),
      colorArgb: 0xFF1A1A1A,
      opacity: 0.85,
    ),
    PdfFillItem(
      path: PdfVectorPath.rect(const Rect.fromLTRB(150, 10, 190.75, 40)),
      colorArgb: 0x80336699,
      fillRule: PdfFillRule.evenOdd,
    ),
  ],
);

const List<int> composeFixtureVerbs = [
  0, 1, 1, 1, 3, 7, // paper
  0, 1, 0, 1, 7, // template lines
  0, 1, 7, // highlighter
  0, 2, 1, 3, 7, // cubic fill
  0, 1, 1, 1, 3, 7, // even-odd fill
];

const List<double> composeFixtureCoords = [
  0, 0, 200, 0, 200, 100, 0, 100, 0, //
  0, 25, 200, 25, 0, 50, 200, 50, 1, //
  10, 30, 90.5, 30, 2, //
  20, 60, 30, 50, 40, 70, 50.25, 60, 20, 80, 3, //
  150, 10, 190.75, 10, 190.75, 40, 150, 40, 4,
];

/// [type, r, g, b, a, width, cap, join, blend, fillMode] × 5.
const List<double> composeFixturePaints = [
  0, 0xFB, 0xF7, 0xEC, 255, 0, 0, 0, 0, 2, //
  1, 0xC8, 0xD2, 0xDC, 255, 0.5, 0, 0, 0, 0, //
  1, 0xFF, 0xE6, 0x00, 89, 12, 1, 1, 1, 0, //
  0, 0x1A, 0x1A, 0x1A, 217, 0, 0, 0, 0, 2, //
  0, 0x33, 0x66, 0x99, 128, 0, 0, 0, 0, 1,
];

/// verbs, then coords and paints as little-endian float32 (the wire layout, 6.11.5).
Uint8List composeOpsBytes(PdfComposePageOps ops) {
  final out = ByteData(ops.byteLength);
  var o = 0;
  for (final v in ops.verbs) {
    out.setUint8(o++, v);
  }
  for (final list in [ops.coords, ops.paints]) {
    for (final v in list) {
      out.setFloat32(o, v, Endian.little);
      o += 4;
    }
  }
  return out.buffer.asUint8List();
}

/// sha256 of composeOpsBytes(encode(composeFixtureVectors())).
const String composeFixtureSha256 =
    'ca515ac38698932e4faec2b60884f44458c09fc42497d8d4a834e392eab88778';
