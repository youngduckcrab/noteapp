// PdfBackgroundLayerBuilder, the INK extension point (06-pdf 4.7, 6.8, 6.9; 8 T9; contract
// 7.2.16 v1.1): handles(), paramsFrom (incl. isThumbnail, deviceScale = ctx.deviceScale), the
// ancestorScale rule (PDF-2-1: layout = pageSize × viewScale, resolution = deviceScale), the
// lazy renderer (reading the builder list builds no renderer; the first build does — PDF-2-2)
// and renderStill (size, opaque paper, PdfPageFit placement, null without the original and
// no download request).
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

const ui.Size _a4 = ui.Size(595.276, 841.89);
const String _asset = 'asset-a';

Uint8List _pdf() =>
    Uint8List.fromList('%PDF-1.7\n% adapter\n%%EOF\n'.codeUnits);

ink.InkBackgroundSpec _spec({
  String? assetId = _asset,
  int? pdfPageIndex = 0,
  int paper = 0xFFFFFFFF,
  ink.InkBackgroundKind kind = ink.InkBackgroundKind.pdf,
}) => ink.InkBackgroundSpec(
  kind: kind,
  paperColorArgb: paper,
  assetId: assetId,
  pdfPageIndex: pdfPageIndex,
);

ink.PageBackgroundContext _ctx({
  ui.Size pageSize = _a4,
  double viewScale = 1.5,
  double ancestorScale = 1,
  double devicePixelRatio = 2,
  bool isScaling = false,
  bool isThumbnail = false,
  ui.Rect? visible,
  ink.InkBackgroundSpec? background,
}) => ink.PageBackgroundContext(
  pageId: 'p1',
  pageSize: pageSize,
  background: background ?? _spec(),
  viewScale: viewScale,
  ancestorScale: ancestorScale,
  devicePixelRatio: devicePixelRatio,
  isScaling: isScaling,
  visiblePageRect: visible,
  isThumbnail: isThumbnail,
);

final class _World {
  _World({ui.Size pdfPageSize = _a4, this.fetcher}) {
    engine = FakePdfEngine(pageSize: pdfPageSize, imageArgb: 0xFF000000);
    gateway.arriveBytes(_asset, _pdf());
    pool = DefaultPdfDocumentPool(
      engine: engine,
      gateway: gateway,
      remoteAssets: fetcher,
    );
    service = PdfRenderService(
      pool: pool,
      budget: const PdfRenderBudget.web(),
      trimOnAppHidden: false,
    );
    builder = PdfBackgroundLayerBuilder(renderer: () => service);
  }

  late final FakePdfEngine engine;
  final FakePdfNoteGateway gateway = FakePdfNoteGateway();
  final FakeRemoteAssetFetcher? fetcher;
  late final DefaultPdfDocumentPool pool;
  late final PdfRenderService service;
  late final PdfBackgroundLayerBuilder builder;

  Future<void> close() async {
    await service.dispose();
    await pool.dispose();
  }
}

/// RGBA at (x, y) of [image].
Future<List<int>> _pixel(ui.Image image, int x, int y) async {
  final data = (await image.toByteData())!;
  final i = (y * image.width + x) * 4;
  return [for (var c = 0; c < 4; c++) data.getUint8(i + c)];
}

void main() {
  test('handles: pdf kind with an asset and a page index only', () {
    final builder = PdfBackgroundLayerBuilder(
      renderer: () => throw StateError('not needed'),
    );
    expect(builder.isPaperOnly, isFalse);
    expect(builder.handles(_spec()), isTrue);
    expect(builder.handles(_spec(assetId: null)), isFalse);
    expect(builder.handles(_spec(pdfPageIndex: null)), isFalse);
    for (final kind in ink.InkBackgroundKind.values) {
      if (kind == ink.InkBackgroundKind.pdf) continue;
      expect(builder.handles(_spec(kind: kind)), isFalse, reason: kind.name);
    }
  });

  test(
    'paramsFrom maps every field (isThumbnail, deviceScale = ctx.deviceScale)',
    () {
      final ctx = _ctx(
        ancestorScale: 2,
        isScaling: true,
        isThumbnail: true,
        visible: const ui.Rect.fromLTWH(1, 2, 3, 4),
        background: _spec(paper: 0xFFFBF7EC, pdfPageIndex: 7),
      );
      final params = PdfBackgroundLayerBuilder.paramsFrom(ctx);
      expect(params.assetId, _asset);
      expect(params.pdfPageIndex, 7);
      expect(params.pageSize, _a4);
      expect(params.deviceScale, 1.5 * 2 * 2);
      expect(params.deviceScale, ctx.deviceScale);
      expect(params.paperColorArgb, 0xFFFBF7EC);
      expect(params.visiblePageRect, const ui.Rect.fromLTWH(1, 2, 3, 4));
      expect(params.isScaling, isTrue);
      expect(params.isThumbnail, isTrue);
      expect(params.pageId, 'p1');
      expect(params.usesThumbnailMode, isTrue);
      expect(PdfBackgroundLayerBuilder.paramsFrom(_ctx()).isThumbnail, isFalse);
    },
  );

  testWidgets(
    'ancestorScale 2: widget = pageSize × viewScale, deviceScale = 1.5 × 2 × 2 = 6',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1032, 1376)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final w = _World();
      Future<Size> sizeFor(ink.PageBackgroundContext ctx) async {
        const key = Key('bg');
        await tester.pumpWidget(
          MaterialApp(
            home: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: KeyedSubtree(
                  key: key,
                  child: Builder(
                    builder: (context) => w.builder.build(context, ctx),
                  ),
                ),
              ),
            ),
          ),
        );
        return tester.getSize(find.byKey(key));
      }

      final zoomed = await sizeFor(_ctx(ancestorScale: 2));
      expect(zoomed.width, closeTo(595.276 * 1.5, 1e-6));
      expect(zoomed.height, closeTo(841.89 * 1.5, 1e-6));
      final view = tester.widget<PdfPageBackgroundView>(
        find.byType(PdfPageBackgroundView),
      );
      expect(view.viewScale, 1.5);
      expect(view.params.deviceScale, 6);
      expect(identical(view.renderer, w.service), isTrue);
      expect(await sizeFor(_ctx()), zoomed);
      await tester.pumpWidget(const SizedBox());
      await w.close();
    },
  );

  testWidgets(
    'reading the builder list builds no renderer; the first build does',
    (tester) async {
      final store = core_testing.createFakeNoteStore();
      addTearDown(store.close);
      final w = _World();
      var renderers = 0;
      final container = ProviderContainer(
        overrides: [
          ...pdfIoOverrides(),
          core.noteStoreProvider.overrideWithValue(store),
          pdfPageRendererProvider.overrideWith((ref) {
            renderers++;
            return w.service;
          }),
        ],
      );
      addTearDown(container.dispose);
      final builders = container.read(ink.pageBackgroundBuildersProvider);
      final builder = builders.first as PdfBackgroundLayerBuilder;
      expect(builder.isPaperOnly, isFalse);
      expect(
        identical(builder, container.read(pdfBackgroundLayerBuilderProvider)),
        isTrue,
      );
      expect(renderers, 0);
      expect(
        builder.highlights,
        same(container.read(pdfSearchHighlightsProvider)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: Builder(
              builder: (context) => builder.build(context, _ctx()),
            ),
          ),
        ),
      );
      expect(renderers, 1);
      await tester.pumpWidget(const SizedBox());
      await w.close();
    },
  );

  group('renderStill', () {
    test('opaque image of pixelSize: paper + the PDF page', () async {
      final w = _World();
      final image = await w.builder.renderStill(
        _spec(paper: 0x80FBF7EC),
        pageSize: _a4,
        pixelSize: const Size(120.4, 170),
      );
      expect(image, isNotNull);
      expect((image!.width, image.height), (121, 170));
      // Same aspect: the black PDF image covers the page.
      expect(await _pixel(image, 60, 85), [0, 0, 0, 0xFF]);
      expect(await _pixel(image, 1, 1), [0, 0, 0, 0xFF]);
      image.dispose();
      expect(w.engine.renderRequests.single.backgroundArgb, 0xFFFBF7EC);
      expect(
        w.service.stats.liveImages,
        0,
        reason: 'renderThumbnail is not cached',
      );
      await w.close();
    });

    test(
      's ≠ 1: the PDF box sits where PdfPageFit puts it (letterbox in paper)',
      () async {
        // Letter PDF on an A4 note page: k ≈ 0.97267, oy ≈ 35.767 pt.
        final w = _World(pdfPageSize: const ui.Size(612, 792));
        const pixelSize = Size(300, 424);
        final image = (await w.builder.renderStill(
          _spec(paper: 0xFFFBF7EC),
          pageSize: _a4,
          pixelSize: pixelSize,
        ))!;
        final fit = PdfPageFit(
          notePageSize: _a4,
          pdfPageSize: const ui.Size(612, 792),
        );
        final top = fit.oy * pixelSize.height / _a4.height; // ≈ 18 px
        expect(top, closeTo(18.0, 0.5));
        const paper = [0xFB, 0xF7, 0xEC, 0xFF];
        const black = [0, 0, 0, 0xFF];
        expect(await _pixel(image, 150, (top - 3).floor()), paper);
        expect(await _pixel(image, 150, (top + 3).ceil()), black);
        expect(await _pixel(image, 150, 212), black);
        final bottom = (fit.oy + 792 * fit.k) * pixelSize.height / _a4.height;
        expect(await _pixel(image, 150, (bottom - 3).floor()), black);
        expect(await _pixel(image, 150, (bottom + 3).ceil()), paper);
        expect(await _pixel(image, 2, 212), black, reason: 'full width');
        image.dispose();
        await w.close();
      },
    );

    test(
      'original missing → null, no download request; paperOnly → null',
      () async {
        final fetcher = FakeRemoteAssetFetcher();
        final w = _World(fetcher: fetcher);
        expect(
          await w.builder.renderStill(
            _spec(assetId: 'nowhere'),
            pageSize: _a4,
            pixelSize: const Size(100, 141),
          ),
          isNull,
        );
        expect(fetcher.ensureLocalCalls, isEmpty);
        expect(fetcher.watchListenerCount('nowhere'), 0);
        expect(
          await const PdfBackgroundLayerBuilder.paperOnly().renderStill(
            _spec(),
            pageSize: _a4,
            pixelSize: const Size(100, 141),
          ),
          isNull,
        );
        await w.close();
      },
    );

    test('a password-protected original → null', () async {
      final w = _World();
      w.engine.userPassword = 'pw';
      expect(
        await w.builder.renderStill(
          _spec(),
          pageSize: _a4,
          pixelSize: const Size(100, 141),
        ),
        isNull,
      );
      await w.close();
    });

    test('a render error → null and reported', () async {
      final w = _World();
      w.engine.renderError = StateError('boom');
      final reports = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reports.add;
      try {
        expect(
          await w.builder.renderStill(
            _spec(),
            pageSize: _a4,
            pixelSize: const Size(100, 141),
          ),
          isNull,
        );
      } finally {
        FlutterError.onError = previous;
      }
      expect(reports, hasLength(1));
      expect(reports.single.library, 'pdf_io');
      await w.close();
    });
  });
}
