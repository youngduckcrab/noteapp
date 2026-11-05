// PDF T0 init_test, B4 version (contract 00-overview 7.6 B4 v1.2, 06-pdf 8 T0, PDF-2-2,
// PDF-3-3): a ProviderContainer that holds ONLY pdfIoOverrides() — no other override, not
// even core.noteStoreProvider — reads the two providers other areas read during the
// foundation stage and concurrent development without an exception:
//   - ink.pageBackgroundBuildersProvider = [PdfBackgroundLayerBuilder.paperOnly(),
//     TemplateBackgroundLayerBuilder()] (INK controllers / thumbnail renderer, INFRA
//     pdf_module_test),
//   - pdfRenderStatsProvider = ValueNotifier(PdfRenderStats.zero) (INFRA
//     pdfRenderStatsSection, feature_wiring_module_test, pdf_wiring_test).
// From PDF T8 / T17 the stats provider needs core.noteStoreProvider (PDF-4-2); this file is
// then rewritten with a fake store.
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';

const String _assetId =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

ink.InkBackgroundSpec _pdfSpec({int paper = core.PaperColors.white}) =>
    ink.InkBackgroundSpec(
      kind: ink.InkBackgroundKind.pdf,
      paperColorArgb: paper,
      assetId: _assetId,
      pdfPageIndex: 0,
    );

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer(overrides: pdfIoOverrides()));
  tearDown(() => container.dispose());

  test('pdfIoOverrides() = config + INK builder list (always both)', () {
    expect(pdfIoOverrides(), hasLength(2));
    expect(pdfIoOverrides(config: const PdfIoConfig()), hasLength(2));
  });

  test(
    'builders and stats read in the same container without an exception',
    () {
      final builders = container.read(ink.pageBackgroundBuildersProvider);
      expect(builders, hasLength(2));
      final first = builders[0];
      expect(first, isA<PdfBackgroundLayerBuilder>());
      expect((first as PdfBackgroundLayerBuilder).isPaperOnly, isTrue);
      expect(builders[1], isA<ink.TemplateBackgroundLayerBuilder>());
      expect(
        identical(first, container.read(pdfBackgroundLayerBuilderProvider)),
        isTrue,
      );

      final stats = container.read(pdfRenderStatsProvider);
      expect(stats.value, PdfRenderStats.zero);
    },
  );

  test('neither read touches core.noteStoreProvider (not overridden here)', () {
    container.read(ink.pageBackgroundBuildersProvider);
    container.read(pdfRenderStatsProvider);
    // The container really has no store: reading it fails, the reads above did not.
    expect(() => container.read(core.noteStoreProvider), throwsA(anything));
  });

  test('pdfIoConfigProvider = the given config, else the default', () {
    expect(container.read(pdfIoConfigProvider), const PdfIoConfig());
    const config = PdfIoConfig(warmUpOnStart: false);
    final custom = ProviderContainer(overrides: pdfIoOverrides(config: config));
    addTearDown(custom.dispose);
    expect(custom.read(pdfIoConfigProvider), config);
  });

  test('stats notifier starts at zero and skips equal values', () {
    final stats = container.read(pdfRenderStatsProvider);
    expect(stats, isA<ValueNotifier<PdfRenderStats>>());
    var calls = 0;
    void listener() => calls++;
    stats.addListener(listener);
    // A separately built zero (calls is 0 here), not the PdfRenderStats.zero instance.
    (stats as ValueNotifier<PdfRenderStats>).value = PdfRenderStats(
      previewBytes: calls,
      tileBytes: 0,
      thumbnailBytes: 0,
      liveImages: 0,
      queued: 0,
      inflight: 0,
      rendered: 0,
      cancelled: 0,
      lastRenderMs: 0,
      p95RenderMs: 0,
      openDocuments: 0,
      overBudgetBytes: 0,
    );
    expect(calls, 0);
    stats.removeListener(listener);
  });

  test('INK readers of the builder list work in this container', () {
    expect(
      container.read(ink.inkPageThumbnailRendererProvider),
      isA<core.PageThumbnailRenderer>(),
    );
  });

  test('other B4 state providers read their idle values', () {
    expect(container.read(pdfActiveSearchProvider), PdfSearchState.idle);
    expect(
      container.read(pdfSearchHighlightsProvider).value,
      PdfSearchState.idle,
    );
    expect(
      container.read(pdfImportJobProvider),
      const PdfJobIdle<PdfImportResult>(),
    );
    expect(
      container.read(pdfExportJobProvider),
      const PdfJobIdle<PdfExportResult>(),
    );
    expect(container.read(pdfBatchExportJobProvider), const PdfBatchJobIdle());
  });

  group('paperOnly builder', () {
    late PdfBackgroundLayerBuilder builder;
    setUp(() {
      builder =
          container.read(ink.pageBackgroundBuildersProvider).first
              as PdfBackgroundLayerBuilder;
    });

    test('handles pdf backgrounds with an asset and a page index only', () {
      expect(builder.handles(_pdfSpec()), isTrue);
      expect(
        builder.handles(
          const ink.InkBackgroundSpec(
            kind: ink.InkBackgroundKind.pdf,
            pdfPageIndex: 0,
          ),
        ),
        isFalse,
      );
      expect(
        builder.handles(
          const ink.InkBackgroundSpec(
            kind: ink.InkBackgroundKind.pdf,
            assetId: _assetId,
          ),
        ),
        isFalse,
      );
      for (final kind in [
        ink.InkBackgroundKind.blank,
        ink.InkBackgroundKind.template,
        ink.InkBackgroundKind.image,
        ink.InkBackgroundKind.unknown,
      ]) {
        expect(
          builder.handles(
            ink.InkBackgroundSpec(
              kind: kind,
              assetId: _assetId,
              pdfPageIndex: 0,
            ),
          ),
          isFalse,
          reason: kind.name,
        );
      }
    });

    test('renderStill → null', () async {
      expect(
        await builder.renderStill(
          _pdfSpec(),
          pageSize: const Size(595, 842),
          pixelSize: const Size(119, 168),
        ),
        isNull,
      );
    });

    testWidgets(
      'build: opaque paper of pageSize × viewScale, no pointer handling',
      (tester) async {
        // Semi-transparent ivory: the paper must still be painted opaque.
        final ctx = ink.PageBackgroundContext(
          pageId: 'p1',
          pageSize: const Size(200, 100),
          background: _pdfSpec(paper: 0x80FBF7EC),
          viewScale: 1.5,
          ancestorScale:
              2, // never multiplied into the layout (contract 7.2.16 v1.1)
          devicePixelRatio: 2,
          isScaling: false,
        );
        const key = Key('background');
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: key,
                child: Builder(
                  builder: (context) => builder.build(context, ctx),
                ),
              ),
            ),
          ),
        );

        expect(tester.getSize(find.byKey(key)), const Size(300, 150));
        final ignore = tester.widget<IgnorePointer>(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(IgnorePointer),
          ),
        );
        expect(ignore.ignoring, isTrue);

        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(key),
        );
        final pixels = await tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            final data = await image.toByteData();
            return (image.width, image.height, data!);
          } finally {
            image.dispose();
          }
        });
        final (width, height, data) = pixels!;
        expect((width, height), (300, 150));
        for (final (x, y) in [(0, 0), (150, 75), (299, 149), (299, 0)]) {
          final i = (y * width + x) * 4;
          expect(
            [
              data.getUint8(i),
              data.getUint8(i + 1),
              data.getUint8(i + 2),
              data.getUint8(i + 3),
            ],
            [0xFB, 0xF7, 0xEC, 0xFF],
            reason: 'pixel ($x, $y)',
          );
        }
      },
    );
  });
}
