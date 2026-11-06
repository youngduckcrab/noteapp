// Shared cases of PDF T21 (m5-7/06-pdf 6.2.3, 6.2.6, 4.1.4, 4.3.1): object matrices and the v2
// compose encoder (image / text ops, parts at the 8 MiB limit, fonts on first use, the ops
// checks of the backends, RecordingComposeBackend v2). unit/affine_test and
// unit/compose_encoder_v2_test run them on the VM, web/pure_logic_browser_test under dart2js
// (the same assertions — contract 7.4.8 number differences). Web-safe.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/export/compose_ops_check.dart';
import 'package:pdf_io/src/export/object_geometry.dart';
import 'package:pdf_io/testing.dart';

import 'compose_fixture.dart';

void _near(ui.Offset actual, double x, double y) {
  expect(actual.dx, closeTo(x, 1e-6), reason: 'x of $actual');
  expect(actual.dy, closeTo(y, 1e-6), reason: 'y of $actual');
}

core.ElementFrame _frame(double degrees) => core.ElementFrame(
  const core.PageRect(40, 60, 240, 160),
  rotation: degrees * math.pi / 180,
);

/// unit/affine_test (VM) and web/pure_logic_browser_test (dart2js) run these.
void affineCases() {
  group('PdfAffine.frame', () {
    for (final degrees in [0.0, 90.0, -30.0, 180.0]) {
      test('rotation $degrees°: local corners = ElementFrame.corners', () {
        final frame = _frame(degrees);
        final m = PdfAffine.frame(frame);
        const w = 200.0, h = 100.0;
        const local = [
          ui.Offset.zero,
          ui.Offset(w, 0),
          ui.Offset(w, h),
          ui.Offset(0, h),
        ];
        final corners = frame.corners;
        for (var i = 0; i < 4; i++) {
          _near(m.apply(local[i]), corners[i].x, corners[i].y);
        }
        // The rect's center stays put whatever the rotation.
        _near(m.apply(const ui.Offset(w / 2, h / 2)), 140, 110);
      });
    }

    test('rotation 0 is the exact translation to the top-left corner', () {
      expect(PdfAffine.frame(_frame(0)), const PdfAffine(1, 0, 0, 1, 40, 60));
    });

    test('90° turns clockwise on screen (y down)', () {
      final m = PdfAffine.frame(_frame(90));
      // Local x axis (along the top edge) now points down the page.
      final o = m.apply(ui.Offset.zero), x = m.apply(const ui.Offset(1, 0));
      _near(x - o, 0, 1);
    });
  });

  group('unit square → rect (U)', () {
    test('PDF image space corners → y-down rect corners', () {
      final u = unitSquareToRect(const ui.Rect.fromLTWH(10, 20, 64, 48));
      expect(u, const PdfAffine(64, 0, 0, -48, 10, 68));
      _near(u.apply(const ui.Offset(0, 1)), 10, 20); // top-left pixel
      _near(u.apply(const ui.Offset(1, 1)), 74, 20);
      _near(u.apply(const ui.Offset(1, 0)), 74, 68);
      _near(u.apply(ui.Offset.zero), 10, 68); // bottom-left
    });

    for (final degrees in [0.0, 90.0, -30.0, 180.0]) {
      test('F ∘ U at $degrees°: the image fills the rotated frame', () {
        final frame = _frame(degrees);
        final m = unitSquareToRect(const ui.Rect.fromLTWH(0, 0, 200, 100))
            .then(PdfAffine.frame(frame));
        final corners = frame.corners;
        const unit = [
          ui.Offset(0, 1),
          ui.Offset(1, 1),
          ui.Offset(1, 0),
          ui.Offset.zero,
        ];
        for (var i = 0; i < 4; i++) {
          _near(m.apply(unit[i]), corners[i].x, corners[i].y);
        }
      });
    }
  });

  group('text space (T)', () {
    test('baseline origin, glyph up (+y) → screen up (−y)', () {
      final t = textSpaceAt(12, 30);
      expect(t, const PdfAffine(1, 0, 0, -1, 12, 30));
      _near(t.apply(ui.Offset.zero), 12, 30);
      _near(t.apply(const ui.Offset(5, 0)), 17, 30); // along the line
      _near(t.apply(const ui.Offset(0, 8)), 12, 22); // an ascender goes up
    });

    test('F ∘ T at −30°: the baseline turns with the frame', () {
      final frame = _frame(-30);
      final f = PdfAffine.frame(frame);
      final m = textSpaceAt(0, 20).then(f);
      final start = f.apply(const ui.Offset(0, 20));
      _near(m.apply(ui.Offset.zero), start.dx, start.dy);
      final along = m.apply(const ui.Offset(10, 0)) - start;
      _near(along, 10 * math.cos(-math.pi / 6), 10 * math.sin(-math.pi / 6));
      // Glyph up stays perpendicular to the baseline, towards the frame top.
      final up = m.apply(const ui.Offset(0, 10)) - start;
      expect(up.dx * along.dx + up.dy * along.dy, closeTo(0, 1e-9));
      final top = f.apply(ui.Offset.zero) - f.apply(const ui.Offset(0, 1));
      expect(up.dx * top.dx + up.dy * top.dy, greaterThan(0));
    });
  });

  test('then: outer ∘ this, identity on both sides', () {
    const m = PdfAffine(2, 0.5, -1, 3, 7, -4);
    expect(m.then(PdfAffine.identity), m);
    expect(PdfAffine.identity.then(m), m);
    const outer = PdfAffine(0, 1, -1, 0, 100, 0);
    const p = ui.Offset(3, 5);
    final composed = m.then(outer).apply(p);
    final stepwise = outer.apply(m.apply(p));
    _near(composed, stepwise.dx, stepwise.dy);
  });
}

const int _limit = PdfTuning.exportChunkMaxBytes;
const int _imageOpBytes = 1 + 4 * PdfComposeOpcodes.imageArgs; // 29
const int _textOpBytes = 1 + 4 * PdfComposeOpcodes.textArgs; // 53

PdfFillItem _fill(double x, {int argb = 0xFF1A1A1A, double opacity = 1}) =>
    PdfFillItem(
      path: PdfVectorPath.rect(ui.Rect.fromLTWH(x, 0, 10, 10)),
      colorArgb: argb,
      opacity: opacity,
    );

/// A JPEG item whose op costs exactly [cost] bytes in a part (the encoder never decodes).
PdfImageItem _jpegCosting(int cost) => PdfImageItem(
  image: PdfJpegData(Uint8List(cost - _imageOpBytes), width: 1, height: 1),
  matrix: PdfAffine.identity,
);

PdfTextItem _text(String text, {int fontId = PdfComposeOpcodes.fontRegular}) =>
    PdfTextItem(
      text: text,
      fontId: fontId,
      fontSize: 12.5,
      colorArgb: 0xCC336699,
      matrix: const PdfAffine(1, 0, 0, -1, 30, 40),
    );

final Map<int, Uint8List> _fonts = {
  PdfComposeOpcodes.fontRegular: Uint8List.fromList(List.filled(1000, 1)),
  PdfComposeOpcodes.fontBold: Uint8List.fromList(List.filled(700, 2)),
};

List<PdfComposePageOps> _encode(
  List<PdfDrawItem> items, {
  Set<int>? sentFonts,
  int outputIndex = 3,
}) => PdfComposeEncoder.encodeItems(
  outputIndex: outputIndex,
  items: items,
  fontBytes: _fonts,
  sentFonts: sentFonts ?? <int>{},
);

void _checkAll(List<PdfComposePageOps> parts) {
  final loaded = <int>{};
  for (final part in parts) {
    checkComposeOps(part, loadedFonts: loaded);
    loaded.addAll(part.fonts.keys);
  }
}

PdfComposePageOps _ops(
  List<int> verbs,
  List<double> coords, {
  int paints = 1,
  List<PdfImageData> images = const [],
  List<String> texts = const [],
  Map<int, Uint8List> fonts = const {},
}) => PdfComposePageOps(
  outputIndex: 0,
  verbs: Uint8List.fromList(verbs),
  coords: Float32List.fromList(coords),
  paints: Float32List(paints * PdfComposeOpcodes.paintStride),
  images: images,
  texts: texts,
  fonts: fonts,
);

final PdfJpegData _tinyJpeg = PdfJpegData(Uint8List(4), width: 64, height: 48);

/// unit/compose_encoder_v2_test (VM) and web/pure_logic_browser_test (dart2js) run these.
void encoderV2Cases() {
  group('opcodes v2', () {
    test('image 8 (7 args), text 9 (13 args), fonts 0 / 1', () {
      expect(PdfComposeOpcodes.image, 8);
      expect(PdfComposeOpcodes.text, 9);
      expect(PdfComposeOpcodes.imageArgs, 7);
      expect(PdfComposeOpcodes.textArgs, 13);
      expect(PdfComposeOpcodes.fontRegular, 0);
      expect(PdfComposeOpcodes.fontBold, 1);
    });

    test('a 1차 part: no images / texts / fonts, same byteLength', () {
      final ops = PdfComposeEncoder.encode(
        outputIndex: 0,
        vectors: composeFixtureVectors(),
      );
      expect(ops.images, isEmpty);
      expect(ops.texts, isEmpty);
      expect(ops.fonts, isEmpty);
      expect(
        ops.byteLength,
        ops.verbs.length + 4 * ops.coords.length + 4 * ops.paints.length,
      );
    });
  });

  group('PdfComposeEncoder.encodeItems', () {
    test('vectors only: the 1차 bytes in one part', () {
      final v = composeFixtureVectors();
      final parts = _encode([...v.underlay, ...v.ink], outputIndex: 2);
      expect(parts, hasLength(1));
      expect(parts.single.outputIndex, 2);
      expect(parts.single.verbs, composeFixtureVerbs);
      expect(parts.single.coords, composeFixtureCoords);
      expect(parts.single.paints, composeFixturePaints);
      expect(parts.single.fonts, isEmpty);
      _checkAll(parts);
    });

    test('image and text ops: placement and argument counts', () {
      const m = PdfAffine(64, 0, 0, -48, 10, 68);
      final rgba = PdfRgbaData(
        Uint8List(2 * 3 * 4),
        width: 2,
        height: 3,
        hasAlpha: true,
      );
      final parts = _encode([
        _fill(0),
        PdfImageItem(image: _tinyJpeg, matrix: m),
        _text('한글 abc'),
        PdfImageItem(image: rgba, matrix: PdfAffine.identity),
        _text('굵게', fontId: PdfComposeOpcodes.fontBold),
        _fill(20),
      ]);
      expect(parts, hasLength(1));
      final p = parts.single;
      expect(p.verbs, [0, 1, 1, 1, 3, 7, 8, 9, 8, 9, 0, 1, 1, 1, 3, 7]);
      expect(p.images, [same(_tinyJpeg), same(rgba)]);
      expect(p.texts, ['한글 abc', '굵게']);
      expect(p.fonts.keys.toSet(), {0, 1});
      expect(p.coords.sublist(9, 16), [0, 64, 0, 0, -48, 10, 68]);
      expect(p.coords.sublist(16, 29), [
        0, // text index
        0, // fontId
        12.5,
        0x33,
        0x66,
        0x99,
        0xCC,
        1,
        0,
        0,
        -1,
        30,
        40,
      ]);
      expect(p.coords.sublist(29, 36), [1, 1, 0, 0, 1, 0, 0]);
      expect(p.coords[36], 1); // second text
      expect(p.coords[37], PdfComposeOpcodes.fontBold);
      // Both fills share the one paint.
      expect(p.paints, hasLength(PdfComposeOpcodes.paintStride));
      expect(p.coords.last, 0);
      _checkAll(parts);
    });

    test(
      'byteLength = verbs + coords + paints + images + 2 B/char + fonts',
      () {
        final parts = _encode([
          _fill(0),
          PdfImageItem(image: _tinyJpeg, matrix: PdfAffine.identity),
          _text('abc'),
        ]);
        final p = parts.single;
        expect(
          p.byteLength,
          p.verbs.length +
              4 * p.coords.length +
              4 * p.paints.length +
              4 +
              2 * 3 +
              1000,
        );
      },
    );

    test('no drawable item → no part; empty paths are skipped', () {
      expect(_encode(const []), isEmpty);
      final empty = PdfFillItem(
        path: PdfVectorPath(Uint8List(0), Float32List(0)),
        colorArgb: 0xFF000000,
      );
      expect(_encode([empty]), isEmpty);
      final parts = _encode([empty, _fill(0), empty]);
      expect(parts.single.verbs, [0, 1, 1, 1, 3, 7]);
    });

    test('a bad path is rejected (1차 rule)', () {
      final bad = PdfFillItem(
        path: PdfVectorPath(
          Uint8List.fromList(const [1]),
          Float32List.fromList(const [0, 0]),
        ),
        colorArgb: 0xFF000000,
      );
      expect(() => _encode([bad]), throwsArgumentError);
    });

    test('parts are cut at the 8 MiB limit (≤ limit stays together)', () {
      final half = _jpegCosting(_limit ~/ 2);
      final exact = _encode([half, _jpegCosting(_limit ~/ 2)]);
      expect(exact, hasLength(1));
      expect(exact.single.byteLength, _limit);
      final over = _encode([half, _jpegCosting(_limit ~/ 2 + 1), _fill(0)]);
      expect(over, hasLength(2));
      expect(over[0].images, [same(half.image)]);
      expect(over[1].images, hasLength(1));
      expect(over[1].verbs, [8, 0, 1, 1, 1, 3, 7]);
      for (final part in over) {
        expect(part.byteLength, lessThanOrEqualTo(_limit));
        expect(part.outputIndex, 3);
      }
      _checkAll(over);
    });

    test('a 16 MiB RGBA image is a part of its own', () {
      final big = PdfRgbaData(
        Uint8List(2048 * 2048 * 4),
        width: 2048,
        height: 2048,
        hasAlpha: false,
      );
      final parts = _encode([
        _fill(0),
        PdfImageItem(image: big, matrix: PdfAffine.identity),
        _fill(10),
        _text('after'),
      ]);
      expect(parts, hasLength(3));
      expect(parts[0].verbs, [0, 1, 1, 1, 3, 7]);
      expect(parts[1].verbs, [8]);
      expect(parts[1].images.single, same(big));
      expect(parts[1].byteLength, 16 * 1024 * 1024 + _imageOpBytes);
      expect(parts[2].verbs, [0, 1, 1, 1, 3, 7, 9]);
      // Each part has its own paint table.
      expect(parts[0].paints, hasLength(PdfComposeOpcodes.paintStride));
      expect(parts[2].paints, hasLength(PdfComposeOpcodes.paintStride));
      expect(parts[2].fonts.keys, [PdfComposeOpcodes.fontRegular]);
      _checkAll(parts);
    });

    test('a font rides on the first part that uses it, never again', () {
      final sent = <int>{};
      final first = _encode([
        _fill(0),
        _jpegCosting(_limit - 200),
        _text('one'), // does not fit with its font → next part
        _text('two'),
        _text('three', fontId: PdfComposeOpcodes.fontBold),
      ], sentFonts: sent);
      expect(first, hasLength(2));
      expect(first[0].fonts, isEmpty);
      expect(first[1].fonts.keys.toSet(), {0, 1});
      expect(first[1].texts, ['one', 'two', 'three']);
      expect(first[1].byteLength, 3 * _textOpBytes + 2 * 11 + 1000 + 700);
      expect(sent, {0, 1});
      _checkAll(first);
      // The next page of the same job: fonts already sent.
      final next = _encode([_text('again')], sentFonts: sent);
      expect(next.single.fonts, isEmpty);
      checkComposeOps(next.single, loadedFonts: {0, 1});
      // A fresh job (batch export: one job per note) starts with an empty set.
      expect(_encode([_text('fresh')]).single.fonts.keys, [0]);
    });

    test('a text whose font has no bytes and was not sent → ArgumentError', () {
      final sent = <int>{};
      expect(
        () => PdfComposeEncoder.encodeItems(
          outputIndex: 0,
          items: [_text('x', fontId: PdfComposeOpcodes.fontBold)],
          fontBytes: const {},
          sentFonts: sent,
        ),
        throwsArgumentError,
      );
      expect(sent, isEmpty);
      expect(
        PdfComposeEncoder.encodeItems(
          outputIndex: 0,
          items: [_text('x', fontId: PdfComposeOpcodes.fontBold)],
          fontBytes: const {},
          sentFonts: {PdfComposeOpcodes.fontBold},
        ).single.fonts,
        isEmpty,
      );
    });
  });

  group('ops checks (the backends\' rules, 6.2.6)', () {
    test('an image or a text inside an open path → ArgumentError', () {
      expect(
        () => checkComposeOps(
          _ops(
            [0, 1, 8],
            [0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 0],
            images: [_tinyJpeg],
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => checkComposeOps(
          _ops(
            [0, 9],
            [0, 0, 0, 0, 12, 0, 0, 0, 255, 1, 0, 0, -1, 0, 0],
            texts: ['a'],
            fonts: {0: Uint8List(1)},
          ),
        ),
        throwsArgumentError,
      );
    });

    test('ops ending inside an object, bad indexes, unknown verbs', () {
      expect(
        () => checkComposeOps(_ops([0, 1], [0, 0, 1, 1])),
        throwsArgumentError,
      );
      expect(
        () => checkComposeOps(_ops([0, 1, 7], [0, 0, 1, 1, 1])), // paint 1 of 1
        throwsArgumentError,
      );
      expect(
        () => checkComposeOps(
          _ops([8], [1, 1, 0, 0, 1, 0, 0], images: [_tinyJpeg]),
        ),
        throwsArgumentError,
      );
      expect(() => checkComposeOps(_ops([5], [])), throwsArgumentError);
      expect(
        () => checkComposeOps(
          _ops([0, 1, 7], [0, 0, 1, 1, 0, 99]),
        ), // extra coord
        throwsArgumentError,
      );
      expect(
        () => checkComposeOps(_ops([1, 7], [1, 1, 0])),
        throwsArgumentError,
      );
      checkComposeOps(
        _ops(
          [0, 1, 7, 8],
          [0, 0, 1, 1, 0, 0, 1, 0, 0, 1, 0, 0],
          images: [_tinyJpeg],
        ),
      );
    });

    test('a text needs its font loaded; a font is never loaded twice', () {
      final text = _ops(
        [9],
        [0, 1, 12, 0, 0, 0, 255, 1, 0, 0, -1, 0, 0],
        paints: 0,
        texts: ['a'],
      );
      expect(() => checkComposeOps(text), throwsArgumentError);
      checkComposeOps(text, loadedFonts: {1});
      final carrying = _ops(
        [9],
        [0, 1, 12, 0, 0, 0, 255, 1, 0, 0, -1, 0, 0],
        paints: 0,
        texts: ['a'],
        fonts: {1: Uint8List(3)},
      );
      checkComposeOps(carrying);
      expect(
        () => checkComposeOps(carrying, loadedFonts: {1}),
        throwsArgumentError,
      );
    });
  });

  group('RecordingComposeBackend v2', () {
    final plan = PdfComposePlan(
      sources: const [],
      pages: const [
        PdfComposeBlankPage(noteSize: ui.Size(300, 200)),
        PdfComposeBlankPage(noteSize: ui.Size(300, 200)),
      ],
    );

    test(
      'records every part: job, page, z position, images, texts, fonts',
      () async {
        final backend = RecordingComposeBackend();
        final job = await backend.begin(plan);
        final sent = <int>{};
        final page0 = PdfComposeEncoder.encodeItems(
          outputIndex: 0,
          items: [
            _fill(0),
            _jpegCosting(_limit - 100),
            PdfImageItem(
              image: PdfRgbaData(
                Uint8List(16),
                width: 2,
                height: 2,
                hasAlpha: true,
              ),
              matrix: PdfAffine.identity,
            ),
            _text('안녕'),
          ],
          fontBytes: _fonts,
          sentFonts: sent,
        );
        expect(page0, hasLength(2));
        await job.addPages([page0[0]]);
        await job.addPages([
          page0[1],
          ...PdfComposeEncoder.encodeItems(
            outputIndex: 1,
            items: [_text('bold', fontId: PdfComposeOpcodes.fontBold)],
            fontBytes: _fonts,
            sentFonts: sent,
          ),
        ]);
        expect(backend.parts.map((p) => (p.job, p.outputIndex, p.part)), [
          (1, 0, 1),
          (1, 0, 2),
          (1, 1, 1),
        ]);
        expect(backend.parts[0].images, ['jpeg 1x1']);
        expect(backend.parts[1].images, ['rgba 2x2 alpha']);
        expect(backend.parts[1].texts, ['안녕']);
        expect(backend.parts[1].fontIds, [0]);
        expect(backend.parts[2].fontIds, [1]);
        expect(backend.parts[1].byteLength, page0[1].byteLength);
        expect(backend.partsOfPage(0), [same(page0[0]), same(page0[1])]);
        await job.finish();
      },
    );

    test('rejects what the real backends reject, records nothing', () async {
      final backend = RecordingComposeBackend();
      final job = await backend.begin(plan);
      await expectLater(
        job.addPages([
          _ops(
            [0, 1, 8],
            [0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 0],
            images: [_tinyJpeg],
          ),
        ]),
        throwsArgumentError,
      );
      final withFont = _encode([_text('a')], outputIndex: 0);
      await job.addPages(withFont);
      await expectLater(
        job.addPages(_encode([_text('b')], outputIndex: 1)), // font 0 again
        throwsArgumentError,
      );
      expect(backend.parts, hasLength(1));
      expect(backend.chunks, hasLength(1));
      await job.abort();
    });
  });
}
