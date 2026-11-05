// Export end to end on real PDFium (06-pdf 6.11.2; 8 T15): FakePdfNoteGateway with a real
// fixture PDF + BoxInkVectorizer + the native compose backend → the exported PDF, reopened
// with PdfrxEngine, has the note's page count and order, the original text, the stroke
// boxes at their note positions, the paper fill of a template page, and a missing original
// as a blank page with the stroke on it.
@Tags(['pdfium'])
@TestOn('vm')
library;

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/compose/compose_backend_native.dart'
    show NativePdfComposeBackend, debugNativeComposeJobCount;
import 'package:pdf_io/testing.dart';

import '../support/compose_probes.dart';
import '../support/pdfium_env.dart';

core.Stroke _marker(String id, core.PageId pageId, ui.Rect rect, int at) =>
    core.Stroke(
      id: id,
      pageId: pageId,
      style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint)
          .copyWith(colorArgb: markerArgb, width: 4),
      points: core.StrokePoints.fromList([
        core.StrokePoint(rect.left, rect.top),
        core.StrokePoint(rect.right, rect.bottom),
      ]),
      createdAt: at,
    );

ui.Rect _bounds(core.Stroke s) => ui.Rect.fromLTRB(
  s.bounds.left,
  s.bounds.top,
  s.bounds.right,
  s.bounds.bottom,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initPdfiumForTests();
    await PdfrxEngine.shared().ensureInitialized();
  });

  late FakePdfNoteGateway gateway;
  late NativePdfComposeBackend backend;
  late DefaultPdfExportService service;
  late ComposeProbeContext ctx;

  setUp(() {
    gateway = FakePdfNoteGateway();
    backend = NativePdfComposeBackend();
    service = DefaultPdfExportService(
      gateway: gateway,
      vectorizer: const BoxInkVectorizer(),
      backend: backend,
    );
    ctx = ComposeProbeContext(backend: backend, engine: PdfrxEngine.shared());
  });

  tearDown(() async {
    await ctx.dispose();
    expect(backend.openJobCount, 0);
    await backend.dispose();
    expect(await debugNativeComposeJobCount(), 0);
  });

  test(
    'pages, text, stroke boxes and paper fill in the exported PDF',
    () async {
      final pdf =
          (PdfFixtureBuilder()
                ..addPage(
                  const PdfFixturePage(texts: [PdfFixtureText('Hello export')]),
                )
                ..addPage(
                  const PdfFixturePage(
                    width: 612,
                    height: 792,
                    texts: [PdfFixtureText('Second page')],
                  ),
                ))
              .build();
      final asset = await gateway.putPdf(pdf, fileName: 'lecture.pdf');
      final note = await gateway.createNote(
        title: '강의 노트',
        pages: [
          core.PageDraft(
            size: core.PageSize.a4Portrait,
            background: core.PdfBackground(assetId: asset.id, pdfPageIndex: 0),
          ),
          const core.PageDraft(
            size: core.PageSize(400, 300),
            background: core.BlankBackground(
              paperColorArgb: core.PaperColors.ivory,
            ),
          ),
          core.PageDraft(
            size: core.PageSize.letterPortrait,
            background: core.PdfBackground(assetId: asset.id, pdfPageIndex: 1),
          ),
        ],
      );
      final pages = await gateway.pagesOf(note.id);
      final onPdf = _marker(
        's1',
        pages[0].id,
        const ui.Rect.fromLTWH(200, 300, 80, 60),
        1,
      );
      final onBlank = _marker(
        's2',
        pages[1].id,
        const ui.Rect.fromLTWH(40, 40, 50, 30),
        2,
      );
      gateway
        ..addStrokes(pages[0].id, [onPdf])
        ..addStrokes(pages[1].id, [onBlank]);

      final result = await service.exportNote(
        note.id,
        const PdfExportOptions(),
      );
      expect(result.fileName, '강의 노트.pdf');
      expect(result.pageCount, 3);
      expect(result.warnings, isEmpty);

      final out = await ctx.open(result.bytes);
      expect(out.pageCount, 3);
      expect(out.sizeOf(0).width, closeTo(595.276, 0.01));
      expect(out.sizeOf(1), const ui.Size(400, 300));
      expect(out.sizeOf(2), const ui.Size(612, 792));
      expect(await out.text(0), contains('Hello export'));
      expect(await out.text(1), isEmpty);
      expect(await out.text(2), contains('Second page'));

      expectMarkersAt(await out.render(0), [_bounds(onPdf)], reason: 'page 1');
      final blank = await out.render(1);
      expectMarkersAt(blank, [_bounds(onBlank)], reason: 'page 2');
      // Ivory paper (0xFBF7EC) away from the stroke.
      final (r, g, b) = blank.pixel(const ui.Offset(300, 200));
      expect([r, g, b], [closeTo(0xFB, 2), closeTo(0xF7, 2), closeTo(0xEC, 2)]);
      expectNoMarker(await out.render(2), reason: 'page 3 has no ink');
    },
  );

  test(
    'a missing original → a blank page of the note size with its ink',
    () async {
      final present =
          (PdfFixtureBuilder()..addPage(
                const PdfFixturePage(texts: [PdfFixtureText('Kept')]),
              ))
              .build();
      final asset = await gateway.putPdf(present, fileName: 'kept.pdf');
      const remote = 'feedfacefeedface';
      gateway.addRemoteAsset(remote, fileName: 'remote.pdf');
      final note = await gateway.createNote(
        title: 'n',
        pages: [
          core.PageDraft(
            size: core.PageSize.a4Portrait,
            background: core.PdfBackground(assetId: asset.id, pdfPageIndex: 0),
          ),
          const core.PageDraft(
            size: core.PageSize.letterPortrait,
            background: core.PdfBackground(assetId: remote, pdfPageIndex: 4),
          ),
        ],
      );
      final pages = await gateway.pagesOf(note.id);
      final ink = _marker(
        's1',
        pages[1].id,
        const ui.Rect.fromLTWH(100, 100, 60, 40),
        1,
      );
      gateway.addStrokes(pages[1].id, [ink]);

      final result = await service.exportNote(
        note.id,
        const PdfExportOptions(),
      );
      expect(
        (result.warnings.single as PdfExportBlankedMissingAsset)
            .notePageNumbers,
        [2],
      );
      final out = await ctx.open(result.bytes);
      expect(out.pageCount, 2);
      expect(await out.text(0), contains('Kept'));
      expect(out.sizeOf(1), const ui.Size(612, 792));
      expect(await out.text(1), isEmpty);
      expectMarkersAt(await out.render(1), [_bounds(ink)]);
    },
  );
}
