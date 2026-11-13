/// Handwriting and math recognition (web-safe entry point — ML Kit only
/// behind `*_native.dart`).
///
/// Owned by LIBRARY (docs/plans/m5-7/05-library.md). Public API = contract
/// m5-7/00-overview 7.2.11 (05-library 4.2 export list); everything under
/// `src/` is private. Since the 2차 foundation step R2-B6.
library;

// lib/ink_recognition.dart — web-safe entry. Exactly these names (R14 — checked again at R2-B6).
export 'src/actions/recognition_actions.dart'
    show
        RecognitionTarget,
        RecognitionAction,
        recognitionSelectionActions,
        recognitionInsertActions;
export 'src/indexer/handwriting_indexer.dart' show HandwritingIndexer;
export 'src/indexer/indexer_status.dart'
    show HandwritingIndexerStatus, HandwritingIndexerPhase;
// (handwriting search — m5-7/05-library 6.19a) for the library's search hint.
export 'src/indexer/search_readiness.dart'
    show
        HandwritingSearchPhase,
        HandwritingSearchStatus,
        HandwritingSearchReadiness,
        handwritingSearchReadinessProvider;
export 'src/lines/group_into_lines.dart' show groupIntoLines;
// (math pen, phase 1 — docs/plans/m5-7/research/math-pen-phase1.md 11.1)
export 'src/math_pen/math_pen.dart'
    show
        RecognitionMathPen,
        RecognitionMathPenContext,
        RecognitionMathPenSession,
        recognitionMathPen;
export 'src/model/candidates.dart' show TextCandidate, RecognitionModelState;
export 'src/model/failures.dart'
    show
        RecognitionFailure,
        RecognizerUnsupported,
        ModelNotReady,
        RecognizerOffline,
        RecognizerQuotaExceeded,
        RecognizerCancelled,
        RecognizerConsentRequired,
        RecognizerEngineError;
export 'src/model/handwriting_trace.dart'
    show HandwritingTrace, HandwritingLineInput;
export 'src/model/math_types.dart' show MathInput, MathResult;
export 'src/ports/handwriting_recognizer.dart'
    show HandwritingRecognizer, UnsupportedHandwritingRecognizer;
export 'src/ports/math_recognizer.dart'
    show MathRecognizer, ManualOnlyMathRecognizer;
export 'src/providers.dart'
    show
        handwritingRecognizerProvider,
        mathRecognizerProvider,
        RecognitionConfig,
        recognitionOverrides,
        handwritingIndexerProvider,
        recognitionDevOverlayLinesProvider;
export 'src/settings/recognition_settings_section.dart'
    show RecognitionSettingsSection;
export 'src/shapes/geometric_shape_fitter.dart' show GeometricShapeFitter;
export 'src/shapes/shape_fit_tuning.dart' show ShapeFitTuning;
