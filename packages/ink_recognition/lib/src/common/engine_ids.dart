// lib/src/common/engine_ids.dart — (internal, v2.1) every engine id string in
// one place (m5-7/05-library 6.7.2). The ML Kit ids name the native SDK the
// plugin google_mlkit_digital_ink_recognition 0.16.1 ships (Android
// com.google.mlkit:digital-ink-recognition 19.0.0, iOS GoogleMLKit/
// DigitalInkRecognition 9.0.0): bump them together with the plugin (README).
// Provenance only — the indexer's freshness ignores the engine id (6.9.3).

/// HandwritingText.engineId prefix of ML Kit results on Android.
const String kMlKitAndroidEngineId = 'mlkit-digital-ink/19.0.0';

/// HandwritingText.engineId prefix of ML Kit results on iOS.
const String kMlKitIosEngineId = 'mlkit-digital-ink-ios/9.0.0';

/// UnsupportedHandwritingRecognizer (4.4.2).
const String kUnsupportedEngineId = 'unsupported';

/// ManualOnlyMathRecognizer, and the MathObject.engineId of LaTeX typed or
/// edited by hand (6.14.6, 6.15.1).
const String kManualMathEngineId = 'manual';

/// CallableMathRecognizer before an answer names its engine (6.11.2).
const String kCallableMathEngineId = 'callable';

/// OnDeviceMathRecognizer: the on-device math model and its file set
/// (ondevice/math_model_manifest.dart — bump both with a new model).
const String kOnDeviceMathEngineId = 'pix2text-mfr/1.5-int8pc';
