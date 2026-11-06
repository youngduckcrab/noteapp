// lib/src/model/failures.dart — contract m5-7/00-overview 7.2.11
// (m5-7/05-library 4.2, 6.22). Final since the 2차 foundation step R2-B6.
//
// Every engine failure the recognition UI and the indexer handle. The
// declarations are the contract's (no const constructors); toString only adds
// the short English form used in reports and the developer overlay.

sealed class RecognitionFailure implements Exception {}

/// web + ML Kit, manual-only math
final class RecognizerUnsupported extends RecognitionFailure {
  @override
  String toString() => 'RecognizerUnsupported';
}

final class ModelNotReady extends RecognitionFailure {
  ModelNotReady(this.languageTag);
  final String languageTag;

  @override
  String toString() => 'ModelNotReady($languageTag)';
}

final class RecognizerOffline extends RecognitionFailure {
  @override
  String toString() => 'RecognizerOffline';
}

final class RecognizerQuotaExceeded extends RecognitionFailure {
  @override
  String toString() => 'RecognizerQuotaExceeded';
}

final class RecognizerCancelled extends RecognitionFailure {
  @override
  String toString() => 'RecognizerCancelled';
}

/// math engine before recog.mathConsent (G-3)
final class RecognizerConsentRequired extends RecognitionFailure {
  @override
  String toString() => 'RecognizerConsentRequired';
}

final class RecognizerEngineError extends RecognitionFailure {
  RecognizerEngineError(this.code, this.message);
  final String code, message;

  @override
  String toString() => 'RecognizerEngineError($code: $message)';
}
