// Compose probes (06-pdf 8 T13/T14, 6.11.3–6.11.5): one list of cases that both compose
// backends must pass — pdfium/compose_native_test (VM, FFI on the pdfrx worker) and
// web/compose_browser_test (Chrome, compose Worker). Each probe builds sources with
// PdfFixtureBuilder, composes a plan with marker ops through the backend under test and
// checks the output by opening it again with a PdfEngine (PdfrxEngine on both platforms):
// marker pixels where the note coordinates say, text kept, page order and sizes, no
// security handler. Web safe: no dart:io.
//
// (2차, m5-7/06-pdf T22/T23 — 6.1 E1–E4, 6.2.5, 6.2.6) composeObjectProbes: image and text
// ops on the real PDFium of each platform — text objects extract as the strings put in (one
// embedded TrueType per font id), glyph boxes of rotated text, JPEG as /DCTDecode at its own
// size, RGBA with alpha → /SMask and transparent pixels show what is under them, several
// parts of one page all kept, an image on a rotated original page, broken parts →
// exportFailed. The font bytes come from ComposeProbeContext.fontBytes (default
// ink.InkFonts.noteSansBytes: the real NoteSans on the VM, the INK test font after
// useInkTestFonts() in Chrome — every probe sentence is inside the test font's characters).
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/export/object_geometry.dart';
import 'package:pdf_io/testing.dart';

typedef ComposeProbeBody = Future<void> Function(ComposeProbeContext ctx);

final class ComposeProbe {
  const ComposeProbe(this.name, this.body);
  final String name;
  final ComposeProbeBody body;
}

/// What a probe runs against. Opened output documents are disposed by [dispose].
final class ComposeProbeContext {
  ComposeProbeContext({
    required this.backend,
    required this.engine,
    Future<Uint8List> Function({bool bold})? fontBytes,
  }) : fontBytes = fontBytes ?? ink.InkFonts.noteSansBytes;

  final PdfComposeBackend backend;
  final PdfEngine engine;

  /// TrueType bytes for the object probes' text (regular / bold).
  final Future<Uint8List> Function({bool bold}) fontBytes;
  final List<PdfEngineDocument> _opened = [];
  static var _sources = 0;

  /// begin → addPages (in [chunks] calls, each page whole) → finish.
  Future<Uint8List> compose(
    PdfComposePlan plan,
    List<PdfComposePageOps> ops, {
    int chunks = 1,
  }) async {
    final job = await backend.begin(plan);
    try {
      final size = ops.isEmpty ? 1 : (ops.length / chunks).ceil();
      for (var i = 0; i < ops.length; i += size) {
        final end = i + size < ops.length ? i + size : ops.length;
        await job.addPages(ops.sublist(i, end));
      }
      return await job.finish();
    } on Object {
      await job.abort();
      rethrow;
    }
  }

  Future<ComposedPdf> open(
    Uint8List bytes, {
    PdfPasswordCallback? onPassword,
  }) async {
    final doc = await engine.open(
      bytes,
      sourceName: 'compose-probe:${_sources++}',
      fileName: 'composed.pdf',
      onPassword: onPassword,
    );
    _opened.add(doc);
    return ComposedPdf(doc);
  }

  Future<void> dispose() async {
    for (final doc in _opened) {
      await doc.dispose();
    }
    _opened.clear();
  }
}

final class ComposedPdf {
  ComposedPdf(this.doc);
  final PdfEngineDocument doc;

  int get pageCount => doc.info.pageCount;

  ui.Size sizeOf(int page) =>
      ui.Size(doc.info.pages[page].width, doc.info.pages[page].height);

  Future<String> text(int page) async => (await doc.loadText(page)).text;

  Future<ProbeImage> render(int page, {double scale = 1}) async {
    final image = await doc.render(
      PdfRenderRequest(pageIndex: page, scale: scale),
    );
    if (image == null) throw StateError('render of page $page was cancelled');
    try {
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return ProbeImage(data, image.width, image.height, scale);
    } finally {
      image.dispose();
    }
  }
}

/// RGBA pixels of a rendered page; rects and points are displayed pt.
final class ProbeImage {
  ProbeImage(this.rgba, this.width, this.height, this.scale);
  final ByteData rgba;
  final int width, height;
  final double scale;

  (int, int, int) pixel(ui.Offset pt) {
    final x = (pt.dx * scale).floor().clamp(0, width - 1);
    final y = (pt.dy * scale).floor().clamp(0, height - 1);
    final i = (y * width + x) * 4;
    return (rgba.getUint8(i), rgba.getUint8(i + 1), rgba.getUint8(i + 2));
  }

  /// Pixels matching [test] in the pixel box (whole image when null).
  int count(bool Function(int r, int g, int b) test, {ui.Rect? pixelBox}) {
    final box =
        pixelBox ?? ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    var n = 0;
    final y0 = box.top.floor().clamp(0, height),
        y1 = box.bottom.ceil().clamp(0, height);
    final x0 = box.left.floor().clamp(0, width),
        x1 = box.right.ceil().clamp(0, width);
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final i = (y * width + x) * 4;
        if (test(
          rgba.getUint8(i),
          rgba.getUint8(i + 1),
          rgba.getUint8(i + 2),
        )) {
          n++;
        }
      }
    }
    return n;
  }

  ui.Rect toPixels(ui.Rect pt) => ui.Rect.fromLTRB(
    pt.left * scale,
    pt.top * scale,
    pt.right * scale,
    pt.bottom * scale,
  );
}

// ---------------------------------------------------------------------------------------
// Markers.

const int markerArgb = 0xFFE01010;

bool isMarker(int r, int g, int b) => r > 170 && g < 100 && b < 100;

PdfFillItem markerItem(ui.Rect noteRect) =>
    PdfFillItem(path: PdfVectorPath.rect(noteRect), colorArgb: markerArgb);

PdfComposePageOps markerOps(int outputIndex, List<ui.Rect> noteRects) =>
    PdfComposeEncoder.encode(
      outputIndex: outputIndex,
      vectors: PdfPageVectors(ink: [for (final r in noteRects) markerItem(r)]),
    );

/// The marker fills [displayRects] (displayed pt) and nothing else on the page.
void expectMarkersAt(
  ProbeImage image,
  List<ui.Rect> displayRects, {
  String? reason,
}) {
  var inside = 0;
  for (final rect in displayRects) {
    final px = image.toPixels(rect);
    final inner = px.deflate(1.5);
    final area = inner.width.floor() * inner.height.floor();
    final hit = image.count(isMarker, pixelBox: inner);
    expect(
      hit,
      greaterThanOrEqualTo((area * 0.95).floor()),
      reason: '${reason ?? ''} marker pixels inside $rect (pt) = $px (px)',
    );
    inside += image.count(isMarker, pixelBox: px.inflate(1.5));
  }
  final total = image.count(isMarker);
  expect(
    total - inside,
    lessThanOrEqualTo(4),
    reason: '${reason ?? ''} marker pixels outside $displayRects',
  );
}

void expectNoMarker(ProbeImage image, {String? reason}) =>
    expect(image.count(isMarker), 0, reason: reason);

/// Applies a PDF matrix [a b c d e f] to a rect (axis-aligned scale + translate only).
ui.Rect applyFit(List<double> f, ui.Rect r) => ui.Rect.fromLTRB(
  f[0] * r.left + f[4],
  f[3] * r.top + f[5],
  f[0] * r.right + f[4],
  f[3] * r.bottom + f[5],
);

// ---------------------------------------------------------------------------------------
// Plans.

const core.AssetId _assetA = 'probe-a';
const core.AssetId _assetB = 'probe-b';

PdfComposeSource sourceOf(Uint8List bytes, {core.AssetId id = _assetA}) =>
    PdfComposeSource(assetId: id, bytes: bytes);

PdfComposeSourcePage sourcePage(int source, int index, ui.Size noteSize) =>
    PdfComposeSourcePage(
      sourceIndex: source,
      pdfPageIndex: index,
      noteSize: noteSize,
    );

Uint8List onePage(PdfFixturePage page) =>
    (PdfFixtureBuilder()..addPage(page)).build();

Future<void> _markerOnSourcePage(
  ComposeProbeContext ctx, {
  required PdfFixturePage page,
  required ui.Size noteSize,
  required List<ui.Rect> noteRects,
  required List<ui.Rect> expectedDisplayRects,
  ui.Size? displaySize, // the original page's displayed size; default noteSize
  double scale = 1,
  String? reason,
}) async {
  final bytes = await ctx.compose(
    PdfComposePlan(
      sources: [sourceOf(onePage(page))],
      pages: [sourcePage(0, 0, noteSize)],
    ),
    [markerOps(0, noteRects)],
  );
  final out = await ctx.open(bytes);
  expect(out.pageCount, 1);
  // The output page is the original page (its boxes and /Rotate) with the ink on top.
  final display = displaySize ?? noteSize;
  expect(out.sizeOf(0).width, closeTo(display.width, 0.01), reason: reason);
  expect(out.sizeOf(0).height, closeTo(display.height, 0.01), reason: reason);
  expectMarkersAt(
    await out.render(0, scale: scale),
    expectedDisplayRects,
    reason: reason,
  );
}

const ui.Size _a4 = ui.Size(595.2756, 841.8898);

/// All probes, in a fixed order.
List<ComposeProbe> composeProbes() => [
  for (final rotate in const [0, 90, 180, 270])
    ComposeProbe('rotation $rotate: marker at its note position', (ctx) {
      const rect = ui.Rect.fromLTWH(40, 30, 60, 40);
      final display = rotate == 90 || rotate == 270
          ? const ui.Size(300, 400)
          : const ui.Size(400, 300);
      return _markerOnSourcePage(
        ctx,
        page: PdfFixturePage(width: 400, height: 300, rotate: rotate),
        noteSize: display,
        noteRects: const [rect],
        expectedDisplayRects: const [rect],
        scale: 2,
        reason: 'rotate $rotate',
      );
    }),
  ComposeProbe('CropBox [36 72 576 756] + 90°: marker position', (ctx) {
    const rect = ui.Rect.fromLTWH(50, 40, 80, 50);
    return _markerOnSourcePage(
      ctx,
      page: const PdfFixturePage(
        mediaBox: [0, 0, 612, 792],
        cropBox: [36, 72, 576, 756],
        rotate: 90,
      ),
      noteSize: const ui.Size(684, 540),
      noteRects: const [rect],
      expectedDisplayRects: const [rect],
    );
  }),
  ComposeProbe(
    'MediaBox [−100 −50 512 742] + CropBox + 270°: marker position',
    (ctx) {
      const rect = ui.Rect.fromLTWH(60, 50, 70, 45);
      return _markerOnSourcePage(
        ctx,
        page: const PdfFixturePage(
          mediaBox: [-100, -50, 512, 742],
          cropBox: [-80, -30, 500, 700],
          rotate: 270,
        ),
        noteSize: const ui.Size(730, 580),
        noteRects: const [rect],
        expectedDisplayRects: const [rect],
      );
    },
  ),
  ComposeProbe('unbalanced CTM left by the original: marker position', (ctx) {
    const rect = ui.Rect.fromLTWH(40, 30, 60, 40);
    return _markerOnSourcePage(
      ctx,
      page: const PdfFixturePage(
        width: 400,
        height: 300,
        rawContent: '2 0 0 2 0 0 cm\n',
      ),
      noteSize: const ui.Size(400, 300),
      noteRects: const [rect],
      expectedDisplayRects: const [rect],
      scale: 2,
    );
  }),
  ComposeProbe('note 72×72 on a 50×50 PDF page: F scales uniformly', (ctx) {
    const note = ui.Size(72, 72);
    const rect = ui.Rect.fromLTWH(14.4, 14.4, 7.2, 7.2);
    final fit = PdfPageFit(
      notePageSize: note,
      pdfPageSize: const ui.Size(50, 50),
    );
    final expected = applyFit(fit.noteToPdfMatrix(), rect);
    expect(expected.left, closeTo(10, 1e-9));
    expect(expected.width, closeTo(5, 1e-9));
    return _markerOnSourcePage(
      ctx,
      page: const PdfFixturePage(width: 50, height: 50),
      noteSize: note,
      displaySize: const ui.Size(50, 50),
      noteRects: const [rect],
      expectedDisplayRects: [expected],
      scale: 8,
    );
  }),
  ComposeProbe(
    'A4 note on a Letter PDF page: F = PdfPageFit.noteToPdfMatrix()',
    (ctx) async {
      const letter = ui.Size(612, 792);
      final fit = PdfPageFit(notePageSize: _a4, pdfPageSize: letter);
      expect(fit.oy, closeTo(35.767, 1e-3));
      // One marker in the middle, one starting in the top letterbox band (note y < oy).
      const rects = [
        ui.Rect.fromLTWH(100, 300, 80, 60),
        ui.Rect.fromLTWH(300, 20, 40, 40),
      ];
      final f = fit.noteToPdfMatrix();
      final expected = [for (final r in rects) applyFit(f, r)];
      final bytes = await ctx.compose(
        PdfComposePlan(
          sources: [
            sourceOf(onePage(const PdfFixturePage(width: 612, height: 792))),
          ],
          pages: [sourcePage(0, 0, _a4)],
        ),
        [markerOps(0, rects)],
      );
      final out = await ctx.open(bytes);
      // The output page is the original Letter page; the band part falls outside it.
      expect(out.sizeOf(0), letter);
      final image = await out.render(0, scale: 1);
      expectMarkersAt(image, [
        expected[0],
        expected[1].intersect(ui.Offset.zero & letter),
      ]);
      // Same place as the screen layout: note → display with PdfPageFit.noteToPdf.
      expect(fit.noteToPdf(rects[0]).left, closeTo(expected[0].left, 1e-9));
      expect(fit.noteToPdf(rects[0]).top, closeTo(expected[0].top, 1e-9));
    },
  ),
  ComposeProbe(
    'highlighter: one Multiply object, crossing = single-segment color',
    (ctx) async {
      const page = ui.Size(200, 200);
      // Blue band under the left end shows the Multiply blend.
      final blue = PdfFillItem(
        path: PdfVectorPath.rect(const ui.Rect.fromLTWH(0, 0, 60, 200)),
        colorArgb: 0xFF0000FF,
      );
      final cross = PdfVectorPath(
        Uint8List.fromList(const [0, 1, 0, 1]),
        Float32List.fromList(const [20, 50, 180, 150, 20, 150, 180, 50]),
      );
      PdfStrokeItem highlighter(PdfVectorPath path) => PdfStrokeItem(
        path: path,
        colorArgb: 0xFFFFE600,
        opacity: 0.35,
        blend: PdfBlend.multiply,
        width: 16,
      );
      // Control page: the same cross as TWO objects darkens at the crossing.
      final halves = [
        PdfVectorPath(
          Uint8List.fromList(const [0, 1]),
          Float32List.fromList(const [20, 50, 180, 150]),
        ),
        PdfVectorPath(
          Uint8List.fromList(const [0, 1]),
          Float32List.fromList(const [20, 150, 180, 50]),
        ),
      ];
      final bytes = await ctx.compose(
        const PdfComposePlan(
          sources: [],
          pages: [
            PdfComposeBlankPage(noteSize: page),
            PdfComposeBlankPage(noteSize: page),
          ],
        ),
        [
          PdfComposeEncoder.encode(
            outputIndex: 0,
            vectors: PdfPageVectors(ink: [blue, highlighter(cross)]),
          ),
          PdfComposeEncoder.encode(
            outputIndex: 1,
            vectors: PdfPageVectors(
              ink: [for (final h in halves) highlighter(h)],
            ),
          ),
        ],
      );
      final out = await ctx.open(bytes);
      final one = await out.render(0, scale: 2);
      final single = one.pixel(const ui.Offset(150, 131.25));
      final crossing = one.pixel(const ui.Offset(100, 100));
      expect(single.$3, inInclusiveRange(140, 190), reason: 'single $single');
      expect((crossing.$1 - single.$1).abs(), lessThanOrEqualTo(4));
      expect((crossing.$2 - single.$2).abs(), lessThanOrEqualTo(4));
      expect(
        (crossing.$3 - single.$3).abs(),
        lessThanOrEqualTo(4),
        reason: 'crossing $crossing vs single $single',
      );
      final overBlue = one.pixel(const ui.Offset(30, 56.25));
      expect(overBlue.$1, lessThan(40), reason: 'Multiply over blue $overBlue');
      expect(overBlue.$3, greaterThan(120));
      final two = await out.render(1, scale: 2);
      final doubled = two.pixel(const ui.Offset(100, 100));
      expect(
        doubled.$3,
        lessThan(single.$3 - 20),
        reason: 'two objects overlap: $doubled vs $single',
      );
    },
  ),
  ComposeProbe('original text is kept under the ink', (ctx) async {
    final bytes = await ctx.compose(
      PdfComposePlan(
        sources: [
          sourceOf(
            onePage(
              const PdfFixturePage(
                width: 400,
                height: 300,
                texts: [PdfFixtureText('KEEPTEXT', x: 50, y: 200)],
              ),
            ),
          ),
        ],
        pages: [sourcePage(0, 0, const ui.Size(400, 300))],
      ),
      [
        markerOps(0, const [ui.Rect.fromLTWH(40, 30, 60, 40)]),
      ],
    );
    final out = await ctx.open(bytes);
    expect(await out.text(0), contains('KEEPTEXT'));
  }),
  ComposeProbe('sources A, blank, B, A: order and page sizes', (ctx) async {
    final a =
        (PdfFixtureBuilder()
              ..addPage(
                const PdfFixturePage(
                  width: 400,
                  height: 300,
                  texts: [PdfFixtureText('PAGEA0')],
                ),
              )
              ..addPage(
                const PdfFixturePage(
                  width: 300,
                  height: 500,
                  texts: [PdfFixtureText('PAGEA1')],
                ),
              ))
            .build();
    final b = onePage(
      const PdfFixturePage(
        width: 250,
        height: 250,
        texts: [PdfFixtureText('PAGEB0')],
      ),
    );
    const sizes = [
      ui.Size(300, 500),
      ui.Size(500, 400),
      ui.Size(250, 250),
      ui.Size(400, 300),
    ];
    final bytes = await ctx.compose(
      PdfComposePlan(
        sources: [
          sourceOf(a),
          sourceOf(b, id: _assetB),
        ],
        pages: [
          sourcePage(0, 1, sizes[0]),
          PdfComposeBlankPage(noteSize: sizes[1]),
          sourcePage(1, 0, sizes[2]),
          sourcePage(0, 0, sizes[3]),
        ],
      ),
      [
        for (var i = 0; i < 4; i++)
          markerOps(i, [ui.Rect.fromLTWH(10 + 20.0 * i, 10, 15, 15)]),
      ],
      chunks: 2,
    );
    final out = await ctx.open(bytes);
    expect(out.pageCount, 4);
    for (var i = 0; i < 4; i++) {
      expect(out.sizeOf(i), sizes[i], reason: 'page $i');
      expectMarkersAt(await out.render(i, scale: 2), [
        ui.Rect.fromLTWH(10 + 20.0 * i, 10, 15, 15),
      ], reason: 'page $i');
    }
    expect(await out.text(0), contains('PAGEA1'));
    expect((await out.text(1)).trim(), isEmpty);
    expect(await out.text(2), contains('PAGEB0'));
    expect(await out.text(3), contains('PAGEA0'));
  }),
  ComposeProbe('interleaved sources B, A, B, A, blank, A', (ctx) async {
    Uint8List doc(String name, int count) =>
        (PdfFixtureBuilder()..addPages(
              count,
              (i) => PdfFixturePage(
                width: 200,
                height: 200,
                texts: [PdfFixtureText('$name$i', x: 20, y: 100)],
              ),
            ))
            .build();
    const note = ui.Size(200, 200);
    final bytes = await ctx.compose(
      PdfComposePlan(
        sources: [
          sourceOf(doc('DOCA', 2)),
          sourceOf(doc('DOCB', 1), id: _assetB),
        ],
        pages: [
          sourcePage(1, 0, note),
          sourcePage(0, 1, note),
          sourcePage(1, 0, note),
          sourcePage(0, 0, note),
          const PdfComposeBlankPage(noteSize: note),
          sourcePage(0, 1, note),
        ],
      ),
      const [],
    );
    final out = await ctx.open(bytes);
    const expected = ['DOCB0', 'DOCA1', 'DOCB0', 'DOCA0', '', 'DOCA1'];
    expect(out.pageCount, expected.length);
    for (var i = 0; i < expected.length; i++) {
      final text = (await out.text(i)).trim();
      expect(text, expected[i], reason: 'page $i');
    }
  }),
  ComposeProbe('shared font: 50 pages, output ≤ source × 1.3', (ctx) async {
    final source =
        (PdfFixtureBuilder()..addPages(
              50,
              (i) => PdfFixturePage(
                texts: [
                  PdfFixtureText('Shared font page ${i + 1}'),
                  PdfFixtureText(
                    'The quick brown fox jumps over the lazy dog',
                    y: 120,
                  ),
                ],
              ),
            ))
            .build();
    final bytes = await ctx.compose(
      PdfComposePlan(
        sources: [sourceOf(source)],
        pages: [for (var i = 0; i < 50; i++) sourcePage(0, i, _a4)],
      ),
      const [],
    );
    expect(
      bytes.length,
      lessThanOrEqualTo(source.length * 1.3),
      reason: 'output ${bytes.length} B, source ${source.length} B',
    );
    final out = await ctx.open(bytes);
    expect(out.pageCount, 50);
    expect(await out.text(49), contains('Shared font page 50'));
  }),
  ComposeProbe(
    'the same PDF page twice; a page without ops stays the original (includeInk: false)',
    (ctx) async {
      const note = ui.Size(300, 200);
      final bytes = await ctx.compose(
        PdfComposePlan(
          sources: [
            sourceOf(
              onePage(
                const PdfFixturePage(
                  width: 300,
                  height: 200,
                  texts: [PdfFixtureText('TWICE', x: 20, y: 150)],
                ),
              ),
            ),
          ],
          pages: [sourcePage(0, 0, note), sourcePage(0, 0, note)],
        ),
        [
          PdfComposeEncoder.encode(
            outputIndex: 0,
            vectors: PdfPageVectors.empty,
          ),
          markerOps(1, const [ui.Rect.fromLTWH(30, 20, 50, 40)]),
        ],
      );
      final out = await ctx.open(bytes);
      expect(out.pageCount, 2);
      expectNoMarker(await out.render(0, scale: 2), reason: 'page 0');
      expectMarkersAt(await out.render(1, scale: 2), const [
        ui.Rect.fromLTWH(30, 20, 50, 40),
      ]);
      expect(await out.text(0), contains('TWICE'));
      expect(await out.text(1), contains('TWICE'));
    },
  ),
  ComposeProbe(
    'permission-password source: output has no security handler, text kept',
    (ctx) async {
      final source =
          (PdfFixtureBuilder()
                ..addPage(
                  const PdfFixturePage(
                    width: 300,
                    height: 200,
                    texts: [PdfFixtureText('SECRET', x: 20, y: 150)],
                  ),
                )
                ..encrypt(userPassword: ''))
              .build();
      final bytes = await ctx.compose(
        PdfComposePlan(
          sources: [sourceOf(source)],
          pages: [sourcePage(0, 0, const ui.Size(300, 200))],
        ),
        [
          markerOps(0, const [ui.Rect.fromLTWH(30, 20, 50, 40)]),
        ],
      );
      expect(_contains(bytes, '/Encrypt'), isFalse);
      var asked = 0;
      final out = await ctx.open(
        bytes,
        onPassword: (_) async {
          asked++;
          return null;
        },
      );
      expect(asked, 0);
      expect(out.doc.info.isEncrypted, isFalse);
      expect(await out.text(0), contains('SECRET'));
      expectMarkersAt(await out.render(0, scale: 2), const [
        ui.Rect.fromLTWH(30, 20, 50, 40),
      ]);
    },
  ),
  ComposeProbe('template underlay on a blank page: line pixels', (ctx) async {
    const page = ui.Size(300, 200);
    const paper = 0xFFFBF7EC, line = 0xFF3050A0;
    final bytes = await ctx.compose(
      const PdfComposePlan(
        sources: [],
        pages: [PdfComposeBlankPage(noteSize: page)],
      ),
      [
        PdfComposeEncoder.encode(
          outputIndex: 0,
          vectors: PdfPageVectors(
            underlay: [
              PdfFillItem(
                path: PdfVectorPath.rect(ui.Offset.zero & page),
                colorArgb: paper,
              ),
              PdfStrokeItem(
                path: PdfVectorPath(
                  Uint8List.fromList(const [0, 1, 0, 1]),
                  Float32List.fromList(const [
                    0,
                    60,
                    300,
                    60,
                    0,
                    140,
                    300,
                    140,
                  ]),
                ),
                colorArgb: line,
                width: 2,
                cap: PdfLineCap.butt,
                join: PdfLineJoin.miter,
              ),
            ],
          ),
        ),
      ],
    );
    final out = await ctx.open(bytes);
    expect(out.sizeOf(0), page);
    final image = await out.render(0, scale: 2);
    bool near((int, int, int) px, int argb) =>
        (px.$1 - (argb ~/ 0x10000) % 0x100).abs() <= 12 &&
        (px.$2 - (argb ~/ 0x100) % 0x100).abs() <= 12 &&
        (px.$3 - argb % 0x100).abs() <= 12;
    for (final x in const [10.0, 150.0, 290.0]) {
      for (final y in const [60.0, 140.0]) {
        final px = image.pixel(ui.Offset(x, y - 0.25));
        expect(near(px, line), isTrue, reason: 'line at ($x, $y): $px');
      }
      for (final y in const [30.0, 56.0, 64.0, 100.0, 180.0]) {
        final px = image.pixel(ui.Offset(x, y));
        expect(near(px, paper), isTrue, reason: 'paper at ($x, $y): $px');
      }
    }
  }),
  ComposeProbe('a source that is not a PDF → exportFailed', (ctx) async {
    await expectLater(
      ctx.backend.begin(
        PdfComposePlan(
          sources: [sourceOf(Uint8List.fromList('%PDF-1.4 broken'.codeUnits))],
          pages: [sourcePage(0, 0, const ui.Size(100, 100))],
        ),
      ),
      throwsA(_code(PdfErrorCode.exportFailed)),
    );
  }),
  ComposeProbe('a PDF page index beyond the source → exportFailed', (
    ctx,
  ) async {
    await expectLater(
      ctx.backend.begin(
        PdfComposePlan(
          sources: [sourceOf(onePage(const PdfFixturePage()))],
          pages: [sourcePage(0, 0, _a4), sourcePage(0, 1, _a4)],
        ),
      ),
      throwsA(_code(PdfErrorCode.exportFailed)),
    );
  }),
  ComposeProbe('job lifecycle: abort is idempotent, no calls after finish', (
    ctx,
  ) async {
    const plan = PdfComposePlan(
      sources: [],
      pages: [PdfComposeBlankPage(noteSize: ui.Size(100, 100))],
    );
    final aborted = await ctx.backend.begin(plan);
    await aborted.abort();
    await aborted.abort();
    expect(() => aborted.addPages(const []), throwsStateError);
    expect(aborted.finish, throwsStateError);
    final finished = await ctx.backend.begin(plan);
    final bytes = await finished.finish();
    expect((await ctx.open(bytes)).pageCount, 1);
    expect(() => finished.addPages(const []), throwsStateError);
    await finished.abort(); // no-op after finish
  }),
];

Matcher _code(PdfErrorCode code) =>
    isA<PdfIoException>().having((e) => e.code, 'code', code);

bool _contains(Uint8List bytes, String ascii) {
  final pattern = ascii.codeUnits;
  outer:
  for (var i = 0; i + pattern.length <= bytes.length; i++) {
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) continue outer;
    }
    return true;
  }
  return false;
}

// ---------------------------------------------------------------------------------------
// (2차, m5-7/06-pdf T22/T23) Object probes — image and text ops.

/// One image XObject of a saved PDF (read from its dictionary — PDFium writes them as plain
/// dictionaries, so the same scan works on both platforms).
final class ProbePdfImage {
  const ProbePdfImage({
    required this.objectNumber,
    required this.width,
    required this.height,
    required this.filter,
    required this.smask,
  });
  final int objectNumber;
  final int width, height;
  final String? filter; // first filter name, e.g. 'DCTDecode'
  final int? smask; // object number of its /SMask

  @override
  String toString() =>
      'image #$objectNumber ${width}x$height /$filter smask: $smask';
}

/// The object dictionaries of a saved PDF (stream data skipped).
final class ProbePdfObjects {
  factory ProbePdfObjects(Uint8List bytes) {
    final text = latin1.decode(bytes);
    final header = RegExp(r'(\d+)\s+\d+\s+obj\b');
    final dicts = <int, String>{};
    var from = 0;
    while (true) {
      final m = header.firstMatch(text.substring(from));
      if (m == null) break;
      final start = from + m.end;
      final endobj = text.indexOf('endobj', start);
      final stream = text.indexOf('stream', start);
      final end = endobj < 0 ? text.length : endobj;
      final dictEnd = stream >= 0 && stream < end ? stream : end;
      dicts[int.parse(m.group(1)!)] = text.substring(start, dictEnd);
      if (stream >= 0 && stream < end) {
        final endstream = text.indexOf('endstream', stream);
        from = endstream < 0 ? text.length : endstream + 9;
      } else {
        from = end < text.length ? end + 6 : text.length;
      }
    }
    return ProbePdfObjects._(dicts);
  }

  ProbePdfObjects._(this.dicts);

  /// object number → dictionary text
  final Map<int, String> dicts;

  /// Every image XObject (soft masks included).
  List<ProbePdfImage> get allImages => [
    for (final MapEntry(key: n, value: d) in dicts.entries)
      if (RegExp(r'/Subtype\s*/Image\b').hasMatch(d))
        ProbePdfImage(
          objectNumber: n,
          width: _int(d, 'Width') ?? -1,
          height: _int(d, 'Height') ?? -1,
          filter: RegExp(r'/Filter\s*\[?\s*/(\w+)').firstMatch(d)?.group(1),
          smask: int.tryParse(
            RegExp(r'/SMask\s+(\d+)\s+\d+\s+R').firstMatch(d)?.group(1) ?? '',
          ),
        ),
  ];

  /// The image objects a page draws (not the soft masks other images point at).
  List<ProbePdfImage> get images {
    final all = allImages;
    final masks = {for (final i in all) ?i.smask};
    return [
      for (final i in all)
        if (!masks.contains(i.objectNumber)) i,
    ];
  }

  /// Embedded TrueType files (one per loaded font).
  int get fontFiles =>
      dicts.values.where((d) => RegExp(r'/FontFile2\b').hasMatch(d)).length;

  static int? _int(String dict, String key) =>
      int.tryParse(RegExp('/$key\\s+(\\d+)').firstMatch(dict)?.group(1) ?? '');
}

/// The image's unit square onto [rect] (note pt).
PdfImageItem imageAt(PdfImageData image, ui.Rect rect) =>
    PdfImageItem(image: image, matrix: unitSquareToRect(rect));

/// One text line with its baseline start at ([x], [baselineY]) in [frame] (frame-local pt),
/// placed by the frame (rotation about its centre) — the resolver's F ∘ T (6.2.3).
PdfTextItem textLine(
  String text, {
  required core.ElementFrame frame,
  double x = 0,
  required double baselineY,
  double fontSize = 18,
  bool bold = false,
  int colorArgb = 0xFF202020,
}) => PdfTextItem(
  text: text,
  fontId: bold ? PdfComposeOpcodes.fontBold : PdfComposeOpcodes.fontRegular,
  fontSize: fontSize,
  colorArgb: colorArgb,
  matrix: textSpaceAt(x, baselineY).then(PdfAffine.frame(frame)),
);

/// The parts of one page for [items] (fonts from [ProbeFonts]; a fresh job each call).
Future<List<PdfComposePageOps>> partsOf(
  ComposeProbeContext ctx,
  int outputIndex,
  List<PdfDrawItem> items, {
  Set<int>? sentFonts,
}) async => PdfComposeEncoder.encodeItems(
  outputIndex: outputIndex,
  items: items,
  fontBytes: {
    PdfComposeOpcodes.fontRegular: await ctx.fontBytes(),
    PdfComposeOpcodes.fontBold: await ctx.fontBytes(bold: true),
  },
  sentFonts: sentFonts ?? {},
);

/// Straight RGBA: the left half opaque [left], the right half [right] at [rightAlpha].
PdfRgbaData halfAndHalf(
  int width,
  int height, {
  required (int, int, int) left,
  required (int, int, int) right,
  int rightAlpha = 0,
}) {
  final rgba = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final (r, g, b) = x < width ~/ 2 ? left : right;
      rgba[i] = r;
      rgba[i + 1] = g;
      rgba[i + 2] = b;
      rgba[i + 3] = x < width ~/ 2 ? 255 : rightAlpha;
    }
  }
  return PdfRgbaData(
    rgba,
    width: width,
    height: height,
    hasAlpha: rightAlpha < 255,
  );
}

bool _near((int, int, int) px, (int, int, int) want, {int tolerance = 14}) =>
    (px.$1 - want.$1).abs() <= tolerance &&
    (px.$2 - want.$2).abs() <= tolerance &&
    (px.$3 - want.$3).abs() <= tolerance;

/// PdfObjectFixtures.jpegBaseline64x48 drawn into [rect] (displayed pt, upright): its four
/// quadrant colours where they belong (top-left blue, top-right red, bottom-left green,
/// bottom-right yellow — Pillow values (66, 61, 128), (193, 59, 30), (66, 180, 128),
/// (195, 181, 32)).
void expectBaselineJpegAt(ProbeImage image, ui.Rect rect, {String? reason}) {
  ui.Offset at(double fx, double fy) =>
      ui.Offset(rect.left + rect.width * fx, rect.top + rect.height * fy);
  final cases = <String, ((double, double), (int, int, int))>{
    'top-left': ((0.25, 0.25), (66, 61, 128)),
    'top-right': ((0.75, 0.25), (193, 59, 30)),
    'bottom-left': ((0.25, 0.75), (66, 180, 128)),
    'bottom-right': ((0.75, 0.75), (195, 181, 32)),
  };
  for (final MapEntry(key: name, value: ((fx, fy), want)) in cases.entries) {
    final px = image.pixel(at(fx, fy));
    expect(
      _near(px, want, tolerance: 30),
      isTrue,
      reason: '${reason ?? ''} $name of the JPEG at $rect: $px, want ~$want',
    );
  }
  for (final outside in [
    rect.topLeft - const ui.Offset(4, 4),
    rect.bottomRight + const ui.Offset(4, 4),
  ]) {
    expect(
      _near(image.pixel(outside), (255, 255, 255), tolerance: 6),
      isTrue,
      reason: '${reason ?? ''} paper outside the JPEG at $outside',
    );
  }
}

/// Dark (text) pixels inside [rect] (displayed pt).
int _inkIn(ProbeImage image, ui.Rect rect) => image.count(
  (r, g, b) => r < 128 && g < 128 && b < 128,
  pixelBox: image.toPixels(rect),
);

/// Lines of PDFium's page text (\r\n separated), trimmed, empty ones dropped. U+00A0 reads
/// as a space: PDFium's ToUnicode for a loaded TrueType maps the space glyph to the last code
/// point of the font's cmap that uses it — NoteSans maps U+0020 and U+00A0 to one glyph, so
/// the VM extracts NBSP (the Chrome test font has no U+00A0 and gives U+0020). CORE
/// SearchText folds both as whitespace (7.2.5), so search does not see the difference.
List<String> _lines(String text) => [
  for (final line in text.replaceAll('\u00A0', ' ').split(RegExp(r'\r?\n')))
    if (line.trim().isNotEmpty) line.trim(),
];

const ui.Size _objectsPage = ui.Size(300, 200);

const PdfComposePlan _blankObjectsPage = PdfComposePlan(
  sources: [],
  pages: [PdfComposeBlankPage(noteSize: _objectsPage)],
);

core.ElementFrame _frame(ui.Rect rect, {double rotation = 0}) =>
    core.ElementFrame(
      core.PageRect(rect.left, rect.top, rect.right, rect.bottom),
      rotation: rotation,
    );

/// All object probes, in a fixed order (pdfium/compose_objects_native_test on the VM,
/// web/compose_objects_browser_test in Chrome — the same assertions).
List<ComposeProbe> composeObjectProbes() => [
  ComposeProbe(
    'text objects: Korean and Latin lines extract as the strings put in',
    (ctx) async {
      final frame = _frame(const ui.Rect.fromLTWH(20, 30, 260, 120));
      final bytes = await ctx.compose(_blankObjectsPage, [
        ...await partsOf(ctx, 0, [
          textLine('안녕 hello', frame: frame, baselineY: 30),
          textLine('한글 텍스트 상자', frame: frame, baselineY: 80, fontSize: 16),
        ]),
      ]);
      final objects = ProbePdfObjects(bytes);
      expect(objects.fontFiles, 1, reason: 'one font id → one embedded file');
      expect(objects.images, isEmpty);
      final out = await ctx.open(bytes);
      final text = await out.doc.loadText(0);
      expect(_lines(text.text), ['안녕 hello', '한글 텍스트 상자']);
      // The first glyph's box sits on the first baseline (note y 60), starting at x 20.
      final first = text.charRects[text.text.indexOf('안')];
      expect(first.left, closeTo(20, 3), reason: 'box of 안: $first');
      expect(first.bottom, closeTo(60, 4), reason: 'box of 안: $first');
      expect(first.top, lessThan(60 - 8), reason: 'box of 안: $first');
      final second = text.charRects[text.text.indexOf('한')];
      expect(second.bottom, closeTo(110, 4), reason: 'box of 한: $second');
      final image = await out.render(0, scale: 2);
      expect(
        _inkIn(image, const ui.Rect.fromLTWH(18, 40, 140, 24)),
        greaterThan(100),
        reason: 'glyph pixels of the first line',
      );
    },
  ),
  ComposeProbe('text objects: bold is a second embedded font', (ctx) async {
    final frame = _frame(const ui.Rect.fromLTWH(20, 30, 260, 120));
    final bytes = await ctx.compose(_blankObjectsPage, [
      ...await partsOf(ctx, 0, [
        textLine('hello', frame: frame, baselineY: 30),
        textLine('안녕', frame: frame, baselineY: 70, bold: true),
        textLine('줄 1', frame: frame, baselineY: 110),
      ]),
    ]);
    expect(ProbePdfObjects(bytes).fontFiles, 2);
    final out = await ctx.open(bytes);
    expect(_lines(await out.text(0)), ['hello', '안녕', '줄 1']);
  }),
  ComposeProbe(
    'text objects: a line rotated 30° — glyph boxes along the turned baseline',
    (ctx) async {
      const rect = ui.Rect.fromLTWH(60, 60, 180, 40);
      final frame = _frame(rect, rotation: math.pi / 6);
      final bytes = await ctx.compose(_blankObjectsPage, [
        ...await partsOf(ctx, 0, [
          textLine('hello hello', frame: frame, x: 4, baselineY: 28),
        ]),
      ]);
      final out = await ctx.open(bytes);
      final text = await out.doc.loadText(0);
      expect(_lines(text.text), ['hello hello']);
      final boxes = [
        for (var i = 0; i < text.text.length; i++)
          if (text.text[i].trim().isNotEmpty) text.charRects[i],
      ];
      expect(boxes, hasLength(10));
      final a = boxes.first.center, b = boxes.last.center;
      final angle = math.atan2(b.dy - a.dy, b.dx - a.dx) * 180 / math.pi;
      expect(angle, closeTo(30, 3), reason: 'centres $a → $b');
      // The baseline start (frame-local (4, 28)) is at the first glyph.
      final start = PdfAffine.frame(frame).apply(const ui.Offset(4, 28));
      expect(
        boxes.first.inflate(4).contains(start),
        isTrue,
        reason: 'first glyph box ${boxes.first}, baseline start $start',
      );
    },
  ),
  ComposeProbe('image objects: a JPEG goes in as /DCTDecode at its own size', (
    ctx,
  ) async {
    const rect = ui.Rect.fromLTWH(40, 30, 128, 96);
    final jpeg = PdfJpegData(
      PdfObjectFixtures.jpegBaseline64x48,
      width: 64,
      height: 48,
    );
    final bytes = await ctx.compose(_blankObjectsPage, [
      ...await partsOf(ctx, 0, [imageAt(jpeg, rect)]),
    ]);
    final objects = ProbePdfObjects(bytes);
    expect(objects.images, hasLength(1), reason: '${objects.allImages}');
    final image = objects.images.single;
    expect(image.filter, 'DCTDecode', reason: '$image');
    expect((image.width, image.height), (64, 48));
    expect(image.smask, isNull);
    expect(objects.fontFiles, 0);
    final out = await ctx.open(bytes);
    expectBaselineJpegAt(await out.render(0, scale: 2), rect);
  }),
  ComposeProbe(
    'image objects: RGBA with alpha gets an /SMask, its transparent half shows the paper',
    (ctx) async {
      const paper = (251, 247, 236);
      const withAlpha = ui.Rect.fromLTWH(20, 20, 160, 60);
      const opaque = ui.Rect.fromLTWH(20, 110, 160, 60);
      final bytes = await ctx.compose(_blankObjectsPage, [
        ...await partsOf(ctx, 0, [
          PdfFillItem(
            path: PdfVectorPath.rect(ui.Offset.zero & _objectsPage),
            colorArgb: 0xFFFBF7EC,
          ),
          imageAt(
            halfAndHalf(40, 16, left: (20, 40, 220), right: (230, 20, 20)),
            withAlpha,
          ),
          imageAt(
            halfAndHalf(
              40,
              16,
              left: (20, 160, 60),
              right: (240, 200, 0),
              rightAlpha: 255,
            ),
            opaque,
          ),
        ]),
      ]);
      final objects = ProbePdfObjects(bytes);
      expect(objects.images, hasLength(2), reason: '${objects.allImages}');
      expect(
        [for (final i in objects.images) i.smask != null],
        unorderedEquals([true, false]),
        reason:
            'only the image with alpha has a soft mask: ${objects.allImages}',
      );
      final masked = objects.images.firstWhere((i) => i.smask != null);
      expect((masked.width, masked.height), (40, 16));
      final out = await ctx.open(bytes);
      final image = await out.render(0, scale: 2);
      ui.Offset at(ui.Rect r, double fx) =>
          ui.Offset(r.left + r.width * fx, r.center.dy);
      expect(_near(image.pixel(at(withAlpha, 0.25)), (20, 40, 220)), isTrue);
      expect(
        _near(image.pixel(at(withAlpha, 0.75)), paper),
        isTrue,
        reason: 'transparent half: ${image.pixel(at(withAlpha, 0.75))}',
      );
      expect(_near(image.pixel(at(opaque, 0.25)), (20, 160, 60)), isTrue);
      expect(_near(image.pixel(at(opaque, 0.75)), (240, 200, 0)), isTrue);
      expect(_near(image.pixel(const ui.Offset(250, 100)), paper), isTrue);
    },
  ),
  ComposeProbe(
    'parts: two parts of one page in two addPages calls — every object kept, in order',
    (ctx) async {
      const jpegRect = ui.Rect.fromLTWH(20, 20, 96, 72);
      const markerA = ui.Rect.fromLTWH(150, 20, 40, 30);
      const markerB = ui.Rect.fromLTWH(220, 20, 40, 30);
      final gray = PdfJpegData(
        PdfObjectFixtures.jpegGray64x48,
        width: 64,
        height: 48,
      );
      final sent = <int>{};
      final frame = _frame(const ui.Rect.fromLTWH(20, 120, 260, 60));
      final first = await partsOf(ctx, 0, [
        imageAt(gray, jpegRect),
        markerItem(markerA),
      ], sentFonts: sent);
      final second = await partsOf(ctx, 0, [
        textLine('안녕 hello', frame: frame, baselineY: 30),
        markerItem(markerB),
        // On top of the JPEG's right half: drawn after it, so it covers it.
        markerItem(const ui.Rect.fromLTWH(80, 30, 30, 20)),
      ], sentFonts: sent);
      expect((first.length, second.length), (1, 1));
      final bytes = await ctx.compose(_blankObjectsPage, [
        ...first,
        ...second,
      ], chunks: 2);
      final objects = ProbePdfObjects(bytes);
      expect(objects.images, hasLength(1));
      expect(objects.fontFiles, 1);
      final out = await ctx.open(bytes);
      expect(_lines(await out.text(0)), ['안녕 hello']);
      final image = await out.render(0, scale: 2);
      for (final rect in [
        markerA,
        markerB,
        const ui.Rect.fromLTWH(80, 30, 30, 20),
      ]) {
        final px = image.toPixels(rect).deflate(1.5);
        expect(
          image.count(isMarker, pixelBox: px),
          greaterThanOrEqualTo(
            (px.width.floor() * px.height.floor() * 0.95).floor(),
          ),
          reason: 'marker at $rect',
        );
      }
      // The gray JPEG where the second part did not cover it: grays grow right and down.
      final tl = image.pixel(const ui.Offset(32, 30));
      final bl = image.pixel(const ui.Offset(32, 80));
      expect(
        tl.$1 == tl.$2 && tl.$2 == tl.$3 || (tl.$1 - tl.$3).abs() < 8,
        isTrue,
        reason: 'gray $tl',
      );
      expect(bl.$1, greaterThan(tl.$1 + 30), reason: 'gray $tl above $bl');
    },
  ),
  ComposeProbe(
    'image objects: a JPEG on a 90°-rotated original page sits at its note position',
    (ctx) async {
      const rect = ui.Rect.fromLTWH(40, 30, 128, 96);
      const display = ui.Size(300, 400);
      final jpeg = PdfJpegData(
        PdfObjectFixtures.jpegBaseline64x48,
        width: 64,
        height: 48,
      );
      final bytes = await ctx.compose(
        PdfComposePlan(
          sources: [
            sourceOf(
              onePage(
                const PdfFixturePage(width: 400, height: 300, rotate: 90),
              ),
            ),
          ],
          pages: [sourcePage(0, 0, display)],
        ),
        [
          ...await partsOf(ctx, 0, [imageAt(jpeg, rect)]),
        ],
      );
      final out = await ctx.open(bytes);
      expect(out.sizeOf(0).width, closeTo(display.width, 0.01));
      expect(out.sizeOf(0).height, closeTo(display.height, 0.01));
      expectBaselineJpegAt(await out.render(0, scale: 2), rect);
    },
  ),
  ComposeProbe('parts: a text op whose font no part carried → exportFailed', (
    ctx,
  ) async {
    final frame = _frame(const ui.Rect.fromLTWH(20, 30, 200, 40));
    final parts = PdfComposeEncoder.encodeItems(
      outputIndex: 0,
      items: [textLine('hello', frame: frame, baselineY: 20)],
      fontBytes: const {},
      sentFonts: {PdfComposeOpcodes.fontRegular}, // pretend it was sent
    );
    final job = await ctx.backend.begin(_blankObjectsPage);
    try {
      await expectLater(
        job.addPages(parts),
        throwsA(_code(PdfErrorCode.exportFailed)),
      );
    } finally {
      await job.abort();
    }
  }),
  ComposeProbe('parts: the same font id carried twice → exportFailed', (
    ctx,
  ) async {
    final frame = _frame(const ui.Rect.fromLTWH(20, 30, 200, 40));
    Future<List<PdfComposePageOps>> fresh() =>
        partsOf(ctx, 0, [textLine('hello', frame: frame, baselineY: 20)]);
    final job = await ctx.backend.begin(_blankObjectsPage);
    try {
      await job.addPages(await fresh());
      await expectLater(
        job.addPages(await fresh()),
        throwsA(_code(PdfErrorCode.exportFailed)),
      );
    } finally {
      await job.abort();
    }
  }),
];
