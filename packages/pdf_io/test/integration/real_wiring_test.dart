// The PDF provider graph wired as the app wires it (contract 7.3.3: CoreModule's
// noteStoreProvider, PdfModule's pdfIoOverrides(), FeatureWiringModule's
// pageThumbnailRendererProvider → ink.inkPageThumbnailRendererProvider) over the REAL CORE
// store (openTestNoteStore), the REAL INK thumbnail renderer and vector export, real PDFium
// and the native compose backend — integration stage only (`ws test --run-skipped -t
// integration`, contract 7.7 step 5; 06-pdf 10 item 5). Nothing PDF-side is overridden. (2차,
// m5-7/06-pdf 8.2 T29 — PDF-M14) The wiring itself is test/support/real_wiring.dart, shared
// with V11 (export_objects_v11_test) and V10's PDF part (search_indexer_core_test):
//   - import → note in CORE, cover written by INK's renderer through the PDF builder,
//   - search over the stored original (note pt),
//   - strokes through a CORE session → export with InkEngineVectorizer: pen fill and
//     Multiply highlighter where the note says, original text kept,
//   - template page → INK's template lines in the output, none with includeTemplates off,
//   - import into a note the editor has open → same asset, one undo step (U7).
@Tags(['integration'])
@TestOn('vm')
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing_vm.dart' as core_vm;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/compose/compose_backend_native.dart'
    show debugNativeComposeJobCount;
import 'package:pdf_io/testing.dart';

import '../support/compose_probes.dart';
import '../support/export_world.dart' show captureFlutterErrors;
import '../support/pdfium_env.dart';
import '../support/real_wiring.dart';

/// Page 1: 400 × 300 pt, 'HHHH' at x 100, baseline y 80, size 40 (glyphs ≈ 100–200 ×
/// 51–80 pt). Page 2: A4 with 'Second lecture'.
Uint8List _lecture() =>
    (PdfFixtureBuilder()
          ..addPage(
            const PdfFixturePage(
              width: 400,
              height: 300,
              texts: [PdfFixtureText('HHHH', x: 100, y: 80, size: 40)],
            ),
          )
          ..addPage(
            const PdfFixturePage(
              texts: [PdfFixtureText('Second lecture', x: 72, y: 120)],
            ),
          ))
        .build();

/// A horizontal stroke from x 60 to 340 at [y] (11 points).
core.Stroke _line(
  String id,
  core.PageId pageId,
  core.PenTool tool, {
  required double y,
  required int createdAt,
  int? colorArgb,
  double? width,
}) {
  final style = core.StrokeStyle.defaultsFor(tool);
  return core.Stroke(
    id: id,
    pageId: pageId,
    style: style.copyWith(colorArgb: colorArgb, width: width),
    points: core.StrokePoints.fromList([
      for (var i = 0; i <= 10; i++) core.StrokePoint(60 + 28.0 * i, y),
    ]),
    createdAt: createdAt,
  );
}

bool _dark(int r, int g, int b) => r < 100 && g < 100 && b < 100;

/// Yellow highlighter (0xFFE600, opacity 0.35) multiplied onto white paper ≈ (255, 246, 166).
bool _highlighterOnWhite(int r, int g, int b) =>
    r > 235 && g > 225 && b > 130 && b < 200;

bool _notWhite(int r, int g, int b) => r < 245 || g < 245 || b < 245;

Future<ui.Image> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

Future<int> _countImage(
  ui.Image image,
  bool Function(int r, int g, int b) test,
  ui.Rect box,
) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return ProbeImage(
    data,
    image.width,
    image.height,
    1,
  ).count(test, pixelBox: box);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RealWiring app;
  late ComposeProbeContext out;
  late List<FlutterErrorDetails> reports;

  setUpAll(() async {
    await initPdfiumForTests();
    await PdfrxEngine.shared().ensureInitialized();
  });

  setUp(() async {
    reports = captureFlutterErrors();
    app = RealWiring(await core_vm.openTestNoteStore());
    out = ComposeProbeContext(
      backend: app.read(pdfComposeBackendProvider),
      engine: PdfrxEngine.shared(),
    );
  });

  tearDown(() async {
    await out.dispose();
    await app
        .close(); // the pool's documents, the compose backend, then the store
    expect(await debugNativeComposeJobCount(), 0);
    expect(reports, isEmpty, reason: 'no reported PDF errors');
  });

  test('import → INK cover, search, CORE strokes → export with the real INK vectors', () async {
    final bytes = _lecture();
    final imported = await app.import(bytes, const PdfImportAsNewNote());
    expect(imported.createdNewNote, isTrue);
    expect(imported.sourcePageCount, 2);
    expect(imported.insertedPageIds, hasLength(2));

    // The note in the real CORE store.
    final note = (await app.store.library.getNote(imported.noteId))!;
    expect(note.title, 'lecture');
    expect(note.pageCount, 2);
    final session = await app.store.openSession(imported.noteId);
    final pages = session.pages;
    expect([for (final p in pages) p.id], imported.insertedPageIds);
    expect(pages[0].size, const core.PageSize(400, 300));
    expect(
      [
        for (final p in pages)
          (
            (p.background as core.PdfBackground).assetId,
            (p.background as core.PdfBackground).pdfPageIndex,
          ),
      ],
      [(imported.assetId, 0), (imported.assetId, 1)],
    );
    expect(await app.store.assets.readBytes(imported.assetId), bytes);

    // The cover: INK's renderer with the PDF builder (FeatureWiringModule row), long side
    // 512, the PDF text where the page has it, nothing in the lower half.
    final cover = (await app.store.thumbnails.read(pages[0].id))!;
    expect(cover.contentRevision, pages[0].contentRevision);
    final coverImage = await _decode(cover.bytes);
    expect((coverImage.width, coverImage.height), (512, 384));
    const s = 512 / 400;
    expect(
      await _countImage(
        coverImage,
        _dark,
        const ui.Rect.fromLTRB(100 * s, 52 * s, 200 * s, 80 * s),
      ),
      greaterThan(500),
    );
    expect(
      await _countImage(
        coverImage,
        _dark,
        const ui.Rect.fromLTRB(0, 150 * s, 400 * s, 300 * s),
      ),
      0,
    );
    coverImage.dispose();

    // Search over the stored original: rects in note pt on the right pages.
    final h = await app.search(imported.noteId, 'HHHH');
    expect(h, hasLength(1));
    expect((h.single.pageId, h.single.notePageNumber), (pages[0].id, 1));
    // Glyph boxes of 'HHHH' (x from 100, cap height ≈ 51–80 pt; page size = PDF size).
    final box = h.single.rects.reduce((a, b) => a.expandToInclude(b));
    const around = ui.Rect.fromLTRB(95, 45, 225, 85);
    expect(
      around.contains(box.topLeft) && around.contains(box.bottomRight),
      isTrue,
      reason: 'HHHH at $box',
    );
    expect(box.width, greaterThan(90), reason: 'HHHH at $box');
    expect(box.height, greaterThan(20), reason: 'HHHH at $box');
    final second = await app.search(imported.noteId, 'LECTURE');
    expect(
      (second.single.pageId, second.single.notePageNumber),
      (pages[1].id, 2),
    );

    // Strokes through the real CORE session (what EDITOR does), then export.
    await session.openPage(pages[0].id);
    session.execute(
      core.AddStrokes(
        pageId: pages[0].id,
        strokes: [
          _line(
            'pen-1',
            pages[0].id,
            core.PenTool.ballpoint,
            y: 200,
            createdAt: 1,
            colorArgb: markerArgb,
            width: 6,
          ),
          _line(
            'hl-1',
            pages[0].id,
            core.PenTool.highlighter,
            y: 260,
            createdAt: 2,
          ),
        ],
      ),
    );
    session.closePage(pages[0].id);
    await session.close();

    final result = await app
        .read(pdfExportServiceProvider)
        .exportNote(imported.noteId, const PdfExportOptions());
    expect(result.fileName, 'lecture.pdf');
    expect(result.pageCount, 2);
    expect(result.warnings, isEmpty);

    final pdf = await out.open(result.bytes);
    expect(pdf.pageCount, 2);
    expect(pdf.sizeOf(0), const ui.Size(400, 300));
    expect(pdf.sizeOf(1).width, closeTo(595.276, 0.01));
    expect(await pdf.text(0), contains('HHHH'));
    expect(await pdf.text(1), contains('Second lecture'));

    final page1 = await pdf.render(0);
    // Pen: the red fill along y 200 (x 60–340), nothing red away from it.
    expect(
      page1.count(
        isMarker,
        pixelBox: const ui.Rect.fromLTRB(70, 198, 330, 202),
      ),
      greaterThan(260 * 4 * 0.9),
    );
    expect(
      page1.count(isMarker) -
          page1.count(
            isMarker,
            pixelBox: const ui.Rect.fromLTRB(50, 188, 350, 212),
          ),
      0,
    );
    // Highlighter: Multiply yellow on white along y 260, not elsewhere.
    expect(
      page1.count(
        _highlighterOnWhite,
        pixelBox: const ui.Rect.fromLTRB(70, 257, 330, 263),
      ),
      greaterThan(260 * 6 * 0.9),
    );
    expect(
      page1.count(
        _highlighterOnWhite,
        pixelBox: const ui.Rect.fromLTRB(0, 0, 400, 230),
      ),
      0,
    );
    // The original text is still drawn.
    expect(
      page1.count(_dark, pixelBox: const ui.Rect.fromLTRB(100, 52, 200, 80)),
      greaterThan(400),
    );
    expectNoMarker(await pdf.render(1), reason: 'page 2 has no ink');
  });

  test('template page: INK template lines in the output, none with includeTemplates off', () async {
    final gateway = app.read(pdfNoteGatewayProvider);
    final note = await gateway.createNote(
      title: '줄노트',
      pages: const [
        core.PageDraft(
          size: core.PageSize.a4Portrait,
          background: core.TemplateBackground(
            template: core.PageTemplate(kind: core.PageTemplateKind.lined),
          ),
        ),
      ],
    );
    final export = app.read(pdfExportServiceProvider);

    final withTemplate = await out.open(
      (await export.exportNote(note.id, const PdfExportOptions())).bytes,
    );
    expect(withTemplate.pageCount, 1);
    final lined = await withTemplate.render(0);
    expect(lined.count(_notWhite), greaterThan(1000), reason: 'ruled lines');

    final plain = await out.open(
      (await export.exportNote(
        note.id,
        const PdfExportOptions(includeTemplates: false),
      )).bytes,
    );
    expect(plain.sizeOf(0), withTemplate.sizeOf(0));
    expect((await plain.render(0)).count(_notWhite), 0);
  });

  test(
    'import into a note the editor has open: same asset, one undo step (U7)',
    () async {
      final bytes = _lecture();
      final first = await app.import(bytes, const PdfImportAsNewNote());
      final editor = await app.store.openSession(first.noteId);
      addTearDown(editor.close);
      final before = editor.history.undoDepth;

      final inserted = await app.import(
        bytes,
        PdfImportIntoNote(
          noteId: first.noteId,
          position: core.PageAfter(first.firstPageId),
        ),
        range: PdfPageRange.parse('2', pageCount: 2),
      );
      expect(inserted.createdNewNote, isFalse);
      expect(inserted.assetId, first.assetId, reason: 'same bytes, one asset');
      expect(inserted.insertedPageIds, hasLength(1));
      expect(editor.isClosed, isFalse);
      expect(
        [for (final p in editor.pages) p.id],
        [
          first.insertedPageIds[0],
          inserted.firstPageId,
          first.insertedPageIds[1],
        ],
      );
      final page = editor.pages[1];
      expect(page.background, isA<core.PdfBackground>());
      expect((page.background as core.PdfBackground).pdfPageIndex, 1);
      expect(page.size.width, closeTo(595.276, 0.01));
      expect(editor.history.undoDepth, before + 1);
      // insertPages does not wait for the commit (N-1, 4.4); after a flush the library has it.
      await app.store.flush();
      expect((await app.store.library.getNote(first.noteId))!.pageCount, 3);

      await editor.undo();
      expect([for (final p in editor.pages) p.id], first.insertedPageIds);
      await app.store.flush();
      expect((await app.store.library.getNote(first.noteId))!.pageCount, 2);
    },
  );
}
