// Compose ops encoder and vector helpers (06-pdf 4.9, 6.11.5, 6.11.8; 8 T12): path helpers,
// alpha255, command layout (verbs · endObject · paint values · order · shared paints),
// highlighter split by width / cap, template underlay through the encoder, the page plan
// stride, and a fixed fixture whose bytes must not change (the backends of T13 / T14 read
// them; the browser test checks the same digest under dart2js).
import 'dart:typed_data';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/ink_adapter/ink_vectorizer.dart';
import 'package:pdf_io/src/ink_adapter/template_underlay.dart';

import '../support/compose_fixture.dart';

PdfVectorPath _line(double x0, double y0, double x1, double y1) =>
    PdfVectorPath(
      Uint8List.fromList(const [0, 1]),
      Float32List.fromList([x0, y0, x1, y1]),
    );

void main() {
  group('PdfVectorPath', () {
    test('rect: one closed subpath', () {
      final p = PdfVectorPath.rect(const Rect.fromLTRB(1, 2, 11, 22));
      expect(p.verbs, [0, 1, 1, 1, 3]);
      expect(p.coords, [1, 2, 11, 2, 11, 22, 1, 22]);
      expect(p.isEmpty, isFalse);
    });

    test('circles: four cubics per circle (k = 0.5523), one subpath each', () {
      final p = PdfVectorPath.circles(const [
        (Offset(10, 20), 2),
        (Offset.zero, 1),
      ]);
      expect(p.verbs, [0, 2, 2, 2, 2, 3, 0, 2, 2, 2, 2, 3]);
      expect(p.coords, hasLength(52));
      // First circle: start (12, 20), first cubic to (10, 22) with k·r = 1.1046.
      expect(p.coords.sublist(0, 8).map((v) => v.toStringAsFixed(4)), [
        '12.0000',
        '20.0000',
        '12.0000',
        '21.1046',
        '11.1046',
        '22.0000',
        '10.0000',
        '22.0000',
      ]);
      // Ends where it started.
      expect(p.coords.sublist(24, 26), [12, 20]);
      // Second circle starts at (1, 0).
      expect(p.coords.sublist(26, 28), [1, 0]);
      expect(PdfVectorPath.circles(const []).isEmpty, isTrue);
    });

    test('concat: subpaths in order, empty inputs skipped', () {
      final p = PdfVectorPath.concat([
        _line(0, 0, 1, 1),
        PdfVectorPath(Uint8List(0), Float32List(0)),
        PdfVectorPath.rect(const Rect.fromLTWH(5, 5, 1, 1)),
      ]);
      expect(p.verbs, [0, 1, 0, 1, 1, 1, 3]);
      expect(p.coords, [0, 0, 1, 1, 5, 5, 6, 5, 6, 6, 5, 6]);
      expect(PdfVectorPath.concat(const []).isEmpty, isTrue);
    });

    test('concat: an input not starting with moveTo → ArgumentError', () {
      expect(
        () => PdfVectorPath.concat([
          PdfVectorPath(
            Uint8List.fromList(const [1]),
            Float32List.fromList(const [1, 1]),
          ),
        ]),
        throwsArgumentError,
      );
    });
  });

  group('alpha255', () {
    PdfVectorItem fill(int argb, double opacity) => PdfFillItem(
      path: PdfVectorPath.rect(Rect.zero),
      colorArgb: argb,
      opacity: opacity,
    );

    test('round(255 · opacity · alpha / 255)', () {
      expect(fill(0xFFFFE600, 0.35).alpha255, 89); // 89.25
      expect(fill(0xFF000000, 1).alpha255, 255);
      expect(fill(0x80123456, 1).alpha255, 128);
      expect(fill(0x80123456, 0.5).alpha255, 64);
      expect(fill(0x7F000000, 0.5).alpha255, 64); // 63.5 → 64
      expect(fill(0x00FFFFFF, 1).alpha255, 0);
    });

    test('opacity clamped to 0..1', () {
      expect(fill(0xFF000000, 1.5).alpha255, 255);
      expect(fill(0xFF000000, -1).alpha255, 0);
    });
  });

  group('PdfComposeEncoder.encode', () {
    test('no vectors → empty ops', () {
      final ops = PdfComposeEncoder.encode(
        outputIndex: 4,
        vectors: PdfPageVectors.empty,
      );
      expect(ops.outputIndex, 4);
      expect(ops.isEmpty, isTrue);
      expect(ops.coords, isEmpty);
      expect(ops.paints, isEmpty);
      expect(ops.byteLength, 0);
    });

    test('one object per item: path verbs then endObject(paint index)', () {
      final ops = PdfComposeEncoder.encode(
        outputIndex: 0,
        vectors: PdfPageVectors(
          underlay: [
            PdfFillItem(
              path: PdfVectorPath.rect(const Rect.fromLTWH(0, 0, 10, 10)),
              colorArgb: 0xFFFBF7EC,
            ),
          ],
          ink: [
            PdfStrokeItem(
              path: _line(1, 2, 3, 4),
              colorArgb: 0xFFFFE600,
              opacity: 0.35,
              blend: PdfBlend.multiply,
              width: 12,
              cap: PdfLineCap.square,
            ),
            PdfFillItem(
              path: PdfVectorPath.rect(const Rect.fromLTWH(5, 5, 1, 1)),
              colorArgb: 0xFF1A1A1A,
              opacity: 0.85,
              fillRule: PdfFillRule.evenOdd,
            ),
          ],
        ),
      );
      expect(ops.verbs, [0, 1, 1, 1, 3, 7, 0, 1, 7, 0, 1, 1, 1, 3, 7]);
      expect(ops.coords, [
        0, 0, 10, 0, 10, 10, 0, 10, 0, // underlay rect, paint 0
        1, 2, 3, 4, 1, // highlighter line, paint 1
        5, 5, 6, 5, 6, 6, 5, 6, 2, // ink fill, paint 2
      ]);
      expect(ops.paints, hasLength(3 * PdfComposeOpcodes.paintStride));
      List<double> paint(int i) => ops.paints.sublist(
        i * PdfComposeOpcodes.paintStride,
        (i + 1) * PdfComposeOpcodes.paintStride,
      );
      // [type, r, g, b, a, width, cap, join, blend, fillMode]
      expect(paint(0), [0, 0xFB, 0xF7, 0xEC, 255, 0, 0, 0, 0, 2]);
      expect(paint(1), [1, 0xFF, 0xE6, 0x00, 89, 12, 2, 1, 1, 0]);
      expect(paint(2), [0, 0x1A, 0x1A, 0x1A, 217, 0, 0, 0, 0, 1]);
      expect(
        ops.byteLength,
        ops.verbs.length + 4 * ops.coords.length + 4 * ops.paints.length,
      );
    });

    test('stroke caps / joins and equal paints sharing one index', () {
      PdfStrokeItem stroke(PdfLineCap cap, PdfLineJoin join) => PdfStrokeItem(
        path: _line(0, 0, 1, 1),
        colorArgb: 0xFF000000,
        width: 2,
        cap: cap,
        join: join,
      );
      final ops = PdfComposeEncoder.encode(
        outputIndex: 0,
        vectors: PdfPageVectors(
          ink: [
            stroke(PdfLineCap.butt, PdfLineJoin.miter),
            stroke(PdfLineCap.round, PdfLineJoin.round),
            stroke(
              PdfLineCap.butt,
              PdfLineJoin.miter,
            ), // same paint as the first
            stroke(PdfLineCap.square, PdfLineJoin.bevel),
          ],
        ),
      );
      final endObjects = _endObjects(ops);
      expect(endObjects, [0, 1, 0, 2]);
      expect(ops.paints, hasLength(3 * 10));
      expect(ops.paints.sublist(6, 8), [0, 0]); // butt, miter
      expect(ops.paints.sublist(16, 18), [1, 1]); // round, round
      expect(ops.paints.sublist(26, 28), [2, 2]); // square, bevel
    });

    test('underlay before ink whatever the list order', () {
      final ops = PdfComposeEncoder.encode(
        outputIndex: 0,
        vectors: PdfPageVectors(
          ink: [PdfFillItem(path: _rectAt(100), colorArgb: 0xFF000001)],
          underlay: [PdfFillItem(path: _rectAt(0), colorArgb: 0xFF000002)],
        ),
      );
      expect(ops.coords.first, 0); // the underlay rect comes first
      expect(ops.paints[3], 2); // blue channel of the underlay paint
    });

    test('empty paths are skipped; bad paths are rejected', () {
      final empty = PdfVectorPath(Uint8List(0), Float32List(0));
      final ops = PdfComposeEncoder.encode(
        outputIndex: 0,
        vectors: PdfPageVectors(
          ink: [
            PdfFillItem(path: empty, colorArgb: 0xFF000000),
            PdfFillItem(path: _rectAt(1), colorArgb: 0xFF000000),
          ],
        ),
      );
      expect(ops.verbs, [0, 1, 1, 1, 3, 7]);
      expect(
        () => PdfComposeEncoder.encode(
          outputIndex: 0,
          vectors: PdfPageVectors(
            ink: [
              PdfFillItem(
                path: PdfVectorPath(
                  Uint8List.fromList(const [0, 1]),
                  Float32List.fromList(const [0, 0]),
                ),
                colorArgb: 0xFF000000,
              ),
            ],
          ),
        ),
        throwsArgumentError,
      );
    });

    test('highlighters split by width and cap, one object each', () {
      final items = pdfHighlighterItems(
        colorArgb: 0xFFFFE600,
        opacity: 0.35,
        blend: PdfBlend.multiply,
        lines: [
          (centerline: _line(0, 0, 10, 0), width: 12, cap: PdfLineCap.round),
          (centerline: _line(0, 5, 10, 5), width: 20, cap: PdfLineCap.round),
          (centerline: _line(0, 9, 10, 9), width: 12, cap: PdfLineCap.round),
          (centerline: _line(0, 7, 10, 7), width: 12, cap: PdfLineCap.square),
        ],
      );
      expect(
        [for (final i in items) (i.width, i.cap, i.path.verbs.length)],
        [
          (12.0, PdfLineCap.round, 4), // two subpaths
          (20.0, PdfLineCap.round, 2),
          (12.0, PdfLineCap.square, 2),
        ],
      );
      expect(items.first.path.coords, [0, 0, 10, 0, 0, 9, 10, 9]);
      for (final item in items) {
        expect(item.blend, PdfBlend.multiply);
        expect(item.join, PdfLineJoin.round);
        expect(item.opacity, 0.35);
        expect(item.colorArgb, 0xFFFFE600);
      }
      final ops = PdfComposeEncoder.encode(
        outputIndex: 0,
        vectors: PdfPageVectors(ink: items),
      );
      expect(ops.verbs.where((v) => v == 7), hasLength(3));
      expect(ops.paints[8], 1); // multiply
    });

    test('template underlay: lines by (color, width), dots by color', () {
      final underlay = pdfTemplateItems(const [
        ink.TemplateLine(
          Offset(0, 10),
          Offset(100, 10),
          width: 0.5,
          colorArgb: 0xFFAAAAAA,
        ),
        ink.TemplateLine(
          Offset(0, 20),
          Offset(100, 20),
          width: 0.5,
          colorArgb: 0xFFAAAAAA,
        ),
        ink.TemplateLine(
          Offset(10, 0),
          Offset(10, 100),
          width: 1,
          colorArgb: 0xFFAAAAAA,
        ),
        ink.TemplateDot(Offset(5, 5), radius: 0.8, colorArgb: 0xFFBBBBBB),
        ink.TemplateDot(Offset(15, 5), radius: 0.8, colorArgb: 0xFFBBBBBB),
      ]);
      final ops = PdfComposeEncoder.encode(
        outputIndex: 0,
        vectors: PdfPageVectors(underlay: underlay),
      );
      // Two stroke objects (0.5 pt: 2 segments, 1 pt: 1 segment) and one dot fill object.
      expect(ops.verbs, [
        0, 1, 0, 1, 7, //
        0, 1, 7, //
        0, 2, 2, 2, 2, 3, 0, 2, 2, 2, 2, 3, 7,
      ]);
      expect(ops.paints, hasLength(30));
      expect(ops.paints.sublist(0, 8), [1, 0xAA, 0xAA, 0xAA, 255, 0.5, 0, 0]);
      expect(ops.paints[15], 1); // width of the second line object
      expect(ops.paints.sublist(20, 25), [0, 0xBB, 0xBB, 0xBB, 255]);
    });

    test('fixed fixture: the exact bytes (backends read these)', () {
      final ops = PdfComposeEncoder.encode(
        outputIndex: 2,
        vectors: composeFixtureVectors(),
      );
      expect(ops.outputIndex, 2);
      expect(ops.verbs, composeFixtureVerbs);
      expect(ops.coords, composeFixtureCoords);
      expect(ops.paints, composeFixturePaints);
      expect(
        sha256.convert(composeOpsBytes(ops)).toString(),
        composeFixtureSha256,
      );
    });
  });

  test('PdfComposePlan.encodePages: stride 6, blank pages −1', () {
    const plan = PdfComposePlan(
      sources: [],
      pages: [
        PdfComposeSourcePage(
          sourceIndex: 1,
          pdfPageIndex: 7,
          noteSize: Size(595.276, 841.89),
        ),
        PdfComposeBlankPage(noteSize: Size(72, 72)),
      ],
    );
    final encoded = plan.encodePages();
    expect(encoded, [
      0, 1, 7, 595.276, 841.89, 0, //
      1, -1, -1, 72, 72, 0,
    ]);
    expect(const PdfComposePlan(sources: [], pages: []).encodePages(), isEmpty);
  });
}

PdfVectorPath _rectAt(double x) =>
    PdfVectorPath.rect(Rect.fromLTWH(x, 0, 1, 1));

/// The paint index of every endObject, walking the verbs.
List<double> _endObjects(PdfComposePageOps ops) {
  final out = <double>[];
  var c = 0;
  for (final verb in ops.verbs) {
    switch (verb) {
      case 0 || 1:
        c += 2;
      case 2:
        c += 6;
      case 7:
        out.add(ops.coords[c++]);
    }
  }
  return out;
}
