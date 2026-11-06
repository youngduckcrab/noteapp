// lib/src/engines/mlkit_errors.dart — (internal) ML Kit plugin errors →
// RecognitionFailure (m5-7/05-library 6.7.3). Pure functions: no ML Kit
// import (the plugin's errors are flutter/services PlatformException /
// MissingPluginException), so the table is tested on the VM and the web.
//
// The codes are the plugin's own (google_mlkit_digital_ink_recognition
// 0.16.1 DigitalInkRecognizer.kt / GoogleMlKitDigitalInkRecognitionPlugin
// .swift, google_mlkit_commons 0.13.0 GenericModelManager.kt / .swift):
//
// | plugin                                                  | failure |
// |---------------------------------------------------------|---------|
// | 'Model Error' / 'Error Model has not been downloaded yet' (message 'not been downloaded') | ModelNotReady(tag) |
// | 'Failed to create model identifier', 'Model Identifier error', 'invalid_model' | RecognizerEngineError('unsupported-language', message) |
// | 'Model download check failed' (Android — the check Task failed) | RecognizerEngineError('model-check-failed', message) |
// | 'recognition Error' (Android), 'Error <n>' (iOS NSError code) | RecognizerEngineError(code, message) |
// | 'download_in_progress', 'cancelled' (iOS model manager) | RecognizerEngineError('download-in-progress', message) — ensureModel waits instead (isDownloadElsewhere) |
// | MissingPluginException (no plugin: web app, desktop)    | RecognizerUnsupported() |
// | a RecognitionFailure                                    | itself |
// | anything else                                           | RecognizerEngineError('unknown', '$e') |
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;

import '../model/failures.dart';

/// Plugin codes of an invalid language tag (Android: model identifier,
/// iOS: invalid_model).
const Set<String> _unsupportedLanguageCodes = {
  'Failed to create model identifier',
  'Model Identifier error',
  'invalid_model',
};

/// The iOS model manager answers a download it does not track itself:
/// another download of the model is running ('download_in_progress'), or the
/// plugin replaced its manager while this download waited ('cancelled' — the
/// plugin makes a new GenericModelManager for every vision#manageInkModels
/// call, and the old one cancels its pending results; ML Kit keeps
/// downloading).
const Set<String> _downloadElsewhereCodes = {
  'download_in_progress',
  'cancelled',
};

/// iOS recognition errors are 'Error' + the NSError code ('Error 3').
final RegExp _iosRecognitionCode = RegExp(r'^Error -?\d+$');

/// The text of a plugin error for the failure's message: message, else
/// details, else the code.
String _messageOf(PlatformException e) {
  final message = e.message;
  if (message != null && message.isNotEmpty) return message;
  final details = e.details;
  if (details is String && details.isNotEmpty) return details;
  return e.code;
}

/// Whether [error] says the model has not been downloaded (both platforms
/// put 'not been downloaded' in the code or the message).
bool _isModelNotDownloaded(PlatformException e) =>
    e.code.contains('not been downloaded') ||
    (e.message ?? '').contains('not been downloaded') ||
    e.code == 'Model Error';

/// Whether [error] is an invalid language tag (6.7.3) — modelState answers
/// [RecognitionModelState.unsupported] for it.
bool isUnsupportedLanguageError(Object error) =>
    error is PlatformException &&
    _unsupportedLanguageCodes.contains(error.code);

/// Whether [error] is the iOS model manager's 'another download / replaced
/// manager' answer — ensureModel then waits for the model instead of failing
/// (6.7.3 'iOS 같은 모델 받는 중').
bool isDownloadElsewhere(Object error) =>
    error is PlatformException && _downloadElsewhereCodes.contains(error.code);

/// [error] from the ML Kit plugin as the failure the UI and the indexer
/// handle (6.7.3). [languageTag] names the model of [ModelNotReady].
RecognitionFailure mlkitFailureOf(Object error, {required String languageTag}) {
  if (error is RecognitionFailure) return error;
  if (error is MissingPluginException) return RecognizerUnsupported();
  if (error is PlatformException) {
    final code = error.code;
    if (_unsupportedLanguageCodes.contains(code)) {
      return RecognizerEngineError('unsupported-language', _messageOf(error));
    }
    if (code == 'Model download check failed') {
      return RecognizerEngineError('model-check-failed', _messageOf(error));
    }
    if (_isModelNotDownloaded(error)) return ModelNotReady(languageTag);
    if (_downloadElsewhereCodes.contains(code)) {
      return RecognizerEngineError('download-in-progress', _messageOf(error));
    }
    if (code == 'recognition Error' || _iosRecognitionCode.hasMatch(code)) {
      return RecognizerEngineError(code, _messageOf(error));
    }
  }
  return RecognizerEngineError('unknown', '$error');
}
