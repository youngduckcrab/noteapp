// Thumbnails (06-pdf 6.7.1 thumbnail mode, 6.9; 8 T10): one image of 256 px on the long side
// for page-panel backgrounds (ctx.isThumbnail) and tiny pages (≤ 320 device px), shared
// through the cache by every thumbnail of the same page, inside the 16 MiB-style thumbnail
// budget (LRU of unused thumbnails); renderThumbnail(longSidePx) gives exactly that long
// side and is never cached (the caller owns the image).
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

const ui.Size _a4 = ui.Size(595.276, 841.89);
const String _asset = 'asset-a';

Uint8List _pdf() => Uint8List.fromList('%PDF-1.7\n% thumbs\n%%EOF\n'.codeUnits);

final class _World {
  _World({
    List<PdfPageInfo>? pages,
    PdfRenderBudget budget = const PdfRenderBudget.web(),
  }) : engine = FakePdfEngine(pages: pages, pageCount: 4) {
    gateway.arriveBytes(_asset, _pdf());
    pool = DefaultPdfDocumentPool(engine: engine, gateway: gateway);
    service = PdfRenderService(
      pool: pool,
      budget: budget,
      trimOnAppHidden: false,
    );
  }

  final FakePdfEngine engine;
  final FakePdfNoteGateway gateway = FakePdfNoteGateway();
  late final DefaultPdfDocumentPool pool;
  late final PdfRenderService service;

  Future<void> close() async {
    await service.dispose();
    await pool.dispose();
  }
}

PdfBackgroundParams _thumb(int page, {double deviceScale = 2}) =>
    PdfBackgroundParams(
      assetId: _asset,
      pdfPageIndex: page,
      pageSize: _a4,
      deviceScale: deviceScale,
      isThumbnail: true,
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
}

void main() {
  testWidgets('thumbnail mode: one 256 px image, no tiles, thumbnail budget', (
    tester,
  ) async {
    final w = _World();
    final handle = w.service.attach(_thumb(0, deviceScale: 8));
    await _settle(tester);
    final snapshot = handle.snapshot;
    expect(snapshot.status, PdfRenderStatus.ready);
    expect(snapshot.tiles, isEmpty);
    final image = snapshot.base!.image;
    expect(math.max(image.width, image.height), 256);
    expect((image.width, image.height), (182, 256));
    expect(w.engine.renderRequests, hasLength(1));
    final stats = w.service.stats;
    expect(stats.thumbnailBytes, 182 * 256 * 4);
    expect(stats.previewBytes, 0);
    expect(stats.tileBytes, 0);
    handle.dispose();
    await w.close();
  });

  testWidgets(
    'a tiny page (long side ≤ 320 device px) uses thumbnail mode too',
    (tester) async {
      final w = _World();
      final handle = w.service.attach(
        const PdfBackgroundParams(
          assetId: _asset,
          pdfPageIndex: 0,
          pageSize: _a4,
          deviceScale: 0.3, // 841.89 × 0.3 ≈ 253 px
        ),
      );
      await _settle(tester);
      expect(
        math.max(
          handle.snapshot.base!.image.width,
          handle.snapshot.base!.image.height,
        ),
        256,
      );
      expect(w.service.stats.thumbnailBytes, greaterThan(0));
      handle.dispose();
      await w.close();
    },
  );

  testWidgets('thumbnails of one page share one cached image', (tester) async {
    final w = _World();
    final first = w.service.attach(_thumb(1));
    await _settle(tester);
    // Same page at another device scale: still the one 256 px image.
    final second = w.service.attach(_thumb(1, deviceScale: 3));
    await _settle(tester);
    expect(w.engine.renderRequests, hasLength(1));
    expect(
      identical(first.snapshot.base!.image, second.snapshot.base!.image),
      isTrue,
    );
    first.dispose();
    second.dispose();
    // Unmounted thumbnails stay in the LRU: mounting again needs no render.
    final third = w.service.attach(_thumb(1));
    await _settle(tester);
    expect(w.engine.renderRequests, hasLength(1));
    expect(third.snapshot.status, PdfRenderStatus.ready);
    third.dispose();
    await w.close();
  });

  testWidgets('over the thumbnail budget the least recently used leave', (
    tester,
  ) async {
    // 182 × 256 × 4 = 186 368 bytes per A4 thumbnail; room for two.
    final w = _World(
      budget: const PdfRenderBudget(
        previewBytes: 1 << 20,
        tileBytes: 1 << 20,
        thumbnailBytes: 2 * 186368,
      ),
    );
    final images = <ui.Image>[];
    for (var page = 0; page < 3; page++) {
      final handle = w.service.attach(_thumb(page));
      await _settle(tester);
      images.add(handle.snapshot.base!.image);
      handle.dispose();
      await _settle(tester);
    }
    expect(w.service.stats.thumbnailBytes, 2 * 186368);
    expect(images[0].debugDisposed, isTrue, reason: 'oldest unused');
    expect(images[1].debugDisposed, isFalse);
    expect(images[2].debugDisposed, isFalse);
    // In use, the budget may be exceeded: shown as overBudgetBytes.
    final handles = [
      for (var page = 0; page < 3; page++) w.service.attach(_thumb(page)),
    ];
    await _settle(tester);
    expect(w.service.stats.thumbnailBytes, 3 * 186368);
    expect(w.service.stats.overBudgetBytes, 186368);
    for (final h in handles) {
      h.dispose();
    }
    await _settle(tester);
    expect(w.service.stats.overBudgetBytes, 0);
    await w.close();
  });

  group('renderThumbnail', () {
    test('exact long side for portrait, landscape and rotated pages', () async {
      final w = _World(
        pages: const [
          PdfPageInfo(
            index: 0,
            width: 595.276,
            height: 841.89,
            rotationQuarterTurns: 0,
          ),
          PdfPageInfo(
            index: 1,
            width: 960,
            height: 540,
            rotationQuarterTurns: 0,
          ),
          // Rotated 90°: the displayed size is already swapped (PdfPageInfo).
          PdfPageInfo(
            index: 2,
            width: 841.89,
            height: 595.276,
            rotationQuarterTurns: 1,
          ),
        ],
      );
      for (final (page, longSide) in [(0, 256), (1, 512), (2, 300)]) {
        final image = (await w.service.renderThumbnail(
          assetId: _asset,
          pdfPageIndex: page,
          longSidePx: longSide,
        ))!;
        expect(
          math.max(image.width, image.height),
          longSide,
          reason: 'page $page',
        );
        image.dispose();
      }
      expect(w.service.stats.liveImages, 0, reason: 'never cached');
      expect(w.service.stats.rendered, 3);
      await w.close();
    });

    test(
      'the caller owns the image; the background color is passed on',
      () async {
        final w = _World();
        final image = (await w.service.renderThumbnail(
          assetId: _asset,
          pdfPageIndex: 0,
          longSidePx: 64,
          backgroundArgb: 0xFFFBF7EC,
        ))!;
        expect(w.engine.renderRequests.single.backgroundArgb, 0xFFFBF7EC);
        expect(
          w.engine.renderRequests.single.priority,
          PdfRenderPriority.normal,
        );
        expect(image.debugDisposed, isFalse);
        w.service.trimMemory();
        expect(image.debugDisposed, isFalse);
        image.dispose();
        await w.close();
      },
    );

    test('missing bytes / password / out-of-range page → null', () async {
      final w = _World();
      expect(
        await w.service.renderThumbnail(
          assetId: 'nowhere',
          pdfPageIndex: 0,
          longSidePx: 64,
        ),
        isNull,
      );
      final reports = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reports.add;
      try {
        expect(
          await w.service.renderThumbnail(
            assetId: _asset,
            pdfPageIndex: 9,
            longSidePx: 64,
          ),
          isNull,
        );
      } finally {
        FlutterError.onError = previous;
      }
      expect(reports, hasLength(1), reason: 'out of range is reported');
      await w.close();

      final locked = _World()..engine.userPassword = 'pw';
      expect(
        await locked.service.renderThumbnail(
          assetId: _asset,
          pdfPageIndex: 0,
          longSidePx: 64,
        ),
        isNull,
      );
      await locked.close();
    });
  });
}
