// lib/src/ports/handwriting_recognizer.dart — contract m5-7/00-overview
// 7.2.11 (m5-7/05-library 4.2, 4.4.2). Final since the 2차 foundation step
// R2-B6.
//
// The handwriting engine port and its default: UnsupportedHandwritingRecognizer
// is handwritingRecognizerProvider's value without recognitionOverrides()
// (FEATURE_RECOGNITION=false builds, tests) and the web / desktop engine.
import '../model/candidates.dart';
import '../model/failures.dart';
import '../model/handwriting_trace.dart';

abstract interface class HandwritingRecognizer {
  /// 'mlkit-digital-ink/19.0.0', 'fake'
  String get engineId;

  /// false on web
  bool get isAvailable;
  Future<RecognitionModelState> modelState(String languageTag);

  /// (v2.1) Android honours wifiOnly (the download waits for Wi-Fi); the iOS plugin ignores it —
  /// on iOS the app asks before downloading (two-press warning, 05-library Q2).
  Future<void> ensureModel(String languageTag, {bool wifiOnly = true});
  Future<List<TextCandidate>> recognizeLine(
    HandwritingLineInput line, {
    required String languageTag,
  });
  Future<void> dispose();
}

/// No handwriting engine (web, desktop, recognition switched off): every
/// model is [RecognitionModelState.unsupported], and ensureModel /
/// recognizeLine throw [RecognizerUnsupported] (05-library 4.4.2).
final class UnsupportedHandwritingRecognizer implements HandwritingRecognizer {
  const UnsupportedHandwritingRecognizer();

  @override
  String get engineId => 'unsupported';

  @override
  bool get isAvailable => false;

  @override
  Future<RecognitionModelState> modelState(String languageTag) async =>
      RecognitionModelState.unsupported;

  @override
  Future<void> ensureModel(String languageTag, {bool wifiOnly = true}) async =>
      throw RecognizerUnsupported();

  @override
  Future<List<TextCandidate>> recognizeLine(
    HandwritingLineInput line, {
    required String languageTag,
  }) async => throw RecognizerUnsupported();

  /// Completes; nothing else (there is nothing to release).
  @override
  Future<void> dispose() async {}
}
