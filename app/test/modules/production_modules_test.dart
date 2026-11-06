// productionModules() (docs/plans/01-infra.md 4.5.9, 6.4, 9.1; contract
// 7.3.3 order core → pdf → featureWiring), and the modules together through
// AppBootstrapper / BootstrapApp with a fake CORE open.
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
import 'package:noteapp/src/modules/core_module.dart';
import 'package:noteapp/src/modules/feature_wiring_module.dart';
import 'package:noteapp/src/modules/pdf_module.dart';
import 'package:noteapp/src/modules/production_modules.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';
import 'package:pdf_io/pdf_io.dart';

import '../fakes/counting_note_store.dart';
import '../fakes/fake_note_store_opener.dart';
import '../fakes/fake_web_platform.dart';

/// productionModules() with CORE's open replaced (B2 openNoteStore throws)
/// and a no-op PDF initialize; everything else is the production module.
List<AppModule> _modules(FakeNoteStoreOpener opener) {
  final production = productionModules();
  return [
    CoreModule(open: opener.call),
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
  test('ids in contract 7.3.3 order, unique; module types and timeouts', () {
    final modules = productionModules();
    expect(modules.map((m) => m.id), ['core', 'pdf', 'featureWiring']);
    expect(modules.map((m) => m.id).toSet(), hasLength(modules.length));
    expect(modules[0], isA<CoreModule>());
    expect(modules[1], isA<PdfModule>());
    expect(modules[2], isA<FeatureWiringModule>());
    expect(modules.map((m) => m.critical), [true, false, false]);
    expect(modules.map((m) => m.startTimeout), const [
      Duration(seconds: 20),
      Duration(seconds: 10),
      Duration(seconds: 1),
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
    expect(success.report.steps.map((s) => s.outcome), [
      StartupStepOutcome.ok,
      StartupStepOutcome.ok,
      StartupStepOutcome.ok,
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
