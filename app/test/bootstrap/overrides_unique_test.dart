// The root overrides never override one provider twice
// (docs/plans/01-infra.md 6.5, 9.1; contract 7.3.3; 2nd round
// docs/plans/m5-7/01-infra.md 6.7 '중복 없음 시험' v2, S2-2). Riverpod only
// asserts on duplicates in debug builds, so this test checks Override.origin.
//
// The modules are the five production modules with fakes inside — given
// through the module constructors' injection arguments, never as test
// overrides (6.7 '시험 이음새'): CoreModule with fakeOpenNoteStore,
// PdfModule with a no-op initialize (the real pdfIoOverrides()), MediaModule
// whose mediaOverrides gives CORE's FakeAudioRecorder / FakeAudioPlayback,
// RecognitionModule whose overridesFor gives the three recognition rows,
// FeatureWiringModule with fake PDF actions and an image importer (and, in
// the iPad case, a FakePencilPort — R2-B8b).
// Table-driven: each scenario lists which contract 7.3.3 rows it expects.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_recognition/ink_recognition.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_io/media_io.dart' show MediaIoConfig;
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:noteapp/src/bootstrap/app_bootstrapper.dart';
import 'package:noteapp/src/bootstrap/app_module.dart';
import 'package:noteapp/src/bootstrap/startup_report.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/features/app_features.dart';
import 'package:noteapp/src/modules/core_module.dart';
import 'package:noteapp/src/modules/feature_wiring_module.dart';
import 'package:noteapp/src/modules/media_module.dart';
import 'package:noteapp/src/modules/pdf_module.dart';
import 'package:noteapp/src/modules/pencil_wiring.dart';
import 'package:noteapp/src/modules/production_modules.dart';
import 'package:noteapp/src/modules/recognition_module.dart';
import 'package:noteapp/src/providers.dart';
import 'package:noteapp/src/runtime/build_info.dart';
import 'package:noteapp/src/runtime/runtime_info.dart';
import 'package:noteapp/src/settings/settings_sections.dart';
import 'package:pdf_io/pdf_io.dart';

import '../fakes/counting_note_store.dart';
import '../fakes/fake_native_paths.dart';
import '../fakes/fake_note_store_opener.dart';
import '../fakes/fake_pdf_actions.dart';
import '../fakes/fake_pencil_port.dart';
import '../fakes/fake_web_platform.dart';

/// Which non-critical module fails in a scenario.
enum _Fail { none, pdf, media, recognition, featureWiring }

final _importer = EditorImageImporter(
  sources: const {ImageImportSource.files},
  pick: (context, source) async => null,
);

/// The five production modules with fakes inside (or the three left when
/// [features] switches media and recognition off — modulesFor).
List<AppModule> _modules(
  NoteStore store, {
  _Fail fail = _Fail.none,
  AppFeatures features = AppFeatures.all,
  PencilPort pencil = const PencilPort(),
}) {
  final pdf = FakePdfActions();
  Never boom(String what) => throw StateError('$what down');
  return modulesFor(
    features: features,
    core: CoreModule(
      nativePaths: noNativePaths,
      open: fakeOpenNoteStore(store: store).call,
    ),
    pdf: PdfModule(
      initialize: () async {
        if (fail == _Fail.pdf) boom('pdf');
      },
    ),
    media: MediaModule(
      initialize: ({MediaIoConfig config = const MediaIoConfig()}) async {
        if (fail == _Fail.media) boom('media');
      },
      mediaOverrides: ({MediaIoConfig? config}) => [
        audioRecorderServiceProvider.overrideWithValue(
          FakeAudioRecorder(store: store),
        ),
        audioPlaybackServiceProvider.overrideWithValue(FakeAudioPlayback()),
      ],
    ),
    recognition: RecognitionModule(
      overridesFor: ({RecognitionConfig config = const RecognitionConfig()}) {
        if (fail == _Fail.recognition) boom('recognition');
        return [
          handwritingRecognizerProvider.overrideWithValue(
            const UnsupportedHandwritingRecognizer(),
          ),
          mathRecognizerProvider.overrideWithValue(
            const ManualOnlyMathRecognizer(),
          ),
          ink.inkShapeFitterProvider.overrideWithValue(
            const ink.NoShapeFitter(),
          ),
        ];
      },
      selectionActions: () => [
        RecognitionAction(
          id: 'recog.toText',
          label: '텍스트로',
          icon: Icons.text_fields,
          run: (context, target) async {},
        ),
      ],
    ),
    wiring: FeatureWiringModule(
      importPdf: pdf.importPdf,
      exportPdf: pdf.exportPdf,
      // overrides() reads the PDF menus: a throw there fails the module.
      moreMenuActions: () =>
          fail == _Fail.featureWiring ? boom('wiring') : pdf.moreMenuActions(),
      addPageActions: pdf.addPageActions,
      pencil: pencil,
      imageImporter: () => _importer,
    ),
  );
}

Future<BootstrapSuccess> _boot(
  List<AppModule> modules, {
  AppFeatures features = AppFeatures.all,
}) async {
  final web = FakeWebPlatform();
  final bootstrapper = AppBootstrapper(
    modules: modules,
    buildInfo: BuildInfo.local,
    runtimeInfo: RuntimeInfo.detect(web),
    web: web,
    errorLog: AppErrorLog(),
    ownerId: kLocalOwnerId,
    features: features,
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

/// Contract 7.3.3 rows (+ the shell providers and the feature packages' own
/// lists) a scenario expects — each exactly once.
Set<Object> _expected({
  required bool pdf,
  required bool media,
  required bool recognition,
  required bool wiring,
  required bool editorExtensions,
  bool pencil = false,
}) => {
  buildInfoProvider,
  webPlatformProvider,
  runtimeInfoProvider,
  appErrorLogProvider,
  startupReportProvider,
  appBootstrapperProvider,
  appFeaturesProvider,
  shellContributionsProvider,
  noteStoreProvider,
  if (pdf) ...{
    ink.pageBackgroundBuildersProvider,
    pdfIoConfigProvider,
    pdfShareFilesProvider,
  },
  if (media) ...{audioRecorderServiceProvider, audioPlaybackServiceProvider},
  if (recognition) ...{
    handwritingRecognizerProvider,
    mathRecognizerProvider,
    ink.inkShapeFitterProvider,
  },
  if (wiring) ...{
    for (final o in [...featureEditorOverrides(), ...featureLibraryOverrides()])
      o.origin,
    pageThumbnailRendererProvider,
    if (pdf) ...{
      libraryPdfImportActionProvider,
      libraryPdfExportActionProvider,
    },
    // (handwriting search) the recognition contribution's library slot.
    if (recognition) libraryInkSearchProvider,
    // (v2.13-search) … and the editor's in-note search slot.
    if (recognition) editorInkSearchProvider,
    if (editorExtensions) editorExtensionsProvider,
    // Image import: outside FEATURE_MEDIA — in every scenario (D2-15).
    editorImageImporterProvider,
    devOverlaySectionsProvider,
    // iOS only (R2-B8b): the pencil adapter.
    if (pencil) stylusExtrasProvider,
  },
};

void main() {
  final scenarios = <String, (_Fail, AppFeatures, Set<Object>)>{
    'all five started': (
      _Fail.none,
      AppFeatures.all,
      _expected(
        pdf: true,
        media: true,
        recognition: true,
        wiring: true,
        editorExtensions: true,
      ),
    ),
    'pdf failed': (
      _Fail.pdf,
      AppFeatures.all,
      _expected(
        pdf: false,
        media: true,
        recognition: true,
        wiring: true,
        editorExtensions: true,
      ),
    ),
    'media failed (fallback panel keeps the editor extensions)': (
      _Fail.media,
      AppFeatures.all,
      _expected(
        pdf: true,
        media: false,
        recognition: true,
        wiring: true,
        editorExtensions: true,
      ),
    ),
    'recognition failed': (
      _Fail.recognition,
      AppFeatures.all,
      _expected(
        pdf: true,
        media: true,
        recognition: false,
        wiring: true,
        editorExtensions: true,
      ),
    ),
    'featureWiring failed': (
      _Fail.featureWiring,
      AppFeatures.all,
      _expected(
        pdf: true,
        media: true,
        recognition: true,
        wiring: false,
        editorExtensions: false,
      ),
    ),
    'three features off (modulesFor)': (
      _Fail.none,
      const AppFeatures(media: false, recognition: false, mathEngine: false),
      _expected(
        pdf: true,
        media: false,
        recognition: false,
        wiring: true,
        editorExtensions: true,
      ),
    ),
  };

  for (final MapEntry(key: name, value: (fail, features, expected))
      in scenarios.entries) {
    test('$name: every Override.origin is different and the expected 7.3.3 '
        'rows appear exactly once', () async {
      final store = CountingNoteStore();
      addTearDown(store.inner.close);
      final success = await _boot(
        _modules(store, fail: fail, features: features),
        features: features,
      );
      expect(_duplicateOrigins(success.overrides), isEmpty);
      expect(success.overrides.map((o) => o.origin).toSet(), expected);
      // And Riverpod accepts the list (no "overridden twice" assertion).
      final container = ProviderContainer.test(overrides: success.overrides);
      expect(container.read(noteStoreProvider), same(store));
      if (expected.contains(editorImageImporterProvider)) {
        expect(container.read(editorImageImporterProvider), same(_importer));
      }
    });
  }

  test('iPad (pencil supported): stylusExtrasProvider appears exactly once, '
      'next to every other row', () async {
    final store = CountingNoteStore();
    addTearDown(store.inner.close);
    final success = await _boot(_modules(store, pencil: FakePencilPort()));
    expect(_duplicateOrigins(success.overrides), isEmpty);
    expect(
      success.overrides.map((o) => o.origin).toSet(),
      _expected(
        pdf: true,
        media: true,
        recognition: true,
        wiring: true,
        editorExtensions: true,
        pencil: true,
      ),
    );
    final container = ProviderContainer.test(overrides: success.overrides);
    expect(container.read(stylusExtrasProvider).isSupported, isTrue);
  });

  test(
    'the outcomes of the failure scenarios are what the table assumes',
    () async {
      for (final fail in _Fail.values.skip(1)) {
        final store = CountingNoteStore();
        addTearDown(store.inner.close);
        final success = await _boot(_modules(store, fail: fail));
        expect(
          success.report.steps
              .where((s) => s.outcome != StartupStepOutcome.ok)
              .map((s) => (s.id, s.outcome)),
          [(fail.name, StartupStepOutcome.failedNonCritical)],
          reason: fail.name,
        );
      }
    },
  );

  test('the check catches one provider overridden by two modules', () async {
    final store = CountingNoteStore();
    addTearDown(store.inner.close);
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
