// V11 (m5-7/06-pdf 8.3 4-a VM · 4-b Chrome; 8.2 T29 — PDF-M14): the app's real wiring
// (support/real_wiring.dart) over the REAL CORE store, the REAL INK export and real PDFium. A
// note with the four object kinds (image object, rectangle shape, text box, formula), an image
// page, a dashed stroke and tape → PdfExportService.exportNote → the PDF reopened:
//   - the text box's Hangul line is text (extracted by PDFium),
//   - image objects in the file = image objects + image backgrounds + one formula raster (the
//     two JPEGs as /DCTDecode, the raster the only image with a soft mask),
//   - the dashed stroke's dash pieces are all in the PDF: INK exports a dashed stroke as ONE
//     InkFillShape whose sub-paths are its dash outlines (03-ink 6.21, contract 7.2.9 'pre-split
//     into dash segments'), so the page paints as many path objects as those shapes (one) and
//     starts as many sub-paths (`m`) as INK's dash pieces (the moveTo verbs of those paths),
//   - the tape page paints one path: the cover.
// Web-safe; the callers are integration/export_objects_v11_test.dart (VM: openTestNoteStore,
// native compose backend, dart:io zlib) and web/export_objects_v11_browser_test.dart (Chrome:
// openWebTestNoteStore, the compose Worker, DecompressionStream; useInkTestFonts — the text box
// sentence is inside the test font's characters).
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

import 'compose_probes.dart';
import 'pdf_page_content.dart';
import 'real_wiring.dart';

/// The text box sentence (inside the INK Chrome test font — tool/fonts/test_font_chars.txt).
const String v11TextBoxText = '한글 텍스트 상자';

const String _dashedId = 'v11-dashed';
const String _tapeId = 'v11-tape';

core.Stroke _line(String id, core.PenTool tool, {required int createdAt}) =>
    core.Stroke(
      id: id,
      pageId: 'draft',
      style: core.StrokeStyle.defaultsFor(tool),
      points: core.StrokePoints.fromList([
        for (var i = 0; i <= 20; i++) core.StrokePoint(80 + 20.0 * i, 400),
      ]),
      createdAt: createdAt,
    );

/// Extracted text as trimmed lines (NoteSans maps U+00A0 and U+0020 to one glyph — T22).
List<String> _lines(String text) => [
  for (final line in text.replaceAll(' ', ' ').split(RegExp(r'\r?\n')))
    if (line.trim().isNotEmpty) line.trim(),
];

/// Runs V11 on [app]'s store; [out] reopens the PDF with the platform's PDFium, [inflate]
/// decodes the content streams.
Future<void> runV11Scenario(
  RealWiring app, {
  required ComposeProbeContext out,
  required PdfInflate inflate,
}) async {
  final store = app.store;
  final photo = await store.assets.put(
    PdfObjectFixtures.jpegBaseline64x48,
    type: core.AssetType.image,
    mimeType: 'image/jpeg',
    fileName: 'photo.jpg',
  );
  final scan = await store.assets.put(
    PdfObjectFixtures.jpegProgressive64x48,
    type: core.AssetType.image,
    mimeType: 'image/jpeg',
    fileName: 'scan.jpg',
  );

  final note = await store.library.createNote(
    title: 'V11',
    pages: [
      core.PageDraft(
        size: core.PageSize.a4Portrait,
        background: const core.BlankBackground(),
        objects: [
          core_testing.PageObjectFixtures.image(
            pageId: 'draft',
            assetId: photo.id,
            pixelWidth: 64,
            pixelHeight: 48,
            createdAt: 1,
          ),
          core_testing.PageObjectFixtures.shape(pageId: 'draft', createdAt: 2),
          core_testing.PageObjectFixtures.textBox(
            pageId: 'draft',
            text: v11TextBoxText,
            createdAt: 3,
          ),
          core_testing.PageObjectFixtures.math(
            pageId: 'draft',
            latex: r'\frac{a+b}{c}',
            createdAt: 4,
          ),
        ],
      ),
      core.PageDraft(
        size: core.PageSize.a4Portrait,
        background: core.ImageBackground(assetId: scan.id),
      ),
      core.PageDraft(
        size: core.PageSize.a4Portrait,
        background: const core.BlankBackground(),
        strokes: [_line(_dashedId, core.PenTool.dashed, createdAt: 5)],
      ),
      core.PageDraft(
        size: core.PageSize.a4Portrait,
        background: const core.BlankBackground(),
        strokes: [_line(_tapeId, core.PenTool.tape, createdAt: 6)],
      ),
    ],
  );
  await store.flush();
  final pages = await store.content.pagesOf(note.id);
  expect(pages, hasLength(4));
  final contents = [for (final p in pages) await store.content.loadPage(p.id)];
  expect(
    contents[0].objects,
    hasLength(4),
    reason: 'the store kept the objects',
  );

  // What INK exports for these pages (the vectorizer reads the same values).
  await ink.InkFonts.ensureLoaded();
  ink.InkPageVectors exported(core.PageContent c) =>
      ink.InkVectorExport.exportPage(
        ink.InkPageContent.fromCore(
          page: c.page,
          strokes: c.strokes,
          objects: c.objects,
          revision: 0,
        ),
      );
  final first = exported(contents[0]);
  final dashed = exported(contents[2]);
  final tape = exported(contents[3]);
  expect(first.underlay, isNotEmpty, reason: 'INK exports the image object');
  expect(
    first.annotations,
    isNotEmpty,
    reason: 'INK exports the text box and the formula',
  );
  final dashedShapes = [
    for (final s in dashed.inkShapes)
      if (s.strokeId == contents[2].strokes.single.id) s,
  ];
  expect(dashedShapes, isNotEmpty, reason: 'the dashed stroke is exported');
  final dashPieces = [
    for (final s in dashedShapes)
      s.path.verbs.where((v) => v == ink.InkPathVerb.moveTo.index).length,
  ].fold(0, (a, b) => a + b);
  expect(
    dashPieces,
    greaterThan(1),
    reason: 'INK splits a dashed stroke into dash pieces (sub-paths — no dash operator in PDF)',
  );
  expect(tape.cover, hasLength(1));
  expect(tape.inkShapes, isEmpty, reason: 'tape is exported as its cover only');

  final result = await app
      .read(pdfExportServiceProvider)
      .exportNote(note.id, const PdfExportOptions());
  expect(result.warnings, isEmpty);
  expect(result.pageCount, 4);

  final pdf = await out.open(result.bytes);
  expect(pdf.pageCount, 4);
  expect(
    _lines(await pdf.text(0)),
    contains(v11TextBoxText),
    reason: 'the text box is text in the PDF',
  );

  final objects = ProbePdfObjects(result.bytes);
  final images = objects.images;
  debugPrint('V11 images: ${images.join(', ')}');
  expect(
    images,
    hasLength(3),
    reason: 'image object + image background + formula raster',
  );
  expect(images.where((i) => i.filter == 'DCTDecode'), hasLength(2));
  final rasters = images.where((i) => i.filter != 'DCTDecode').toList();
  expect(rasters, hasLength(1), reason: 'one formula raster');
  expect(
    rasters.single.smask,
    isNotNull,
    reason: 'transparent around the formula',
  );
  expect(objects.fontFiles, greaterThanOrEqualTo(1));

  final ops = await PdfPageContents.read(result.bytes, inflate: inflate);
  expect(ops.pages, hasLength(4));
  debugPrint('V11 page ops: ${ops.pages}');
  expect(ops.pages[0].paintedPaths, greaterThanOrEqualTo(1), reason: 'shape');
  expect(ops.pages[0].textObjects, greaterThanOrEqualTo(1));
  expect(ops.pages[1].xObjects, 1, reason: 'the image background');
  expect(
    ops.pages[2].paintedPaths,
    dashedShapes.length,
    reason: 'one painted path object per INK fill shape of the dashed stroke',
  );
  expect(
    ops.pages[2].counts['m'],
    dashPieces,
    reason: 'every INK dash piece starts a sub-path in the PDF',
  );
  expect(ops.pages[3].paintedPaths, 1, reason: 'the tape cover');
  expect(ops.pages[3].filledPaths, 1);
  expect(latin1.decode(result.bytes.sublist(0, 5)), '%PDF-');
}
