// API surface of pdf_io (contract 00-overview 7.2.19, 06-pdf 4.0–4.15, 8 T0 / B4).
//
// 1. Export lists: lib/pdf_io.dart exports with `show` only, and the shown names are exactly
//    the 06-pdf 4.15 list; names removed from the draft (CORE / INK concepts such as
//    PageTemplateSpec, Page, Stroke) are not exported and lib/ does not use PageTemplateSpec.
//    lib/testing.dart declares exactly the 4.14 helpers.
// 2. Compile-time shape: every contract function, constructor and member is referenced with
//    the contract types (typed tear-offs), and every port is implemented below member by
//    member, so a renamed / retyped / removed member breaks the build.
// 3. Value types construct (const where the contract says const) with the contract defaults,
//    and PdfBackgroundLayerBuilder is an ink.PageBackgroundStillRenderer.
// 4. The B4 bodies of the 7.2.19 functions (contract 7.6 B4).
// 5. (2차 v2 — m5-7/06-pdf 4.1.6, 8.1 T20, 2nd-round contract 7.2.12 / 7.6.2 R2-B4) the 18 new
//    barrel names with their final shapes, the src-only names kept out of the barrel
//    (PdfIndexerGate, createPdfSearchIndexer, IndexerGate, PdfPageLayers, …), PdfSearchIndexer's
//    only public constructor (NoteStore) and its R2-B4 body (start() does nothing,
//    dispose() idempotent), PdfAffine / value equality / PdfPagePlan.isEmpty working.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderBase;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/testing.dart';

// ---- 1. export lists ----------------------------------------------------------------------

/// 06-pdf 4.15, in barrel order.
const Set<String> barrelNames = {
  // src/config.dart
  'PdfImportLimits', 'PdfRenderBudget', 'PdfUserPasswordPolicy', 'PdfIoConfig',
  // src/init.dart
  'initializePdfIo', 'pdfIoOverrides',
  // src/errors.dart
  'PdfErrorCode', 'PdfIoException',
  // src/common/
  'PdfCancelSignal',
  'PdfJobPhase', 'PdfProgress', 'PdfProgressCallback', 'PdfBatchProgress',
  'PdfBatchProgressCallback',
  'PdfJobState',
  'PdfJobIdle',
  'PdfJobRunning',
  'PdfJobSucceeded',
  'PdfJobFailed',
  // src/engine/
  'PdfPageInfo', 'PdfDocumentInfo', 'PdfPasswordRequest', 'PdfPasswordCallback',
  'PdfRenderPriority',
  'PdfRenderCancelToken',
  'PdfPixelRect',
  'PdfRenderRequest',
  'PdfPageTextData',
  'PdfEngine', 'PdfEngineDocument',
  'PdfrxEngine',
  // src/gateway/
  'PdfNoteGateway', 'CorePdfNoteGateway',
  // src/files/
  'PickedPdfFile',
  'PdfFileSource',
  'FilePickerPdfSource',
  'PdfIncomingFileSource',
  'NoIncomingPdfFiles',
  // src/model/
  'PdfPageRange', 'PdfPageSizePolicy', 'PdfPageFit', 'PdfFileNaming',
  // src/import/
  'PdfImportTarget',
  'PdfImportAsNewNote',
  'PdfImportIntoNote',
  'PdfImportResult',
  'PdfImportService', 'PdfImportSession', 'DefaultPdfImportService',
  // src/render/
  'PdfBackgroundParams',
  'PdfRenderStatus',
  'PdfPlacedImage',
  'PdfRenderSnapshot',
  'PdfRenderStats',
  'PdfPageRenderHandle',
  'PdfPageRenderer',
  'PdfRenderService',
  'PdfPageBackgroundView',
  'PdfDocumentLease', 'PdfDocumentPool', 'DefaultPdfDocumentPool',
  // src/ink_adapter/
  'PdfBackgroundLayerBuilder', 'InkEngineVectorizer',
  // src/text/
  'PdfNormalizedText', 'PdfTextNormalizer',
  'PdfSearchHit', 'PdfSearchStatus', 'PdfSearchState', 'PdfSearchProgress',
  'PdfTextService', 'DefaultPdfTextService',
  'PdfSearchNotifier',
  // src/export/
  'PdfExportRange',
  'PdfExportAllPages',
  'PdfExportCurrentPage',
  'PdfExportSelectedPages',
  'PdfMissingAssetPolicy', 'PdfExportOptions', 'PdfExportWarning',
  'PdfExportBlankedMissingAsset', 'PdfExportResult',
  'PdfBatchExportItem', 'PdfBatchExportResult',
  'PdfExportService', 'DefaultPdfExportService',
  'PdfBlend',
  'PdfFillRule',
  'PdfLineCap',
  'PdfLineJoin',
  'PdfVectorPath',
  'PdfVectorItem',
  'PdfFillItem', 'PdfStrokeItem', 'PdfPageVectors', 'PdfInkVectorizer',
  // (2차) m5-7/06-pdf 4.1.6 — the 18 new names are listed in barrelNamesV2 below.
  ...barrelNamesV2,
  ...barrelNamesV26,
  'PdfComposeSource',
  'PdfComposePagePlan',
  'PdfComposeSourcePage',
  'PdfComposeBlankPage',
  'PdfComposePlan', 'PdfComposePageOps', 'PdfComposeOpcodes',
  'PdfComposeEncoder',
  // src/compose/
  'PdfComposeJob', 'PdfComposeBackend', 'createPlatformComposeBackend',
  // src/output/
  'PdfOutputAction',
  'PdfOutputOutcome',
  'PdfOutputSink',
  'createPlatformOutputSink',
  // src/ui/
  'PdfNavigateCallback',
  'PdfExportPurpose',
  'runPdfImportFlow',
  'importPdfAsNewNote',
  'runPdfExportFlow', 'exportNotesAsPdf', 'showPdfSearchPanel',
  'PdfMenuInvocation',
  'PdfMenuAction',
  'pdfEditorMoreMenuActions',
  'pdfEditorAddPageSources',
  // src/tuning.dart
  'PdfTuning',
  // src/providers.dart
  'pdfIoConfigProvider', 'pdfEngineProvider', 'pdfNoteGatewayProvider',
  'pdfDocumentPoolProvider',
  'pdfPageRendererProvider',
  'pdfRenderStatsProvider',
  'pdfTextServiceProvider',
  'pdfActiveSearchProvider',
  'pdfSearchHighlightsProvider',
  'pdfBackgroundLayerBuilderProvider', 'pdfFileSourceProvider',
  'pdfIncomingFileSourceProvider',
  'pdfOutputSinkProvider',
  'pdfInkVectorizerProvider',
  'pdfComposeBackendProvider',
  'pdfImportServiceProvider',
  'pdfExportServiceProvider',
  'pdfImportJobProvider', 'pdfExportJobProvider', 'pdfBatchExportJobProvider',
  'PdfImportJobNotifier',
  'PdfExportJobNotifier',
  'PdfBatchJobState',
  'PdfBatchJobIdle',
  'PdfBatchJobRunning', 'PdfBatchJobFinished', 'PdfBatchJobFailed',
  'PdfBatchExportJobNotifier',
};

/// (2차) m5-7/06-pdf 4.1.6: the names the 2nd round adds to the barrel (18).
const Set<String> barrelNamesV2 = {
  'PdfSearchIndexer',
  'pdfSearchIndexerProvider',
  'PdfPlanItem',
  'PdfDrawItem',
  'PdfAffine',
  'PdfImageData',
  'PdfJpegData',
  'PdfRgbaData',
  'PdfImageItem',
  'PdfTextItem',
  'PdfTextLine',
  'PdfAssetImageRef',
  'PdfTextBoxRef',
  'PdfMathRef',
  'PdfPagePlan',
  'PdfExportMissingImages',
  'PdfExportRasterizedText',
  'PdfExportSkippedFormulas',
};

/// (2차, contract v2.6 C26-02 — added only) the developer overlay lines of the export.
const Set<String> barrelNamesV26 = {'pdfDevOverlayLinesProvider'};

/// (2차) m5-7/06-pdf 4.1.1, 4.1.3, 4.1.6: src only — never in the barrel (the draft's
/// PdfIndexerGate is not exported either, v2.1 PDF-M9).
const Set<String> srcOnlyNamesV2 = {
  'PdfIndexerGate',
  'createPdfSearchIndexer',
  'IndexerGate',
  'AppIndexerGate',
  'AlwaysOpenIndexerGate',
  'debugPdfSearchIndexerState',
  'PdfPageLayers',
  'PdfPageBackgroundPart',
  'planFromLayers',
  'layersFromInk',
  'PdfMathRasterizer',
  'PdfTextRasterizer',
  'ExportMemoryLedger',
  // (contract v2.6) C26-02 the ledger record behind the lines, C26-04 the adapter's text fix
  'PdfExportDiagnostics',
  'pdfExportDiagnosticsProvider',
  'softenPdfiumHyphenJoins',
};

/// 06-pdf 4.14.
const Set<String> testingNames = {
  'PdfFixtureText',
  'PdfFixturePage',
  'PdfFixtureBuilder',
  'FakePdfEngine',
  'FakePdfNoteGateway',
  'FakePdfFileSource',
  'FakePdfOutputSink',
  'RecordingComposeBackend',
  'BoxInkVectorizer',
  'FakeRemoteAssetFetcher',
  // (2차) m5-7/06-pdf 4.3.1
  'PdfObjectFixtures',
};

/// Internal per 4.15 ('내부 전용'): never exported.
const Set<String> internalNames = {
  'PdfIoRuntime',
  'PdfTitlePolicy',
  'HangulJamo',
};

/// Names the draft defined again although CORE / INK own them (06-pdf 13.1 PDF-M1, 5.1;
/// contract 7.2.0): pdf_io must not export them.
const Set<String> removedDraftNames = {
  'PageTemplateSpec',
  'Asset',
  'AssetType',
  'Note',
  'Page',
  'PageAfter',
  'PageAtEnd',
  'PageAtStart',
  'PageBefore',
  'PageBackground',
  'PdfBackground',
  'AppliedEdit',
  'Stroke',
};

String _read(String path) => File(path).readAsStringSync();

/// Every `export` directive of [source]: (uri, shown names or null without `show`).
List<(String, Set<String>?)> _exports(String source) {
  final out = <(String, Set<String>?)>[];
  final directive = RegExp(r'''^export\s+'([^']+)'([^;]*);''', multiLine: true);
  for (final m in directive.allMatches(source)) {
    final rest = m.group(2)!;
    final show = RegExp(r'\bshow\b([\s\S]*)').firstMatch(rest);
    out.add((
      m.group(1)!,
      show == null
          ? null
          : {
              for (final n in show.group(1)!.split(','))
                if (n.trim().isNotEmpty) n.trim(),
            },
    ));
  }
  return out;
}

/// Public top-level declarations of a library file found at column 0.
Set<String> _publicTopLevelNames(String source) {
  final names = <String>{};
  final typeDecl = RegExp(
    r'^(?:(?:abstract|final|sealed|base|interface|mixin)\s+)*'
    r'(?:class|enum|mixin|typedef|extension(?:\s+type)?)\s+(\w+)',
    multiLine: true,
  );
  for (final m in typeDecl.allMatches(source)) {
    names.add(m.group(1)!);
  }
  final function = RegExp(r'^[A-Za-z_][\w<>?, ]*\s+(\w+)\(', multiLine: true);
  for (final m in function.allMatches(source)) {
    names.add(m.group(1)!);
  }
  final variable = RegExp(
    r'^(?:final|const|var|late)\s+(?:[\w<>?, ]+\s+)?(\w+)\s*=',
    multiLine: true,
  );
  for (final m in variable.allMatches(source)) {
    names.add(m.group(1)!);
  }
  return names.where((n) => !n.startsWith('_')).toSet();
}

// ---- 2. ports implemented member by member ------------------------------------------------

Never _no() => throw UnimplementedError();

const String _assetId =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

final class _Engine implements PdfEngine {
  @override
  bool get isInitialized => _no();
  @override
  Future<void> ensureInitialized() => _no();
  @override
  Future<PdfEngineDocument> open(
    Uint8List bytes, {
    required String sourceName,
    String fileName = '',
    PdfPasswordCallback? onPassword,
    int maxPasswordAttempts = 5,
    bool transferOwnership = false,
  }) => _no();
}

final class _Document implements PdfEngineDocument {
  @override
  String get sourceName => _no();
  @override
  PdfDocumentInfo get info => _no();
  @override
  bool get isDisposed => _no();
  @override
  Future<ui.Image?> render(
    PdfRenderRequest request, {
    PdfRenderCancelToken? cancelToken,
  }) => _no();
  @override
  Future<PdfPageTextData> loadText(int pageIndex) => _no();
  @override
  Future<Uint8List> encodeWithoutSecurity() => _no();
  @override
  Future<void> dispose() => _no();
}

final class _Gateway implements PdfNoteGateway {
  @override
  Future<core.Asset> putPdf(Uint8List bytes, {required String fileName}) =>
      _no();
  @override
  Future<Uint8List?> readAssetBytes(core.AssetId assetId) => _no();
  @override
  Stream<core.AssetId> get bytesArrived => _no();
  @override
  Future<core.Note> createNote({
    core.FolderId? folderId,
    required String title,
    required List<core.PageDraft> pages,
  }) => _no();
  @override
  Future<List<core.PageId>> insertPages(
    core.NoteId noteId,
    List<core.PageDraft> pages,
    core.PagePosition position,
  ) => _no();
  @override
  Future<void> flush() => _no();
  @override
  Future<core.Note?> getNote(core.NoteId noteId) => _no();
  @override
  Future<List<core.Page>> pagesOf(core.NoteId noteId) => _no();
  @override
  Future<core.PageContent> loadPage(core.PageId pageId) => _no();
  @override
  Future<void> writeThumbnail(core.PageThumbnail thumbnail) => _no();
}

final class _FileSource implements PdfFileSource {
  @override
  bool get isSupported => _no();
  @override
  Future<PickedPdfFile?> pickPdf() => _no();
}

final class _Incoming implements PdfIncomingFileSource {
  @override
  Stream<PickedPdfFile> get incoming => _no();
}

final class _ImportService implements PdfImportService {
  @override
  Future<PdfImportSession> open(
    PickedPdfFile file, {
    PdfPasswordCallback? onPassword,
    PdfProgressCallback? onProgress,
    PdfCancelSignal? cancel,
  }) => _no();
}

final class _ImportSession implements PdfImportSession {
  @override
  PickedPdfFile get file => _no();
  @override
  PdfDocumentInfo get info => _no();
  @override
  int get byteLength => _no();
  @override
  bool get isLargeFile => _no();
  @override
  bool get willStoreDecryptedCopy => _no();
  @override
  String get suggestedTitle => _no();
  @override
  Future<PdfImportResult> commit(
    PdfImportTarget target, {
    PdfPageRange range = const PdfPageRange.all(),
    PdfProgressCallback? onProgress,
    PdfCancelSignal? cancel,
  }) => _no();
  @override
  Future<void> dispose() => _no();
}

final class _Handle implements PdfPageRenderHandle {
  @override
  PdfBackgroundParams get params => _no();
  @override
  PdfRenderSnapshot get snapshot => _no();
  @override
  void update(PdfBackgroundParams params) => _no();
  @override
  void dispose() => _no();
  @override
  void addListener(VoidCallback listener) => _no();
  @override
  void removeListener(VoidCallback listener) => _no();
}

final class _Renderer implements PdfPageRenderer {
  @override
  PdfPageRenderHandle attach(PdfBackgroundParams params) => _no();
  @override
  Future<ui.Image?> renderThumbnail({
    required core.AssetId assetId,
    required int pdfPageIndex,
    required int longSidePx,
    int backgroundArgb = 0xFFFFFFFF,
  }) => _no();
  @override
  PdfRenderStats get stats => _no();
  @override
  ValueListenable<PdfRenderStats> get statsListenable => _no();
  @override
  void trimMemory() => _no();
  @override
  Future<void> dispose() => _no();
}

final class _Lease implements PdfDocumentLease {
  @override
  core.AssetId get assetId => _no();
  @override
  PdfEngineDocument get document => _no();
  @override
  void release() => _no();
}

final class _Pool implements PdfDocumentPool {
  @override
  Future<PdfDocumentLease> acquire(core.AssetId assetId) => _no();
  @override
  void adopt(core.AssetId assetId, PdfEngineDocument document) => _no();
  @override
  Stream<core.AssetId> get assetArrived => _no();
  @override
  Stream<core.RemoteAssetProgress>? requestRemote(core.AssetId assetId) =>
      _no();
  @override
  int get openCount => _no();
  @override
  Future<void> closeIdle() => _no();
  @override
  Future<void> dispose() => _no();
}

final class _TextService implements PdfTextService {
  @override
  Future<PdfPageTextData> pageText(core.AssetId assetId, int pdfPageIndex) =>
      _no();
  @override
  Stream<PdfSearchProgress> searchNote(
    core.NoteId noteId,
    String query, {
    PdfCancelSignal? cancel,
    int maxHits = PdfTuning.maxSearchHits,
  }) => _no();
  @override
  void clearCache() => _no();
}

final class _Vectorizer implements PdfInkVectorizer {
  @override
  PdfPageVectors vectorize(
    core.Page page,
    List<core.Stroke> strokes, {
    required bool includeInk,
    required bool includeTemplate,
  }) => _no();
  // (2차, m5-7/06-pdf 4.1.3)
  @override
  PdfPagePlan planPage(
    core.PageContent content, {
    required bool includeInk,
    required bool includeTemplate,
  }) => _no();
}

final class _ComposeJob implements PdfComposeJob {
  @override
  Future<void> addPages(List<PdfComposePageOps> pages) => _no();
  @override
  Future<Uint8List> finish() => _no();
  @override
  Future<void> abort() => _no();
}

final class _ComposeBackend implements PdfComposeBackend {
  @override
  bool get isSupported => _no();
  @override
  Future<PdfComposeJob> begin(PdfComposePlan plan) => _no();
  @override
  Future<void> dispose() => _no();
}

final class _OutputSink implements PdfOutputSink {
  @override
  Set<PdfOutputAction> availableActions(List<PdfExportResult> results) => _no();
  @override
  Future<PdfOutputOutcome> deliver(
    List<PdfExportResult> results,
    PdfOutputAction action,
  ) => _no();
}

final class _ExportService implements PdfExportService {
  @override
  Future<PdfExportResult> exportNote(
    core.NoteId noteId,
    PdfExportOptions options, {
    PdfProgressCallback? onProgress,
    PdfCancelSignal? cancel,
  }) => _no();
  @override
  Future<PdfBatchExportResult> exportNotes(
    List<core.NoteId> noteIds,
    PdfExportOptions options, {
    PdfBatchProgressCallback? onProgress,
    PdfCancelSignal? cancel,
  }) => _no();
}

Future<Uint8List> _bytes() async => Uint8List(0);

// Sealed hierarchies: these switches compile only while the subtypes are exactly the
// contract's (an extra subtype makes them non-exhaustive).
String _jobState(PdfJobState<int> s) => switch (s) {
  PdfJobIdle<int>() => 'idle',
  PdfJobRunning<int>() => 'running',
  PdfJobSucceeded<int>() => 'succeeded',
  PdfJobFailed<int>() => 'failed',
};
String _batchState(PdfBatchJobState s) => switch (s) {
  PdfBatchJobIdle() => 'idle',
  PdfBatchJobRunning() => 'running',
  PdfBatchJobFinished() => 'finished',
  PdfBatchJobFailed() => 'failed',
};
String _target(PdfImportTarget t) => switch (t) {
  PdfImportAsNewNote() => 'new',
  PdfImportIntoNote() => 'into',
};
String _range(PdfExportRange r) => switch (r) {
  PdfExportAllPages() => 'all',
  PdfExportCurrentPage() => 'current',
  PdfExportSelectedPages() => 'selected',
};
String _warning(PdfExportWarning w) => switch (w) {
  PdfExportBlankedMissingAsset() => 'blanked',
  // (2차, m5-7/06-pdf 4.1.5)
  PdfExportMissingImages() => 'missingImages',
  PdfExportRasterizedText() => 'rasterizedText',
  PdfExportSkippedFormulas() => 'skippedFormulas',
};
String _item(PdfVectorItem i) => switch (i) {
  PdfFillItem() => 'fill',
  PdfStrokeItem() => 'stroke',
};
// (2차, m5-7/06-pdf 4.1.3) the plan item families.
String _planItem(PdfPlanItem i) => switch (i) {
  PdfDrawItem() => 'draw',
  PdfAssetImageRef() => 'imageRef',
  PdfTextBoxRef() => 'textRef',
  PdfMathRef() => 'mathRef',
};
String _drawItem(PdfDrawItem i) => switch (i) {
  PdfVectorItem() => 'vector',
  PdfImageItem() => 'image',
  PdfTextItem() => 'text',
};
String _imageData(PdfImageData d) => switch (d) {
  PdfJpegData() => 'jpeg',
  PdfRgbaData() => 'rgba',
};
String _pagePlan(PdfComposePagePlan p) => switch (p) {
  PdfComposeSourcePage() => 'source',
  PdfComposeBlankPage() => 'blank',
};

void main() {
  group('export lists (06-pdf 4.14, 4.15)', () {
    test('lib/pdf_io.dart show list = 4.15', () {
      final names = <String>{};
      for (final (uri, shown) in _exports(_read('lib/pdf_io.dart'))) {
        expect(
          shown,
          isNotNull,
          reason: 'pdf_io.dart exports $uri without show',
        );
        expect(uri, startsWith('src/'), reason: 'pdf_io.dart re-exports $uri');
        names.addAll(shown!);
      }
      expect(names.difference(barrelNames), isEmpty, reason: 'not in 4.15');
      expect(barrelNames.difference(names), isEmpty, reason: 'missing');
      expect(names.intersection(internalNames), isEmpty);
      expect(names.intersection(removedDraftNames), isEmpty);
    });

    test('lib/testing.dart declares exactly the 4.14 helpers', () {
      final source = _read('lib/testing.dart');
      expect(
        _exports(source),
        isEmpty,
        reason: 'testing.dart re-exports nothing',
      );
      expect(_publicTopLevelNames(source), testingNames);
      expect(testingNames.intersection(barrelNames), isEmpty);
    });

    test('no draft names in lib/ (PageTemplateSpec, resolved)', () {
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.readAsStringSync().contains('PageTemplateSpec')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty);
    });

    test('only lib/pdf_io.dart and lib/testing.dart at the top of lib/', () {
      final entries = [
        for (final f in Directory('lib').listSync())
          if (f is File) f.uri.pathSegments.last,
      ]..sort();
      expect(entries, ['pdf_io.dart', 'testing.dart']);
    });
  });

  group('contract 7.2.19 shapes', () {
    test('functions and providers have the contract types', () {
      final Future<void> Function({PdfIoConfig config}) init = initializePdfIo;
      final List<Override> Function({PdfIoConfig? config}) overrides =
          pdfIoOverrides;
      // LibraryPdfImportAction / LibraryPdfExportAction shapes (contract 7.2.18).
      final Future<String?> Function(BuildContext context, {String? folderId})
      importAction = importPdfAsNewNote;
      final Future<void> Function(BuildContext context, List<String> noteIds)
      exportAction = exportNotesAsPdf;
      final List<PdfMenuAction> Function() more = pdfEditorMoreMenuActions;
      final List<PdfMenuAction> Function() add = pdfEditorAddPageSources;
      final Provider<ValueListenable<PdfRenderStats>> stats =
          pdfRenderStatsProvider;
      // contract v2.6 C26-02
      final Provider<List<String>> devLines = pdfDevOverlayLinesProvider;
      expect([
        devLines,
        init,
        overrides,
        importAction,
        exportAction,
        more,
        add,
        stats,
      ], everyElement(isNotNull));
    });

    test('PdfMenuAction / PdfMenuInvocation fields (4.11)', () {
      Future<void> run(BuildContext context, PdfMenuInvocation invocation) =>
          Future<void>.value();
      bool enabled(PdfMenuInvocation invocation) =>
          invocation.noteId.isNotEmpty;
      final action = PdfMenuAction(
        id: 'pdf.export',
        label: 'PDF로 내보내기',
        icon: const IconData(0xe000),
        run: run,
        isEnabled: enabled,
      );
      final String id = action.id;
      final String label = action.label;
      final IconData icon = action.icon;
      final Future<void> Function(BuildContext, PdfMenuInvocation) runField =
          action.run;
      final bool Function(PdfMenuInvocation)? enabledField = action.isEnabled;
      expect([
        id,
        label,
        icon,
        runField,
        enabledField,
      ], everyElement(isNotNull));

      void navigate(String pageId, Rect? focusRectPt) {}
      final invocation = PdfMenuInvocation(
        noteId: 'n1',
        currentPageId: 'p1',
        selectedPageIds: const ['p1', 'p2'],
        onNavigate: navigate,
      );
      final String noteId = invocation.noteId;
      final String? current = invocation.currentPageId;
      final List<String> selected = invocation.selectedPageIds;
      // Same shape as EditorMenuContext.navigateToPage (contract 7.2.17), both ways.
      final void Function(String pageId, Rect? focusRectPt)? onNavigate =
          invocation.onNavigate;
      final PdfNavigateCallback back = navigate;
      expect([
        noteId,
        current,
        selected,
        onNavigate,
        back,
      ], everyElement(isNotNull));
      const minimal = PdfMenuInvocation(noteId: 'n2');
      expect(minimal.currentPageId, isNull);
      expect(minimal.selectedPageIds, isEmpty);
      expect(minimal.onNavigate, isNull);
    });

    test('PdfBackgroundLayerBuilder is an INK builder and still renderer', () {
      const builder = PdfBackgroundLayerBuilder.paperOnly();
      expect(builder, isA<ink.PageBackgroundLayerBuilder>());
      expect(builder, isA<ink.PageBackgroundStillRenderer>());
      expect(builder.isPaperOnly, isTrue);
      expect(builder.highlights, isNull);
      final lazy = PdfBackgroundLayerBuilder(
        renderer: _Renderer.new,
        highlights: ValueNotifier(PdfSearchState.idle),
      );
      expect(lazy.isPaperOnly, isFalse);
      final PdfBackgroundParams Function(ink.PageBackgroundContext ctx) params =
          PdfBackgroundLayerBuilder.paramsFrom;
      expect(params, isNotNull);
    });
  });

  group('4.1–4.14 shapes', () {
    test('ports and constructors', () {
      final ports = <Object>[
        _Engine(),
        _Document(),
        _Gateway(),
        _FileSource(),
        _Incoming(),
        _ImportService(),
        _ImportSession(),
        _Handle(),
        _Renderer(),
        _Lease(),
        _Pool(),
        _TextService(),
        _Vectorizer(),
        _ComposeJob(),
        _ComposeBackend(),
        _OutputSink(),
        _ExportService(),
      ];
      expect(ports, hasLength(17));

      final PdfrxEngine Function() shared = PdfrxEngine.shared;
      expect(identical(PdfrxEngine.shared(), PdfrxEngine.shared()), isTrue);
      final void Function(PdfIoConfig) configure =
          PdfrxEngine.shared().configure;
      final CorePdfNoteGateway Function(core.NoteStore) gateway =
          CorePdfNoteGateway.new;
      final DefaultPdfImportService Function({
        required PdfEngine engine,
        required PdfNoteGateway gateway,
        required PdfDocumentPool pool,
        required PdfPageRenderer renderer,
        required PdfIoConfig config,
        core.PageThumbnailRenderer? thumbnailRenderer,
      })
      importService = DefaultPdfImportService.new;
      final PdfRenderService Function({
        required PdfDocumentPool pool,
        required PdfRenderBudget budget,
        int maxInflight,
        bool trimOnAppHidden,
      })
      renderService = PdfRenderService.new;
      final DefaultPdfDocumentPool Function({
        required PdfEngine engine,
        required PdfNoteGateway gateway,
        core.RemoteAssetFetcher? remoteAssets,
        int maxIdleDocuments,
        Duration idleTtl,
      })
      pool = DefaultPdfDocumentPool.new;
      final DefaultPdfTextService Function({
        required PdfDocumentPool pool,
        required PdfNoteGateway gateway,
      })
      textService = DefaultPdfTextService.new;
      final DefaultPdfExportService Function({
        required PdfNoteGateway gateway,
        required PdfInkVectorizer vectorizer,
        required PdfComposeBackend backend,
      })
      exportService = DefaultPdfExportService.new;
      const PdfFileSource picker = FilePickerPdfSource();
      const PdfIncomingFileSource incoming = NoIncomingPdfFiles();
      const PdfInkVectorizer vectorizer = InkEngineVectorizer();
      expect([
        shared,
        configure,
        gateway,
        importService,
        renderService,
        pool,
        textService,
        exportService,
        picker,
        incoming,
        vectorizer,
      ], everyElement(isNotNull));
    });

    test('static functions and flows', () {
      final core.PageSize Function(double widthPt, double heightPt) size =
          PdfPageSizePolicy.toNotePageSize;
      final String Function(
        String noteTitle,
        PdfExportRange range, {
        int? currentPageNumber,
        int? selectedCount,
      })
      forExport = PdfFileNaming.forExport;
      final String Function(String) sanitize = PdfFileNaming.sanitize;
      final List<String> Function(List<String>) dedupe =
          PdfFileNaming.deduplicate;
      final PdfNormalizedText Function(String) normalize =
          PdfTextNormalizer.normalize;
      final String Function(String) normalizeQuery =
          PdfTextNormalizer.normalizeQuery;
      final PdfComposePageOps Function({
        required int outputIndex,
        required PdfPageVectors vectors,
      })
      encode = PdfComposeEncoder.encode;
      final PdfComposeBackend Function(PdfIoConfig) composeFactory =
          createPlatformComposeBackend;
      final PdfOutputSink Function() sinkFactory = createPlatformOutputSink;
      final Future<PdfImportResult?> Function(BuildContext, PdfImportTarget)
      importFlow = runPdfImportFlow;
      final Future<PdfExportResult?> Function(
        BuildContext, {
        required String noteId,
        String? currentPageId,
        List<String> selectedPageIds,
        PdfExportPurpose purpose,
      })
      exportFlow = runPdfExportFlow;
      final Future<void> Function(
        BuildContext, {
        required String noteId,
        required PdfNavigateCallback onNavigate,
      })
      search = showPdfSearchPanel;
      final PdfPageRange Function(String, {required int pageCount}) parse =
          PdfPageRange.parse;
      final PdfVectorPath Function(ui.Rect) rect = PdfVectorPath.rect;
      final PdfVectorPath Function(List<(ui.Offset, double)>) circles =
          PdfVectorPath.circles;
      final PdfVectorPath Function(List<PdfVectorPath>) concat =
          PdfVectorPath.concat;
      final PickedPdfFile Function(String, Uint8List) fromBytes =
          PickedPdfFile.fromBytes;
      expect([
        size,
        forExport,
        sanitize,
        dedupe,
        normalize,
        normalizeQuery,
        encode,
        composeFactory,
        sinkFactory,
        importFlow,
        exportFlow,
        search,
        parse,
        rect,
        circles,
        concat,
        fromBytes,
      ], everyElement(isNotNull));
    });

    test('instance members', () {
      final signal = PdfCancelSignal();
      final void Function() cancel = signal.cancel;
      final void Function() throwIfCancelled = signal.throwIfCancelled;
      final Future<T> Function<T>(Future<T> future) race = signal.raceCancel;
      final token = PdfRenderCancelToken();
      final void Function() cancelRender = token.cancel;

      const range = PdfPageRange.all();
      final List<int> Function(int) resolve = range.resolve;
      final String Function() format = range.format;

      final fit = PdfPageFit(
        notePageSize: const ui.Size(100, 100),
        pdfPageSize: const ui.Size(100, 100),
      );
      final ui.Rect Function(ui.Rect) toNote = fit.pdfToNote;
      final ui.Rect Function(ui.Rect) toPdf = fit.noteToPdf;
      final List<double> Function() matrix = fit.noteToPdfMatrix;
      final double k = fit.k, ox = fit.ox, oy = fit.oy;
      final bool identity = fit.isIdentity;
      final ui.Rect box = fit.pdfBoxInNote;

      final importJob = PdfImportJobNotifier();
      final Future<PdfImportResult?> Function(
        PdfImportSession,
        PdfImportTarget, {
        PdfPageRange range,
      })
      runImport = importJob.run;
      final exportJob = PdfExportJobNotifier();
      final Future<PdfExportResult?> Function(String, PdfExportOptions)
      runExport = exportJob.run;
      final batchJob = PdfBatchExportJobNotifier();
      final Future<PdfBatchExportResult?> Function(
        List<String>,
        PdfExportOptions,
      )
      runBatch = batchJob.run;
      final search = PdfSearchNotifier();
      final void Function(core.NoteId, String) start = search.start;
      final void Function(int) select = search.select;
      final List<void Function()> moves = [
        search.selectNext,
        search.selectPrevious,
        search.clear,
        importJob.cancel,
        importJob.reset,
        exportJob.cancel,
        exportJob.reset,
        batchJob.cancel,
        batchJob.reset,
      ];

      final builder = PdfFixtureBuilder();
      final PdfFixtureBuilder Function(PdfFixturePage) addPage =
          builder.addPage;
      final PdfFixtureBuilder Function(int, PdfFixturePage Function(int))
      addPages = builder.addPages;
      final PdfFixtureBuilder Function({
        required String userPassword,
        String ownerPassword,
      })
      encrypt = builder.encrypt;
      final Uint8List Function() build = builder.build;
      final gatewayFake = FakePdfNoteGateway();
      final void Function(core.AssetId, Uint8List) arrive =
          gatewayFake.arriveBytes;
      final fetcher = FakeRemoteAssetFetcher();
      final void Function(core.AssetId, core.RemoteAssetProgress) emit =
          fetcher.emit;
      final void Function(core.AssetId, bool) complete =
          fetcher.completeEnsureLocal;
      final core.RemoteAssetFetcher asFetcher = fetcher;
      final fakes = <Object>[
        FakePdfEngine(),
        FakePdfFileSource(),
        FakePdfOutputSink(),
        RecordingComposeBackend(),
        const BoxInkVectorizer(),
      ];

      expect([
        cancel,
        throwIfCancelled,
        race,
        cancelRender,
        resolve,
        format,
        toNote,
        toPdf,
        matrix,
        k,
        ox,
        oy,
        identity,
        box,
        runImport,
        runExport,
        runBatch,
        start,
        select,
        moves,
        addPage,
        addPages,
        encrypt,
        build,
        arrive,
        emit,
        complete,
        asFetcher,
        fakes,
      ], everyElement(isNotNull));
    });

    test('sealed hierarchies and enums', () {
      expect(_jobState(const PdfJobIdle<int>()), 'idle');
      expect(_batchState(const PdfBatchJobIdle()), 'idle');
      expect(_target(const PdfImportAsNewNote()), 'new');
      expect(_range(const PdfExportAllPages()), 'all');
      expect(_warning(const PdfExportBlankedMissingAsset([3])), 'blanked');
      expect(
        _item(
          PdfFillItem(
            path: PdfVectorPath(Uint8List(0), Float32List(0)),
            colorArgb: 0xFF000000,
          ),
        ),
        'fill',
      );
      expect(
        _pagePlan(const PdfComposeBlankPage(noteSize: ui.Size(1, 1))),
        'blank',
      );

      List<String> names(List<Enum> values) => [for (final v in values) v.name];
      expect(names(PdfErrorCode.values), [
        'notPdf',
        'tooLarge',
        'tooManyPages',
        'passwordCancelled',
        'userPasswordRefused',
        'corrupt',
        'engineUnavailable',
        'assetMissing',
        'noteNotFound',
        'readOnlyNote',
        'storageFailed',
        'exportFailed',
        'pickerFailed',
        'cancelled',
        'busy',
        'unsupportedPlatform',
      ]);
      expect(names(PdfJobPhase.values), [
        'readingFile',
        'openingPdf',
        'storingPdf',
        'creatingPages',
        'coverThumbnail',
        'preparingExport',
        'composing',
        'finishingExport',
      ]);
      expect(names(PdfUserPasswordPolicy.values), [
        'storeDecryptedCopy',
        'refuse',
      ]);
      expect(names(PdfRenderPriority.values), ['high', 'normal', 'low']);
      expect(names(PdfRenderStatus.values), [
        'loading',
        'ready',
        'assetMissing',
        'downloading',
        'needsPassword',
        'failed',
      ]);
      expect(names(PdfSearchStatus.values), [
        'idle',
        'searching',
        'done',
        'failed',
      ]);
      expect(names(PdfMissingAssetPolicy.values), ['fail', 'blankPage']);
      expect(names(PdfBlend.values), ['normal', 'multiply']);
      expect(names(PdfFillRule.values), ['evenOdd', 'nonZero']);
      expect(names(PdfLineCap.values), ['butt', 'round', 'square']);
      expect(names(PdfLineJoin.values), ['miter', 'round', 'bevel']);
      expect(names(PdfOutputAction.values), [
        'share',
        'download',
        'openInNewTab',
      ]);
      expect(names(PdfOutputOutcome.values), [
        'done',
        'dismissedByUser',
        'needsUserGesture',
        'failed',
        'unsupported',
      ]);
      expect(names(PdfExportPurpose.values), ['save', 'share', 'print']);
    });

    test('typedefs', () {
      void onProgress(PdfProgress progress) {}
      void onBatch(PdfBatchProgress progress) {}
      Future<String?> onPassword(PdfPasswordRequest request) async => null;
      final PdfProgressCallback p = onProgress;
      final PdfBatchProgressCallback b = onBatch;
      final PdfPasswordCallback pw = onPassword;
      final void Function(PdfProgress) p2 = p;
      final void Function(PdfBatchProgress) b2 = b;
      final Future<String?> Function(PdfPasswordRequest) pw2 = pw;
      expect([p2, b2, pw2], everyElement(isNotNull));
    });

    test('providers: types and name: = variable name (contract 7.4.4)', () {
      final Map<String, ProviderBase<Object?>> providers = {
        'pdfIoConfigProvider': pdfIoConfigProvider,
        'pdfEngineProvider': pdfEngineProvider,
        'pdfNoteGatewayProvider': pdfNoteGatewayProvider,
        'pdfDocumentPoolProvider': pdfDocumentPoolProvider,
        'pdfPageRendererProvider': pdfPageRendererProvider,
        'pdfRenderStatsProvider': pdfRenderStatsProvider,
        'pdfTextServiceProvider': pdfTextServiceProvider,
        'pdfActiveSearchProvider': pdfActiveSearchProvider,
        'pdfSearchHighlightsProvider': pdfSearchHighlightsProvider,
        'pdfBackgroundLayerBuilderProvider': pdfBackgroundLayerBuilderProvider,
        'pdfFileSourceProvider': pdfFileSourceProvider,
        'pdfIncomingFileSourceProvider': pdfIncomingFileSourceProvider,
        'pdfOutputSinkProvider': pdfOutputSinkProvider,
        'pdfInkVectorizerProvider': pdfInkVectorizerProvider,
        'pdfSearchIndexerProvider': pdfSearchIndexerProvider, // 2차
        'pdfComposeBackendProvider': pdfComposeBackendProvider,
        'pdfImportServiceProvider': pdfImportServiceProvider,
        'pdfExportServiceProvider': pdfExportServiceProvider,
        'pdfImportJobProvider': pdfImportJobProvider,
        'pdfExportJobProvider': pdfExportJobProvider,
        'pdfBatchExportJobProvider': pdfBatchExportJobProvider,
        'pdfDevOverlayLinesProvider': pdfDevOverlayLinesProvider, // v2.6 C26-02
      };
      providers.forEach((name, provider) {
        expect(provider.name, name);
      });
      expect(
        providers.keys.toSet(),
        barrelNames.where((n) => n.endsWith('Provider')).toSet(),
      );

      final Provider<PdfIoConfig> config = pdfIoConfigProvider;
      final Provider<PdfEngine> engine = pdfEngineProvider;
      final Provider<PdfNoteGateway> gateway = pdfNoteGatewayProvider;
      final Provider<PdfDocumentPool> pool = pdfDocumentPoolProvider;
      final Provider<PdfPageRenderer> renderer = pdfPageRendererProvider;
      final Provider<ValueListenable<PdfRenderStats>> stats =
          pdfRenderStatsProvider;
      final Provider<PdfTextService> text = pdfTextServiceProvider;
      final NotifierProvider<PdfSearchNotifier, PdfSearchState> search =
          pdfActiveSearchProvider;
      final Provider<ValueListenable<PdfSearchState>> highlights =
          pdfSearchHighlightsProvider;
      final Provider<PdfBackgroundLayerBuilder> builder =
          pdfBackgroundLayerBuilderProvider;
      final Provider<PdfFileSource> files = pdfFileSourceProvider;
      final Provider<PdfIncomingFileSource> incoming =
          pdfIncomingFileSourceProvider;
      final Provider<PdfOutputSink> sink = pdfOutputSinkProvider;
      final Provider<PdfInkVectorizer> vectorizer = pdfInkVectorizerProvider;
      final Provider<PdfComposeBackend> compose = pdfComposeBackendProvider;
      final Provider<PdfImportService> importService = pdfImportServiceProvider;
      final Provider<PdfExportService> exportService = pdfExportServiceProvider;
      final NotifierProvider<PdfImportJobNotifier, PdfJobState<PdfImportResult>>
      importJob = pdfImportJobProvider;
      final NotifierProvider<PdfExportJobNotifier, PdfJobState<PdfExportResult>>
      exportJob = pdfExportJobProvider;
      final NotifierProvider<PdfBatchExportJobNotifier, PdfBatchJobState>
      batchJob = pdfBatchExportJobProvider;
      expect([
        config,
        engine,
        gateway,
        pool,
        renderer,
        stats,
        text,
        search,
        highlights,
        builder,
        files,
        incoming,
        sink,
        vectorizer,
        compose,
        importService,
        exportService,
        importJob,
        exportJob,
        batchJob,
      ], everyElement(isNotNull));
    });
  });

  group('value types (const, contract defaults)', () {
    test('config (4.1)', () {
      const limits = PdfImportLimits();
      expect(limits.maxBytes, 300 * 1024 * 1024);
      expect(limits.warnBytes, 100 * 1024 * 1024);
      expect(limits.maxPages, 2000);
      expect(limits.maxPasswordAttempts, 5);

      // (2차, D22 — m5-7/06-pdf 6.2.10, contract 7.4.5) web preview 32 → 24 MiB.
      const web = PdfRenderBudget.web();
      expect(
        [web.previewBytes, web.tileBytes, web.thumbnailBytes],
        [24 * 1024 * 1024, 64 * 1024 * 1024, 16 * 1024 * 1024],
      );
      expect(web.totalBytes, 104 * 1024 * 1024);
      const native = PdfRenderBudget.native();
      expect(
        [native.previewBytes, native.tileBytes, native.thumbnailBytes],
        [64 * 1024 * 1024, 160 * 1024 * 1024, 32 * 1024 * 1024],
      );
      const custom = PdfRenderBudget(
        previewBytes: 1,
        tileBytes: 2,
        thumbnailBytes: 3,
      );
      expect(custom.totalBytes, 6);

      const config = PdfIoConfig();
      expect(config.pdfiumWasmModulesUrl, isNull);
      expect(
        config.composeExtensionUrl,
        'assets/packages/pdf_io/web/pdf_io_compose_ext.js',
      );
      expect(config.warmUpOnStart, isTrue);
      expect(config.limits, const PdfImportLimits());
      expect(config.renderBudget, isNull);
      expect(config.generateCoverThumbnail, isTrue);
      expect(
        config.userPasswordPolicy,
        PdfUserPasswordPolicy.storeDecryptedCopy,
      );
      // VM: no renderBudget → native() (web() on the web, test/web/).
      expect(config.effectiveRenderBudget, const PdfRenderBudget.native());
      expect(
        const PdfIoConfig(renderBudget: custom).effectiveRenderBudget,
        custom,
      );
    });

    test('render stats zero and tuning colors (4.7, 4.13)', () {
      const zero = PdfRenderStats.zero;
      expect([
        zero.previewBytes,
        zero.tileBytes,
        zero.thumbnailBytes,
        zero.liveImages,
        zero.queued,
        zero.inflight,
        zero.rendered,
        zero.cancelled,
        zero.openDocuments,
        zero.overBudgetBytes,
      ], everyElement(0));
      expect(zero.lastRenderMs, 0.0);
      expect(zero.p95RenderMs, 0.0);
      expect(PdfRenderSnapshot.loading.status, PdfRenderStatus.loading);
      expect(PdfRenderSnapshot.loading.tiles, isEmpty);
      expect(PdfTuning.searchHighlightArgb, 0x66FFC107);
      expect(PdfTuning.searchCurrentArgb, 0x99FF9800);
      expect(PdfTuning.searchCurrentOutlinePt, 1.5);
      expect(PdfTuning.maxInflightRenders, 2);
      expect(PdfTuning.defaultTitle, 'PDF 문서');
      expect(PdfComposeOpcodes.paintStride, 10);
      expect(
        [
          PdfComposeOpcodes.moveTo,
          PdfComposeOpcodes.lineTo,
          PdfComposeOpcodes.cubicTo,
          PdfComposeOpcodes.close,
          PdfComposeOpcodes.endObject,
        ],
        [0, 1, 2, 3, 7],
      );
      expect(PdfComposeOpcodes.fillModeEvenOdd, 1);
      expect(PdfComposeOpcodes.fillModeNonZero, 2);
    });

    test('other value types construct with the contract defaults', () {
      const exception = PdfIoException(PdfErrorCode.busy);
      expect(exception.detail, isNull);
      expect(exception.cause, isNull);
      const progress = PdfProgress(PdfJobPhase.composing);
      expect([progress.done, progress.total], [0, 0]);
      expect(progress.fraction, isNull);
      expect(
        const PdfProgress(PdfJobPhase.composing, done: 1, total: 4).fraction,
        0.25,
      );
      const batch = PdfBatchProgress(
        noteIndex: 1,
        noteCount: 4,
        current: PdfProgress(PdfJobPhase.composing, done: 1, total: 2),
      );
      expect(batch.fraction, (1 + 0.5) / 4);

      const page = PdfPageInfo(
        index: 0,
        width: 612,
        height: 792,
        rotationQuarterTurns: 0,
      );
      const info = PdfDocumentInfo(
        pages: [page],
        isEncrypted: false,
        usedPassword: false,
      );
      expect(info.pageCount, 1);
      const request = PdfRenderRequest(pageIndex: 0, scale: 1.5);
      expect(request.region, isNull);
      expect(request.backgroundArgb, 0xFFFFFFFF);
      expect(request.priority, PdfRenderPriority.normal);
      expect(request.fullPixelSize(page), (918, 1188));
      const pixels = PdfPixelRect(10, 20, 30, 40);
      expect([pixels.right, pixels.bottom], [40, 60]);
      expect(pixels.isEmpty, isFalse);
      expect(const PdfPixelRect(0, 0, 0, 5).isEmpty, isTrue);
      const text = PdfPageTextData(pageIndex: 0, text: '', charRects: []);
      const password = PdfPasswordRequest(fileName: 'a.pdf', attempt: 1);
      expect([text, password], everyElement(isNotNull));

      const picked = PickedPdfFile(name: 'a.pdf', readBytes: _bytes);
      expect(picked.sizeBytes, isNull);
      expect(picked.mimeType, isNull);
      final fromBytes = PickedPdfFile.fromBytes('b.pdf', Uint8List(3));
      expect(fromBytes.sizeBytes, 3);

      const target = PdfImportIntoNote(
        noteId: 'n1',
        position: core.PageAtEnd(),
      );
      expect(target.position, const core.PageAtEnd());
      const asNew = PdfImportAsNewNote();
      expect(asNew.folderId, isNull);
      expect(asNew.title, isNull);
      const result = PdfImportResult(
        noteId: 'n1',
        insertedPageIds: ['p1', 'p2'],
        assetId: 'a',
        sourcePageCount: 2,
        storedDecryptedCopy: false,
        createdNewNote: true,
      );
      expect(result.firstPageId, 'p1');

      const options = PdfExportOptions();
      expect(options.range, isA<PdfExportAllPages>());
      expect(options.includeInk, isTrue);
      expect(options.includeTemplates, isTrue);
      expect(options.missingAssetPolicy, PdfMissingAssetPolicy.blankPage);
      expect(options.fileName, isNull);
      final copy = options.copyWith(
        range: const PdfExportCurrentPage('p1'),
        includeInk: false,
      );
      expect(copy.range, isA<PdfExportCurrentPage>());
      expect(copy.includeInk, isFalse);
      expect(copy.includeTemplates, isTrue);

      final exported = PdfExportResult(
        bytes: Uint8List(4),
        fileName: 'a.pdf',
        pageCount: 1,
        elapsed: Duration.zero,
      );
      expect(exported.mimeType, 'application/pdf');
      expect(exported.warnings, isEmpty);
      final batchResult = PdfBatchExportResult(
        requestedCount: 3,
        items: [
          PdfBatchExportItem(noteId: 'n1', title: 'a', result: exported),
          const PdfBatchExportItem(
            noteId: 'n2',
            title: '',
            error: PdfIoException(PdfErrorCode.noteNotFound),
          ),
        ],
      );
      expect(batchResult.files, [same(exported)]);
      expect(batchResult.notReachedCount, 1);
      expect(batchResult.items.first.succeeded, isTrue);
      expect(batchResult.items.last.succeeded, isFalse);
      expect(batchResult.cancelled, isFalse);
      expect(batchResult.stoppedAtSizeLimit, isFalse);

      expect(PdfPageVectors.empty.isEmpty, isTrue);
      expect(const PdfSearchState(noteId: 'n1').status, PdfSearchStatus.idle);
      expect(PdfSearchState.idle.currentIndex, -1);
      expect(PdfSearchState.idle.current, isNull);
      const fixture = PdfFixturePage();
      expect([fixture.width, fixture.height], [595.2756, 841.8898]);
      expect(const PdfFixtureText('a').size, 18);
    });
  });

  group('2차 surface (m5-7/06-pdf 4.1, T20)', () {
    test('18 new barrel names; src-only names stay out', () {
      expect(barrelNamesV2, hasLength(18));
      final names = <String>{
        for (final (_, shown) in _exports(_read('lib/pdf_io.dart'))) ...?shown,
      };
      expect(names.containsAll(barrelNamesV2), isTrue);
      expect(names.intersection(srcOnlyNamesV2), isEmpty);
      // The indexer file is exported for the class only; the gate file not at all.
      final indexerExports = [
        for (final (uri, shown) in _exports(_read('lib/pdf_io.dart')))
          if (uri.startsWith('src/search_index/')) (uri, shown),
      ];
      expect(indexerExports, hasLength(1));
      expect(
        indexerExports.single.$1,
        'src/search_index/pdf_search_indexer.dart',
      );
      expect(indexerExports.single.$2, {'PdfSearchIndexer'});
    });

    test(
      'PdfSearchIndexer: one public constructor (NoteStore), start, dispose',
      () {
        final PdfSearchIndexer Function(core.NoteStore store) ctor =
            PdfSearchIndexer.new;
        final Provider<PdfSearchIndexer> provider = pdfSearchIndexerProvider;
        expect([ctor, provider], everyElement(isNotNull));
        final source = _read('lib/src/search_index/pdf_search_indexer.dart');
        final body = source.substring(
          source.indexOf('final class PdfSearchIndexer {'),
          source.indexOf('\nPdfSearchIndexer createPdfSearchIndexer('),
        );
        // Constructors of the class: the contract one and the private one only.
        final ctors = RegExp(
          r'^  PdfSearchIndexer(\.\w+)?\(',
          multiLine: true,
        ).allMatches(body).map((m) => m.group(1) ?? '').toList();
        expect(ctors, ['', '._']);
        expect(body, contains('  PdfSearchIndexer(core.NoteStore store)\n'));
        // Public members: start and dispose only.
        final members = RegExp(
          r'^  (?:[\w<>?]+ )+([a-z]\w*)(?:\(| =>|;| =)',
          multiLine: true,
        ).allMatches(body).map((m) => m.group(1)!).toSet();
        expect(members, {'start', 'dispose'});
      },
    );

    test('plan item shapes (4.1.3)', () {
      const frame = core.ElementFrame(core.PageRect(10, 20, 110, 70));
      const affine = PdfAffine(1, 0, 0, 1, 5, 6);
      final double a = affine.a, b = affine.b, c = affine.c;
      final double d = affine.d, e = affine.e, f = affine.f;
      final PdfAffine Function(core.ElementFrame frame) fromFrame =
          PdfAffine.frame;
      final PdfAffine Function(PdfAffine outer) then = affine.then;
      final ui.Offset Function(ui.Offset p) apply = affine.apply;
      expect([a, b, c, d, e, f], [1, 0, 0, 1, 5, 6]);
      expect([fromFrame, then, apply], everyElement(isNotNull));
      const id = PdfAffine.identity;
      expect([id.a, id.b, id.c, id.d, id.e, id.f], [1, 0, 0, 1, 0, 0]);

      final jpeg = PdfJpegData(Uint8List(4), width: 2, height: 1);
      final rgba = PdfRgbaData(
        Uint8List(8),
        width: 2,
        height: 1,
        hasAlpha: true,
      );
      final PdfImageData data = jpeg;
      expect([data.width, data.height, data.byteLength], [2, 1, 4]);
      expect([rgba.byteLength, rgba.hasAlpha], [8, true]);
      final Uint8List bytes = jpeg.bytes, pixels = rgba.rgba;
      expect([bytes, pixels], everyElement(isNotNull));

      final image = PdfImageItem(image: jpeg, matrix: affine);
      const text = PdfTextItem(
        text: '안녕',
        fontId: 0,
        fontSize: 16,
        colorArgb: 0xFF1A1A1A,
        matrix: PdfAffine.identity,
      );
      final PdfDrawItem drawn = image;
      final PdfPlanItem planned = text;
      expect([drawn, planned], everyElement(isNotNull));
      expect(_drawItem(image), 'image');
      expect(_drawItem(text), 'text');
      expect(
        _drawItem(
          PdfFillItem(path: PdfVectorPath.rect(ui.Rect.zero), colorArgb: 0),
        ),
        'vector',
      );
      expect(_imageData(jpeg), 'jpeg');
      expect(_imageData(rgba), 'rgba');

      const objectRef = PdfAssetImageRef.object(
        assetId: _assetId,
        frame: frame,
      );
      const backgroundRef = PdfAssetImageRef.background(
        assetId: _assetId,
        fit: core.ImageFit.cover,
        pageSize: ui.Size(595, 842),
      );
      expect(
        [objectRef.frame, objectRef.fit, objectRef.pageSize],
        [frame, null, null],
      );
      expect(
        [backgroundRef.frame, backgroundRef.fit, backgroundRef.pageSize],
        [null, core.ImageFit.cover, const ui.Size(595, 842)],
      );
      final textBox = core_testing.PageObjectFixtures.textBox(pageId: 'p1');
      const PdfTextLine line = (text: 'a', x: 0, baselineY: 16, width: 10);
      final textRef = PdfTextBoxRef(textBox, const [line]);
      final mathRef = PdfMathRef(
        core_testing.PageObjectFixtures.math(pageId: 'p1'),
      );
      final core.TextBoxObject object = textRef.object;
      final List<PdfTextLine> lines = textRef.lines;
      final core.MathObject math = mathRef.object;
      expect([object, lines, math], everyElement(isNotNull));
      expect(
        [_planItem(objectRef), _planItem(textRef), _planItem(mathRef)],
        ['imageRef', 'textRef', 'mathRef'],
      );
      expect(_planItem(image), 'draw');

      const empty = PdfPagePlan.empty;
      final List<PdfPlanItem> items = empty.items;
      expect(
        [items.isEmpty, empty.isEmpty, empty.hasReferences],
        [true, true, false],
      );
      final plan = PdfPagePlan([text, objectRef]);
      expect([plan.isEmpty, plan.hasReferences], [false, true]);
      expect(PdfPagePlan([text]).hasReferences, isFalse);
    });

    test('export warnings v2 (4.1.5)', () {
      const missing = PdfExportMissingImages([2]);
      const raster = PdfExportRasterizedText([3]);
      const formulas = PdfExportSkippedFormulas([4, 5]);
      final List<int> pages = missing.notePageNumbers;
      expect(pages, [2]);
      expect(raster.notePageNumbers, [3]);
      expect(formulas.notePageNumbers, [4, 5]);
      expect(
        [_warning(missing), _warning(raster), _warning(formulas)],
        ['missingImages', 'rasterizedText', 'skippedFormulas'],
      );
    });

    test('PdfInkVectorizer.planPage shape (2차)', () {
      final PdfPagePlan Function(
        core.PageContent content, {
        required bool includeInk,
        required bool includeTemplate,
      })
      plan = const InkEngineVectorizer().planPage;
      final PdfPagePlan Function(
        core.PageContent content, {
        required bool includeInk,
        required bool includeTemplate,
      })
      box = const BoxInkVectorizer().planPage;
      expect([plan, box], everyElement(isNotNull));
    });

    test('R2-B4 body: start() does nothing, dispose() idempotent', () async {
      final store = core_testing.createFakeNoteStore();
      addTearDown(store.close);
      final indexer = PdfSearchIndexer(store);
      indexer.start();
      indexer.start();
      await indexer.dispose();
      await indexer.dispose();
      indexer.start(); // after dispose: nothing
      await expectLater(indexer.dispose(), completes);
    });
  });

  group('B4 bodies (contract 7.6 B4)', () {
    // importPdfAsNewNote is the real flow from PDF T6 (widget/import_flow_test.dart),
    // exportNotesAsPdf from T15b (widget/batch_export_flow_test.dart), initializePdfIo
    // and the menu functions from T17 (unit/init_test.dart, widget/menu_actions_test.dart).

    test('platform factories on the VM', () async {
      expect(createPlatformOutputSink().availableActions(const []), isEmpty);
      // dart:ffi is available on the VM → the native FFI backend (PDF T13); creating it
      // starts nothing (pdfrx is touched on the first begin).
      final compose = createPlatformComposeBackend(const PdfIoConfig());
      expect(compose.isSupported, isTrue);
      await compose.dispose();
      expect(const NoIncomingPdfFiles().incoming, emitsDone);
    });
  });
}
