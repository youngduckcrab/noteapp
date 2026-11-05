/// Static wiring between feature packages (docs/plans/01-infra.md 4.5.9,
/// contract 7.3.3 rows owned by FeatureWiringModule).
library;

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' show pageThumbnailRendererProvider;
import 'package:pdf_io/pdf_io.dart';

import '../bootstrap/app_module.dart';
import 'pdf_module.dart';
import 'pdf_wiring.dart';

/// Static wiring between feature packages (계약 7.3.3). No async work.
/// PDF-related overrides are added only when the PDF module started.
/// The PDF render stats section takes no injected stats: pdfRenderStatsProvider
/// is read as is (B4: zero-stats notifier, 계약 7.6 B4 v1.2 — C12-06).
final class FeatureWiringModule extends AppModule {
  FeatureWiringModule({
    this._importPdf = importPdfAsNewNote,
    this._exportPdf = exportNotesAsPdf,
    this._moreMenuActions = pdfEditorMoreMenuActions,
    this._addPageActions = pdfEditorAddPageSources,
  });

  static const String moduleId = 'featureWiring';

  final LibraryPdfImportAction _importPdf;
  final LibraryPdfExportAction _exportPdf;
  final List<PdfMenuAction> Function() _moreMenuActions;
  final List<PdfMenuAction> Function() _addPageActions;

  bool _pdfAvailable = false;

  @override
  String get id => moduleId;
  @override
  String get label => '화면 연결 중';
  @override
  bool get critical => false;
  @override
  Duration get startTimeout => const Duration(seconds: 1);

  /// pdfAvailable = context.isStarted(PdfModule.moduleId); builds the list.
  @override
  Future<void> start(AppModuleContext context) async {
    _pdfAvailable = context.isStarted(PdfModule.moduleId);
  }

  /// In this order:
  ///   ...featureEditorOverrides(), ...featureLibraryOverrides(),
  ///   pageThumbnailRendererProvider.overrideWith(
  ///       (ref) => ref.watch(inkPageThumbnailRendererProvider)),
  ///   if (pdfAvailable) ...[
  ///     libraryPdfImportActionProvider.overrideWithValue(importPdf),
  ///     libraryPdfExportActionProvider.overrideWithValue(exportPdf),
  ///     editorExtensionsProvider.overrideWithValue(editorExtensionsFromPdf(
  ///         moreMenu: moreMenuActions(), addPageSources: addPageActions())),
  ///     devOverlaySectionsProvider.overrideWith(
  ///         (ref) => [pdfRenderStatsSection(ref)]),
  ///   ]
  @override
  List<Override> overrides() => [
    ...featureEditorOverrides(),
    ...featureLibraryOverrides(),
    pageThumbnailRendererProvider.overrideWith(
      (ref) => ref.watch(ink.inkPageThumbnailRendererProvider),
    ),
    if (_pdfAvailable) ...[
      libraryPdfImportActionProvider.overrideWithValue(_importPdf),
      libraryPdfExportActionProvider.overrideWithValue(_exportPdf),
      editorExtensionsProvider.overrideWithValue(
        editorExtensionsFromPdf(
          moreMenu: _moreMenuActions(),
          addPageSources: _addPageActions(),
        ),
      ),
      devOverlaySectionsProvider.overrideWith(
        (ref) => [pdfRenderStatsSection(ref)],
      ),
    ],
  ];
}
