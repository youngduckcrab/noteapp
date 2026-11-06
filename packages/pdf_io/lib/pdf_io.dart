/// PDF import, PDF page background rendering and PDF export.
///
/// Owned by PDF (docs/plans/06-pdf.md, 2차 docs/plans/m5-7/06-pdf.md). Public
/// API = contract 00-overview 7.2.19 (06-pdf 4.0–4.13) and 2차 contract 7.2.12
/// (m5-7/06-pdf 4.0–4.1). This `show` list is the complete list of exported
/// names (06-pdf 4.15 + m5-7/06-pdf 4.1.6, checked by
/// test/contract/api_surface_test.dart; integration check R14 compares it with
/// the other packages). Everything else under `src/` is internal. Web-safe.
library;

export 'src/common/cancel_signal.dart' show PdfCancelSignal;
export 'src/common/job_state.dart'
    show PdfJobState, PdfJobIdle, PdfJobRunning, PdfJobSucceeded, PdfJobFailed;
export 'src/common/progress.dart'
    show
        PdfJobPhase,
        PdfProgress,
        PdfProgressCallback,
        PdfBatchProgress,
        PdfBatchProgressCallback;
export 'src/compose/compose_backend.dart' show PdfComposeJob, PdfComposeBackend;
export 'src/compose/compose_backend_factory.dart'
    show createPlatformComposeBackend;
export 'src/config.dart'
    show PdfImportLimits, PdfRenderBudget, PdfUserPasswordPolicy, PdfIoConfig;
export 'src/engine/page_info.dart'
    show
        PdfPageInfo,
        PdfDocumentInfo,
        PdfPasswordRequest,
        PdfPasswordCallback,
        PdfRenderPriority,
        PdfRenderCancelToken,
        PdfPixelRect,
        PdfRenderRequest,
        PdfPageTextData;
export 'src/engine/pdf_engine.dart' show PdfEngine, PdfEngineDocument;
export 'src/engine/pdfrx_engine.dart' show PdfrxEngine;
export 'src/errors.dart' show PdfErrorCode, PdfIoException;
export 'src/export/batch_export.dart'
    show PdfBatchExportItem, PdfBatchExportResult;
export 'src/export/compose_encoder.dart' show PdfComposeEncoder;
export 'src/export/compose_plan.dart'
    show
        PdfComposeSource,
        PdfComposePagePlan,
        PdfComposeSourcePage,
        PdfComposeBlankPage,
        PdfComposePlan,
        PdfComposePageOps,
        PdfComposeOpcodes;
export 'src/export/export_service.dart'
    show PdfExportService, DefaultPdfExportService;
export 'src/export/export_types.dart'
    show
        PdfExportRange,
        PdfExportAllPages,
        PdfExportCurrentPage,
        PdfExportSelectedPages,
        PdfMissingAssetPolicy,
        PdfExportOptions,
        PdfExportWarning,
        PdfExportBlankedMissingAsset,
        PdfExportMissingImages,
        PdfExportRasterizedText,
        PdfExportSkippedFormulas,
        PdfExportResult;
export 'src/export/vectors.dart'
    show
        PdfBlend,
        PdfFillRule,
        PdfLineCap,
        PdfLineJoin,
        PdfVectorPath,
        PdfPlanItem,
        PdfDrawItem,
        PdfVectorItem,
        PdfFillItem,
        PdfStrokeItem,
        PdfPageVectors,
        PdfAffine,
        PdfImageData,
        PdfJpegData,
        PdfRgbaData,
        PdfImageItem,
        PdfTextItem,
        PdfAssetImageRef,
        PdfTextLine,
        PdfTextBoxRef,
        PdfMathRef,
        PdfPagePlan,
        PdfInkVectorizer;
export 'src/files/pdf_file_source.dart'
    show
        PickedPdfFile,
        PdfFileSource,
        FilePickerPdfSource,
        PdfIncomingFileSource,
        NoIncomingPdfFiles;
export 'src/gateway/core_note_gateway.dart' show CorePdfNoteGateway;
export 'src/gateway/pdf_note_gateway.dart' show PdfNoteGateway;
export 'src/import/import_service.dart'
    show PdfImportService, PdfImportSession, DefaultPdfImportService;
export 'src/import/import_types.dart'
    show
        PdfImportTarget,
        PdfImportAsNewNote,
        PdfImportIntoNote,
        PdfImportResult;
export 'src/init.dart' show initializePdfIo, pdfIoOverrides;
export 'src/ink_adapter/ink_background_builder.dart'
    show PdfBackgroundLayerBuilder;
export 'src/ink_adapter/ink_vectorizer.dart' show InkEngineVectorizer;
export 'src/model/file_naming.dart' show PdfFileNaming;
export 'src/model/page_range.dart' show PdfPageRange;
export 'src/model/page_size_policy.dart' show PdfPageSizePolicy, PdfPageFit;
export 'src/output/output_sink_factory.dart' show createPlatformOutputSink;
export 'src/output/pdf_output_sink.dart'
    show PdfOutputAction, PdfOutputOutcome, PdfOutputSink;
export 'src/providers.dart'
    show
        pdfIoConfigProvider,
        pdfEngineProvider,
        pdfNoteGatewayProvider,
        pdfDocumentPoolProvider,
        pdfPageRendererProvider,
        pdfRenderStatsProvider,
        pdfTextServiceProvider,
        pdfActiveSearchProvider,
        pdfSearchHighlightsProvider,
        pdfBackgroundLayerBuilderProvider,
        pdfFileSourceProvider,
        pdfIncomingFileSourceProvider,
        pdfOutputSinkProvider,
        pdfInkVectorizerProvider,
        pdfSearchIndexerProvider,
        pdfComposeBackendProvider,
        pdfImportServiceProvider,
        pdfExportServiceProvider,
        pdfImportJobProvider,
        pdfExportJobProvider,
        pdfBatchExportJobProvider,
        PdfImportJobNotifier,
        PdfExportJobNotifier,
        PdfBatchJobState,
        PdfBatchJobIdle,
        PdfBatchJobRunning,
        PdfBatchJobFinished,
        PdfBatchJobFailed,
        PdfBatchExportJobNotifier;
export 'src/render/document_pool.dart'
    show PdfDocumentLease, PdfDocumentPool, DefaultPdfDocumentPool;
export 'src/render/page_background_view.dart' show PdfPageBackgroundView;
export 'src/render/render_service.dart'
    show
        PdfBackgroundParams,
        PdfRenderStatus,
        PdfPlacedImage,
        PdfRenderSnapshot,
        PdfRenderStats,
        PdfPageRenderHandle,
        PdfPageRenderer,
        PdfRenderService;
export 'src/search_index/pdf_search_indexer.dart' show PdfSearchIndexer;
export 'src/text/search_notifier.dart' show PdfSearchNotifier;
export 'src/text/search_types.dart'
    show PdfSearchHit, PdfSearchStatus, PdfSearchState, PdfSearchProgress;
export 'src/text/text_normalizer.dart'
    show PdfNormalizedText, PdfTextNormalizer;
export 'src/text/text_service.dart' show PdfTextService, DefaultPdfTextService;
export 'src/tuning.dart' show PdfTuning;
export 'src/ui/flows.dart'
    show
        PdfNavigateCallback,
        PdfExportPurpose,
        runPdfImportFlow,
        importPdfAsNewNote,
        runPdfExportFlow,
        exportNotesAsPdf,
        showPdfSearchPanel;
export 'src/ui/menu_actions.dart'
    show
        PdfMenuInvocation,
        PdfMenuAction,
        pdfEditorMoreMenuActions,
        pdfEditorAddPageSources;
