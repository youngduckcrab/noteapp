// productionModules() / modulesFor() (docs/plans/01-infra.md 4.5.9, 6.4,
// 9.1; 2nd round docs/plans/m5-7/01-infra.md 4.6.4, S2-1, 6.6 — order core →
// pdf → media → recognition → featureWiring), and the modules together
// through AppBootstrapper / BootstrapApp with a fake CORE open.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/app/note_app.dart';
import 'package:noteapp/src/bootstrap/app_bootstrapper.dart';
import 'package:noteapp/src/bootstrap/app_module.dart';
import 'package:noteapp/src/bootstrap/bootstrap_app.dart';
import 'package:noteapp/src/bootstrap/startup_error_screen.dart';
import 'package:noteapp/src/bootstrap/startup_report.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/features/app_features.dart';
import 'package:noteapp/src/modules/core_module.dart';
import 'package:noteapp/src/modules/feature_wiring_module.dart';
import 'package:noteapp/src/modules/media_module.dart';
import 'package:noteapp/src/modules/pdf_module.dart';
import 'package:noteapp/src/modules/production_modules.dart';
import 'package:noteapp/src/modules/recognition_module.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';
import 'package:pdf_io/pdf_io.dart';

import '../fakes/counting_note_store.dart';
import '../fakes/fake_native_paths.dart';
import '../fakes/fake_note_store_opener.dart';
import '../fakes/fake_web_platform.dart';

/// productionModules() with CORE's open replaced (B2 openNoteStore throws)
/// and a no-op PDF initialize; everything else is the production module.
List<AppModule> _modules(FakeNoteStoreOpener opener) {
  final production = productionModules();
  return [
    CoreModule(nativePaths: noNativePaths, open: opener.call),
    PdfModule(initialize: () async {}),
    ...production.skip(2),
  ];
}

AppBootstrapper _bootstrapper(List<AppModule> modules, AppErrorLog log) {
  final web = FakeWebPlatform();
  return AppBootstrapper(
    modules: modules,
    buildInfo: BuildInfo.local,
    runtimeInfo: RuntimeInfo.detect(web),
    web: web,
    errorLog: log,
    ownerId: kLocalOwnerId,
  );
}

void main() {
  test('ids in S2-1 order, unique; module types and timeouts (default '
      'build: every FEATURE_* on)', () {
    expect(AppFeatures.compileTime, AppFeatures.all);
    final modules = productionModules();
    expect(modules.map((m) => m.id), [
      'core',
      'pdf',
      'media',
      'recognition',
      'featureWiring',
    ]);
    expect(modules.map((m) => m.id).toSet(), hasLength(modules.length));
    expect(modules[0], isA<CoreModule>());
    expect(modules[1], isA<PdfModule>());
    expect(modules[2], isA<MediaModule>());
    expect(modules[3], isA<RecognitionModule>());
    expect(modules[4], isA<FeatureWiringModule>());
    expect(modules.map((m) => m.critical), [true, false, false, false, false]);
    expect(modules.map((m) => m.startTimeout), const [
      Duration(seconds: 20),
      Duration(seconds: 10),
      Duration(seconds: 5),
      Duration(seconds: 3),
      Duration(seconds: 1),
    ]);
    expect(modules.map((m) => m.label), [
      '노트 저장소 여는 중',
      'PDF 엔진 준비 중',
      '녹음 준비 중',
      '인식 준비 중',
      '화면 연결 중',
    ]);
    // A fresh list (and fresh modules) per call: a retry never reuses a
    // module that held the previous attempt's store.
    final again = productionModules();
    for (var i = 0; i < modules.length; i++) {
      expect(identical(again[i], modules[i]), isFalse);
    }
  });

  test('the modules together: store published and overridden, PDF '
      'backgrounds, flush on hide, close on shutdown', () async {
    final store = CountingNoteStore();
    addTearDown(store.inner.close);
    final opener = fakeOpenNoteStore(store: store);
    final log = AppErrorLog();
    final bootstrapper = _bootstrapper(_modules(opener), log);

    final success = await bootstrapper.run() as BootstrapSuccess;
    expect(
      success.report.steps.map((s) => s.outcome),
      List.filled(5, StartupStepOutcome.ok),
    );
    expect(success.features, AppFeatures.all);
    expect(success.contributions.map((c) => c.moduleId), [
      'media',
      'recognition',
    ]);
    expect(success.idleTasks.map((t) => t.id), [
      'pdf.searchIndexer',
      'media.leaveGuard',
      'media.recoverDrafts',
      'recognition.indexer',
      'featureWiring.markdownScreen',
    ]);
    expect(success.report.storage, same(store.storageInfo));
    expect(opener.openCount, 1);
    expect(Uri.parse(opener.lastConfig!.web.sqlite3WasmPath).isAbsolute, true);
    expect(log.totalCount, 0);

    final container = ProviderContainer.test(overrides: success.overrides);
    expect(container.read(noteStoreProvider), same(store));
    // Contract v2.2 7.3.3: PdfModule → pdfIoOverrides() = [pdf, image,
    // template].
    expect(container.read(ink.pageBackgroundBuildersProvider), [
      isA<PdfBackgroundLayerBuilder>(),
      isA<ink.ImageBackgroundLayerBuilder>(),
      isA<ink.TemplateBackgroundLayerBuilder>(),
    ]);

    await bootstrapper.notifyAppHidden();
    expect(store.flushCount, 1);
    await bootstrapper.shutdown();
    expect(store.closeCount, 1);
  });

  test('a CORE open failure stops startup before PDF (critical)', () async {
    var pdfStarts = 0;
    final bootstrapper = _bootstrapper([
      CoreModule(
        nativePaths: noNativePaths,
        open: fakeOpenNoteStore(
          error: const NoteStoreOpenException(
            NoteStoreOpenFailure.corrupted,
            'bad page',
          ),
        ).call,
      ),
      PdfModule(initialize: () async => pdfStarts++),
      ...productionModules().skip(2),
    ], AppErrorLog());
    final failure = await bootstrapper.run() as BootstrapFailure;
    expect(failure.moduleId, 'core');
    expect(failure.error, isA<NoteStoreOpenException>());
    expect(failure.resetLocalData, isNotNull);
    expect(pdfStarts, 0);
  });

  group('modulesFor', () {
    const combos = {
      'all on': (
        AppFeatures.all,
        ['core', 'pdf', 'media', 'recognition', 'featureWiring'],
      ),
      'media off': (
        AppFeatures(media: false),
        ['core', 'pdf', 'recognition', 'featureWiring'],
      ),
      'recognition off': (
        AppFeatures(recognition: false),
        ['core', 'pdf', 'media', 'featureWiring'],
      ),
      'all three off': (
        AppFeatures(media: false, recognition: false, mathEngine: false),
        ['core', 'pdf', 'featureWiring'],
      ),
    };
    for (final MapEntry(key: name, value: (features, ids)) in combos.entries) {
      test('$name: ${ids.join(' → ')}', () {
        final modules = modulesFor(features: features);
        expect(modules.map((m) => m.id), ids);
        // FeatureWiringModule is always there (with its default image
        // importer, outside FEATURE_MEDIA — D17).
        expect(modules.last, isA<FeatureWiringModule>());
      });
    }

    test('injected modules are used as given', () {
      final core = CoreModule();
      final pdf = PdfModule();
      final media = MediaModule();
      final recognition = RecognitionModule();
      final wiring = FeatureWiringModule();
      final modules = modulesFor(
        features: AppFeatures.all,
        core: core,
        pdf: pdf,
        media: media,
        recognition: recognition,
        wiring: wiring,
      );
      expect(modules, [
        same(core),
        same(pdf),
        same(media),
        same(recognition),
        same(wiring),
      ]);
      expect(
        modulesFor(features: const AppFeatures(media: false), media: media),
        isNot(contains(same(media))),
      );
    });

    test('media off: image import is still wired by FeatureWiringModule '
        '(default importer = mediaImageImporterOrNull())', () async {
      final store = CountingNoteStore();
      addTearDown(store.inner.close);
      final importer = EditorImageImporter(
        sources: const {ImageImportSource.files},
        pick: (context, source) async => null,
      );
      final modules = modulesFor(
        features: const AppFeatures(media: false, recognition: false),
        core: CoreModule(
          nativePaths: noNativePaths,
          open: fakeOpenNoteStore(store: store).call,
        ),
        pdf: PdfModule(initialize: () async {}),
        wiring: FeatureWiringModule(imageImporter: () => importer),
      );
      final bootstrapper = _bootstrapper(modules, AppErrorLog());
      addTearDown(bootstrapper.shutdown);
      final success = await bootstrapper.run() as BootstrapSuccess;
      expect(success.report.steps.map((s) => s.id), [
        'core',
        'pdf',
        'featureWiring',
      ]);
      final container = ProviderContainer.test(overrides: success.overrides);
      expect(container.read(editorImageImporterProvider), same(importer));
      expect(container.read(editorExtensionsProvider).recordingPanel, isNull);
    });
  });

  testWidgets('BootstrapApp with the default app builder shows the library', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(2064, 2752)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final store = CountingNoteStore();
    final log = AppErrorLog();
    await tester.pumpWidget(
      BootstrapApp(
        createBootstrapper: () =>
            _bootstrapper(_modules(fakeOpenNoteStore(store: store)), log),
        errorLog: log,
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(NoteApp), findsOneWidget);
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.byType(StartupErrorScreen), findsNothing);

    await tester.pumpWidget(const SizedBox());
    // shutdown: status unsubscribed, then close.
    await tester.pump(const Duration(milliseconds: 100));
    expect(store.closeCount, 1);
  });
}
