// Page backgrounds on real PDFium (06-pdf 6.7, 6.8; 8 T9): PdfRenderService + DefaultPdfDocumentPool
// over PdfrxEngine draw the fixture's text where it is — dark pixels at the glyphs in the
// preview and in the tile that holds them, none elsewhere.
@Tags(['pdfium'])
@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

import '../support/pdfium_env.dart';

const String _asset = 'asset-real';

/// 'HHHH' at x 100, baseline y 80, size 40 on a 400 × 300 pt page: glyphs ≈ x 100–200,
/// y 51–80 (pt).
Uint8List _textPage() =>
    (PdfFixtureBuilder()..addPage(
          const PdfFixturePage(
            width: 400,
            height: 300,
            texts: [PdfFixtureText('HHHH', x: 100, y: 80, size: 40)],
          ),
        ))
        .build();

/// Dark pixels (all channels < 100) of [image] inside the pixel box.
Future<int> _dark(ui.Image image, ui.Rect box) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  var count = 0;
  for (var y = box.top.floor(); y < box.bottom.ceil(); y++) {
    for (var x = box.left.floor(); x < box.right.ceil(); x++) {
      if (x < 0 || y < 0 || x >= image.width || y >= image.height) continue;
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

/// Waits until [done] holds for the handle's snapshot.
Future<PdfRenderSnapshot> _until(
  PdfPageRenderHandle handle,
  bool Function(PdfRenderSnapshot snapshot) done,
) {
  if (done(handle.snapshot)) return Future.value(handle.snapshot);
  final completer = Completer<PdfRenderSnapshot>();
  void listener() {
    if (!completer.isCompleted && done(handle.snapshot)) {
      completer.complete(handle.snapshot);
    }
  }

  handle.addListener(listener);
  return completer.future.whenComplete(() => handle.removeListener(listener));
}

/// Pixels of [placed]'s image that show the note-pt rect [pagePt].
ui.Rect _pixelsOf(PdfPlacedImage placed, ui.Rect pagePt) {
  final sx = placed.srcRect.width / placed.pageRect.width;
  final sy = placed.srcRect.height / placed.pageRect.height;
  return ui.Rect.fromLTRB(
    placed.srcRect.left + (pagePt.left - placed.pageRect.left) * sx,
    placed.srcRect.top + (pagePt.top - placed.pageRect.top) * sy,
    placed.srcRect.left + (pagePt.right - placed.pageRect.left) * sx,
    placed.srcRect.top + (pagePt.bottom - placed.pageRect.top) * sy,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakePdfNoteGateway gateway;
  late DefaultPdfDocumentPool pool;
  late PdfRenderService service;

  setUpAll(() async {
    await initPdfiumForTests();
    await PdfrxEngine.shared().ensureInitialized();
  });

  setUp(() {
    gateway = FakePdfNoteGateway()..arriveBytes(_asset, _textPage());
    pool = DefaultPdfDocumentPool(
      engine: PdfrxEngine.shared(),
      gateway: gateway,
    );
    service = PdfRenderService(
      pool: pool,
      budget: const PdfRenderBudget.native(),
      trimOnAppHidden: false,
    );
  });

  tearDown(() async {
    await service.dispose();
    await pool.dispose();
  });

  test('preview: the glyphs are dark, the empty lower half is not', () async {
    final handle = service.attach(
      const PdfBackgroundParams(
        assetId: _asset,
        pdfPageIndex: 0,
        pageSize: ui.Size(400, 300),
        deviceScale: 1,
      ),
    );
    final snapshot = await _until(
      handle,
      (s) => s.status != PdfRenderStatus.loading,
    );
    expect(snapshot.status, PdfRenderStatus.ready);
    final base = snapshot.base!;
    expect((base.image.width, base.image.height), (400, 300));
    expect(
      await _dark(
        base.image,
        _pixelsOf(base, const ui.Rect.fromLTRB(100, 52, 200, 80)),
      ),
      greaterThan(500),
    );
    expect(
      await _dark(
        base.image,
        _pixelsOf(base, const ui.Rect.fromLTRB(0, 150, 400, 300)),
      ),
      0,
    );
    handle.dispose();
  });

  test(
    'tiles: the tile holding the glyphs is dark, a far one is not',
    () async {
      final handle = service.attach(
        const PdfBackgroundParams(
          assetId: _asset,
          pdfPageIndex: 0,
          pageSize: ui.Size(400, 300),
          deviceScale: 4,
        ),
      );
      // Whole page at bucket 3.815: 3 × 3 tiles.
      final snapshot = await _until(
        handle,
        (s) => s.status == PdfRenderStatus.ready && s.tiles.length == 9,
      );
      PdfPlacedImage tileAt(ui.Offset pt) =>
          snapshot.tiles.firstWhere((t) => t.pageRect.contains(pt));
      final textTile = tileAt(const ui.Offset(110, 70));
      expect(
        await _dark(
          textTile.image,
          _pixelsOf(textTile, const ui.Rect.fromLTRB(100, 52, 130, 80)),
        ),
        greaterThan(500),
      );
      final emptyTile = tileAt(const ui.Offset(350, 250));
      expect(await _dark(emptyTile.image, emptyTile.srcRect), 0);
      handle.dispose();
    },
  );

  test(
    's ≠ 1: the PDF is placed with PdfPageFit (note 576 × 432 = 1.44×)',
    () async {
      final handle = service.attach(
        const PdfBackgroundParams(
          assetId: _asset,
          pdfPageIndex: 0,
          pageSize: ui.Size(576, 432),
          deviceScale: 1,
        ),
      );
      final snapshot = await _until(
        handle,
        (s) => s.status != PdfRenderStatus.loading,
      );
      final base = snapshot.base!;
      expect(base.pageRect, const ui.Rect.fromLTWH(0, 0, 576, 432));
      // The glyphs in note pt: × 1.44.
      expect(
        await _dark(
          base.image,
          _pixelsOf(base, const ui.Rect.fromLTRB(144, 75, 288, 115)),
        ),
        greaterThan(500),
      );
      handle.dispose();
    },
  );
}
