/// Static wiring between feature packages (docs/plans/01-infra.md 4.5.9,
/// contract 7.3.3 rows owned by FeatureWiringModule; 2nd round
/// docs/plans/m5-7/01-infra.md 4.6.4, 6.7).
library;

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' show pageThumbnailRendererProvider;
import 'package:pdf_io/pdf_io.dart';

import '../bootstrap/app_module.dart';
import '../errors/app_error_log.dart';
import 'media_wiring.dart';
import 'pdf_module.dart';
import 'pdf_wiring.dart';
import 'search_wiring.dart';

/// Static wiring between feature packages (계약 7.3.3). No async work.
/// PDF-related overrides are added only when the PDF module started; the
/// slots of media and recognition come from the modules' contributions
/// (AppModuleContext.contributions — recorded outcomes only). Image import is
/// wired here directly, outside FEATURE_MEDIA (v2.1, D2-15 / D17).
/// The PDF render stats section takes no injected stats: pdfRenderStatsProvider
/// is read as is (계약 7.6 B4 v1.2 — C12-06; since PDF T8 the renderer's own
/// stats, which need noteStoreProvider — CoreModule starts first).
/// The default arguments are the real pdf_io / media_io functions (계약
/// 7.3.3).
final class FeatureWiringModule extends AppModule {
  FeatureWiringModule({
    this._importPdf = importPdfAsNewNote,
    this._exportPdf = exportNotesAsPdf,
    this._moreMenuActions = pdfEditorMoreMenuActions,
    this._addPageActions = pdfEditorAddPageSources,

    /// (v2.1, D2-15) Image import outside FEATURE_MEDIA: production =
    /// mediaImageImporterOrNull (media_io supportedImageSources +
    /// importImageForNote — works without initializeMediaIo).
    this._imageImporter = mediaImageImporterOrNull,
  });

  static const String moduleId = 'featureWiring';

  final LibraryPdfImportAction _importPdf;
  final LibraryPdfExportAction _exportPdf;
  final List<PdfMenuAction> Function() _moreMenuActions;
  final List<PdfMenuAction> Function() _addPageActions;
  final EditorImageImporter? Function() _imageImporter;

  bool _pdfAvailable = false;
  List<ShellContribution> _contributions = const [];
  EditorImageImporter? _importer;

  @override
  String get id => moduleId;

  @override
  String get label => '화면 연결 중';

  @override
  bool get critical => false;

  @override
  Duration get startTimeout => const Duration(seconds: 1);

  /// pdfAvailable = context.isStarted('pdf'); contributions =
  /// context.contributions; importer = imageImporter() (throw → errorLog,
  /// null).
  @override
  Future<void> start(AppModuleContext context) async {
    _pdfAvailable = context.isStarted(PdfModule.moduleId);
    _contributions = context.contributions;
    try {
      _importer = _imageImporter();
    } on Object catch (error, stackTrace) {
      final record = AppErrorRecord.fromError(
        error,
        stackTrace,
        source: AppErrorSource.module,
      );
      context.errorLog.add(
        AppErrorRecord(
          time: record.time,
          source: record.source,
          summary: record.summary,
          details: 'image importer not available — image insert hidden',
          stackTrace: record.stackTrace,
        ),
      );
      _importer = null;
    }
  }

  /// In this order:
  ///   ...featureEditorOverrides(), ...featureLibraryOverrides(),
  ///   pageThumbnailRendererProvider ← ink (1차),
  ///   if (pdfAvailable) libraryPdfImportActionProvider,
  ///       libraryPdfExportActionProvider (1차),
  ///   if (pdfAvailable or a contribution has editor items)
  ///     editorExtensionsProvider.overrideWithValue(EditorExtensions(
  ///       moreMenuItems: pdf…, addPageSources: pdf…,
  ///       selectionMenuItems: ⋃ c.selectionMenuItems,
  ///       insertMenuItems: ⋃ c.insertMenuItems,
  ///       recordingPanel: the media contribution's panel)),
  ///   if (importer != null) editorImageImporterProvider,
  ///   devOverlaySectionsProvider.overrideWith((ref) => [
  ///       if (pdfAvailable) pdfRenderStatsSection(ref),
  ///       for c in contributions for f in c.devOverlaySections f(ref),
  ///       searchIndexSection(ref)]).
  @override
  List<Override> overrides() {
    final contributions = _contributions;
    final hasEditorItems = contributions.any((c) => c.hasEditorItems);
    return [
      ...featureEditorOverrides(),
      ...featureLibraryOverrides(),
      pageThumbnailRendererProvider.overrideWith(
        (ref) => ref.watch(ink.inkPageThumbnailRendererProvider),
      ),
      if (_pdfAvailable) ...[
        libraryPdfImportActionProvider.overrideWithValue(_importPdf),
        libraryPdfExportActionProvider.overrideWithValue(_exportPdf),
      ],
      if (_pdfAvailable || hasEditorItems)
        editorExtensionsProvider.overrideWithValue(
          _editorExtensions(contributions),
        ),
      if (_importer case final importer?)
        editorImageImporterProvider.overrideWithValue(importer),
      devOverlaySectionsProvider.overrideWith(
        (ref) => [
          if (_pdfAvailable) pdfRenderStatsSection(ref),
          for (final contribution in contributions)
            for (final section in contribution.devOverlaySections) section(ref),
          searchIndexSection(ref),
        ],
      ),
    ];
  }

  EditorExtensions _editorExtensions(List<ShellContribution> contributions) {
    final pdf = _pdfAvailable
        ? editorExtensionsFromPdf(
            moreMenu: _moreMenuActions(),
            addPageSources: _addPageActions(),
          )
        : const EditorExtensions();
    EditorPanelBuilder? recordingPanel;
    for (final contribution in contributions) {
      recordingPanel ??= contribution.recordingPanel;
    }
    return EditorExtensions(
      moreMenuItems: pdf.moreMenuItems,
      addPageSources: pdf.addPageSources,
      selectionMenuItems: List.unmodifiable([
        for (final c in contributions) ...c.selectionMenuItems,
      ]),
      insertMenuItems: List.unmodifiable([
        for (final c in contributions) ...c.insertMenuItems,
      ]),
      recordingPanel: recordingPanel,
    );
  }
}
