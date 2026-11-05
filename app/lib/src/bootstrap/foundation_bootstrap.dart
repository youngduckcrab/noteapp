/// Interim startup modules of the foundation step (docs/plans/01-infra.md
/// 8.1 B8-1), run by AppBootstrapper until I10 brings CoreModule, PdfModule
/// and FeatureWiringModule (productionModules()).
library;

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:note_core/note_core.dart';
import 'package:pdf_io/pdf_io.dart';

import 'app_module.dart';

/// Opens the note store (CORE openNoteStore shape, contract 7.2.12).
typedef FoundationStoreOpener = Future<NoteStore> Function(
  NoteStoreConfig config,
);

/// Starts PDF (pdf_io initializePdfIo shape, contract 7.2.19).
typedef FoundationPdfInitializer = Future<void> Function();

/// The foundation step's start sequence as modules, in contract 7.3.3 order:
///
/// 1. `core` (critical, 20 s): `open(const NoteStoreConfig())`, publishes the
///    NoteStore, overrides noteStoreProvider; flush on hide, close on stop.
/// 2. `pdf` (non-critical, 10 s): `initializePdf()`, then pdfIoOverrides().
///    On failure the PDF overrides are left out (contract 7.3.3: default =
///    template backgrounds only).
/// 3. `featureWiring` (static): the feature packages' own override lists.
///
/// INFRA-3-4: `const NoteStoreConfig()` uses CORE's relative static file
/// paths. That is fine while nothing is deployed; I10's CoreModule passes
/// absolute URLs against document.baseURI (contract 7.2.12 / 7.4.3), logs
/// persistence errors and closes a store that opens after the timeout.
List<AppModule> foundationModules({
  FoundationStoreOpener open = openNoteStore,
  FoundationPdfInitializer initializePdf = initializePdfIo,
}) => [
  _FoundationCoreModule(open),
  _FoundationPdfModule(initializePdf),
  StaticOverridesModule(
    id: 'featureWiring',
    label: '화면 연결하는 중',
    overrides: [...featureLibraryOverrides(), ...featureEditorOverrides()],
  ),
];

final class _FoundationCoreModule extends AppModule {
  _FoundationCoreModule(this._open);

  final FoundationStoreOpener _open;
  NoteStore? _store;

  @override
  String get id => 'core';

  @override
  String get label => '노트 저장소 여는 중';

  @override
  Duration get startTimeout => const Duration(seconds: 20);

  @override
  Future<void> start(AppModuleContext context) async {
    final store = await _open(const NoteStoreConfig());
    _store = store;
    context.publish<NoteStore>(store);
  }

  @override
  List<Override> overrides() => [noteStoreProvider.overrideWithValue(_store!)];

  @override
  Future<void> onAppHidden() async {
    await _store?.flush();
  }

  @override
  Future<void> stop() async {
    final store = _store;
    _store = null;
    await store?.close();
  }
}

final class _FoundationPdfModule extends AppModule {
  _FoundationPdfModule(this._initialize);

  final FoundationPdfInitializer _initialize;

  @override
  String get id => 'pdf';

  @override
  String get label => 'PDF 준비하는 중';

  @override
  bool get critical => false;

  @override
  Future<void> start(AppModuleContext context) => _initialize();

  @override
  List<Override> overrides() => pdfIoOverrides();
}
