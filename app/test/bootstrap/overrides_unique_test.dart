// The root overrides never override one provider twice
// (docs/plans/01-infra.md 6.5, 9.1; contract 7.3.3). Riverpod only asserts
// on duplicates in debug builds, so this test checks Override.origin.
//
// The modules are the three production modules with fakes inside:
// CoreModule with fakeOpenNoteStore, PdfModule with a no-op initialize (the
// real pdfIoOverrides()), FeatureWiringModule with fake PDF actions.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart';
import 'package:noteapp/src/bootstrap/app_bootstrapper.dart';
import 'package:noteapp/src/bootstrap/app_module.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/modules/core_module.dart';
import 'package:noteapp/src/modules/feature_wiring_module.dart';
import 'package:noteapp/src/modules/pdf_module.dart';
import 'package:noteapp/src/providers.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';
import 'package:pdf_io/pdf_io.dart';

import '../fakes/counting_note_store.dart';
import '../fakes/fake_note_store_opener.dart';
import '../fakes/fake_pdf_actions.dart';
import '../fakes/fake_web_platform.dart';

/// The production modules with fakes inside.
List<AppModule> _modules(NoteStore store) {
  final pdf = FakePdfActions();
  return [
    CoreModule(open: fakeOpenNoteStore(store: store).call),
    PdfModule(initialize: () async {}),
    FeatureWiringModule(
      importPdf: pdf.importPdf,
      exportPdf: pdf.exportPdf,
      moreMenuActions: pdf.moreMenuActions,
      addPageActions: pdf.addPageActions,
    ),
  ];
}

Future<BootstrapSuccess> _boot(List<AppModule> modules) async {
  final web = FakeWebPlatform();
  final bootstrapper = AppBootstrapper(
    modules: modules,
    buildInfo: BuildInfo.local,
    runtimeInfo: RuntimeInfo.detect(web),
    web: web,
    errorLog: AppErrorLog(),
    ownerId: kLocalOwnerId,
  );
  addTearDown(bootstrapper.shutdown);
  return await bootstrapper.run() as BootstrapSuccess;
}

/// The overridden providers / families that appear more than once.
List<Object> _duplicateOrigins(List<Override> overrides) {
  final seen = <Object>{};
  return [
    // Override.origin is @visibleForTesting: tests only, never in lib/.
    for (final origin in overrides.map((o) => o.origin))
      if (!seen.add(origin)) origin,
  ];
}

void main() {
  test(
    'shell + module overrides: every Override.origin is different',
    () async {
      final store = CountingNoteStore();
      final success = await _boot(_modules(store));
      expect(success.report.steps, hasLength(3));
      expect(success.overrides, isNotEmpty);
      expect(_duplicateOrigins(success.overrides), isEmpty);
      // Exactly the contract 7.3.3 rows of this scope (+ the shell
      // providers and the feature packages' own lists).
      expect(success.overrides.map((o) => o.origin).toSet(), {
        buildInfoProvider,
        webPlatformProvider,
        runtimeInfoProvider,
        appErrorLogProvider,
        startupReportProvider,
        appBootstrapperProvider,
        noteStoreProvider,
        ink.pageBackgroundBuildersProvider,
        pdfIoConfigProvider,
        pageThumbnailRendererProvider,
        libraryPdfImportActionProvider,
        libraryPdfExportActionProvider,
        editorExtensionsProvider,
        devOverlaySectionsProvider,
        for (final o in [
          ...featureEditorOverrides(),
          ...featureLibraryOverrides(),
        ])
          o.origin,
      });
      // And Riverpod accepts the list (no "overridden twice" assertion).
      final container = ProviderContainer.test(overrides: success.overrides);
      expect(container.read(noteStoreProvider), same(store));
    },
  );

  test('the check catches one provider overridden by two modules', () async {
    final store = CountingNoteStore();
    final success = await _boot([
      ..._modules(store),
      StaticOverridesModule(
        id: 'duplicate',
        label: '중복',
        overrides: [noteStoreProvider.overrideWithValue(store)],
      ),
    ]);
    expect(_duplicateOrigins(success.overrides), [same(noteStoreProvider)]);
    expect(
      () => ProviderContainer.test(overrides: success.overrides),
      throwsA(isA<AssertionError>()),
    );
  });
}
