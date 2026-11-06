// package:ink_recognition/testing.dart fake engines (contract
// m5-7/00-overview 7.6; m5-7/05-library 4.3, 8.1 B6-b): the default answers
// '줄 1', '줄 2', failNext / failWith, latency without real time
// (fake_async), cancel, the CP-L4 members and (L2-10a) the internal
// RecognizerModelAdmin of the handwriting fake. SyntheticHandwriting moved to
// unit/synthetic_handwriting_test.dart with the 6.6 v2.1 generator (L2-05).
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/ports/model_admin.dart';
import 'package:ink_recognition/testing.dart';
import 'package:note_core/note_core.dart' as core;

const _line = HandwritingLineInput([]);

void main() {
  group('FakeHandwritingRecognizer', () {
    test('engineId fake; default answers 줄 1, 줄 2 with two variants', () async {
      final fake = FakeHandwritingRecognizer();
      expect(fake.engineId, 'fake');
      expect(fake.isAvailable, isTrue);

      final first = await fake.recognizeLine(_line, languageTag: 'ko');
      final second = await fake.recognizeLine(_line, languageTag: 'en');
      expect(first.map((c) => c.text), ['줄 1', '줄 1?', '줄 1!']);
      expect(second.map((c) => c.text), ['줄 2', '줄 2?', '줄 2!']);
      expect(
        first.every((c) => c.languageTag == 'ko' && c.score == null),
        isTrue,
      );
      expect(second.first.languageTag, 'en');
      expect(fake.calls, hasLength(2));
      expect(fake.calls[0].$1, same(_line));
      expect(fake.calls.map((c) => c.$2), ['ko', 'en']);
    });

    test('answer callback receives the line', () async {
      final fake = FakeHandwritingRecognizer(
        answer: (line) => '획 ${line.traces.length}개',
      );
      final out = await fake.recognizeLine(
        HandwritingLineInput([
          HandwritingTrace.fromStroke(
            core.Stroke(
              id: 's1',
              pageId: 'p1',
              style: core.StrokeStyle.defaultsFor(core.PenTool.ballpoint),
              points: core.StrokePoints.fromList(const [
                core.StrokePoint(1, 1),
              ]),
              createdAt: 1,
            ),
          ),
        ]),
        languageTag: 'ko',
      );
      expect(out.first, const TextCandidate('획 1개', languageTag: 'ko'));
    });

    test(
      'failNext is thrown once, then cleared; the call is recorded',
      () async {
        final fake = FakeHandwritingRecognizer()
          ..failNext = ModelNotReady('ko');
        await expectLater(
          fake.recognizeLine(_line, languageTag: 'ko'),
          throwsA(
            isA<ModelNotReady>().having((e) => e.languageTag, 'tag', 'ko'),
          ),
        );
        expect(fake.failNext, isNull);
        expect(fake.calls, hasLength(1));
        final next = await fake.recognizeLine(_line, languageTag: 'ko');
        expect(next.first.text, '줄 2'); // n counts every call
      },
    );

    test(
      'modelStates: missing tag → ready; ensureModel counts and readies',
      () async {
        final fake = FakeHandwritingRecognizer();
        expect(await fake.modelState('ko'), RecognitionModelState.ready);
        fake.modelStates['en'] = RecognitionModelState.notDownloaded;
        expect(
          await fake.modelState('en'),
          RecognitionModelState.notDownloaded,
        );
        expect(fake.ensureModelCalls, 0);
        await fake.ensureModel('en');
        await fake.ensureModel('en', wifiOnly: false);
        expect(fake.ensureModelCalls, 2);
        expect(await fake.modelState('en'), RecognitionModelState.ready);
      },
    );

    test('disposed', () async {
      final fake = FakeHandwritingRecognizer();
      expect(fake.disposed, isFalse);
      await fake.dispose();
      expect(fake.disposed, isTrue);
    });

    test('(L2-10a) the internal RecognizerModelAdmin: modelChanges after '
        'ensureModel / deleteModel, enforcesWifiOnly settable', () async {
      final fake = FakeHandwritingRecognizer();
      expect(fake, isA<RecognizerModelAdmin>());
      expect(fake.enforcesWifiOnly, isTrue);
      final changes = <String>[];
      final sub = fake.modelChanges.listen(changes.add);
      await fake.ensureModel('en');
      await fake.deleteModel('ko');
      await pumpEventQueue();
      expect(changes, ['en', 'ko']);
      expect(await fake.modelState('ko'), RecognitionModelState.notDownloaded);
      expect(await fake.modelState('en'), RecognitionModelState.ready);
      fake.enforcesWifiOnly = false;
      expect(fake.enforcesWifiOnly, isFalse);
      await fake.dispose(); // closes modelChanges
      await fake.ensureModel('ko'); // after dispose: no event, no error
      await pumpEventQueue();
      expect(changes, ['en', 'ko']);
      await sub.cancel();
    });

    test('isAvailable false → unsupported like the real engines', () async {
      final fake = FakeHandwritingRecognizer(isAvailable: false);
      expect(fake.isAvailable, isFalse);
      expect(await fake.modelState('ko'), RecognitionModelState.unsupported);
      await expectLater(
        fake.ensureModel('ko'),
        throwsA(isA<RecognizerUnsupported>()),
      );
      await expectLater(
        fake.recognizeLine(_line, languageTag: 'ko'),
        throwsA(isA<RecognizerUnsupported>()),
      );
      expect(fake.calls, hasLength(1));
    });

    test('latency waits without real time', () {
      fakeAsync((async) {
        final fake = FakeHandwritingRecognizer(
          latency: const Duration(milliseconds: 300),
        );
        List<TextCandidate>? out;
        fake.recognizeLine(_line, languageTag: 'ko').then((v) => out = v);
        async.elapse(const Duration(milliseconds: 299));
        expect(out, isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(out!.first.text, '줄 1');
      });
    });
  });

  group('FakeMathRecognizer', () {
    test(
      'default latex x^2, engine ids fake / fake/1, calls, alternatives',
      () async {
        final fake = FakeMathRecognizer();
        expect(fake.engineId, 'fake');
        expect(fake.isAvailable, isTrue);
        const input = MathInput(traces: []);
        final result = await fake.recognize(input);
        expect(
          result,
          const MathResult(
            latex: r'x^2',
            engineId: 'fake/1',
            latency: Duration.zero,
          ),
        );
        expect(fake.calls.single, same(input));

        fake.alternatives = ['x2', 'x^{2}'];
        final again = await fake.recognize(input);
        expect(again.alternatives, ['x2', 'x^{2}']);
        expect(fake.calls, hasLength(2));
      },
    );

    test('latex and latency arguments', () {
      fakeAsync((async) {
        final fake = FakeMathRecognizer(
          latex: r'\frac{1}{2}',
          latency: const Duration(seconds: 2),
        );
        MathResult? result;
        fake.recognize(const MathInput(traces: [])).then((r) => result = r);
        async.elapse(const Duration(milliseconds: 1999));
        expect(result, isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(result!.latex, r'\frac{1}{2}');
        expect(result!.latency, const Duration(seconds: 2));
      });
    });

    test('failWith is thrown on every call', () async {
      final fake = FakeMathRecognizer(failWith: RecognizerOffline());
      for (var i = 0; i < 2; i++) {
        await expectLater(
          fake.recognize(const MathInput(traces: [])),
          throwsA(isA<RecognizerOffline>()),
        );
      }
      expect(fake.calls, hasLength(2));
    });

    test(
      'isAvailable false → RecognizerUnsupported (like ManualOnly)',
      () async {
        final fake = FakeMathRecognizer()..isAvailable = false;
        expect(fake.isAvailable, isFalse);
        await expectLater(
          fake.recognize(const MathInput(traces: [])),
          throwsA(isA<RecognizerUnsupported>()),
        );
      },
    );

    test(
      'a cancel that completes during the latency → RecognizerCancelled',
      () {
        fakeAsync((async) {
          final fake = FakeMathRecognizer(latency: const Duration(seconds: 1));
          Object? error;
          MathResult? result;
          fake
              .recognize(
                const MathInput(traces: []),
                cancel: Future<void>.delayed(const Duration(milliseconds: 200)),
              )
              .then<void>(
                (r) => result = r,
                onError: (Object e) {
                  error = e;
                },
              );
          async.elapse(const Duration(seconds: 2));
          expect(result, isNull);
          expect(error, isA<RecognizerCancelled>());
        });
      },
    );

    test('a cancel that never completes does not stop the answer', () {
      fakeAsync((async) {
        final fake = FakeMathRecognizer(latency: const Duration(seconds: 1));
        MathResult? result;
        fake
            .recognize(
              const MathInput(traces: []),
              cancel: Future<void>.delayed(const Duration(days: 1)),
            )
            .then((r) => result = r);
        async.elapse(const Duration(seconds: 1));
        expect(result!.latex, r'x^2');
        async.elapse(const Duration(days: 1)); // the cancel later: nothing
      });
    });
  });
}
