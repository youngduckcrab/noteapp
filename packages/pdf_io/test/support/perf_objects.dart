// Shared set-up of the object export performance tests (m5-7/06-pdf 6.2.10 · 9.5; 8.2 T29 —
// P-C): a 50-page note whose every page has four text boxes, one photo, one formula and 200
// strokes, exported through the export service v2 on the compose backend under test —
// perf/compose_objects_perf_test (VM, native backend, ≤ 6 s) and web/perf_compose_objects_test
// (Chrome, compose Worker, ≤ 15 s). Web-safe: no dart:io.
//
// What is real and what stands in: the export service v2, the object resolver, the encoder, the
// compose backend and the NoteSans bytes (the INK test font in Chrome) are real; the page plan
// comes from [ObjectsPerfVectorizer] (INK's vector export v2 is an integration-stage dependency —
// INK T42), the formula raster from FakeMathRasterizer (a solid RGBA of the 300 dpi size — the
// real InkMathRenderer.rasterize is INK T36), and the photo is the 64 × 48 baseline JPEG padded
// with COM segments to the size of a 1600 × 1200 photo (≈ 300 KB — pdf_io cannot encode a JPEG;
// the fast path embeds the bytes as they are, so the byte volume is what costs).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/export/export_memory.dart';
import 'package:pdf_io/src/export/export_service.dart';
import 'package:pdf_io/src/export/object_resolver.dart' show PdfFontBytesSource;
import 'package:pdf_io/testing.dart';

import 'export_world.dart' show ObjectsGateway;
import 'fake_rasterizers.dart';
import 'perf_compose.dart';

const int objectsPerfPages = 50;
const int objectsPerfStrokesPerPage = 200;
const int objectsPerfTextBoxesPerPage = 4;
const int objectsPerfPhotoBytes = 300 * 1024;

/// The text box lines (inside the INK Chrome test font — tool/fonts/test_font_chars.txt).
const List<String> objectsPerfLines = ['한글 텍스트 상자', '안녕 hello'];

/// [jpeg] with COM segments after SOI until it is at least [minBytes] (still a valid JPEG).
Uint8List paddedJpegBytes(Uint8List jpeg, int minBytes) {
  final out = BytesBuilder(copy: false)..add(jpeg.sublist(0, 2)); // SOI
  var size = jpeg.length;
  const chunk = 65533; // the largest COM payload
  while (size < minBytes) {
    final n = minBytes - size < chunk ? minBytes - size : chunk;
    out
      ..add([0xFF, 0xFE, (n + 2) >> 8, (n + 2) & 0xFF])
      ..add(Uint8List(n));
    size += n + 4;
  }
  out.add(jpeg.sublist(2));
  return out.takeBytes();
}

core.ElementFrame _frame(double l, double t, double w, double h) =>
    core.ElementFrame(core.PageRect(l, t, l + w, t + h));

/// The plan of every page: the photo, 200 strokes (a tenth highlighter — DenseStrokeVectorizer),
/// four text boxes of two lines and a formula — the objects of 6.2.10's perf note.
final class ObjectsPerfVectorizer implements PdfInkVectorizer {
  const ObjectsPerfVectorizer();

  static const DenseStrokeVectorizer _strokes = DenseStrokeVectorizer(
    strokesPerPage: objectsPerfStrokesPerPage,
    cubicsPerStroke: 12,
  );

  @override
  PdfPagePlan planPage(
    core.PageContent content, {
    required bool includeInk,
    required bool includeTemplate,
  }) {
    if (!includeInk) return PdfPagePlan.empty;
    final page = content.page;
    return PdfPagePlan([
      PdfAssetImageRef.object(
        assetId: 'photo',
        frame: _frame(60, 60, 320, 240),
      ),
      ..._strokes
          .vectorize(page, const [], includeInk: true, includeTemplate: false)
          .ink,
      for (var i = 0; i < objectsPerfTextBoxesPerPage; i++)
        PdfTextBoxRef(
          core.TextBoxObject(
            id: '${page.id}-text-$i',
            pageId: page.id,
            frame: _frame(60, 340 + 90.0 * i, 300, 60),
            text: objectsPerfLines.join('\n'),
            style: const core.TextBoxStyle(fontSizePt: 16),
            createdAt: 10 + i,
          ),
          [
            for (var l = 0; l < objectsPerfLines.length; l++)
              (
                text: objectsPerfLines[l],
                x: 0,
                baselineY: 18.0 + 24 * l,
                width: 200,
              ),
          ],
        ),
      PdfMathRef(
        core.MathObject(
          id: '${page.id}-math',
          pageId: page.id,
          frame: _frame(400, 60, 140, 70),
          latex: r'\frac{a+b}{c}',
          style: const core.MathStyle(),
          createdAt: 20,
        ),
      ),
    ]);
  }

  @override
  PdfPageVectors vectorize(
    core.Page page,
    List<core.Stroke> strokes, {
    required bool includeInk,
    required bool includeTemplate,
  }) => PdfPageVectors.empty;
}

/// One measured export of the 50-page object note.
typedef ObjectsPerfRun = ({
  PdfExportResult result,
  Duration elapsed,
  ExportMemoryLedger ledger,
});

/// The 50 blank A4 pages in a FakePdfNoteGateway (+ the photo asset), exported with [backend].
final class ObjectsPerfWorld {
  ObjectsPerfWorld._(this._service, this._noteId);

  final DefaultPdfExportService _service;
  final core.NoteId _noteId;
  final List<ExportMemoryLedger> _ledgers = [];

  static Future<ObjectsPerfWorld> create(
    PdfComposeBackend backend, {
    PdfFontBytesSource? fontBytes,
  }) async {
    final gateway = FakePdfNoteGateway()
      ..arriveBytes(
        'photo',
        paddedJpegBytes(
          PdfObjectFixtures.jpegBaseline64x48,
          objectsPerfPhotoBytes,
        ),
      );
    final note = await gateway.createNote(
      title: 'objects perf',
      pages: [
        for (var i = 0; i < objectsPerfPages; i++) core.PageDraft.blankA4,
      ],
    );
    late final ObjectsPerfWorld world;
    final service = createPdfExportService(
      gateway: ObjectsGateway(gateway),
      vectorizer: const ObjectsPerfVectorizer(),
      backend: backend,
      math: FakeMathRasterizer(defaultLayout: const ui.Size(140, 70)),
      text: FakeTextRasterizer(),
      fontBytes: fontBytes,
      onLedger: (l) => world._ledgers.add(l),
    );
    return world = ObjectsPerfWorld._(service, note.id);
  }

  /// exportNote with the default options, timed (building the note and checking the output are
  /// not).
  Future<ObjectsPerfRun> export() async {
    final watch = Stopwatch()..start();
    final result = await _service.exportNote(_noteId, const PdfExportOptions());
    watch.stop();
    debugPrint(
      'objects perf: $objectsPerfPages pages in ${watch.elapsedMilliseconds} ms, '
      '${result.bytes.length} B, ledger peak ${_ledgers.last.peakBytes} B '
      '(copy ${_ledgers.last.peakCopyBytes} B)',
    );
    return (result: result, elapsed: watch.elapsed, ledger: _ledgers.last);
  }
}

/// The exported PDF: 50 pages, warnings none, the text box lines as text on the first and last
/// page, one photo and one formula raster per page; the ledger within 16 MiB.
Future<void> expectObjectsPerfOutput(
  PdfEngine engine,
  ObjectsPerfRun run,
) async {
  expect(run.result.pageCount, objectsPerfPages);
  expect(run.result.warnings, isEmpty);
  expect(run.ledger.peakBytes, lessThanOrEqualTo(16 * 1024 * 1024));
  final doc = await engine.open(
    run.result.bytes,
    sourceName: 'objects-perf-output',
    fileName: 'objects.pdf',
  );
  try {
    expect(doc.info.pageCount, objectsPerfPages);
    for (final page in [0, objectsPerfPages - 1]) {
      final text = (await doc.loadText(page)).text.replaceAll(' ', ' ');
      expect(text, contains(objectsPerfLines.first), reason: 'page $page');
    }
  } finally {
    await doc.dispose();
  }
}
