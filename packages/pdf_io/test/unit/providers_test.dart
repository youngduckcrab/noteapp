// PDF provider graph (06-pdf 4.12, 6.13; 8 T17): every provider builds over fakes, CORE's
// remoteAssetFetcherProvider / pageThumbnailRendererProvider reach the pool / the import
// service, disposing the container closes the pool's documents and the compose backend,
// recoverable errors (cover thumbnail, ensureLocal, renderStill) reach FlutterError.onError
// once each with library 'pdf_io' while a user cancel and a missing original report
// nothing, and the background builder provider survives search start / select / clear
// (PDF-3-4: same instance, built once, its renderer closure still usable).
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

import '../support/export_world.dart' show captureFlutterErrors;
import '../support/render_doubles.dart';

Uint8List _pdf([String body = 'body']) =>
    Uint8List.fromList('%PDF-1.7\n% $body\n%%EOF\n'.codeUnits);

PdfPageTextData _text(int index, String text) => PdfPageTextData(
  pageIndex: index,
  text: text,
  charRects: [
    for (var i = 0; i < text.length; i++)
      ui.Rect.fromLTWH(10 + 5.0 * i, 10, 5, 10),
  ],
);

/// Counts provider creations by name.
final class _Builds extends ProviderObserver {
  final Map<String, int> counts = {};

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    final name = context.provider.name;
    if (name != null) counts[name] = (counts[name] ?? 0) + 1;
  }
}

final class _World {
  _World({FakePdfEngine? engine, bool overrideBackend = true})
    : engine =
          engine ??
          FakePdfEngine(
            pageCount: 2,
            texts: {0: _text(0, 'one two'), 1: _text(1, 'two one')},
          ) {
    container = ProviderContainer(
      overrides: [
        ...pdfIoOverrides(config: const PdfIoConfig(warmUpOnStart: false)),
        core.noteStoreProvider.overrideWithValue(store),
        core.remoteAssetFetcherProvider.overrideWithValue(fetcher),
        core.pageThumbnailRendererProvider.overrideWithValue(thumbnails),
        pdfEngineProvider.overrideWithValue(this.engine),
        if (overrideBackend)
          pdfComposeBackendProvider.overrideWithValue(backend),
      ],
      observers: [builds],
    );
  }

  final core.NoteStore store = core_testing.createFakeNoteStore();
  final FakePdfEngine engine;
  final FakeRemoteAssetFetcher fetcher = FakeRemoteAssetFetcher();
  final ScriptedThumbnailRenderer thumbnails = ScriptedThumbnailRenderer();
  final RecordingComposeBackend backend = RecordingComposeBackend();
  final _Builds builds = _Builds();
  late final ProviderContainer container;
  bool _disposed = false;

  T read<T>(ProviderListenable<T> provider) => container.read(provider);

  /// A note of [pages] PDF pages over one stored PDF.
  Future<(core.Note, core.AssetId)> pdfNote(int pages) async {
    final gateway = read(pdfNoteGatewayProvider);
    final asset = await gateway.putPdf(_pdf(), fileName: 'a.pdf');
    final note = await gateway.createNote(
      title: 'n',
      pages: [
        for (var i = 0; i < pages; i++)
          core.PageDraft(
            size: core.PageSize.a4Portrait,
            background: core.PdfBackground(assetId: asset.id, pdfPageIndex: i),
          ),
      ],
    );
    return (note, asset.id);
  }

  /// Imports a 2-page PDF as a new note through pdfImportServiceProvider.
  Future<PdfImportResult> importNewNote({PdfCancelSignal? cancel}) async {
    final session = await read(pdfImportServiceProvider)
        .open(PickedPdfFile.fromBytes('a.pdf', _pdf('import')));
    try {
      return await session.commit(const PdfImportAsNewNote(), cancel: cancel);
    } finally {
      await session.dispose();
    }
  }

  void disposeContainer() {
    if (_disposed) return;
    _disposed = true;
    container.dispose();
  }

  Future<void> dispose() async {
    disposeContainer();
    await store.close();
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await pumpEventQueue();
  }
}

List<FlutterErrorDetails> _pdfReports(List<FlutterErrorDetails> all) => [
  for (final r in all)
    if (r.library == 'pdf_io') r,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the graph builds over fakes', () async {
    final w = _World();
    addTearDown(w.dispose);
    final gateway = w.read(pdfNoteGatewayProvider);
    expect(gateway, isA<CorePdfNoteGateway>());
    expect((gateway as CorePdfNoteGateway).store, same(w.store));
    expect(w.read(pdfEngineProvider), same(w.engine));
    expect(w.read(pdfDocumentPoolProvider), isA<DefaultPdfDocumentPool>());
    expect(w.read(pdfPageRendererProvider), isA<PdfRenderService>());
    expect(w.read(pdfRenderStatsProvider).value, PdfRenderStats.zero);
    expect(w.read(pdfTextServiceProvider), isA<DefaultPdfTextService>());
    expect(w.read(pdfImportServiceProvider), isA<DefaultPdfImportService>());
    expect(w.read(pdfExportServiceProvider), isA<DefaultPdfExportService>());
    expect(w.read(pdfFileSourceProvider), isA<FilePickerPdfSource>());
    expect(w.read(pdfIncomingFileSourceProvider), isA<NoIncomingPdfFiles>());
    expect(w.read(pdfOutputSinkProvider).availableActions(const []), isEmpty);
    expect(w.read(pdfInkVectorizerProvider), isA<InkEngineVectorizer>());
    expect(w.read(pdfComposeBackendProvider), same(w.backend));
    expect(
      w.read(pdfBackgroundLayerBuilderProvider).isPaperOnly,
      isFalse,
      reason: 'the renderer-backed builder',
    );
    // Reading the graph neither initializes the engine nor opens a document.
    expect(w.engine.ensureInitializedCalls, 0);
    expect(w.engine.openCalls, isEmpty);
    // Every PDF provider is named after its variable (contract 7.4.4).
    for (final name in w.builds.counts.keys.where((n) => n.startsWith('pdf'))) {
      expect(name, endsWith('Provider'));
    }

    // Defaults without the engine / backend overrides: pdfrx and the platform backend.
    final store = core_testing.createFakeNoteStore();
    addTearDown(store.close);
    final plain = ProviderContainer(
      overrides: [
        ...pdfIoOverrides(config: const PdfIoConfig(warmUpOnStart: false)),
        core.noteStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(plain.dispose);
    expect(plain.read(pdfEngineProvider), isA<PdfrxEngine>());
    expect(plain.read(pdfComposeBackendProvider), isA<PdfComposeBackend>());
  });

  test('core.remoteAssetFetcherProvider reaches the pool', () async {
    final w = _World();
    addTearDown(w.dispose);
    const remote =
        'feedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeed';
    final progress = w.read(pdfDocumentPoolProvider).requestRemote(remote);
    expect(progress, isNotNull);
    final sub = progress!.listen((_) {});
    await _settle();
    expect(w.fetcher.ensureLocalCalls, [remote]);
    await sub.cancel();
  });

  test(
    'core.pageThumbnailRendererProvider reaches the import service',
    () async {
      final w = _World();
      addTearDown(w.dispose);
      final result = await w.importNewNote();
      expect(result.insertedPageIds, hasLength(2));
      expect(w.thumbnails.calls, [(result.insertedPageIds.first, 512)]);
    },
  );

  test(
    'container dispose closes the documents and the compose backend',
    () async {
      final w = _World(overrideBackend: false);
      addTearDown(w.dispose);
      final (_, assetId) = await w.pdfNote(1);
      final lease = await w.read(pdfDocumentPoolProvider).acquire(assetId);
      expect(lease, isNotNull);
      expect(w.engine.openDocumentCount, 1);
      // The platform backend (native on the VM) is disposed with its provider.
      final backend = w.read(pdfComposeBackendProvider);
      expect(backend, isNot(same(w.backend)));

      w.disposeContainer();
      await _settle();
      expect(w.engine.openDocumentCount, 0);
      await expectLater(
        backend.begin(
          const PdfComposePlan(
            sources: [],
            pages: [PdfComposeBlankPage(noteSize: ui.Size(100, 100))],
          ),
        ),
        throwsStateError,
      );
    },
  );

  group('error reports (6.13)', () {
    test(
      'a failing cover thumbnail: reported once, the import succeeds',
      () async {
        final reports = captureFlutterErrors();
        final w = _World();
        addTearDown(w.dispose);
        w.thumbnails.error = StateError('cover failed');
        final result = await w.importNewNote();
        expect(result.insertedPageIds, hasLength(2));
        final pdf = _pdfReports(reports);
        expect(pdf, hasLength(1));
        expect(pdf.single.exception, isA<StateError>());
        expect(reports, hasLength(1));
      },
    );

    test(
      'a failing ensureLocal: reported once, the progress says failed',
      () async {
        final reports = captureFlutterErrors();
        final w = _World();
        addTearDown(w.dispose);
        const remote =
            'beefbeefbeefbeefbeefbeefbeefbeefbeefbeefbeefbeefbeefbeefbeefbeef';
        final seen = <core.RemoteAssetProgress>[];
        final sub = w
            .read(pdfDocumentPoolProvider)
            .requestRemote(remote)!
            .listen(seen.add);
        await _settle();
        w.fetcher.failEnsureLocal(remote, StateError('network down'));
        await _settle();
        expect(_pdfReports(reports), hasLength(1));
        expect(reports, hasLength(1));
        expect(seen.last.state, core.RemoteAssetState.failed);
        await sub.cancel();
      },
    );

    test('a failing renderStill: reported once, null', () async {
      final reports = captureFlutterErrors();
      final w = _World();
      addTearDown(w.dispose);
      final (_, assetId) = await w.pdfNote(1);
      w.engine.renderError = StateError('render failed');
      final builder = w.read(pdfBackgroundLayerBuilderProvider);
      final image = await builder.renderStill(
        ink.InkBackgroundSpec(
          kind: ink.InkBackgroundKind.pdf,
          assetId: assetId,
          pdfPageIndex: 0,
        ),
        pageSize: const ui.Size(595, 842),
        pixelSize: const ui.Size(60, 84),
      );
      expect(image, isNull);
      expect(_pdfReports(reports), hasLength(1));
      expect(reports, hasLength(1));
    });

    test('a user cancel and a missing original report nothing', () async {
      final reports = captureFlutterErrors();
      final w = _World();
      addTearDown(w.dispose);
      final cancel = PdfCancelSignal()..cancel();
      await expectLater(
        w.importNewNote(cancel: cancel),
        throwsA(
          isA<PdfIoException>().having(
            (e) => e.code,
            'code',
            PdfErrorCode.cancelled,
          ),
        ),
      );
      const missing =
          'cafecafecafecafecafecafecafecafecafecafecafecafecafecafecafecafe';
      await expectLater(
        w.read(pdfDocumentPoolProvider).acquire(missing),
        throwsA(
          isA<PdfIoException>().having(
            (e) => e.code,
            'code',
            PdfErrorCode.assetMissing,
          ),
        ),
      );
      final still = await w
          .read(pdfBackgroundLayerBuilderProvider)
          .renderStill(
            const ink.InkBackgroundSpec(
              kind: ink.InkBackgroundKind.pdf,
              assetId: missing,
              pdfPageIndex: 0,
            ),
            pageSize: const ui.Size(595, 842),
            pixelSize: const ui.Size(60, 84),
          );
      expect(still, isNull);
      await _settle();
      expect(reports, isEmpty);
    });
  });

  test(
    'PDF-3-4: the builder provider survives search start / select / clear',
    () async {
      final w = _World();
      addTearDown(w.dispose);
      final (note, assetId) = await w.pdfNote(2);
      final seen = <PdfBackgroundLayerBuilder>[];
      final sub = w.container.listen(
        pdfBackgroundLayerBuilderProvider,
        (_, next) => seen.add(next),
        fireImmediately: true,
      );
      addTearDown(sub.close);
      final first = seen.single;
      final highlights = w.read(pdfSearchHighlightsProvider);
      final search = w.read(pdfActiveSearchProvider.notifier);

      search.start(note.id, 'one');
      await _settle();
      expect(w.read(pdfActiveSearchProvider).status, PdfSearchStatus.done);
      expect(w.read(pdfActiveSearchProvider).hits, hasLength(2));
      expect(highlights.value, w.read(pdfActiveSearchProvider));
      search.select(1);
      expect(highlights.value.currentIndex, 1);
      search.clear();
      expect(highlights.value, PdfSearchState.idle);

      expect(seen, hasLength(1), reason: 'never rebuilt');
      expect(
        identical(w.read(pdfBackgroundLayerBuilderProvider), first),
        isTrue,
      );
      expect(w.builds.counts['pdfBackgroundLayerBuilderProvider'], 1);
      expect(w.builds.counts['pdfSearchHighlightsProvider'], 1);
      expect(
        identical(w.read(pdfSearchHighlightsProvider), highlights),
        isTrue,
      );

      // The first instance's renderer closure still works (no UnmountedRefException).
      final image = await first.renderStill(
        ink.InkBackgroundSpec(
          kind: ink.InkBackgroundKind.pdf,
          assetId: assetId,
          pdfPageIndex: 0,
        ),
        pageSize: const ui.Size(595, 842),
        pixelSize: const ui.Size(60, 84),
      );
      expect(image, isNotNull);
      expect((image!.width, image.height), (60, 84));
      image.dispose();
    },
  );
}
