// pdfRenderStatsProvider, T8 body (06-pdf 4.12, 8 T8; PDF-3-3, PDF-4-2): it watches the
// renderer (ref.watch(pdfPageRendererProvider).statsListenable), so a reading container needs
// core.noteStoreProvider — every real container has it (INFRA CoreModule). Reading it builds
// the render chain but never initializes the engine or opens a document; a render shows up
// in the value. (The B4 "pdfIoOverrides() only" read moved here from unit/init_test.)

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

Uint8List _pdf() => Uint8List.fromList('%PDF-1.7\n% stats\n%%EOF\n'.codeUnits);

void main() {
  // PdfRenderService registers its AppLifecycleListener on the first render.
  WidgetsFlutterBinding.ensureInitialized();

  late core.NoteStore store;
  setUp(() => store = core_testing.createFakeNoteStore());
  tearDown(() => store.close());

  test(
    'pdfIoOverrides() + core.noteStoreProvider: reads zero, no exception',
    () {
      final container = ProviderContainer(
        overrides: [
          ...pdfIoOverrides(),
          core.noteStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      final stats = container.read(pdfRenderStatsProvider);
      expect(stats.value, PdfRenderStats.zero);
      expect(
        identical(
          stats,
          container.read(pdfPageRendererProvider).statsListenable,
        ),
        isTrue,
      );
    },
  );

  test('pdfIoOverrides() alone: the T8 body needs core.noteStoreProvider', () {
    final container = ProviderContainer(overrides: pdfIoOverrides());
    addTearDown(container.dispose);
    expect(() => container.read(pdfRenderStatsProvider), throwsA(anything));
  });

  test('reading opens nothing; one render → rendered == 1', () async {
    final engine = FakePdfEngine();
    final container = ProviderContainer(
      overrides: [
        ...pdfIoOverrides(),
        core.noteStoreProvider.overrideWithValue(store),
        pdfEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);

    final ValueListenable<PdfRenderStats> stats = container.read(
      pdfRenderStatsProvider,
    );
    expect(stats.value, PdfRenderStats.zero);
    expect(engine.ensureInitializedCalls, 0);
    expect(engine.openCalls, isEmpty);

    final asset = await container
        .read(pdfNoteGatewayProvider)
        .putPdf(_pdf(), fileName: 'stats.pdf');
    expect(engine.openCalls, isEmpty, reason: 'storing opens nothing');

    final image = await container
        .read(pdfPageRendererProvider)
        .renderThumbnail(assetId: asset.id, pdfPageIndex: 0, longSidePx: 64);
    expect(image, isNotNull);
    image!.dispose();
    await pumpEventQueue();
    expect(engine.openCalls, hasLength(1));
    expect(stats.value.rendered, 1);
    expect(stats.value.openDocuments, 1);
    expect(stats.value.queued, 0);
    expect(stats.value.inflight, 0);
  });

  test('the stats notifier goes with the renderer', () async {
    final engine = FakePdfEngine();
    final container = ProviderContainer(
      overrides: [
        ...pdfIoOverrides(),
        core.noteStoreProvider.overrideWithValue(store),
        pdfEngineProvider.overrideWithValue(engine),
      ],
    );
    final renderer = container.read(pdfPageRendererProvider);
    final stats = container.read(pdfRenderStatsProvider);
    expect(identical(stats, renderer.statsListenable), isTrue);
    expect(stats, isA<ChangeNotifier>());
    final notifier = stats as ChangeNotifier;
    var notified = 0;
    void listener() => notified++;
    stats.addListener(listener);
    expect(ChangeNotifier.debugAssertNotDisposed(notifier), isTrue);

    container.dispose();
    await pumpEventQueue();

    // The renderer was disposed with the container: it renders nothing any more …
    expect(
      await renderer.renderThumbnail(
        assetId: 'gone',
        pdfPageIndex: 0,
        longSidePx: 64,
      ),
      isNull,
    );
    expect(engine.openCalls, isEmpty);
    // … and its stats notifier went with it: using it now is a "used after being
    // disposed" error, and the listener was never called.
    expect(
      () => ChangeNotifier.debugAssertNotDisposed(notifier),
      throwsFlutterError,
    );
    expect(() => stats.addListener(() {}), throwsFlutterError);
    expect(notified, 0);
    // Removing a listener after dispose is still allowed (ChangeNotifier).
    stats.removeListener(listener);
  });
}
