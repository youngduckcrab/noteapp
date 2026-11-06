// mlkit_errors.dart (m5-7/05-library 8.2 L2-08, 6.7.3): every row of the
// plugin error table — the codes and messages the plugin's Kotlin / Swift
// sources send (google_mlkit_digital_ink_recognition 0.16.1,
// google_mlkit_commons 0.13.0).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/engines/mlkit_errors.dart';

RecognitionFailure _of(Object error) =>
    mlkitFailureOf(error, languageTag: 'ko');

Matcher _engineError(String code, String message) =>
    isA<RecognizerEngineError>()
        .having((e) => e.code, 'code', code)
        .having((e) => e.message, 'message', message);

void main() {
  group('model not downloaded → ModelNotReady(tag)', () {
    test('Android: Model Error / Model has not been downloaded yet', () {
      final f = _of(
        PlatformException(
          code: 'Model Error',
          message: 'Model has not been downloaded yet',
        ),
      );
      expect(f, isA<ModelNotReady>());
      expect((f as ModelNotReady).languageTag, 'ko');
    });

    test('iOS: Error Model has not been downloaded yet', () {
      final f = mlkitFailureOf(
        PlatformException(
          code: 'Error Model has not been downloaded yet',
          message: 'Model has not been downloaded yet',
          details: 'Model has not been downloaded yet',
        ),
        languageTag: 'en',
      );
      expect(f, isA<ModelNotReady>());
      expect((f as ModelNotReady).languageTag, 'en');
    });
  });

  group('invalid language tag → unsupported-language', () {
    for (final (code, message) in [
      (
        'Failed to create model identifier',
        'com.google.mlkit.common.MlKitException: bad tag',
      ),
      ('Model Identifier error', 'No model was found'),
      ('invalid_model', 'Invalid language tag: xx-zz'),
    ]) {
      test(code, () {
        final e = PlatformException(code: code, message: message);
        expect(_of(e), _engineError('unsupported-language', message));
        expect(isUnsupportedLanguageError(e), isTrue);
      });
    }

    test('other codes are not an invalid tag', () {
      expect(
        isUnsupportedLanguageError(
          PlatformException(code: 'recognition Error'),
        ),
        isFalse,
      );
      expect(isUnsupportedLanguageError(StateError('x')), isFalse);
    });
  });

  test('(v2.1, S-14) Model download check failed → model-check-failed', () {
    expect(
      _of(
        PlatformException(
          code: 'Model download check failed',
          message: 'java.lang.Exception: no network',
        ),
      ),
      _engineError('model-check-failed', 'java.lang.Exception: no network'),
    );
  });

  group('recognition failures keep the plugin code', () {
    test('Android: recognition Error', () {
      expect(
        _of(
          PlatformException(
            code: 'recognition Error',
            message: 'MlKitException: internal',
          ),
        ),
        _engineError('recognition Error', 'MlKitException: internal'),
      );
    });

    test('iOS: Error <NSError code> (domain as message)', () {
      expect(
        _of(
          PlatformException(
            code: 'Error 3',
            message: 'com.google.mlkit',
            details: 'The operation failed.',
          ),
        ),
        _engineError('Error 3', 'com.google.mlkit'),
      );
      expect(
        _of(PlatformException(code: 'Error -1', details: 'negative code')),
        _engineError('Error -1', 'negative code'),
      );
    });
  });

  group('iOS model manager: a download it does not track', () {
    for (final code in ['download_in_progress', 'cancelled']) {
      test(code, () {
        final e = PlatformException(code: code, message: 'busy');
        expect(isDownloadElsewhere(e), isTrue);
        expect(_of(e), _engineError('download-in-progress', 'busy'));
      });
    }

    test('other errors are not', () {
      expect(isDownloadElsewhere(PlatformException(code: 'error')), isFalse);
      expect(isDownloadElsewhere(MissingPluginException()), isFalse);
    });
  });

  test('no plugin (web app, unsupported platform) → RecognizerUnsupported', () {
    expect(
      _of(MissingPluginException('No implementation found')),
      isA<RecognizerUnsupported>(),
    );
  });

  test('a RecognitionFailure is passed on as it is', () {
    final failure = RecognizerEngineError('timeout', 'slow');
    expect(identical(_of(failure), failure), isTrue);
    final offline = RecognizerOffline();
    expect(identical(_of(offline), offline), isTrue);
  });

  group('anything else → unknown', () {
    test('an unknown plugin code', () {
      final e = PlatformException(code: 'error', message: 'Task failed');
      expect(_of(e), _engineError('unknown', '$e'));
    });

    test('invalid_args', () {
      final e = PlatformException(code: 'invalid_args', message: 'Missing');
      expect(_of(e), _engineError('unknown', '$e'));
    });

    test('a Dart error (a null where the plugin expects a list)', () {
      final e = TypeError();
      expect(_of(e), _engineError('unknown', '$e'));
    });
  });
}
