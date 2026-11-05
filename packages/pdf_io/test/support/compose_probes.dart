// Compose probes (06-pdf 8 T13/T14, 6.11.3–6.11.5): one list of cases that both compose
// backends must pass — pdfium/compose_native_test (VM, FFI on the pdfrx worker) and
// web/compose_browser_test (Chrome, compose Worker). Each probe builds sources with
// PdfFixtureBuilder, composes a plan with marker ops through the backend under test and
// checks the output by opening it again with a PdfEngine (PdfrxEngine on both platforms):
// marker pixels where the note coordinates say, text kept, page order and sizes, no
// security handler. Web safe: no dart:io.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

typedef ComposeProbeBody = Future<void> Function(ComposeProbeContext ctx);

final class ComposeProbe {
  const ComposeProbe(this.name, this.body);
  final String name;
  final ComposeProbeBody body;
}

/// What a probe runs against. Opened output documents are disposed by [dispose].
final class ComposeProbeContext {
  ComposeProbeContext({required this.backend, required this.engine});

  final PdfComposeBackend backend;
  final PdfEngine engine;
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
