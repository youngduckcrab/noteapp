// The cover right after an import (06-pdf 6.3 step 6, 6.9; 8 T10; contract 7.2.11 thumbnail
// path), renderImportCover directly. Own path (no core.PageThumbnailRenderer — foundation
// stage, unit tests): an opaque PNG of 512 px on the long side, the page's contentRevision,
// the PDF placed with PdfPageFit. Renderer path (the INK renderer INFRA injects): that
// renderer's result for content.page with maxSidePx 512, null passed on. A null result is no
// error; exceptions propagate to the import, which reports and ignores them
// (unit/import_service_test 'cover failure is reported once and the import succeeds').
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/import/cover_thumbnail.dart';
import 'package:pdf_io/testing.dart';

import '../support/render_doubles.dart';

Uint8List _pdf() => Uint8List.fromList('%PDF-1.7\n% cover\n%%EOF\n'.codeUnits);

final class _World {
  _World({ui.Size pdfPageSize = const ui.Size(595.276, 841.89)})
    : engine = FakePdfEngine(pageSize: pdfPageSize, imageArgb: 0xFF000000) {
    pool = DefaultPdfDocumentPool(engine: engine, gateway: gateway);
    renderer = PdfRenderService(
      pool: pool,
      budget: const PdfRenderBudget.web(),
      trimOnAppHidden: false,
    );
  }

  final FakePdfEngine engine;
  final FakePdfNoteGateway gateway = FakePdfNoteGateway();
  late final DefaultPdfDocumentPool pool;
  late final PdfRenderService renderer;

  PdfPageInfo get pdfPage => engine.pages.first;

  /// A one-page note whose page has [size] and a PDF background on page 0.
  Future<core.PageContent> page({
    core.PageSize size = core.PageSize.a4Portrait,
    int paper = 0xFFFFFFFF,
  }) async {
    final asset = await gateway.putPdf(_pdf(), fileName: 'cover.pdf');
    final note = await gateway.createNote(
      title: 'cover',
      pages: [
        core.PageDraft(
          size: size,
          background: core.PdfBackground(
            assetId: asset.id,
            pdfPageIndex: 0,
            paperColorArgb: paper,
          ),
        ),
      ],
    );
    final pages = await gateway.pagesOf(note.id);
    return gateway.loadPage(pages.single.id);
  }

  Future<void> close() async {
    await renderer.dispose();
    await pool.dispose();
  }
}

Future<ui.Image> _decode(core.PageThumbnail thumbnail) async {
  final codec = await ui.instantiateImageCodec(thumbnail.bytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

Future<List<int>> _pixel(ui.Image image, int x, int y) async {
  final data = (await image.toByteData())!;
  final i = (y * image.width + x) * 4;
  return [for (var c = 0; c < 4; c++) data.getUint8(i + c)];
}

void main() {
  group('own path (no PageThumbnailRenderer)', () {
    test('PNG, long side 512, contentRevision of the page', () async {
      final w = _World();
      final content = await w.page();
      final thumbnail = (await renderImportCover(
        content: content,
        pdfPage: w.pdfPage,
        renderer: w.renderer,
      ))!;
      expect(thumbnail.pageId, content.page.id);
      expect(thumbnail.contentRevision, content.page.contentRevision);
      expect(thumbnail.mimeType, 'image/png');
      expect((thumbnail.width, thumbnail.height), (362, 512));
      final image = await _decode(thumbnail);
      expect((image.width, image.height), (362, 512));
      expect(await _pixel(image, 181, 256), [0, 0, 0, 0xFF], reason: 'the PDF');
      image.dispose();
      // The PDF image was asked for at the cover size, never cached.
      expect(w.renderer.stats.liveImages, 0);
      await w.close();
    });

    test('landscape page: 512 on the width', () async {
      final w = _World(pdfPageSize: const ui.Size(960, 540));
      final content = await w.page(size: core.PageSize.widescreen16x9);
      final thumbnail = (await renderImportCover(
        content: content,
        pdfPage: w.pdfPage,
        renderer: w.renderer,
      ))!;
      expect((thumbnail.width, thumbnail.height), (512, 288));
      await w.close();
    });

    test(
      's ≠ 1: the PDF in its PdfPageFit box, opaque paper around it',
      () async {
        // Letter PDF on an A4 note page: letterbox bands top and bottom.
        final w = _World(pdfPageSize: const ui.Size(612, 792));
        final content = await w.page(paper: 0x80FBF7EC);
        final thumbnail = (await renderImportCover(
          content: content,
          pdfPage: w.pdfPage,
          renderer: w.renderer,
        ))!;
        final image = await _decode(thumbnail);
        final fit = PdfPageFit(
          notePageSize: const ui.Size(595.2756, 841.8898),
          pdfPageSize: const ui.Size(612, 792),
        );
        final top = fit.oy * 512 / 841.8898; // ≈ 21.75 px
        expect(await _pixel(image, 100, (top - 3).floor()), [
          0xFB,
          0xF7,
          0xEC,
          0xFF,
        ]);
        expect(await _pixel(image, 100, (top + 3).ceil()), [0, 0, 0, 0xFF]);
        expect(w.engine.renderRequests.single.backgroundArgb, 0xFFFBF7EC);
        image.dispose();
        await w.close();
      },
    );

    test('missing bytes → null (nothing to cache)', () async {
      final w = _World();
      final content = await w.page();
      final background = content.page.background as core.PdfBackground;
      w.gateway.dropAssetBytes(background.assetId);
      expect(
        await renderImportCover(
          content: content,
          pdfPage: w.pdfPage,
          renderer: w.renderer,
        ),
        isNull,
      );
      await w.close();
    });

    test('no PDF background → null', () async {
      final w = _World();
      final content = await w.page();
      final blank = core.PageContent(
        page: content.page.copyWith(background: const core.BlankBackground()),
        strokes: const [],
        revision: 0,
      );
      expect(
        await renderImportCover(
          content: blank,
          pdfPage: w.pdfPage,
          renderer: w.renderer,
        ),
        isNull,
      );
      await w.close();
    });
  });

  group('renderer path (core.PageThumbnailRenderer)', () {
    test('the renderer gets content.page and maxSidePx 512; its result is the cover', () async {
      final w = _World();
      final content = await w.page();
      final scripted = ScriptedThumbnailRenderer();
      final thumbnail = await renderImportCover(
        content: content,
        pdfPage: w.pdfPage,
        renderer: w.renderer,
        thumbnailRenderer: scripted,
      );
      expect(scripted.calls, [(content.page.id, 512)]);
      expect(thumbnail!.pageId, content.page.id);
      expect(thumbnail.contentRevision, content.page.contentRevision);
      expect(w.engine.renderRequests, isEmpty, reason: 'no own drawing');
      await w.close();
    });

    test('null from the renderer → null', () async {
      final w = _World();
      final content = await w.page();
      final scripted = ScriptedThumbnailRenderer()..returnNull = true;
      expect(
        await renderImportCover(
          content: content,
          pdfPage: w.pdfPage,
          renderer: w.renderer,
          thumbnailRenderer: scripted,
        ),
        isNull,
      );
      await w.close();
    });

    test('an exception propagates to the import (which ignores it)', () async {
      final w = _World();
      final content = await w.page();
      final scripted = ScriptedThumbnailRenderer()..error = StateError('ink');
      await expectLater(
        renderImportCover(
          content: content,
          pdfPage: w.pdfPage,
          renderer: w.renderer,
          thumbnailRenderer: scripted,
        ),
        throwsStateError,
      );
      await w.close();
    });
  });
}
