// The REAL INK thumbnail renderer with the PDF builder (06-pdf 6.9, 8 T10; contract 7.2.11
// thumbnail path, 7.2.16 v1.1 still renderer) — integration stage only
// (`ws test --run-skipped -t integration`, contract 7.7 step 5): ink.InkPageThumbnailRenderer
// over [PdfBackgroundLayerBuilder, TemplateBackgroundLayerBuilder] draws the PDF page's text
// into the cover (real PDFium), and returns null when the original is missing (callers do
// not cache it) without asking for a download.
@Tags(['integration'])
@TestOn('vm')
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

import '../support/pdfium_env.dart';

/// 'HHHH' at x 100, baseline y 80, size 40 on a 400 × 300 pt page (glyphs ≈ 100–200 ×
/// 51–80 pt).
Uint8List _textPage() =>
    (PdfFixtureBuilder()..addPage(
          const PdfFixturePage(
            width: 400,
            height: 300,
            texts: [PdfFixtureText('HHHH', x: 100, y: 80, size: 40)],
          ),
        ))
        .build();

Future<int> _dark(ui.Image image, ui.Rect box) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  var count = 0;
  for (var y = box.top.floor(); y < box.bottom.ceil(); y++) {
    for (var x = box.left.floor(); x < box.right.ceil(); x++) {
      final i = (y * image.width + x) * 4;
      if (data.getUint8(i) < 100 &&
          data.getUint8(i + 1) < 100 &&
          data.getUint8(i + 2) < 100) {
        count++;
      }
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakePdfNoteGateway gateway;
  late DefaultPdfDocumentPool pool;
  late PdfRenderService service;
  late FakeRemoteAssetFetcher fetcher;
  late ink.InkPageThumbnailRenderer renderer;

  setUpAll(() async {
    await initPdfiumForTests();
    await PdfrxEngine.shared().ensureInitialized();
  });

  setUp(() {
    gateway = FakePdfNoteGateway();
    fetcher = FakeRemoteAssetFetcher();
    pool = DefaultPdfDocumentPool(
      engine: PdfrxEngine.shared(),
      gateway: gateway,
      remoteAssets: fetcher,
    );
    service = PdfRenderService(
      pool: pool,
      budget: const PdfRenderBudget.native(),
      trimOnAppHidden: false,
    );
    renderer = ink.InkPageThumbnailRenderer(
      backgroundBuilders: [
        PdfBackgroundLayerBuilder(renderer: () => service),
        const ink.TemplateBackgroundLayerBuilder(),
      ],
    );
  });

  tearDown(() async {
    await service.dispose();
    await pool.dispose();
  });

  Future<core.PageContent> pdfPage({required bool withBytes}) async {
    final asset = await gateway.putPdf(_textPage(), fileName: 'thumb.pdf');
    final note = await gateway.createNote(
      title: 'thumb',
      pages: [
        core.PageDraft(
          size: const core.PageSize(400, 300),
          background: core.PdfBackground(assetId: asset.id, pdfPageIndex: 0),
        ),
      ],
    );
    if (!withBytes) gateway.dropAssetBytes(asset.id);
    final pages = await gateway.pagesOf(note.id);
    return gateway.loadPage(pages.single.id);
  }

  test('the cover shows the PDF text', () async {
    final content = await pdfPage(withBytes: true);
    final thumbnail = await renderer.render(content, maxSidePx: 400);
    expect(thumbnail, isNotNull);
    expect(thumbnail!.pageId, content.page.id);
    expect(thumbnail.contentRevision, content.page.contentRevision);
    final codec = await ui.instantiateImageCodec(thumbnail.bytes);
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    expect((image.width, image.height), (400, 300));
    expect(
      await _dark(image, const ui.Rect.fromLTRB(100, 52, 200, 80)),
      greaterThan(500),
    );
    expect(await _dark(image, const ui.Rect.fromLTRB(0, 150, 400, 300)), 0);
    image.dispose();
  });

  test('original missing → null, no download request', () async {
    final content = await pdfPage(withBytes: false);
    expect(await renderer.render(content), isNull);
    expect(fetcher.ensureLocalCalls, isEmpty);
  });
}
