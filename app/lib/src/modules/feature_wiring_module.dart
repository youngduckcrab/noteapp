/// Static wiring between feature packages (docs/plans/01-infra.md 4.5.9,
/// contract 7.3.3 rows owned by FeatureWiringModule; 2nd round
/// docs/plans/m5-7/01-infra.md 4.6.4, 6.7, 6.12.3).
library;

import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_library/feature_library.dart';
import 'package:feature_markdown/slots.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart' show Ref;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' show pageThumbnailRendererProvider;
import 'package:pdf_io/pdf_io.dart';
import 'package:pencil_bridge/pencil_bridge.dart' show PencilCapabilities;

import '../bootstrap/app_module.dart';
import '../errors/app_error_log.dart';
import '../pencil/pencil_stylus_extras.dart';
import 'markdown_wiring.dart';
import 'media_wiring.dart';
import 'pdf_module.dart';
import 'pdf_wiring.dart';
import 'pencil_wiring.dart';
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
/// 7.3.3). On iOS the pencil adapter overrides stylusExtrasProvider; its
/// capabilities are read once per app start (6.12.3).
final class FeatureWiringModule extends AppModule {
  FeatureWiringModule({
    this._importPdf = importPdfAsNewNote,
    this._exportPdf = exportNotesAsPdf,
    this._moreMenuActions = pdfEditorMoreMenuActions,
    this._addPageActions = pdfEditorAddPageSources,
    this._pencil = const PencilPort(),

    /// (v2.1, D2-15) Image import outside FEATURE_MEDIA: production =
    /// mediaImageImporterOrNull (media_io supportedImageSources +
    /// importImageForNote — works without initializeMediaIo).
    this._imageImporter = mediaImageImporterOrNull,
    LibraryMarkdownImportAction? importMarkdown,
  }) : _importMarkdown = importMarkdown ?? markdownImportAction();

  /// (v2.17-md) 'MD 가져오기' (tests give a fake picker).
  final LibraryMarkdownImportAction _importMarkdown;

  static const String moduleId = 'featureWiring';

  /// How long start() waits for the pencil capabilities (6.12.3) before it
  /// uses [kPencilFallbackCapabilities].
  static const Duration pencilCapabilitiesTimeout = Duration(milliseconds: 500);

  /// (6.7 '기여 합치기 규칙') Two editor menu items with one id: start()
  /// records each duplicate, drops the later one, then — in debug builds,
  /// while this is true — fails an assert (the module start fails loudly).
  /// Tests turn it off to see the release behaviour.
  @visibleForTesting
  static bool debugAssertUniqueMenuIds = true;

  final LibraryPdfImportAction _importPdf;
  final LibraryPdfExportAction _exportPdf;
  final List<PdfMenuAction> Function() _moreMenuActions;
  final List<PdfMenuAction> Function() _addPageActions;
  final EditorImageImporter? Function() _imageImporter;
  final PencilPort _pencil;

  bool _pdfAvailable = false;
  List<ShellContribution> _contributions = const [];
  List<EditorSelectionMenuItem> _selectionItems = const [];
  List<EditorInsertMenuItem> _insertItems = const [];
  EditorImageImporter? _importer;

  /// Non-null when the pencil is supported (read in start()).
  PencilCapabilities? _pencilCapabilities;

  @override
  String get id => moduleId;

  @override
  String get label => '화면 연결 중';

  @override
  bool get critical => false;

  @override
  Duration get startTimeout => const Duration(seconds: 1);

  /// pdfAvailable = context.isStarted('pdf'); contributions =
  /// context.contributions — their selection / insert items joined in module
  /// order, a repeated id recorded and the later item dropped (then a debug
  /// assert, [debugAssertUniqueMenuIds]); importer = imageImporter() (throw →
  /// errorLog, null);
  /// if (pencil.isSupported) capabilities = await pencil.capabilities() — read ONCE per app start
  /// (≤ 500 ms; throw / timeout → errorLog + kPencilFallbackCapabilities — the override stays,
  /// 계약 7.3.3 row; an iPadOS setting change applies on the next start, 계약 7.2.10 v2.1)
  @override
  Future<void> start(AppModuleContext context) async {
    _pdfAvailable = context.isStarted(PdfModule.moduleId);
    _contributions = context.contributions;
    final duplicates = <String>[];
    _selectionItems = _uniqueById(
      'selection',
      [
        for (final c in _contributions)
          for (final item in c.selectionMenuItems) (c.moduleId, item.id, item),
      ],
      context.errorLog,
      duplicates,
    );
    _insertItems = _uniqueById(
      'insert',
      [
        for (final c in _contributions)
          for (final item in c.insertMenuItems) (c.moduleId, item.id, item),
      ],
      context.errorLog,
      duplicates,
    );
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
    _pencilCapabilities = _pencil.isSupported
        ? await _readPencilCapabilities(context.errorLog)
        : null;
    assert(
      !debugAssertUniqueMenuIds || duplicates.isEmpty,
      'Editor menu item ids must be unique across the contributions; '
      'dropped: ${duplicates.join(', ')}',
    );
  }

  /// [items] as (moduleId, id, item) in contribution order → the items whose
  /// id was not seen before. Each repeat: one record (source module) and its
  /// `'slot:id'` in [duplicates].
  static List<T> _uniqueById<T>(
    String slot,
    List<(String, String, T)> items,
    AppErrorLog errorLog,
    List<String> duplicates,
  ) {
    final firstModule = <String, String>{};
    final kept = <T>[];
    for (final (moduleId, id, item) in items) {
      if (firstModule[id] case final first?) {
        duplicates.add('$slot:$id');
        errorLog.add(
          AppErrorRecord(
            time: DateTime.now(),
            source: AppErrorSource.module,
            summary:
                'duplicate $slot menu item id $id — the one of $moduleId '
                'is dropped',
            details: 'first contributed by $first',
          ),
        );
        continue;
      }
      firstModule[id] = moduleId;
      kept.add(item);
    }
    return List.unmodifiable(kept);
  }

  Future<PencilCapabilities> _readPencilCapabilities(
    AppErrorLog errorLog,
  ) async {
    try {
      return await _pencil.capabilities().timeout(pencilCapabilitiesTimeout);
    } on Object catch (error, stackTrace) {
      final record = AppErrorRecord.fromError(
        error,
        stackTrace,
        source: AppErrorSource.module,
      );
      errorLog.add(
        AppErrorRecord(
          time: record.time,
          source: record.source,
          summary: record.summary,
          details: error is TimeoutException
              ? 'pencil capabilities: no answer within '
                    '${pencilCapabilitiesTimeout.inMilliseconds} ms — '
                    'double tap only'
              : 'pencil capabilities failed — double tap only',
          stackTrace: record.stackTrace,
        ),
      );
      return kPencilFallbackCapabilities;
    }
  }

  /// In this order:
  ///   ...featureEditorOverrides(), ...featureLibraryOverrides(),
  ///   pageThumbnailRendererProvider ← ink (1차),
  ///   if (pdfAvailable) libraryPdfImportActionProvider,
  ///       libraryPdfExportActionProvider (1차),
  ///   (handwriting search) if a contribution has libraryInkSearch,
  ///       libraryInkSearchProvider.overrideWith(it),
  ///   (v2.13-search) if a contribution has editorInkSearch,
  ///       editorInkSearchProvider.overrideWith(it),
  ///   if (pdfAvailable or a contribution has editor items)
  ///     editorExtensionsProvider.overrideWithValue(EditorExtensions(
  ///       moreMenuItems: pdf…, addPageSources: pdf…,
  ///       selectionMenuItems: ⋃ c.selectionMenuItems (unique ids),
  ///       insertMenuItems: ⋃ c.insertMenuItems (unique ids),
  ///       recordingPanel: the media contribution's panel)),
  ///   if (importer != null) editorImageImporterProvider,
  ///   devOverlaySectionsProvider.overrideWith((ref) => [
  ///       if (pdfAvailable) pdfRenderStatsSection(ref),
  ///       for c in contributions for f in c.devOverlaySections f(ref),
  ///       searchIndexSection(ref)]),
  ///   if (pencil.isSupported) stylusExtrasProvider.overrideWithValue(
  ///       PencilStylusExtrasSource(capabilities: capabilities, events: pencil.events)).
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
      // (v2.17-md, C217M-11 · 15) MD 문서 import / export: pdf_io's file helpers need no
      // PDF engine, so they do not wait for the PDF module. No link opener (Q1 open).
      libraryMarkdownImportActionProvider.overrideWithValue(_importMarkdown),
      libraryMarkdownExportActionProvider.overrideWithValue(
        markdownLibraryExportAction(),
      ),
      markdownExportActionProvider.overrideWithValue(exportMarkdownText),
      if (_inkSearch(contributions) case final inkSearch?)
        libraryInkSearchProvider.overrideWith(inkSearch),
      if (_noteInkSearch(contributions) case final inkSearch?)
        editorInkSearchProvider.overrideWith(inkSearch),
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
      if (_pencilCapabilities case final capabilities?)
        stylusExtrasProvider.overrideWithValue(
          PencilStylusExtrasSource(
            capabilities: capabilities,
            events: _pencil.events,
          ),
        ),
    ];
  }

  /// (handwriting search) The first contribution's library ink search.
  static LibraryInkSearch? Function(Ref ref)? _inkSearch(
    List<ShellContribution> contributions,
  ) {
    for (final contribution in contributions) {
      if (contribution.libraryInkSearch case final f?) return f;
    }
    return null;
  }

  /// (v2.13-search) The first contribution's in-note ink search.
  static EditorInkSearch? Function(Ref ref)? _noteInkSearch(
    List<ShellContribution> contributions,
  ) {
    for (final contribution in contributions) {
      if (contribution.editorInkSearch case final f?) return f;
    }
    return null;
  }

  EditorExtensions _editorExtensions(List<ShellContribution> contributions) {
    final pdf = _pdfAvailable
        ? editorExtensionsFromPdf(
            moreMenu: _moreMenuActions(),
            addPageSources: _addPageActions(),
          )
        : const EditorExtensions();
    EditorPanelBuilder? recordingPanel;
    EditorMathPen? mathPen;
    EditorTextPen? textPen;
    for (final contribution in contributions) {
      recordingPanel ??= contribution.recordingPanel;
      mathPen ??= contribution.mathPen;
      textPen ??= contribution.textPen;
    }
    return EditorExtensions(
      moreMenuItems: pdf.moreMenuItems,
      addPageSources: pdf.addPageSources,
      selectionMenuItems: _selectionItems,
      insertMenuItems: _insertItems,
      recordingPanel: recordingPanel,
      mathPen: mathPen,
      textPen: textPen,
    );
  }
}
