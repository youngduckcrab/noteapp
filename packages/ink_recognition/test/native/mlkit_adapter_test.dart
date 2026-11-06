// The ML Kit adapter on the VM with the plugin's method channel faked
// (m5-7/05-library 8.2 L2-08, 6.7.2 – 6.7.5; contract 7.4.6 '플러그인 가짜' —
// the one LIBRARY test file that fakes a plugin channel): the channel
// arguments (model, ink points moved to the line box's top-left with a
// 13-digit int `t`, context), the candidates, every 6.7.3 error row on the
// recognition path, one native call at a time, the 10 s line limit, model
// state / download joining (a different wifiOnly downloads again, the first
// success ends both), the iOS model manager's 'cancelled' answer, delete,
// and close on dispose. Real recognition quality is the APK's A-4.
@TestOn('vm')
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/common/engine_ids.dart';
import 'package:ink_recognition/src/engines/mlkit_recognizer_native.dart';
import 'package:ink_recognition/src/engines/platform_recognizer.dart'
    as platform;
import 'package:ink_recognition/src/ports/line_origin.dart';
import 'package:ink_recognition/src/ports/model_admin.dart';

const _channel = MethodChannel('google_mlkit_digital_ink_recognizer');
const _manage = 'vision#manageInkModels';
const _start = 'vision#startDigitalInkRecognizer';
const _close = 'vision#closeDigitalInkRecognizer';

/// 2025-11-06 epoch ms — 13 digits.
const int _t0 = 1762400000000;

/// The plugin's native side: models, answers and every call.
final class _FakePlugin {
  _FakePlugin() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, _handle);
  }

  void detach() => TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);

  final List<MethodCall> calls = [];
  final Set<String> downloaded = {};

  /// 'check' answer (default: whether the model is in [downloaded]).
  Object? Function(String model)? onCheck;

  /// 'download' answer (default: the model is downloaded, 'success').
  Future<Object?> Function(String model, bool wifi)? onDownload;

  /// 'delete' answer.
  Object? deleteAnswer = 'success';

  /// recognition answer (default: [answer]).
  Future<Object?> Function(Map<String, Object?> args)? onRecognize;
  Object? answer = [
    {'text': '회의', 'score': 0.5},
  ];

  Map<String, Object?> _args(MethodCall call) =>
      (call.arguments as Map).cast<String, Object?>();

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call);
    final args = _args(call);
    switch (call.method) {
      case _manage:
        final model = args['model']! as String;
        switch (args['task']) {
          case 'check':
            final check = onCheck;
            return check != null ? check(model) : downloaded.contains(model);
          case 'download':
            final download = onDownload;
            if (download != null) return download(model, args['wifi']! as bool);
            downloaded.add(model);
            return 'success';
          case 'delete':
            downloaded.remove(model);
            return deleteAnswer;
        }
      case _start:
        final recognize = onRecognize;
        return recognize != null ? recognize(args) : answer;
      case _close:
        return null;
    }
    throw MissingPluginException();
  }

  List<Map<String, Object?>> get recognitions => [
    for (final c in calls)
      if (c.method == _start) _args(c),
  ];

  List<Map<String, Object?>> manageCalls(String task) => [
    for (final c in calls)
      if (c.method == _manage && _args(c)['task'] == task) _args(c),
  ];

  List<String> get closedIds => [
    for (final c in calls)
      if (c.method == _close) _args(c)['id']! as String,
  ];
}

HandwritingTrace _trace(List<(double, double)> points, {int start = _t0}) =>
    HandwritingTrace(
      xs: Float32List.fromList([for (final p in points) p.$1]),
      ys: Float32List.fromList([for (final p in points) p.$2]),
      ts: Float64List.fromList([
        for (var i = 0; i < points.length; i++) (start + 8 * i).toDouble(),
      ]),
    );

/// Two strokes; the line box's top-left is (100, 195).
HandwritingLineInput _line({String preContext = '', Size? area}) =>
    HandwritingLineInput(
      [
        _trace([(100, 200), (110, 210)]),
        _trace([(120, 195), (130, 205)], start: _t0 + 100),
      ],
      preContext: preContext,
      writingAreaPt: area,
    );

List<Map<String, Object?>> _points(Map<String, Object?> args) => [
  for (final stroke
      in ((args['ink']! as Map)['strokes']! as List)
          .cast<Map<Object?, Object?>>())
    for (final p in (stroke['points']! as List).cast<Map<Object?, Object?>>())
      p.cast<String, Object?>(),
];

Matcher _engineError(String code) =>
    isA<RecognizerEngineError>().having((e) => e.code, 'code', code);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePlugin plugin;
  setUp(() => plugin = _FakePlugin());
  tearDown(() => plugin.detach());

  group('choice and identity', () {
    test('the VM (Android in tests) builds the ML Kit adapter', () {
      final engine = platform.createPlatformHandwritingRecognizer();
      expect(engine, isA<MlKitHandwritingRecognizer>());
      expect(engine.engineId, kMlKitAndroidEngineId);
      expect(engine.engineId, 'mlkit-digital-ink/19.0.0');
      expect(engine.isAvailable, isTrue);
      expect(engine, isA<RecognizerModelAdmin>());
      expect((engine as RecognizerModelAdmin).enforcesWifiOnly, isTrue);
      expect(engine, isA<PageOriginLineRecognizer>());
      expect(plugin.calls, isEmpty); // nothing happens before a call
    });

    test('iOS → the iOS engine id, wifiOnly not enforced', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final engine = platform.createPlatformHandwritingRecognizer();
        expect(engine.engineId, kMlKitIosEngineId);
        expect(engine.engineId, 'mlkit-digital-ink-ios/9.0.0');
        expect((engine as RecognizerModelAdmin).enforcesWifiOnly, isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('recognizeLine', () {
    test('channel arguments: model, points moved to the line box top-left, '
        '13-digit int t, preContext and writing area', () async {
      final engine = MlKitHandwritingRecognizer();
      await engine.recognizeLine(
        _line(preContext: '오늘 회의', area: const Size(595, 36)),
        languageTag: 'ko',
      );
      final args = plugin.recognitions.single;
      expect(args['model'], 'ko');
      expect(args['id'], isA<String>());
      final points = _points(args);
      expect(
        [for (final p in points) (p['x'], p['y'])],
        [(0.0, 5.0), (10.0, 15.0), (20.0, 0.0), (30.0, 10.0)],
      );
      expect(
        [for (final p in points) p['t']],
        [_t0, _t0 + 8, _t0 + 100, _t0 + 108],
      );
      for (final p in points) {
        expect(p['t'], isA<int>());
        expect('${p['t']}', hasLength(13));
      }
      final strokes = (args['ink']! as Map)['strokes']! as List;
      expect(strokes, hasLength(2));
      expect(args['context'], {
        'preContext': '오늘 회의',
        'writingArea': {'width': 595.0, 'height': 36.0},
      });
    });

    test('context: none without preContext and area; area alone; '
        'preContext alone', () async {
      final engine = MlKitHandwritingRecognizer();
      await engine.recognizeLine(_line(), languageTag: 'ko');
      await engine.recognizeLine(
        _line(area: const Size(100, 24)),
        languageTag: 'ko',
      );
      await engine.recognizeLine(_line(preContext: 'abc'), languageTag: 'ko');
      final contexts = [for (final a in plugin.recognitions) a['context']];
      expect(contexts, [
        null,
        {
          'preContext': null,
          'writingArea': {'width': 100.0, 'height': 24.0},
        },
        {'preContext': 'abc', 'writingArea': null},
      ]);
    });

    test(
      'page coordinates as they are (the A-4 lab\'s second origin)',
      () async {
        final engine = MlKitHandwritingRecognizer();
        await engine.recognizeLineInPageCoordinates(_line(), languageTag: 'en');
        final points = _points(plugin.recognitions.single);
        expect(
          [for (final p in points) (p['x'], p['y'])],
          [(100.0, 200.0), (110.0, 210.0), (120.0, 195.0), (130.0, 205.0)],
        );
        expect(plugin.recognitions.single['model'], 'en');
      },
    );

    test('candidates: engine order, blanks and repeats left out, the score '
        'as it comes (0.0 may be "none")', () async {
      plugin.answer = [
        {'text': '회의', 'score': 1.5},
        {'text': '', 'score': 0.0},
        {'text': '회외', 'score': 0.0},
        {'text': '회의', 'score': 2.0},
        {'text': '  ', 'score': 0.0},
        {'text': '휘의', 'score': -0.25},
      ];
      final engine = MlKitHandwritingRecognizer();
      final out = await engine.recognizeLine(_line(), languageTag: 'ko');
      expect(out, const [
        TextCandidate('회의', score: 1.5, languageTag: 'ko'),
        TextCandidate('회외', score: 0.0, languageTag: 'ko'),
        TextCandidate('휘의', score: -0.25, languageTag: 'ko'),
      ]);
    });

    test('no traces, or traces without points → [] without a channel call; '
        'empty traces are left out of the ink', () async {
      final engine = MlKitHandwritingRecognizer();
      expect(
        await engine.recognizeLine(
          const HandwritingLineInput([]),
          languageTag: 'ko',
        ),
        isEmpty,
      );
      expect(
        await engine.recognizeLine(
          HandwritingLineInput([_trace(const [])]),
          languageTag: 'ko',
        ),
        isEmpty,
      );
      expect(plugin.calls, isEmpty);
      await engine.recognizeLine(
        HandwritingLineInput([
          _trace(const []),
          _trace(const [(5, 5), (9, 7)]),
        ]),
        languageTag: 'ko',
      );
      final strokes =
          (plugin.recognitions.single['ink']! as Map)['strokes']! as List;
      expect(strokes, hasLength(1));
    });

    test(
      'one recognizer per language, cached; distinct instance ids',
      () async {
        final engine = MlKitHandwritingRecognizer();
        await engine.recognizeLine(_line(), languageTag: 'ko');
        await engine.recognizeLine(_line(), languageTag: 'en');
        await engine.recognizeLine(_line(), languageTag: 'ko');
        final ids = [for (final a in plugin.recognitions) a['id']];
        expect(ids[0], ids[2]);
        expect(ids[0], isNot(ids[1]));
      },
    );

    group('6.7.3 rows on the recognition path', () {
      Future<Object?> failWith(Exception error) async {
        plugin.onRecognize = (_) async => throw error;
        final engine = MlKitHandwritingRecognizer();
        try {
          await engine.recognizeLine(_line(), languageTag: 'ko');
        } on Object catch (e) {
          return e;
        }
        fail('no failure');
      }

      test(
        'model not downloaded (Android, iOS) → ModelNotReady(tag)',
        () async {
          expect(
            await failWith(
              PlatformException(
                code: 'Model Error',
                message: 'Model has not been downloaded yet',
              ),
            ),
            isA<ModelNotReady>().having((e) => e.languageTag, 'tag', 'ko'),
          );
          expect(
            await failWith(
              PlatformException(
                code: 'Error Model has not been downloaded yet',
                message: 'Model has not been downloaded yet',
              ),
            ),
            isA<ModelNotReady>(),
          );
        },
      );

      test(
        'invalid tag → unsupported-language; modelState → unsupported',
        () async {
          for (final code in [
            'Failed to create model identifier',
            'Model Identifier error',
            'invalid_model',
          ]) {
            expect(
              await failWith(PlatformException(code: code, message: 'bad tag')),
              _engineError('unsupported-language'),
              reason: code,
            );
            plugin.onCheck = (_) => throw PlatformException(code: code);
            expect(
              await MlKitHandwritingRecognizer().modelState('xx-zz'),
              RecognitionModelState.unsupported,
              reason: code,
            );
            plugin.onCheck = null;
          }
        },
      );

      test('(v2.1) Model download check failed → model-check-failed', () async {
        expect(
          await failWith(
            PlatformException(
              code: 'Model download check failed',
              message: 'java.lang.Exception',
            ),
          ),
          _engineError('model-check-failed'),
        );
      });

      test('recognition failures (Android, iOS) keep the code', () async {
        expect(
          await failWith(PlatformException(code: 'recognition Error')),
          _engineError('recognition Error'),
        );
        expect(
          await failWith(PlatformException(code: 'Error 3', message: 'x')),
          _engineError('Error 3'),
        );
      });

      test('no plugin → RecognizerUnsupported', () async {
        expect(
          await failWith(MissingPluginException()),
          isA<RecognizerUnsupported>(),
        );
      });

      test('anything else → unknown', () async {
        expect(
          await failWith(PlatformException(code: 'invalid_args')),
          _engineError('unknown'),
        );
        // The plugin expects a list; a null answer is a Dart error.
        plugin.onRecognize = null;
        plugin.answer = null;
        await expectLater(
          MlKitHandwritingRecognizer().recognizeLine(
            _line(),
            languageTag: 'ko',
          ),
          throwsA(_engineError('unknown')),
        );
      });
    });

    test('two requests at once reach the channel one after the other '
        '(FIFO); a failure does not stop the queue', () async {
      final answers = <Completer<Object?>>[];
      plugin.onRecognize = (_) {
        final c = Completer<Object?>();
        answers.add(c);
        return c.future;
      };
      final engine = MlKitHandwritingRecognizer();
      final a = engine.recognizeLine(_line(), languageTag: 'ko');
      final b = engine.recognizeLine(_line(), languageTag: 'en');
      final c = engine.recognizeLine(_line(), languageTag: 'ko');
      await pumpEventQueue();
      expect(plugin.recognitions, hasLength(1));
      answers[0].completeError(PlatformException(code: 'recognition Error'));
      await expectLater(a, throwsA(_engineError('recognition Error')));
      await pumpEventQueue();
      expect(plugin.recognitions, hasLength(2));
      expect(plugin.recognitions[1]['model'], 'en');
      answers[1].complete([
        {'text': 'meeting', 'score': 0.1},
      ]);
      expect((await b).single.text, 'meeting');
      await pumpEventQueue();
      expect(plugin.recognitions, hasLength(3));
      answers[2].complete([
        {'text': '회의', 'score': 0.1},
      ]);
      expect((await c).single.languageTag, 'ko');
    });

    test('10 s per line → timeout; the next queued line goes on', () {
      fakeAsync((async) {
        var n = 0;
        plugin.onRecognize = (_) {
          n++;
          if (n == 1) return Completer<Object?>().future; // never answers
          return Future.value([
            {'text': '둘째', 'score': 0.0},
          ]);
        };
        final engine = MlKitHandwritingRecognizer();
        Object? first;
        List<TextCandidate>? second;
        engine
            .recognizeLine(_line(), languageTag: 'ko')
            .then<void>((_) {}, onError: (Object e) => first = e);
        engine
            .recognizeLine(_line(), languageTag: 'ko')
            .then((v) => second = v);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 9999));
        expect(first, isNull);
        expect(plugin.recognitions, hasLength(1));
        async.elapse(const Duration(milliseconds: 1));
        expect(first, _engineError('timeout'));
        async.flushMicrotasks();
        expect(plugin.recognitions, hasLength(2));
        expect(second!.single.text, '둘째');
      });
    });
  });

  group('models (Android)', () {
    test('modelState: ready / notDownloaded / downloading while a request '
        'runs / no plugin → unsupported', () async {
      final engine = MlKitHandwritingRecognizer();
      plugin.downloaded.add('ko');
      expect(await engine.modelState('ko'), RecognitionModelState.ready);
      expect(
        await engine.modelState('en'),
        RecognitionModelState.notDownloaded,
      );
      final wifi = Completer<Object?>();
      plugin.onDownload = (_, _) => wifi.future;
      unawaited(engine.ensureModel('en'));
      await pumpEventQueue();
      expect(await engine.modelState('en'), RecognitionModelState.downloading);
      plugin.onCheck = (_) => throw MissingPluginException();
      expect(await engine.modelState('ko'), RecognitionModelState.unsupported);
      plugin.onCheck = (_) =>
          throw PlatformException(code: 'error', message: 'x');
      await expectLater(
        engine.modelState('ko'),
        throwsA(_engineError('unknown')),
      );
      plugin.onCheck = null;
      wifi.complete('success');
    });

    test('a downloaded model is ready even while a request still runs '
        '(L2-18 — cellular finished first)', () async {
      final engine = MlKitHandwritingRecognizer();
      plugin.onDownload = (_, _) => Completer<Object?>().future; // Wi-Fi wait
      unawaited(engine.ensureModel('ko'));
      await pumpEventQueue();
      expect(await engine.modelState('ko'), RecognitionModelState.downloading);
      plugin.downloaded.add('ko');
      expect(await engine.modelState('ko'), RecognitionModelState.ready);
    });

    test(
      'ensureModel: ready → ends at once (no download, no modelChanges)',
      () async {
        final engine = MlKitHandwritingRecognizer();
        final changes = <String>[];
        engine.modelChanges.listen(changes.add);
        plugin.downloaded.add('ko');
        await engine.ensureModel('ko');
        expect(plugin.manageCalls('download'), isEmpty);
        await pumpEventQueue();
        expect(changes, isEmpty);
      },
    );

    test('ensureModel: the same wifiOnly joins (download 1×); success → '
        'modelChanges once', () async {
      final engine = MlKitHandwritingRecognizer();
      final changes = <String>[];
      engine.modelChanges.listen(changes.add);
      final done = Completer<Object?>();
      plugin.onDownload = (model, _) => done.future.then((v) {
        plugin.downloaded.add(model);
        return v;
      });
      final a = engine.ensureModel('ko');
      final b = engine.ensureModel('ko');
      await pumpEventQueue();
      expect(plugin.manageCalls('download'), hasLength(1));
      expect(plugin.manageCalls('download').single['wifi'], isTrue);
      done.complete('success');
      await Future.wait([a, b]);
      await pumpEventQueue();
      expect(changes, ['ko']);
      expect(await engine.modelState('ko'), RecognitionModelState.ready);
    });

    test('(v2.1, S-9) another wifiOnly downloads again (2×); the first to '
        'finish ends both; modelChanges once', () async {
      final engine = MlKitHandwritingRecognizer();
      final changes = <String>[];
      engine.modelChanges.listen(changes.add);
      final wifi = Completer<Object?>();
      plugin.onDownload = (model, wifiRequired) {
        if (wifiRequired) return wifi.future; // waits for Wi-Fi
        plugin.downloaded.add(model);
        return Future.value('success');
      };
      var wifiDone = false;
      unawaited(engine.ensureModel('ko').then((_) => wifiDone = true));
      await pumpEventQueue();
      await engine.ensureModel('ko', wifiOnly: false);
      await pumpEventQueue();
      expect(
        [for (final d in plugin.manageCalls('download')) d['wifi']],
        [true, false],
      );
      expect(wifiDone, isTrue);
      expect(changes, ['ko']);
      wifi.complete('success'); // the late Wi-Fi answer changes nothing
      await pumpEventQueue();
      expect(changes, ['ko']);
    });

    test('a failed request fails alone; the other goes on', () async {
      final engine = MlKitHandwritingRecognizer();
      final wifi = Completer<Object?>();
      plugin.onDownload = (model, wifiRequired) {
        if (wifiRequired) return wifi.future;
        throw PlatformException(code: 'error', message: 'no network');
      };
      var wifiDone = false;
      unawaited(engine.ensureModel('ko').then((_) => wifiDone = true));
      await pumpEventQueue();
      await expectLater(
        engine.ensureModel('ko', wifiOnly: false),
        throwsA(_engineError('download-failed')),
      );
      expect(wifiDone, isFalse);
      expect(await engine.modelState('ko'), RecognitionModelState.downloading);
      plugin.downloaded.add('ko');
      wifi.complete('success');
      await pumpEventQueue();
      expect(wifiDone, isTrue);
    });

    test('download answered not "success" → download-failed; then a new '
        'request downloads again', () async {
      final engine = MlKitHandwritingRecognizer();
      plugin.onDownload = (_, _) async => 'error';
      await expectLater(
        engine.ensureModel('ko'),
        throwsA(_engineError('download-failed')),
      );
      expect(
        await engine.modelState('ko'),
        RecognitionModelState.notDownloaded,
      );
      plugin.onDownload = null;
      await engine.ensureModel('ko');
      expect(plugin.manageCalls('download'), hasLength(2));
    });

    test('ensureModel errors: invalid tag → unsupported-language, no plugin '
        '→ RecognizerUnsupported', () async {
      final engine = MlKitHandwritingRecognizer();
      plugin.onCheck = (_) =>
          throw PlatformException(code: 'Model Identifier error');
      await expectLater(
        engine.ensureModel('xx'),
        throwsA(_engineError('unsupported-language')),
      );
      plugin.onCheck = (_) => throw MissingPluginException();
      await expectLater(
        engine.ensureModel('ko'),
        throwsA(isA<RecognizerUnsupported>()),
      );
    });

    test('deleteModel → the delete task, then modelChanges; not "success" '
        '→ delete-failed', () async {
      final engine = MlKitHandwritingRecognizer();
      final changes = <String>[];
      engine.modelChanges.listen(changes.add);
      plugin.downloaded.add('en');
      await engine.deleteModel('en');
      expect(plugin.manageCalls('delete').single['model'], 'en');
      expect(plugin.downloaded, isEmpty);
      await pumpEventQueue();
      expect(changes, ['en']);
      plugin.deleteAnswer = 'error';
      await expectLater(
        engine.deleteModel('en'),
        throwsA(_engineError('delete-failed')),
      );
      await pumpEventQueue();
      expect(changes, ['en']);
    });
  });

  group('models (iOS model manager)', () {
    test('every request of a tag joins (wifiOnly ignored); modelState while '
        'it runs → downloading without asking the plugin', () async {
      final engine = MlKitHandwritingRecognizer(platform: TargetPlatform.iOS);
      final done = Completer<Object?>();
      plugin.onDownload = (model, _) => done.future.then((v) {
        plugin.downloaded.add(model);
        return v;
      });
      final a = engine.ensureModel('ko');
      final b = engine.ensureModel('ko', wifiOnly: false);
      await pumpEventQueue();
      expect(plugin.manageCalls('download'), hasLength(1));
      final checks = plugin.manageCalls('check').length;
      expect(await engine.modelState('ko'), RecognitionModelState.downloading);
      expect(plugin.manageCalls('check'), hasLength(checks));
      done.complete('success');
      await Future.wait([a, b]);
      expect(await engine.modelState('ko'), RecognitionModelState.ready);
    });

    test("'cancelled' / 'download_in_progress' → polls until the model is "
        'there, then modelChanges', () {
      for (final code in ['cancelled', 'download_in_progress']) {
        fakeAsync((async) {
          final engine = MlKitHandwritingRecognizer(
            platform: TargetPlatform.iOS,
          );
          final changes = <String>[];
          engine.modelChanges.listen(changes.add);
          plugin.calls.clear();
          plugin.downloaded.clear();
          plugin.onDownload = (_, _) async =>
              throw PlatformException(code: code);
          var done = false;
          engine.ensureModel('ko').then((_) => done = true);
          async.flushMicrotasks();
          expect(plugin.manageCalls('check'), hasLength(1)); // before download
          async.elapse(const Duration(seconds: 2));
          expect(plugin.manageCalls('check'), hasLength(2));
          expect(done, isFalse, reason: code);
          plugin.downloaded.add('ko');
          async.elapse(const Duration(seconds: 2));
          expect(done, isTrue, reason: code);
          expect(changes, ['ko']);
          async.elapse(const Duration(seconds: 10));
          expect(plugin.manageCalls('check'), hasLength(3)); // polling ended
        });
      }
    });

    test('polling gives up after its limit → download-failed', () {
      fakeAsync((async) {
        final engine = MlKitHandwritingRecognizer(
          platform: TargetPlatform.iOS,
          pollLimit: const Duration(seconds: 6),
        );
        plugin.onDownload = (_, _) async =>
            throw PlatformException(code: 'cancelled');
        Object? error;
        engine
            .ensureModel('ko')
            .then<void>((_) {}, onError: (Object e) => error = e);
        async.elapse(const Duration(seconds: 5));
        expect(error, isNull);
        async.elapse(const Duration(seconds: 1));
        expect(error, _engineError('download-failed'));
      });
    });
  });

  group('dispose', () {
    test('closes every cached recognizer (not awaited — Android never '
        'answers close); later calls → disposed; idempotent', () async {
      plugin.onRecognize = null;
      final engine = MlKitHandwritingRecognizer();
      await engine.recognizeLine(_line(), languageTag: 'ko');
      await engine.recognizeLine(_line(), languageTag: 'en');
      final ids = {for (final a in plugin.recognitions) a['id']};
      expect(ids, hasLength(2));
      var streamDone = false;
      engine.modelChanges.listen(null, onDone: () => streamDone = true);
      await engine.dispose();
      await engine.dispose();
      await pumpEventQueue();
      expect(plugin.closedIds.toSet(), ids);
      expect(plugin.closedIds, hasLength(2));
      expect(streamDone, isTrue);
      await expectLater(
        engine.recognizeLine(_line(), languageTag: 'ko'),
        throwsA(_engineError('disposed')),
      );
      await expectLater(
        engine.modelState('ko'),
        throwsA(_engineError('disposed')),
      );
      await expectLater(
        engine.ensureModel('ko'),
        throwsA(_engineError('disposed')),
      );
      await expectLater(
        engine.deleteModel('ko'),
        throwsA(_engineError('disposed')),
      );
    });

    test('a running download is not awaited (its request fails disposed); a '
        'queued line fails disposed', () async {
      final engine = MlKitHandwritingRecognizer();
      plugin.onDownload = (_, _) => Completer<Object?>().future;
      final first = Completer<Object?>();
      plugin.onRecognize = (_) => first.future;
      final download = engine.ensureModel('ko');
      final a = engine.recognizeLine(_line(), languageTag: 'ko');
      final b = engine.recognizeLine(_line(), languageTag: 'ko');
      await pumpEventQueue();
      // Listen before dispose: the errors arrive during it.
      final downloadFails = expectLater(
        download,
        throwsA(_engineError('disposed')),
      );
      final aFails = expectLater(a, throwsA(_engineError('disposed')));
      final bFails = expectLater(b, throwsA(_engineError('disposed')));
      await engine.dispose();
      await downloadFails;
      first.complete([
        {'text': 'late', 'score': 0.0},
      ]);
      await aFails;
      await bFails;
      expect(plugin.recognitions, hasLength(1));
    });
  });
}
