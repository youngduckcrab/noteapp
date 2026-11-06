// CallableMathRecognizer against the functions emulator (m5-7/05-library
// 6.11.7, V13; integration stage L2-I6 — runs after SYNC's functions/ are
// merged). Skipped by default (dart_test.yaml `emulator`). From the
// repository root, after `npm ci --prefix functions`:
//
//   dart run tool/ws.dart with-heavy-lock -- npx --prefix functions firebase
//     emulators:exec --config app/firebase.json --only functions,auth
//     --project demo-noteapp
//     "dart run tool/ws.dart test --run-skipped -t emulator --package ink_recognition"
//
// NOTEAPP_FUNCTIONS_URL (default the demo project's recognizeMath) and
// FIREBASE_AUTH_EMULATOR_HOST (set by firebase-tools, default
// 127.0.0.1:9099). Users owner-uid / stranger-uid are made over the Auth
// emulator REST API (07-sync 6.8.11 — 'already there' is fine). Cases E1–E3,
// E5–E9 and G-3 (E4 · E10 are client guarantees — unit/math_payload_test).
// The only LIBRARY test with a real network (loopback) and real time.
@Tags(['emulator'])
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/math/callable_math_recognizer.dart';

final Uri _functionsUrl = Uri.parse(
  Platform.environment['NOTEAPP_FUNCTIONS_URL'] ??
      'http://127.0.0.1:5001/demo-noteapp/asia-northeast3/recognizeMath',
);
final String _authHost =
    Platform.environment['FIREBASE_AUTH_EMULATOR_HOST'] ?? '127.0.0.1:9099';

/// The 67-byte 1×1 grayscale PNG of SYNC's tests (E6 —
/// functions/test/handler.test.ts `png67`).
final Uint8List _png67 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR42mNgAAAAAgAB'
  '5Sfe/AAAAABJRU5ErkJggg==',
);

/// Two strokes, five points in all; the first point at ([x0], [x0]).
MathInput _strokes({double x0 = 10}) => MathInput(
  traces: [
    HandwritingTrace(
      xs: Float32List.fromList([x0, 11, 12]),
      ys: Float32List.fromList([x0, 21, 22]),
      ts: Float64List.fromList([1730800000000, 1730800000008, 1730800000016]),
    ),
    HandwritingTrace(
      xs: Float32List.fromList([30, 31]),
      ys: Float32List.fromList([40, 41]),
      ts: Float64List.fromList([1730800000300, 1730800000308]),
    ),
  ],
);

Future<void> _createUser(http.Client client, String uid) async {
  final response = await client.post(
    Uri.parse(
      'http://$_authHost/identitytoolkit.googleapis.com/v1/projects/'
      'demo-noteapp/accounts',
    ),
    headers: {
      'Authorization': 'Bearer owner',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'localId': uid,
      'email': '$uid@example.test',
      'password': 'test-password',
    }),
  );
  if (response.statusCode == 200) return;
  if (response.body.contains('DUPLICATE_LOCAL_ID') ||
      response.body.contains('EMAIL_EXISTS')) {
    return;
  }
  fail('creating $uid: ${response.statusCode} ${response.body}');
}

Future<String> _idToken(http.Client client, String uid) async {
  final response = await client.post(
    Uri.parse(
      'http://$_authHost/identitytoolkit.googleapis.com/v1/'
      'accounts:signInWithPassword?key=fake-api-key',
    ),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'email': '$uid@example.test',
      'password': 'test-password',
      'returnSecureToken': true,
    }),
  );
  expect(response.statusCode, 200, reason: response.body);
  return (jsonDecode(response.body) as Map<String, Object?>)['idToken']!
      as String;
}

/// Counts the requests the product sends (G-3).
final class _CountingClient extends http.BaseClient {
  _CountingClient(this._inner);
  final http.Client _inner;
  int requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests++;
    return _inner.send(request);
  }
}

Matcher _engineError(String code) =>
    isA<RecognizerEngineError>().having((e) => e.code, 'code', code);

void main() {
  late http.Client client;
  late String ownerToken;
  late String strangerToken;

  setUpAll(() async {
    client = http.Client();
    await _createUser(client, 'owner-uid');
    await _createUser(client, 'stranger-uid');
    ownerToken = await _idToken(client, 'owner-uid');
    strangerToken = await _idToken(client, 'stranger-uid');
  });
  tearDownAll(() => client.close());

  CallableMathRecognizer recognizer({
    String? token,
    String engine = 'fake',
    bool consent = true,
    http.Client? via,
  }) => CallableMathRecognizer(
    endpoint: _functionsUrl,
    client: via ?? client,
    consent: () async => consent,
    idTokenProvider: token == null ? null : () async => token,
    engine: engine,
  );

  test('E1 no token → unauthenticated', () async {
    await expectLater(
      recognizer().recognize(_strokes()),
      throwsA(_engineError('unauthenticated')),
    );
  });

  test('E2 stranger-uid → permission-denied', () async {
    await expectLater(
      recognizer(token: strangerToken).recognize(_strokes()),
      throwsA(_engineError('permission-denied')),
    );
  });

  test('E3 owner-uid, no strokes and no PNG → invalid-argument', () async {
    await expectLater(
      recognizer(token: ownerToken).recognize(const MathInput(traces: [])),
      throwsA(_engineError('invalid-argument')),
    );
  });

  test(r'E5 fake engine, 2 strokes · 5 points → \frac{2}{5}', () async {
    final result = await recognizer(token: ownerToken).recognize(_strokes());
    expect(result.latex, r'\frac{2}{5}');
    expect(result.confidence, 1);
    expect(result.alternatives, ['2/5']);
    expect(result.engineId, 'fake/1');
    expect(result.latency, greaterThan(Duration.zero));
  });

  test(r'E6 fake engine, PNG only (67 B) → \sqrt{67}', () async {
    final result = await recognizer(token: ownerToken)
        .recognize(MathInput(traces: const [], png: _png67));
    expect(result.latex, r'\sqrt{67}');
    expect(result.alternatives, isEmpty);
  });

  test('E7 engine auto (the demo MATH_ENGINE=fake) → the E5 value', () async {
    final result = await recognizer(
      token: ownerToken,
      engine: 'auto',
    ).recognize(_strokes());
    expect(result.latex, r'\frac{2}{5}');
    expect(result.engineId, 'fake/1');
  });

  test('E8 engine gemini (not configured) → RecognizerOffline', () async {
    await expectLater(
      recognizer(token: ownerToken, engine: 'gemini').recognize(_strokes()),
      throwsA(isA<RecognizerOffline>()),
    );
  });

  test(
    'E9 first point (−1, −1) → RecognizerOffline; (−2, −2) → internal',
    () async {
      await expectLater(
        recognizer(token: ownerToken).recognize(_strokes(x0: -1)),
        throwsA(isA<RecognizerOffline>()),
      );
      await expectLater(
        recognizer(token: ownerToken).recognize(_strokes(x0: -2)),
        throwsA(_engineError('internal')),
      );
    },
  );

  test('G-3 consent false → no HTTP, RecognizerConsentRequired', () async {
    final counting = _CountingClient(client);
    await expectLater(
      recognizer(
        token: ownerToken,
        consent: false,
        via: counting,
      ).recognize(_strokes()),
      throwsA(isA<RecognizerConsentRequired>()),
    );
    expect(counting.requests, 0);
  });
}
