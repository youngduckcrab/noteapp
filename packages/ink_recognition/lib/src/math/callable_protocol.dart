// lib/src/math/callable_protocol.dart — (internal, pure) m5-7/05-library
// 6.11.4: the callable answer → MathResult or a RecognitionFailure.
//
// The Firebase callable protocol: 200 `{"result": {latex, confidence?,
// alternatives?, engine, engineVersion, ms}}` (contract 7.2.13 `out`);
// an error is `{"error": {"status": "<CANONICAL_NAME>", "message": …}}` with
// a non-200 HTTP status.
//
// | answer                                   | failure                          |
// |------------------------------------------|----------------------------------|
// | UNAUTHENTICATED                          | RecognizerEngineError('unauthenticated') |
// | PERMISSION_DENIED                        | RecognizerEngineError('permission-denied') |
// | INVALID_ARGUMENT                         | RecognizerEngineError('invalid-argument') |
// | RESOURCE_EXHAUSTED                       | RecognizerQuotaExceeded           |
// | UNAVAILABLE · DEADLINE_EXCEEDED          | RecognizerOffline                 |
// | INTERNAL · any other name                | RecognizerEngineError('internal' / 'not-found' …) |
// | not JSON, no error status                | RecognizerEngineError('internal') |
// | 200 without a string latex               | RecognizerEngineError('bad-response') |
//
// The transport side (cancel, RequestAbortedException before ClientException,
// the 35 s timeout) is CallableMathRecognizer's.
import 'dart:convert';

import '../common/engine_ids.dart';
import '../model/failures.dart';
import '../model/math_types.dart';

/// [status] and [body] of the callable's HTTP answer → the result, or throws
/// the 6.11.4 failure. [latency] is the client's measurement.
MathResult decodeMathAnswer(
  int status,
  String body, {
  required Duration latency,
}) {
  Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    json = null;
  }
  final error = switch (json) {
    {'error': final Map<String, Object?> e} => e,
    _ => null,
  };
  if (status == 200 && error == null) {
    final result = switch (json) {
      {'result': final Map<String, Object?> r} => r,
      _ => null,
    };
    final latex = result?['latex'];
    if (result == null || latex is! String) {
      throw RecognizerEngineError(
        'bad-response',
        'no string latex in the answer (${_clip(body)})',
      );
    }
    final confidence = result['confidence'];
    final alternatives = result['alternatives'];
    final engine = result['engine'];
    final version = result['engineVersion'];
    return MathResult(
      latex: latex,
      confidence: confidence is num ? confidence.toDouble() : null,
      alternatives: List.unmodifiable([
        if (alternatives is List)
          for (final a in alternatives)
            if (a is String) a,
      ]),
      engineId: engine is String && version is String
          ? '$engine/$version'
          : kCallableMathEngineId,
      latency: latency,
    );
  }
  final name = error?['status'];
  final message = switch (error?['message']) {
    final String m => m,
    _ => 'HTTP $status ${_clip(body)}',
  };
  if (name is! String) throw RecognizerEngineError('internal', message);
  throw failureOfCallableStatus(name, message);
}

/// The 6.11.4 failure of a callable error status name ('UNAUTHENTICATED' …).
RecognitionFailure failureOfCallableStatus(String name, String message) =>
    switch (name) {
      'RESOURCE_EXHAUSTED' => RecognizerQuotaExceeded(),
      'UNAVAILABLE' || 'DEADLINE_EXCEEDED' => RecognizerOffline(),
      _ => RecognizerEngineError(
        name.toLowerCase().replaceAll('_', '-'),
        message,
      ),
    };

String _clip(String body) =>
    body.length <= 120 ? body : '${body.substring(0, 120)}…';
