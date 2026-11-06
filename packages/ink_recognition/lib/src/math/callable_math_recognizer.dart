// lib/src/math/callable_math_recognizer.dart — (internal) the server math
// engine over the callable protocol (m5-7/05-library 6.11.2; chosen only by
// recognitionOverrides when RecognitionConfig.mathEndpoint is set — 4.4.8).
//
// L2-07: the constructor, the engine id and availability, and the consent
// gate (G-3 — no network before recog.mathConsent).
// L2-16: one call = ① consent (false → RecognizerConsentRequired, HTTP 0)
// ② the body (math_payload.dart — may end in 'too-large') ③ POST as an
// http.AbortableRequest whose abortTrigger IS the caller's `cancel`,
// Content-Type JSON, `Authorization: Bearer <token>` only with a token
// ④ the answer (callable_protocol.dart) within [timeout] (35 s = server
// 30 s + 5 s). A `cancel` that ends first wins the race (clients that cannot
// abort — MockClient(fn)); the losing answer's error is dropped. Failure
// order (6.11.4): cancel already done → RecognizerCancelled;
// RequestAbortedException (a ClientException subtype — checked FIRST) →
// RecognizerCancelled; ClientException → RecognizerOffline; timeout →
// RecognizerOffline; then the answer table.
import 'dart:async';

import 'package:http/http.dart' as http;

import '../common/engine_ids.dart';
import '../model/failures.dart';
import '../model/math_types.dart';
import '../ports/math_recognizer.dart';
import 'callable_protocol.dart';
import 'math_payload.dart';

final class CallableMathRecognizer implements MathRecognizer {
  CallableMathRecognizer({
    required this.endpoint,
    required this.client,
    required this.consent,
    this.idTokenProvider,
    this.engine = 'auto',
    this.locale = 'ko',
    this.timeout = const Duration(seconds: 35),
  });

  final Uri endpoint;
  final http.Client client;

  /// recog.mathConsent, read on every call (G-3).
  final Future<bool> Function() consent;

  /// null → no Authorization header (M4 auth later).
  final Future<String?> Function()? idTokenProvider;
  final String engine, locale;
  final Duration timeout;

  @override
  String get engineId => kCallableMathEngineId;

  /// The consent gate is checked per call (G-3).
  @override
  bool get isAvailable => true;

  @override
  Future<MathResult> recognize(MathInput input, {Future<void>? cancel}) async {
    final stopwatch = Stopwatch()..start();
    var cancelled = false;
    final cancelSignal = Completer<void>();
    if (cancel != null) {
      void onCancel() {
        cancelled = true;
        if (!cancelSignal.isCompleted) cancelSignal.complete();
      }

      unawaited(
        cancel.then<void>((_) => onCancel(), onError: (_) => onCancel()),
      );
    }
    if (!await consent()) throw RecognizerConsentRequired();
    if (cancelled) throw RecognizerCancelled();
    final body = encodeMathRequest(input, engine: engine, locale: locale);
    final token = await idTokenProvider?.call();
    if (cancelled) throw RecognizerCancelled();

    final request =
        http.AbortableRequest('POST', endpoint, abortTrigger: cancel)
          ..headers['Content-Type'] = 'application/json'
          ..body = body;
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    Future<(int, String)> exchange() async {
      final response = await client.send(request);
      return (response.statusCode, await response.stream.bytesToString());
    }

    (int, String)? answer;
    try {
      answer = await Future.any<(int, String)?>([
        exchange(),
        if (cancel != null) cancelSignal.future.then((_) => null),
      ]).timeout(timeout);
    } on http.RequestAbortedException {
      throw RecognizerCancelled(); // before ClientException (its supertype)
    } on http.ClientException {
      if (cancelled) throw RecognizerCancelled();
      throw RecognizerOffline();
    } on TimeoutException {
      if (cancelled) throw RecognizerCancelled();
      throw RecognizerOffline();
    }
    if (cancelled || answer == null) throw RecognizerCancelled();
    final (status, text) = answer;
    return decodeMathAnswer(status, text, latency: stopwatch.elapsed);
  }
}
