// The interim modules of the foundation step (foundationModules()), run by
// AppBootstrapper / BootstrapApp until I10 brings productionModules()
// (docs/plans/01-infra.md 8.1 B8-1, 8.2 I5).
import 'package:feature_library/feature_library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/app/foundation_app.dart';
import 'package:noteapp/src/bootstrap/app_bootstrapper.dart';
import 'package:noteapp/src/bootstrap/app_module.dart';
import 'package:noteapp/src/bootstrap/bootstrap_app.dart';
import 'package:noteapp/src/bootstrap/foundation_bootstrap.dart';
import 'package:noteapp/src/bootstrap/startup_error_screen.dart';
import 'package:noteapp/src/bootstrap/startup_report.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';
import 'package:pdf_io/pdf_io.dart';

import '../fakes/counting_note_store.dart';
import '../fakes/fake_web_platform.dart';

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
  test('ids, order, criticality and timeouts (contract 7.3.3 order)', () {
    final modules = foundationModules();
    expect(modules.map((m) => m.id), ['core', 'pdf', 'featureWiring']);
    expect(modules.map((m) => m.critical), [true, false, true]);
    expect(modules.map((m) => m.startTimeout), const [
      Duration(seconds: 20),
      Duration(seconds: 10),
      Duration(seconds: 1),
    ]);
  });

  test('core opens CORE’s default config and overrides noteStoreProvider; '
      'pdf adds pdfIoOverrides()', () async {
    final store = CountingNoteStore();
    addTearDown(store.inner.close);
    final configs = <NoteStoreConfig>[];
    var pdfStarts = 0;
    final log = AppErrorLog();
    final bootstrapper = _bootstrapper(
      foundationModules(
        open: (config) async {
          configs.add(config);
          return store;
        },
        initializePdf: () async => pdfStarts++,
      ),
      log,
    );

    final success = await bootstrapper.run() as BootstrapSuccess;
    // INFRA-3-4: the interim core module opens CORE's default config.
    expect(configs, [same(const NoteStoreConfig())]);
    expect(pdfStarts, 1);
    expect(success.report.storage, same(store.storageInfo));
    expect(log.totalCount, 0);

    final container = ProviderContainer.test(overrides: success.overrides);
    expect(container.read(noteStoreProvider), same(store));
    final builders = container.read(ink.pageBackgroundBuildersProvider);
    expect(builders, hasLength(2));
    expect(builders.first, isA<PdfBackgroundLayerBuilder>());
    expect(builders.last, isA<ink.TemplateBackgroundLayerBuilder>());

    await bootstrapper.notifyAppHidden();
    expect(store.flushCount, 1);
    await bootstrapper.shutdown();
    expect(store.closeCount, 1);
  });

  test(
    'a failed PDF start leaves the PDF overrides out and is logged',
    () async {
      final store = CountingNoteStore();
      addTearDown(store.inner.close);
      final log = AppErrorLog();
      final bootstrapper = _bootstrapper(
        foundationModules(
          open: (_) async => store,
          initializePdf: () async => throw StateError('pdf start failed'),
        ),
        log,
      );

      final success = await bootstrapper.run() as BootstrapSuccess;
      expect(
        success.report.steps[1].outcome,
        StartupStepOutcome.failedNonCritical,
      );
      expect(log.records.single.summary, contains('pdf start failed'));
      final container = ProviderContainer.test(overrides: success.overrides);
      expect(container.read(ink.pageBackgroundBuildersProvider), [
        isA<ink.TemplateBackgroundLayerBuilder>(),
      ]);
      await bootstrapper.shutdown();
    },
  );

  test(
    'a failed open (B2 UnimplementedError) fails startup before PDF',
    () async {
      var pdfStarts = 0;
      final bootstrapper = _bootstrapper(
        foundationModules(
          open: (_) async => throw UnimplementedError('CORE T6'),
          initializePdf: () async => pdfStarts++,
        ),
        AppErrorLog(),
      );
      final failure = await bootstrapper.run() as BootstrapFailure;
      expect(failure.moduleId, 'core');
      expect(failure.error, isA<UnimplementedError>());
      expect(failure.resetLocalData, isNull);
      expect(pdfStarts, 0);
    },
  );

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
        createBootstrapper: () => _bootstrapper(
          foundationModules(
            open: (_) async => store,
            initializePdf: () async {},
          ),
          log,
        ),
        errorLog: log,
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(FoundationApp), findsOneWidget);
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.byType(StartupErrorScreen), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(store.closeCount, 1);
  });
}
