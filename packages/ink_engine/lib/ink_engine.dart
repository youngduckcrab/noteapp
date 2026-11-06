/// Ink engine: stroke building and rendering, pens, erasers, lasso
/// geometry, page templates and thumbnails; (v2.0) page objects, playback
/// emphasis, memorization tape, shape assist port, formulas and the text box
/// font.
///
/// Owned by INK (docs/plans/03-ink.md, docs/plans/m5-7/03-ink.md). Public API
/// = contract 00-overview 7.2.15 / 7.2.16 and 2nd round contract 7.2.9 (INK
/// 4.0); this `show` list is the complete list of exported names (checked by
/// test/unit/export_list_test.dart). Everything else under `src/` is
/// internal.
library;

export 'src/background/background_builder.dart'
    show
        PageBackgroundContext,
        PageBackgroundLayerBuilder,
        PageBackgroundStillRenderer;
export 'src/background/background_spec.dart'
    show InkBackgroundSpec, InkBackgroundKind;
export 'src/background/image_builder.dart' show ImageBackgroundLayerBuilder;
export 'src/background/template_builder.dart'
    show TemplateBackgroundLayerBuilder;
export 'src/background/template_vectors.dart'
    show TemplateVectors, TemplateVectorItem, TemplateLine, TemplateDot;
export 'src/diagnostics/diagnostics.dart'
    show InkDiagnostics, InkStatsSnapshot, LatencySummary;
export 'src/diagnostics/ink_clock.dart' show InkClock;
export 'src/edit/eraser_spec.dart' show EraserSpec, EraserMode;
export 'src/edit/ink_edit.dart' show InkEdit, InkEditKind;
export 'src/edit/lasso_options.dart' show LassoOptions;
export 'src/edit/selection_geometry.dart'
    show SelectionGeometry, SelectionHandle;
export 'src/export/vector_export.dart'
    show
        InkVectorExport,
        InkPageVectors,
        InkHighlighterGroup,
        InkHighlighterLine,
        InkFillShape,
        InkExportOptions,
        InkBlendMode,
        InkImageVector,
        InkAnnotationVector,
        InkTextVector,
        InkTextLine,
        InkMathVector;
export 'src/geometry/vector_path.dart' show InkVectorPath, InkPathVerb;
export 'src/image/image_cache.dart' show InkImageCache;
export 'src/input/ink_sample.dart' show InkSample, InkPointerKind;
export 'src/input/predictor.dart' show InkPredictor, NoopPredictor;
export 'src/input/pressure_capability.dart'
    show
        PressureCapability,
        PressureSource,
        PressureCapabilityState,
        PressureCapabilityStore,
        PressureCapabilityNotifier;
export 'src/input/pressure_mode.dart' show PressureMode, PressureModeNotifier;
export 'src/input/sample_adapter.dart' show InkSampleAdapter;
export 'src/math/math_preview.dart' show MathPreview;
export 'src/math/math_renderer.dart' show InkMathRenderer, InkMathLayout;
export 'src/model/ink_layer.dart' show InkLayer;
export 'src/model/ink_points.dart' show InkPoints;
export 'src/model/ink_stroke.dart' show InkStroke;
export 'src/pen/pen_profile.dart' show PenProfile, InkCap, InkRenderMethod;
export 'src/pen/style_ink.dart'
    show StrokeStyleInk, InkStyleExtras, HighlighterStraightening, InkTapeStyle;
export 'src/providers.dart'
    show
        inkRenderConfigProvider,
        inkClockProvider,
        pressureModeProvider,
        pressureCapabilityProvider,
        inkCoreServicesProvider,
        inkCachePoolProvider,
        inkDiagnosticsProvider,
        pencilGrainProvider,
        pageBackgroundBuildersProvider,
        inkPageControllerProvider,
        inkPageThumbnailRendererProvider,
        inkShapeFitterProvider,
        inkImageCacheProvider,
        defaultPageBackgroundBuilders;
export 'src/render/cache_pool.dart' show InkCachePool, InkCacheStats;
export 'src/render/ink_page_content.dart' show InkPageContent;
export 'src/render/ink_page_controller.dart'
    show InkPageController, InkCoreServices, InkRenderLayer, InkPageRenderStats;
export 'src/render/ink_page_view.dart' show InkPageView, InkPageGeometry;
export 'src/render/pen_preview.dart' show PenPreviewPainter, PenPreviewShape;
export 'src/render/pencil_grain.dart' show PencilGrain;
export 'src/render/playback.dart' show InkPlaybackFocus, InkPlaybackStyle;
export 'src/render/render_config.dart' show InkRenderConfig;
export 'src/render/selection.dart' show InkSelection;
export 'src/render/sessions.dart'
    show
        InkGestureSession,
        StrokeSession,
        EraserSession,
        LassoSession,
        LiveStrokeGeometry;
export 'src/render/thumbnail.dart' show InkPageThumbnail;
export 'src/render/thumbnail_renderer.dart' show InkPageThumbnailRenderer;
export 'src/shape/shape_assist.dart'
    show ShapeAssist, InkShapeFitter, InkShapeFit, NoShapeFitter;
export 'src/stroke/stroke_meta.dart' show InkStrokeMeta;
export 'src/text/fonts.dart' show InkFonts;
export 'src/text/text_layout.dart' show InkTextLayout;
export 'src/tuning.dart' show InkTuning;
