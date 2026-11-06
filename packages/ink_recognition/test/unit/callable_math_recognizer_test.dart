// CallableMathRecognizer (m5-7/05-library 8.2 L2-16, 6.11.2–6.11.6;
// contract 7.2.13): the POST (JSON body, Content-Type, Authorization only
// with a token), the 6.11.4 answer table row by row, the consent gate (HTTP
// 0 before recog.mathConsent — G-3), cancelling K1–K4 (MockClient.streaming
// gets the product's own AbortableRequest; K2 is the case that decides the
// catch order — RequestAbortedException before ClientException), the 35 s
// timeout (fakeAsync) and the fake engine's answer → engineId 'fake/1'.
// No real time: Completers only.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/math/callable_math_recognizer.dart';

final Uri _endpoint = Uri.parse(
  'http://127.0.0.1:5001/demo-noteapp/asia-northeast3/recognizeMath',
);

/// Two strokes, five points (the fake engine's \frac{2}{5} input).
final MathInput _input = MathInput(
  traces: [
    HandwritingTrace(
      xs: Float32List.fromList([10, 11, 12]),
      ys: Float32List.fromList([20, 21, 22]),
      ts: Float64List.fromList([1730800000000, 1730800000008, 1730800000016]),
    ),
    HandwritingTrace(
      xs: Float32List.fromList([30, 31]),
      ys: Float32List.fromList([40, 41]),
      ts: Float64List.fromList([1730800000300, 1730800000308]),
    ),
  ],
);

CallableMathRecognizer _recognizer(
  http.Client client, {
  bool consent = true,
  Future<String?> Function()? idTokenProvider,
  String engine = 'auto',
  String locale = 'ko',
}) => CallableMathRecognizer(
  endpoint: _endpoint,
  client: client,
  consent: () async => consent,
  idTokenProvider: idTokenProvider,
  engine: engine,
  locale: locale,
);

/// The fake engine's answer for 2 strokes and 5 points (contract 7.6).
const Map<String, Object?> _fakeResult = {
  'latex': r'\frac{2}{5}',
  'confidence': 1,
  'alternatives': ['2/5'],
  'engine': 'fake',
  'engineVersion': '1',
  'ms': 3,
};

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status);

http.Response _error(int status, String name) => _json(status, {
  'error': {'status': name, 'message': 'from the server'},
});

Matcher _engineError(String code) =>
    isA<RecognizerEngineError>().having((e) => e.code, 'code', code);

void main() {
  group('the request', () {
    test(
      'POST, JSON body, Content-Type; Authorization only with a token',
      () async {
        final requests = <http.Request>[];
        final client = MockClient((request) async {
          requests.add(request);
          return _json(200, {'result': _fakeResult});
        });
        await _recognizer(
          client,
          idTokenProvider: () async => 'id-token',
          engine: 'fake',
          locale: 'en',
        ).recognize(_input);
        await _recognizer(client).recognize(_input);
        await _recognizer(
          client,
          idTokenProvider: () async => null,
        ).recognize(_input);
        await _recognizer(
          client,
          idTokenProvider: () async => '',
        ).recognize(_input);

        expect(requests, hasLength(4));
        final first = requests.first;
        expect(first.method, 'POST');
        expect(first.url, _endpoint);
        expect(first.headers['content-type'], startsWith('application/json'));
        expect(first.headers['authorization'], 'Bearer id-token');
        final body = jsonDecode(first.body) as Map<String, Object?>;
        final data = body['data']! as Map<String, Object?>;
        expect(data['v'], 1);
        expect(data['engine'], 'fake');
        expect(data['locale'], 'en');
        final strokes = data['strokes']! as Map<String, Object?>;
        expect(strokes['x'], [
          [10.0, 11.0, 12.0],
          [30.0, 31.0],
        ]);
        expect(strokes['t'], [
          [0, 8, 16],
          [300, 308],
        ]);
        expect(
          (jsonDecode(requests[1].body) as Map)['data'],
          containsPair('engine', 'auto'),
        );
        for (final r in requests.skip(1)) {
          expect(r.headers.containsKey('authorization'), isFalse);
        }
      },
    );

    test(
      'consent false → RecognizerConsentRequired and no HTTP at all (G-3)',
      () async {
        var calls = 0;
        final client = MockClient((request) async {
          calls++;
          return _json(200, {'result': _fakeResult});
        });
        var tokenAsked = 0;
        await expectLater(
          _recognizer(
            client,
            consent: false,
            idTokenProvider: () async {
              tokenAsked++;
              return 't';
            },
          ).recognize(_input),
          throwsA(isA<RecognizerConsentRequired>()),
        );
        expect(calls, 0);
        expect(tokenAsked, 0);
      },
    );

    test('a body too large even after thinning → too-large, no HTTP', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return _json(200, {'result': _fakeResult});
      });
      final big = MathInput(
        traces: [
          for (var s = 0; s < 600; s++)
            HandwritingTrace(
              xs: Float32List.fromList([for (var i = 0; i < 120; i++) i * 3.0]),
              ys: Float32List.fromList([
                for (var i = 0; i < 120; i++) i.isEven ? 10.0 : -10.0,
              ]),
              ts: Float64List.fromList([
                for (var i = 0; i < 120; i++) 1730800000000.0 + s * 1000 + i,
              ]),
            ),
        ],
      );
      await expectLater(
        _recognizer(client).recognize(big),
        throwsA(_engineError('too-large')),
      );
      expect(calls, 0);
    });
  });

  group('answers (6.11.4)', () {
    Future<MathResult> answer(http.Response response) =>
        _recognizer(MockClient((_) async => response)).recognize(_input);

    test('200 → MathResult; the fake engine → engineId fake/1', () async {
      final result = await answer(_json(200, {'result': _fakeResult}));
      expect(result.latex, r'\frac{2}{5}');
      expect(result.confidence, 1.0);
      expect(result.alternatives, ['2/5']);
      expect(result.engineId, 'fake/1');
      expect(result.latency, greaterThanOrEqualTo(Duration.zero));
    });

    test('200 with the engine version that actually answered', () async {
      final result = await answer(
        _json(200, {
          'result': {
            'latex': 'x',
            'engine': 'mathpix',
            'engineVersion': 'v3-fallback',
          },
        }),
      );
      expect(result.engineId, 'mathpix/v3-fallback');
      expect(result.confidence, isNull);
      expect(result.alternatives, isEmpty);
    });

    test('200 without a string latex → bad-response', () async {
      await expectLater(
        answer(
          _json(200, {
            'result': {'latex': 3},
          }),
        ),
        throwsA(_engineError('bad-response')),
      );
      await expectLater(
        answer(_json(200, {'nothing': true})),
        throwsA(_engineError('bad-response')),
      );
      await expectLater(
        answer(http.Response('<html>', 200)),
        throwsA(_engineError('bad-response')),
      );
    });

    final rows = <(String, int, String, Matcher)>[
      (
        'UNAUTHENTICATED',
        401,
        'unauthenticated',
        _engineError('unauthenticated'),
      ),
      (
        'PERMISSION_DENIED',
        403,
        'permission-denied',
        _engineError('permission-denied'),
      ),
      (
        'INVALID_ARGUMENT',
        400,
        'invalid-argument',
        _engineError('invalid-argument'),
      ),
      (
        'RESOURCE_EXHAUSTED',
        429,
        'RecognizerQuotaExceeded',
        isA<RecognizerQuotaExceeded>(),
      ),
      ('UNAVAILABLE', 503, 'RecognizerOffline', isA<RecognizerOffline>()),
      ('DEADLINE_EXCEEDED', 504, 'RecognizerOffline', isA<RecognizerOffline>()),
      ('INTERNAL', 500, 'internal', _engineError('internal')),
      ('NOT_FOUND', 404, 'not-found', _engineError('not-found')),
    ];
    for (final (name, status, expected, matcher) in rows) {
      test('$name → $expected', () async {
        await expectLater(answer(_error(status, name)), throwsA(matcher));
      });
    }

    test('not JSON / no error status → internal', () async {
      await expectLater(
        answer(http.Response('Bad gateway', 502)),
        throwsA(_engineError('internal')),
      );
      await expectLater(
        answer(_json(500, {'error': 'x'})),
        throwsA(_engineError('internal')),
      );
    });

    test(
      'a connection failure (ClientException) → RecognizerOffline',
      () async {
        final client = MockClient(
          (request) async => throw http.ClientException('refused', request.url),
        );
        await expectLater(
          _recognizer(client).recognize(_input),
          throwsA(isA<RecognizerOffline>()),
        );
      },
    );
  });

  group('cancel (6.11.4 K1–K4)', () {
    test('K1 real abort: the request is the product\'s AbortableRequest with '
        'the given cancel as abortTrigger → RecognizerCancelled', () async {
      final cancel = Completer<void>();
      var sent = false;
      final client = MockClient.streaming((request, body) async {
        expect(request, isA<http.AbortableRequest>());
        expect(
          identical((request as http.Abortable).abortTrigger, cancel.future),
          isTrue,
        );
        sent = true;
        await request.abortTrigger;
        throw http.RequestAbortedException(request.url);
      });
      final result = _recognizer(client)
          .recognize(_input, cancel: cancel.future);
      await pumpEventQueue();
      expect(sent, isTrue);
      cancel.complete();
      await expectLater(result, throwsA(isA<RecognizerCancelled>()));
      await pumpEventQueue(); // the losing answer's error is dropped
    });

    test('K2 RequestAbortedException before cancel → RecognizerCancelled '
        '(the catch order: before ClientException)', () async {
      final cancel = Completer<void>();
      final client = MockClient.streaming(
        (request, body) async =>
            throw http.RequestAbortedException(request.url),
      );
      await expectLater(
        _recognizer(client).recognize(_input, cancel: cancel.future),
        throwsA(isA<RecognizerCancelled>()),
      );
      expect(cancel.isCompleted, isFalse);
    });

    test('K3 control: a plain ClientException with cancel pending → '
        'RecognizerOffline', () async {
      final cancel = Completer<void>();
      final client = MockClient.streaming(
        (request, body) async =>
            throw http.ClientException('connection refused', request.url),
      );
      await expectLater(
        _recognizer(client).recognize(_input, cancel: cancel.future),
        throwsA(isA<RecognizerOffline>()),
      );
      expect(cancel.isCompleted, isFalse);
    });

    test('K4 race: a client that cannot abort (MockClient(fn), never '
        'answers) → cancel wins → RecognizerCancelled', () async {
      final cancel = Completer<void>();
      final never = Completer<http.Response>();
      final client = MockClient((request) => never.future);
      final result = _recognizer(client)
          .recognize(_input, cancel: cancel.future);
      await pumpEventQueue();
      cancel.complete();
      await expectLater(result, throwsA(isA<RecognizerCancelled>()));
    });

    test('cancel already done → RecognizerCancelled without HTTP', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return _json(200, {'result': _fakeResult});
      });
      await expectLater(
        _recognizer(client).recognize(_input, cancel: Future<void>.value()),
        throwsA(isA<RecognizerCancelled>()),
      );
      expect(calls, 0);
    });

    test('an answer that arrives first is kept', () async {
      final cancel = Completer<void>();
      final client = MockClient(
        (request) async => _json(200, {'result': _fakeResult}),
      );
      final result = await _recognizer(client)
          .recognize(_input, cancel: cancel.future);
      expect(result.latex, r'\frac{2}{5}');
      cancel.complete(); // later: nothing happens
      await pumpEventQueue();
    });
  });

  test('35 s timeout → RecognizerOffline (fakeAsync)', () {
    fakeAsync((async) {
      final client = MockClient((request) => Completer<http.Response>().future);
      Object? error;
      var done = false;
      unawaited(
        _recognizer(client)
            .recognize(_input)
            .then<void>(
              (_) => done = true,
              onError: (Object e) {
                error = e;
                done = true;
              },
            ),
      );
      async.elapse(const Duration(seconds: 34, milliseconds: 999));
      expect(done, isFalse);
      async.elapse(const Duration(milliseconds: 1));
      expect(error, isA<RecognizerOffline>());
    });
  });
}
