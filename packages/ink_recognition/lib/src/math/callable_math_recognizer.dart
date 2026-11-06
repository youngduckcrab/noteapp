// lib/src/math/callable_math_recognizer.dart — (internal) the server math
// engine over the callable protocol (m5-7/05-library 6.11.2; chosen only by
// recognitionOverrides when RecognitionConfig.mathEndpoint is set — 4.4.8).
//
// L2-07: the constructor, the engine id and availability, and the consent
// gate (G-3 — no network before recog.mathConsent). L2-16 adds the request
// (math_payload.dart, callable_protocol.dart: body, Authorization, 35 s,
// cancel / RequestAbortedException first, the 6.11.4 answer table); until
// then an allowed call ends in RecognizerEngineError('unavailable').
import 'package:http/http.dart' as http;

import '../common/engine_ids.dart';
import '../model/failures.dart';
import '../model/math_types.dart';
import '../ports/math_recognizer.dart';

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
    if (!await consent()) throw RecognizerConsentRequired();
    throw RecognizerEngineError(
      'unavailable',
      'the callable math request arrives with L2-16',
    );
  }
}
