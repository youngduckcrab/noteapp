// The fakes of the 2nd round app smokes (V5 v2, V6 v2, V15 —
// docs/plans/m5-7/01-infra.md 8.2 J19, 9.1 '앱 스모크 v2 단계'; contract
// 7.3.3 '시험 이음새'): they go in ONLY through the modules' injection
// arguments, never as test overrides, so the origin and count of each
// override is the real module path (Riverpod refuses a provider overridden
// twice):
//
//   MediaModule(initialize: no-op, mediaOverrides: FakeAudioRecorder ·
//       FakeAudioPlayback),
//   RecognitionModule(overridesFor: [FakeHandwritingRecognizer,
//       FakeMathRecognizer, GeometricShapeFitter()] — the provider set of
//       the real recognitionOverrides(); H2 compares the sets),
//   FeatureWiringModule(imageImporter: one fake photo).
//
// CoreModule, PdfModule and everything else are the production modules
// with production arguments. Also here: the 7.3.3 check of a v2 start
// (expectContractOverridesV2) and the V15 rows (featureRows) — the values
// that tell a switched-off feature from an on one, read from the root
// container.
//
// Web-safe: no dart:io, no package:web.
library;

import 'dart:typed_data';

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
import 'package:feature_markdown/slots.dart' show markdownExportActionProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/testing.dart';
import 'package:media_io/media_io.dart' show MediaIoConfig;
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:noteapp/src/app/appearance.dart';
import 'package:noteapp/src/bootstrap/app_module.dart';
import 'package:noteapp/src/bootstrap/startup_report.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/features/app_features.dart';
import 'package:noteapp/src/modules/core_module.dart';
import 'package:noteapp/src/modules/feature_wiring_module.dart';
import 'package:noteapp/src/modules/media_module.dart';
import 'package:noteapp/src/modules/media_wiring.dart';
import 'package:noteapp/src/modules/pdf_module.dart';
import 'package:noteapp/src/modules/production_modules.dart';
import 'package:noteapp/src/modules/recognition_module.dart';
import 'package:noteapp/src/providers.dart';
import 'package:noteapp/src/settings/settings_sections.dart';
import 'package:pdf_io/pdf_io.dart';

import 'smoke_scenario.dart';

/// A 1 × 1 PNG (opaque white): the photo the fake image picker returns.
final Uint8List kSmokePhotoPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xde, 0x00, 0x00, 0x00,
  0x0c, 0x49, 0x44, 0x41, 0x54, 0x08, 0xd7, 0x63, 0xf8, 0xff, 0xff, 0x3f,
  0x00, 0x05, 0xfe, 0x02, 0xfe, 0xa7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

/// The math engine address the smokes give RecognitionModule (an injection
/// argument like the fakes — production reads MATH_ENDPOINT, empty in the
/// test build). Never called: the math recognizer is [SmokeV2Fakes.math].
const String kSmokeMathEndpoint = 'https://math.invalid/recognize';

/// The fakes of one smoke run and the modules that carry them.
final class SmokeV2Fakes {
  SmokeV2Fakes();

  final FakeAudioPlayback playback = FakeAudioPlayback();
  final FakeHandwritingRecognizer handwriting = FakeHandwritingRecognizer();
  final FakeMathRecognizer math = FakeMathRecognizer();

  /// The recorder, once audioRecorderServiceProvider was read (it needs the
  /// store CoreModule opened). H3 drives it (advance / stop).
  FakeAudioRecorder? get recorder => _recorder;
  FakeAudioRecorder? _recorder;

  /// The image sources the fake picker offers (slot 1 — insert menu and the
  /// add page sheet's image page).
  static const Set<ImageImportSource> imageSources = {
    ImageImportSource.photos,
    ImageImportSource.camera,
    ImageImportSource.files,
  };

  /// Every source the fake picker was asked for, in order.
  final List<ImageImportSource> picks = [];

  /// Calls of MediaModule's initialize (no-op).
  int mediaInitializeCalls = 0;

  /// The configs RecognitionModule handed to overridesFor.
  final List<RecognitionConfig> recognitionConfigs = [];

  /// The modules made by [modules] (null when switched off there).
  MediaModule? mediaModule;
  RecognitionModule? recognitionModule;

  /// Slot 1: one photo, put into the app's asset store.
  late final EditorImageImporter importer = EditorImageImporter(
    sources: imageSources,
    pick: (context, source) async {
      picks.add(source);
      final store = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(noteStoreProvider);
      final asset = await store.assets.put(
        kSmokePhotoPng,
        type: AssetType.image,
        mimeType: 'image/png',
        fileName: 'smoke-photo.png',
      );
      return ImportedImage(asset: asset, pixelWidth: 1, pixelHeight: 1);
    },
  );

  MediaModule media() => mediaModule = MediaModule(
    initialize: ({MediaIoConfig config = const MediaIoConfig()}) async {
      mediaInitializeCalls++;
    },
    mediaOverrides: ({MediaIoConfig? config}) => [
      audioRecorderServiceProvider.overrideWith(
        (ref) =>
            _recorder = FakeAudioRecorder(store: ref.watch(noteStoreProvider)),
      ),
      audioPlaybackServiceProvider.overrideWithValue(playback),
    ],
  );

  RecognitionModule recognition() => recognitionModule = RecognitionModule(
    overridesFor: ({RecognitionConfig config = const RecognitionConfig()}) {
      recognitionConfigs.add(config);
      return [
        handwritingRecognizerProvider.overrideWithValue(handwriting),
        mathRecognizerProvider.overrideWithValue(math),
        ink.inkShapeFitterProvider.overrideWithValue(
          const GeometricShapeFitter(),
        ),
      ];
    },
    mathEndpoint: kSmokeMathEndpoint,
  );

  /// The real PDF actions; only the image importer is fake.
  FeatureWiringModule wiring() =>
      FeatureWiringModule(imageImporter: () => importer);

  /// The production sequence (modulesFor — a module whose feature is off in
  /// [features] is not even made) with [core] and the fakes above.
  List<AppModule> modules(
    CoreModule core, {
    AppFeatures features = AppFeatures.all,
  }) {
    mediaModule = null;
    recognitionModule = null;
    return modulesFor(
      features: features,
      core: core,
      media: features.media ? media() : null,
      recognition: features.recognition ? recognition() : null,
      wiring: wiring(),
    );
  }
}

/// Boots the v2 module list of [fakes] over [core] with [features] as the
/// build's switches (AppBootstrapper.features — the --dart-define values of
/// a production build) until the library shows.
Future<SmokeApp> bootSmokeV2App(
  WidgetTester tester,
  SmokeV2Fakes fakes,
  CoreModule core, {
  AppFeatures features = AppFeatures.all,
}) => bootSmokeAppWith(
  tester,
  modules: fakes.modules(core, features: features),
  features: features,
);

/// The editor menu ids the real recognition actions give (slots 3 · 4):
/// whatever ink_recognition's recognitionSelectionActions() /
/// recognitionInsertActions() return — recog.toText, recog.copyText,
/// recog.toMath, recog.editMath / recog.mathPad (H3 expects them
/// non-empty).
List<String> realRecognitionSelectionIds() => [
  for (final a in recognitionSelectionActions()) a.id,
];
List<String> realRecognitionInsertIds() => [
  for (final a in recognitionInsertActions()) a.id,
];

/// Step 1 of the v2 smoke (contract 7.3.3 v2, V5 v2.1): every module of the
/// start ok (the switched-off ones are not in the list); the root overrides
/// are exactly the 7.3.3 rows of the modules that started + the shell rows +
/// the packages' own lists, each provider once; the audio rows come only
/// from MediaModule and the recognition rows only from RecognitionModule;
/// and each value is the real implementation (or the injected fake).
void expectContractOverridesV2(
  SmokeApp app,
  SmokeV2Fakes fakes, {
  AppFeatures features = AppFeatures.all,
}) {
  expect(app.success.features, features);
  // overrides() asks overridesFor each time: the start asked once (read
  // before the origin checks below ask again).
  final configs = [...fakes.recognitionConfigs];
  expect(configs, hasLength(features.recognition ? 1 : 0));
  if (features.recognition) {
    expect(
      configs.single.mathEndpoint,
      features.isOn(AppFeature.mathEngine)
          ? Uri.parse(kSmokeMathEndpoint)
          : isNull,
    );
  }
  expect(
    {for (final s in app.success.report.steps) s.id: s.outcome},
    {
      CoreModule.moduleId: StartupStepOutcome.ok,
      PdfModule.moduleId: StartupStepOutcome.ok,
      if (features.media) MediaModule.moduleId: StartupStepOutcome.ok,
      if (features.recognition)
        RecognitionModule.moduleId: StartupStepOutcome.ok,
      FeatureWiringModule.moduleId: StartupStepOutcome.ok,
    },
    reason: '${app.errorLog}',
  );
  expect(
    [for (final m in app.success.startedModules) m.id],
    [
      CoreModule.moduleId,
      PdfModule.moduleId,
      if (features.media) MediaModule.moduleId,
      if (features.recognition) RecognitionModule.moduleId,
      FeatureWiringModule.moduleId,
    ],
  );

  final audio = <Object>{
    audioRecorderServiceProvider,
    audioPlaybackServiceProvider,
  };
  final recognition = <Object>{
    handwritingRecognizerProvider,
    mathRecognizerProvider,
    ink.inkShapeFitterProvider,
  };
  final origins = [for (final o in app.success.overrides) o.origin];
  expect(origins.toSet(), hasLength(origins.length), reason: 'duplicates');
  expect(origins.toSet(), <Object>{
    // 7.3.3 rows (1차 + 2차).
    noteStoreProvider, // CoreModule
    ink.pageBackgroundBuildersProvider, // PdfModule → pdfIoOverrides()
    pdfIoConfigProvider,
    if (features.media) ...audio, // MediaModule → mediaIoOverrides()
    if (features.recognition) ...recognition, // → recognitionOverrides()
    pageThumbnailRendererProvider, // FeatureWiringModule
    libraryPdfImportActionProvider,
    libraryPdfExportActionProvider,
    // (v2.17-md) the MD 문서 slots.
    libraryMarkdownImportActionProvider,
    libraryMarkdownExportActionProvider,
    markdownExportActionProvider,
    editorExtensionsProvider,
    editorImageImporterProvider,
    devOverlaySectionsProvider,
    // No stylusExtrasProvider: no Apple Pencil bridge in this runtime.
    // Shell rows (01-infra 6.4; m5-7/01-infra 4.6.1 · 4.6.7).
    buildInfoProvider,
    webPlatformProvider,
    runtimeInfoProvider,
    appErrorLogProvider,
    startupReportProvider,
    appBootstrapperProvider,
    appFeaturesProvider,
    initialAppearanceProvider, // (v2.14-ui review)
    shellContributionsProvider,
    // The packages' own lists, added by FeatureWiringModule (4.5.9).
    for (final o in featureEditorOverrides()) o.origin,
    for (final o in featureLibraryOverrides()) o.origin,
  });

  // Where the rows come from: the started modules' own overrides().
  Set<Object> originsOf<T extends AppModule>() => {
    for (final m in app.success.startedModules.whereType<T>())
      for (final o in m.overrides()) o.origin,
  };
  final fromOthers = <Object>{
    for (final m in app.success.startedModules)
      if (m is! MediaModule && m is! RecognitionModule)
        for (final o in m.overrides()) o.origin,
  };
  expect(originsOf<MediaModule>(), features.media ? audio : isEmpty);
  expect(
    originsOf<RecognitionModule>(),
    features.recognition ? recognition : isEmpty,
  );
  expect(fromOthers.intersection({...audio, ...recognition}), isEmpty);

  final c = app.container;
  expect(c.read(ink.pageBackgroundBuildersProvider), [
    isA<PdfBackgroundLayerBuilder>(),
    isA<ink.ImageBackgroundLayerBuilder>(),
    isA<ink.TemplateBackgroundLayerBuilder>(),
  ]);
  expect(
    identical(c.read(libraryPdfImportActionProvider), importPdfAsNewNote),
    isTrue,
  );
  expect(
    identical(c.read(libraryPdfExportActionProvider), exportNotesAsPdf),
    isTrue,
  );
  if (features.media) {
    expect(fakes.mediaInitializeCalls, 1);
    expect(c.read(audioRecorderServiceProvider), same(fakes.recorder));
    expect(c.read(audioPlaybackServiceProvider), same(fakes.playback));
  }
  if (features.recognition) {
    expect(c.read(handwritingRecognizerProvider), same(fakes.handwriting));
    expect(c.read(mathRecognizerProvider), same(fakes.math));
    expect(c.read(ink.inkShapeFitterProvider), isA<GeometricShapeFitter>());
  }
}

/// The values V15 compares (m5-7/01-infra 6.6 table, 9.1
/// feature_switch_test; contract V15 v2.1): one row per thing a switch may
/// take away, each a plain string read from the root container. Provider
/// values, not widgets: the editor's mic button, menus and correction
/// toggle follow these providers (04-editor — recordingPanel null → no mic
/// button; inkShapeFitterProvider NoShapeFitter → no toggle) and are
/// compared on the screens in H5.
Map<String, String> featureRows(SmokeApp app, SmokeV2Fakes fakes) {
  final c = app.container;
  final extensions = c.read(editorExtensionsProvider);
  final sections = [for (final s in c.read(devOverlaySectionsProvider)) s.id];
  final settings = [for (final s in c.read(settingsSectionsProvider)) s.id];
  final idle = {for (final t in app.success.idleTasks) t.id};
  final importer = c.read(editorImageImporterProvider);
  String yes(bool value) => value ? 'yes' : 'no';
  String names(Iterable<Enum> values) =>
      ([for (final v in values) v.name]..sort()).join(',');
  final recognition = fakes.recognitionModule;
  return {
    // FEATURE_MEDIA: recording only (D17).
    '녹음':
        'panel ${yes(identical(extensions.recordingPanel, mediaRecordingPanel))}'
        ' · recorder ${c.read(audioRecorderServiceProvider).runtimeType}'
        ' · section ${yes(sections.contains('media'))}'
        ' · drafts ${yes(idle.contains('media.recoverDrafts'))}'
        ' · leave guard ${yes(idle.contains('media.leaveGuard'))}',
    // FEATURE_RECOGNITION: menus, settings, indexer, handwriting engine.
    '인식 메뉴':
        'selection [${[for (final i in extensions.selectionMenuItems) i.id].join(',')}]'
        ' · insert [${[for (final i in extensions.insertMenuItems) i.id].join(',')}]'
        ' · settings ${yes(settings.contains('recog.settings'))}'
        ' · section ${yes(sections.contains('recog.indexer'))}'
        ' · indexer ${yes(idle.contains('recognition.indexer'))}'
        ' · handwriting ${c.read(handwritingRecognizerProvider).runtimeType}',
    // FEATURE_MATH_ENGINE (counts only with recognition).
    '수식 엔진':
        'endpoint ${recognition?.config.mathEndpoint ?? 'none'}'
        ' · recognizer ${c.read(mathRecognizerProvider).runtimeType}'
        ' · feature ${yes(app.success.features.isOn(AppFeature.mathEngine))}',
    // FEATURE_RECOGNITION also takes the shape fitter (X31).
    '자동 도형 보정': '${c.read(ink.inkShapeFitterProvider).runtimeType}',
    // Never taken (D17): image insert and image page share the importer.
    '이미지 삽입': importer == null
        ? 'none'
        : 'sources ${names(importer.sources)} · '
              'fake ${yes(identical(importer, fakes.importer))}',
    '이미지 페이지':
        'importer ${yes(importer != null)}'
        ' · add page [${[for (final i in extensions.addPageSources) i.id].join(',')}]',
  };
}

/// The rows a start with [features] must show (the V15 sentence: media →
/// 녹음; recognition → 인식 메뉴, 수식 엔진, 자동 도형 보정; mathEngine → 수식
/// 엔진; the two image rows never change).
Map<String, String> expectedFeatureRows(AppFeatures features) {
  String yes(bool value) => value ? 'yes' : 'no';
  final media = features.media;
  final recognition = features.recognition;
  final math = features.isOn(AppFeature.mathEngine);
  return {
    '녹음':
        'panel ${yes(media)}'
        ' · recorder ${media ? 'FakeAudioRecorder' : 'UnsupportedAudioRecorder'}'
        ' · section ${yes(media)}'
        ' · drafts ${yes(media)}'
        ' · leave guard ${yes(media)}',
    '인식 메뉴':
        'selection [${recognition ? realRecognitionSelectionIds().join(',') : ''}]'
        ' · insert [${recognition ? realRecognitionInsertIds().join(',') : ''}]'
        ' · settings ${yes(recognition)}'
        ' · section ${yes(recognition)}'
        ' · indexer ${yes(recognition)}'
        ' · handwriting ${recognition ? 'FakeHandwritingRecognizer' : 'UnsupportedHandwritingRecognizer'}',
    '수식 엔진':
        'endpoint ${math ? kSmokeMathEndpoint : 'none'}'
        ' · recognizer ${recognition ? 'FakeMathRecognizer' : 'ManualOnlyMathRecognizer'}'
        ' · feature ${yes(math)}',
    '자동 도형 보정': recognition ? 'GeometricShapeFitter' : 'NoShapeFitter',
    '이미지 삽입': 'sources camera,files,photos · fake yes',
    '이미지 페이지':
        'importer yes · add page [${[for (final a in pdfEditorAddPageSources()) a.id].join(',')}]',
  };
}

/// The rows where [a] and [b] differ.
Set<String> differingRows(Map<String, String> a, Map<String, String> b) => {
  for (final key in {...a.keys, ...b.keys})
    if (a[key] != b[key]) key,
};

/// No record of the run mentions a missing plugin (V6 v2 — the web runtime
/// calls no native-only plugin).
void expectNoMissingPlugin(AppErrorLog log) {
  for (final record in log.records) {
    expect(
      '${record.summary} ${record.details ?? ''}',
      isNot(contains('MissingPluginException')),
    );
  }
}
