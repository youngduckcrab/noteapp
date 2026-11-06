// PDF init_v2_test (m5-7/06-pdf 6.3 ①~④, 8.1 T20 — 2nd-round contract 7.2.12, 7.6.2 R2-B4):
// pdfIoOverrides() v2 = [pdfIoConfigProvider, ink.pageBackgroundBuildersProvider →
// [PdfBackgroundLayerBuilder, ...ink.defaultPageBackgroundBuilders(ref)]].
//  ① the list has exactly two overrides;
//  ② the builder list is [PdfBackgroundLayerBuilder, ImageBackgroundLayerBuilder,
//    TemplateBackgroundLayerBuilder] in this order;
//  ③ a container with ONLY these overrides (no core.noteStoreProvider, no asset store) reads
//    it without an exception and builds no engine, pool, gateway, renderer or indexer;
//  ④ an image background spec is handled by INK's image builder, not by the PDF builder.
// Plus the R2-B4 body of pdfSearchIndexerProvider (built over a fake store, not started).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/search_index/indexer_gate.dart';
import 'package:pdf_io/src/search_index/pdf_search_indexer.dart'
    show debugPdfSearchIndexerState;

const String _assetId =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

/// Counts provider creations by name.
final class _Builds extends ProviderObserver {
  final Map<String, int> counts = {};

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    final name = context.provider.name;
    if (name != null) counts[name] = (counts[name] ?? 0) + 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('① exactly two overrides, with and without a config', () {
    expect(pdfIoOverrides(), hasLength(2));
    expect(
      pdfIoOverrides(config: const PdfIoConfig(warmUpOnStart: false)),
      hasLength(2),
    );
  });

  test(
    '② builders = [pdf, image, template] (PDF, then INK\'s default list)',
    () {
      final container = ProviderContainer.test(overrides: pdfIoOverrides());
      final builders = container.read(ink.pageBackgroundBuildersProvider);
      expect(builders, [
        isA<PdfBackgroundLayerBuilder>(),
        isA<ink.ImageBackgroundLayerBuilder>(),
        isA<ink.TemplateBackgroundLayerBuilder>(),
      ]);
      expect(
        identical(
          builders.first,
          container.read(pdfBackgroundLayerBuilderProvider),
        ),
        isTrue,
      );
      // The image builder shares INK's image cache (CP-INK-6: the thumbnail renderer finds it
      // as the first ImageBackgroundLayerBuilder of the list).
      final image = builders[1] as ink.ImageBackgroundLayerBuilder;
      expect(
        identical(image.images, container.read(ink.inkImageCacheProvider)),
        isTrue,
      );
    },
  );

  test(
    '③ no store override: reads without an exception, builds nothing else',
    () {
      final builds = _Builds();
      final container = ProviderContainer.test(
        overrides: pdfIoOverrides(),
        observers: [builds],
      );
      final builders = container.read(ink.pageBackgroundBuildersProvider);
      expect(builders, hasLength(3));
      // INK readers of the list work too (controllers / thumbnails read it).
      expect(
        container.read(ink.inkPageThumbnailRendererProvider),
        isA<core.PageThumbnailRenderer>(),
      );
      for (final name in [
        'pdfPageRendererProvider',
        'pdfDocumentPoolProvider',
        'pdfNoteGatewayProvider',
        'pdfEngineProvider',
        'pdfSearchIndexerProvider',
        'noteStoreProvider',
        'assetStoreProvider',
      ]) {
        expect(builds.counts.containsKey(name), isFalse, reason: name);
      }
      // The container really has no store: reading it fails, the reads above did not.
      expect(() => container.read(core.noteStoreProvider), throwsA(anything));
    },
  );

  test('④ an image background is the image builder\'s, a PDF page the PDF builder\'s', () {
    final container = ProviderContainer.test(overrides: pdfIoOverrides());
    final builders = container.read(ink.pageBackgroundBuildersProvider);
    const image = ink.InkBackgroundSpec(
      kind: ink.InkBackgroundKind.image,
      assetId: _assetId,
      imageFit: core.ImageFit.cover,
    );
    const pdf = ink.InkBackgroundSpec(
      kind: ink.InkBackgroundKind.pdf,
      assetId: _assetId,
      pdfPageIndex: 0,
    );
    expect([for (final b in builders) b.handles(image)], [false, true, false]);
    expect(
      builders.firstWhere((b) => b.handles(image)),
      isA<ink.ImageBackgroundLayerBuilder>(),
    );
    expect(builders.first.handles(pdf), isTrue);
    expect(builders[1].handles(pdf), isFalse);
    // From a CORE background as INK builds the spec.
    final fromCore = ink.InkBackgroundSpec.fromCore(
      const core.ImageBackground(assetId: _assetId),
    );
    expect(builders.first.handles(fromCore), isFalse);
    expect(builders[1].handles(fromCore), isTrue);
  });

  test(
    'pdfSearchIndexerProvider over a fake store: built, not started (R2-B4)',
    () async {
      final store = core_testing.createFakeNoteStore();
      addTearDown(store.close);
      final builds = _Builds();
      final container = ProviderContainer(
        overrides: [
          ...pdfIoOverrides(),
          core.noteStoreProvider.overrideWithValue(store),
        ],
        observers: [builds],
      );
      final indexer = container.read(pdfSearchIndexerProvider);
      expect(
        identical(indexer, container.read(pdfSearchIndexerProvider)),
        isTrue,
      );
      final state = debugPdfSearchIndexerState(indexer);
      expect(identical(state.store, store), isTrue);
      expect(
        identical(state.pool, container.read(pdfDocumentPoolProvider)),
        isTrue,
      );
      expect(state.gate, isA<AppIndexerGate>());
      expect(state.started, isFalse);
      expect(state.disposed, isFalse);
      // Building it opens no engine.
      expect(builds.counts.containsKey('pdfEngineProvider'), isTrue);
      expect(container.read(pdfEngineProvider).isInitialized, isFalse);
      // INFRA's idle task may dispose before the container does: both are safe.
      await indexer.dispose();
      container.dispose();
      expect(debugPdfSearchIndexerState(indexer).disposed, isTrue);
    },
  );
}
