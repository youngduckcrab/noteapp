// recognitionOverrides (m5-7/05-library 4.4.8, 6.7.1, 6.10, 8.2 L2-07; contract
// 7.2.11, X31): exactly 3 overrides — the platform handwriting engine, the
// math engine, INK's shape fitter — and nothing else; manual math without an
// endpoint, the callable engine with one (consent read from recog.mathConsent,
// no HTTP before it — G-3); GeometricShapeFitter; the desktop gets the
// unsupported engine; the container disposes the engine once and closes the
// HTTP client; the web stub.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/engines/mlkit_recognizer_native.dart'
    as native;
import 'package:ink_recognition/src/engines/platform_recognizer.dart';
import 'package:ink_recognition/src/engines/platform_recognizer_stub.dart'
    as stub;
import 'package:ink_recognition/src/math/callable_math_recognizer.dart';
import 'package:ink_recognition/src/providers.dart'
    show buildRecognitionOverrides;
import 'package:ink_recognition/src/settings/recognition_settings_keys.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

/// Counts dispose; available so the indexer provider would build on it.
final class _CountingRecognizer implements HandwritingRecognizer {
  int disposes = 0;

  @override
  String get engineId => 'counting';
  @override
  bool get isAvailable => false;
  @override
  Future<RecognitionModelState> modelState(String languageTag) async =>
      RecognitionModelState.unsupported;
  @override
  Future<void> ensureModel(String languageTag, {bool wifiOnly = true}) async {}
  @override
  Future<List<TextCandidate>> recognizeLine(
    HandwritingLineInput line, {
    required String languageTag,
    Future<void>? cancel,
  }) async => const [];
  @override
  Future<void> dispose() async => disposes++;
}

/// Counts requests and close().
final class _CountingClient extends http.BaseClient {
  int requests = 0, closes = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    throw http.ClientException('no network in tests', request.url);
  }

  @override
  void close() => closes++;
}

final Uri _endpoint = Uri.parse('http://127.0.0.1:5001/demo/recognizeMath');

void main() {
  test('exactly 3 overrides, in this order, with or without config', () {
    final expected = [
      handwritingRecognizerProvider,
      mathRecognizerProvider,
      ink.inkShapeFitterProvider,
    ];
    expect(recognitionOverrides().map((o) => o.origin), expected);
    expect(
      recognitionOverrides(config: RecognitionConfig(mathEndpoint: _endpoint))
          .map((o) => o.origin),
      expected,
    );
  });

  test('the shape fitter is GeometricShapeFitter (X31)', () {
    final container = ProviderContainer.test(overrides: recognitionOverrides());
    expect(
      container.read(ink.inkShapeFitterProvider),
      isA<GeometricShapeFitter>(),
    );
  });

  group('math engine', () {
    test('no endpoint → ManualOnlyMathRecognizer, no HTTP client', () {
      var clients = 0;
      final container = ProviderContainer.test(
        overrides: buildRecognitionOverrides(
          config: const RecognitionConfig(),
          createClient: () {
            clients++;
            return _CountingClient();
          },
        ),
      );
      expect(
        container.read(mathRecognizerProvider),
        isA<ManualOnlyMathRecognizer>(),
      );
      expect(clients, 0);
    });

    test('an endpoint → CallableMathRecognizer with it and the token '
        'provider; consent from recog.mathConsent, no HTTP before it (G-3); '
        'the client closes with the container', () async {
      final store = core_testing.createFakeNoteStore();
      addTearDown(store.close);
      final client = _CountingClient();
      Future<String?> token() async => 'id-token';
      final container = ProviderContainer(
        overrides: [
          core.noteStoreProvider.overrideWithValue(store),
          ...buildRecognitionOverrides(
            config: RecognitionConfig(
              mathEndpoint: _endpoint,
              idTokenProvider: token,
            ),
            createClient: () => client,
          ),
        ],
      );
      final math = container.read(mathRecognizerProvider);
      expect(math, isA<CallableMathRecognizer>());
      final callable = math as CallableMathRecognizer;
      expect(callable.endpoint, _endpoint);
      expect(callable.client, same(client));
      expect(callable.idTokenProvider, same(token));
      expect(callable.engineId, 'callable');
      expect(callable.isAvailable, isTrue);

      const input = MathInput(traces: []);
      await expectLater(
        callable.recognize(input),
        throwsA(isA<RecognizerConsentRequired>()),
      );
      expect(client.requests, 0);
      await store.settings.set(RecognitionSettingsKeys.mathConsent, true);
      expect(await callable.consent(), isTrue);
      await expectLater(
        callable.recognize(input),
        throwsA(isNot(isA<RecognizerConsentRequired>())),
      );

      expect(client.closes, 0);
      container.dispose();
      expect(client.closes, 1);
    });
  });

  group('handwriting engine', () {
    test('the container disposes the engine once', () async {
      final recognizer = _CountingRecognizer();
      var made = 0;
      final container = ProviderContainer(
        overrides: buildRecognitionOverrides(
          config: const RecognitionConfig(),
          createHandwriting: () {
            made++;
            return recognizer;
          },
        ),
      );
      expect(container.read(handwritingRecognizerProvider), same(recognizer));
      expect(container.read(handwritingRecognizerProvider), same(recognizer));
      expect(made, 1);
      container.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(recognizer.disposes, 1);
    });

    test('an engine whose dispose fails is reported, not thrown', () async {
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);
      final container = ProviderContainer(
        overrides: buildRecognitionOverrides(
          config: const RecognitionConfig(),
          createHandwriting: _FailingDispose.new,
        ),
      );
      container.read(handwritingRecognizerProvider);
      container.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(reported, hasLength(1));
      expect(reported.single.library, 'ink_recognition');
      expect(reported.single.exception, isA<StateError>());
    });

    test('desktop (linux, macOS, windows) → the unsupported engine', () {
      for (final platform in [
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        try {
          expect(
            createPlatformHandwritingRecognizer(),
            isA<UnsupportedHandwritingRecognizer>(),
            reason: '$platform',
          );
          final container = ProviderContainer.test(
            overrides: recognitionOverrides(),
          );
          final engine = container.read(handwritingRecognizerProvider);
          expect(engine.isAvailable, isFalse);
          expect(container.read(handwritingIndexerProvider), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      }
    });

    test('ML Kit platforms are Android and iOS (6.7.1); the VM build '
        'resolves the native file, the web build the stub', () {
      expect(native.platformHasMlKit(TargetPlatform.android), isTrue);
      expect(native.platformHasMlKit(TargetPlatform.iOS), isTrue);
      for (final p in [
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        expect(native.platformHasMlKit(p), isFalse, reason: '$p');
      }
      // On the VM the conditional export is the native file's function.
      expect(
        identical(
          createPlatformHandwritingRecognizer,
          native.createPlatformHandwritingRecognizer,
        ),
        isTrue,
      );
      expect(
        stub.createPlatformHandwritingRecognizer(),
        isA<UnsupportedHandwritingRecognizer>(),
      );
    });
  });
}

final class _FailingDispose extends _CountingRecognizer {
  @override
  Future<void> dispose() async => throw StateError('dispose failed');
}
