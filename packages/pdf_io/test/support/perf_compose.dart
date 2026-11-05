// Shared set-up of the compose performance tests (06-pdf 8 T18, 6.1 V8, 6.11.1): a 500-page
// lecture PDF note in FakePdfNoteGateway, every page with 200 strokes of 50 cubic Béziers
// (100 000 strokes in all, the V8 measurement), exported through DefaultPdfExportService
// on the compose backend under test — perf/compose_500_native_test (VM, ≤ 30 s) and
// web/perf_compose_500_test (Chrome, ≤ 40 s). Web safe: no dart:io.
//
// The strokes come from DenseStrokeVectorizer (the INK vectorizer is an integration-stage
// dependency): the export pipeline still loads every page from the gateway, vectorizes,
// encodes, sends the ops in chunks and finishes — the vectorizer only skips INK's own
// outline maths.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

const int perfPages = 500;
const int perfStrokesPerPage = 200;
const int perfCubicsPerStroke = 50;

const int perfPenArgb = 0xFF1A237E; // dark blue pen
const int perfHighlighterArgb =
    0xFFFFE600; // yellow highlighter (multiply, 35%)

/// 500 A4 pages with one line of text each (built in the test, nothing committed).
Uint8List perfLecturePdf() =>
    (PdfFixtureBuilder()..addPages(
          perfPages,
          (i) =>
              PdfFixturePage(texts: [PdfFixtureText('Lecture page ${i + 1}')]),
        ))
        .build();

/// Every page gets [strokesPerPage] filled stroke outlines across the page, each one closed
/// subpath of [cubicsPerStroke] cubic Béziers (half along the top edge, half back along the
/// bottom edge). The first tenth are highlighter strokes (multiply, opacity 0.35), drawn
/// first as INK orders them (4.9). Paths are built per call like a real vectorizer.
final class DenseStrokeVectorizer implements PdfInkVectorizer {
  const DenseStrokeVectorizer({
    this.strokesPerPage = perfStrokesPerPage,
    this.cubicsPerStroke = perfCubicsPerStroke,
  });

  final int strokesPerPage;
  final int cubicsPerStroke;

  @override
  PdfPageVectors vectorize(
    core.Page page,
    List<core.Stroke> strokes, {
    required bool includeInk,
    required bool includeTemplate,
  }) {
    if (!includeInk) return PdfPageVectors.empty;
    final w = page.size.width, h = page.size.height;
    final highlighters = strokesPerPage ~/ 10;
    return PdfPageVectors(
      ink: [
        for (var k = 0; k < strokesPerPage; k++)
          k < highlighters
              ? PdfFillItem(
                  path: _outline(k, w, h, thickness: 8),
                  colorArgb: perfHighlighterArgb,
                  opacity: 0.35,
                  blend: PdfBlend.multiply,
                )
              : PdfFillItem(
                  path: _outline(k, w, h, thickness: 1.6),
                  colorArgb: perfPenArgb,
                ),
      ],
    );
  }

  PdfVectorPath _outline(
    int k,
    double w,
    double h, {
    required double thickness,
  }) {
    final top = cubicsPerStroke ~/ 2;
    final bottom = cubicsPerStroke - top;
    final verbs = Uint8List(cubicsPerStroke + 2);
    final coords = Float32List(2 + 6 * cubicsPerStroke);
    var v = 0, c = 0;
    void put(double x, double y) {
      coords[c++] = x;
      coords[c++] = y;
    }

    final y0 = h * 0.05 + h * 0.9 * (k + 0.5) / strokesPerPage;
    final x0 = w * 0.07, x1 = w * 0.93;
    final amplitude = 2.5 + (k % 7) * 0.5;
    // A wavy centre line; the outline is the line ± thickness / 2.
    double wave(double x) => y0 + amplitude * math.sin((x - x0) / 23 + k);

    verbs[v++] = PdfComposeOpcodes.moveTo;
    put(x0, wave(x0) - thickness / 2);
    for (var i = 0; i < top; i++) {
      final a = x0 + (x1 - x0) * i / top, b = x0 + (x1 - x0) * (i + 1) / top;
      final m1 = a + (b - a) / 3, m2 = a + 2 * (b - a) / 3;
      verbs[v++] = PdfComposeOpcodes.cubicTo;
      put(m1, wave(m1) - thickness / 2);
      put(m2, wave(m2) - thickness / 2);
      put(b, wave(b) - thickness / 2);
    }
    for (var i = 0; i < bottom; i++) {
      final a = x1 - (x1 - x0) * i / bottom;
      final b = x1 - (x1 - x0) * (i + 1) / bottom;
      final m1 = a + (b - a) / 3, m2 = a + 2 * (b - a) / 3;
      verbs[v++] = PdfComposeOpcodes.cubicTo;
      put(m1, wave(m1) + thickness / 2);
      put(m2, wave(m2) + thickness / 2);
      put(b, wave(b) + thickness / 2);
    }
    verbs[v++] = PdfComposeOpcodes.close;
    return PdfVectorPath(verbs, coords);
  }
}

/// One measured export of the 500-page note.
typedef PerfExportRun = ({PdfExportResult result, Duration elapsed});

/// The 500-page note (every page a PDF page of [perfLecturePdf]) in a FakePdfNoteGateway,
/// exported with [backend].
final class PerfComposeWorld {
  PerfComposeWorld._(this.gateway, this.note, this.service, this.sourceBytes);

  final FakePdfNoteGateway gateway;
  final core.Note note;
  final DefaultPdfExportService service;
  final int sourceBytes;

  static Future<PerfComposeWorld> create(PdfComposeBackend backend) async {
    final gateway = FakePdfNoteGateway();
    final pdf = perfLecturePdf();
    final asset = await gateway.putPdf(pdf, fileName: 'lecture-500.pdf');
    final note = await gateway.createNote(
      title: '강의 500쪽',
      pages: [
        for (var i = 0; i < perfPages; i++)
          core.PageDraft(
            size: core.PageSize.a4Portrait,
            background: core.PdfBackground(assetId: asset.id, pdfPageIndex: i),
          ),
      ],
    );
    final service = DefaultPdfExportService(
      gateway: gateway,
      vectorizer: const DenseStrokeVectorizer(),
      backend: backend,
    );
    return PerfComposeWorld._(gateway, note, service, pdf.length);
  }

  /// Times exportNote (all pages, ink on) from the call to the finished bytes.
  Future<PerfExportRun> export() async {
    final watch = Stopwatch()..start();
    final result = await service.exportNote(note.id, const PdfExportOptions());
    watch.stop();
    debugPrint(
      'perf compose: ${watch.elapsed.inMilliseconds} ms for $perfPages pages × '
      '$perfStrokesPerPage strokes ($perfCubicsPerStroke cubics each); '
      'output ${(result.bytes.length / (1024 * 1024)).toStringAsFixed(1)} MiB '
      '(source ${(sourceBytes / 1024).round()} KiB)',
    );
    return (result: result, elapsed: watch.elapsed);
  }
}

/// The exported PDF reopened with [engine]: 500 A4 pages in order, the original text kept,
/// and pen-coloured pixels on the first and last page.
Future<void> expectPerfOutput(PdfEngine engine, PdfExportResult result) async {
  expect(result.pageCount, perfPages);
  expect(result.warnings, isEmpty);
  final document = await engine.open(
    result.bytes,
    sourceName: 'perf-compose-output',
    fileName: result.fileName,
  );
  try {
    final info = document.info;
    expect(info.pageCount, perfPages);
    expect(info.pages.last.width, closeTo(595.28, 0.01));
    expect(info.pages.last.height, closeTo(841.89, 0.01));
    for (final page in [0, perfPages - 1]) {
      final text = (await document.loadText(page)).text;
      expect(text, contains('Lecture page ${page + 1}'));
      expect(await _penPixels(document, page), greaterThan(1000));
    }
  } finally {
    await document.dispose();
  }
}

/// Dark-blue pixels of [page] rendered at 0.5 px / pt.
Future<int> _penPixels(PdfEngineDocument document, int page) async {
  final image = await document.render(
    PdfRenderRequest(pageIndex: page, scale: 0.5),
  );
  if (image == null) throw StateError('render of page $page was cancelled');
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    var n = 0;
    for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
      final r = data.getUint8(i), g = data.getUint8(i + 1);
      final b = data.getUint8(i + 2);
      if (b > 90 && r < 90 && g < 90) n++;
    }
    return n;
  } finally {
    image.dispose();
  }
}
