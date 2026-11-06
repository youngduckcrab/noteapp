// package:ink_recognition/testing.dart fake engines and SyntheticHandwriting
// (contract m5-7/00-overview 7.6; m5-7/05-library 4.3, 8.1 B6-b): the
// default answers '줄 1', '줄 2', failNext / failWith, latency without real
// time (fake_async), cancel, and the CP-L4 members.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';
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

  group('SyntheticHandwriting (R2-B6: simple, contract id format)', () {
    test('ids syn_<seed>_l<line>_<n>, createdAt increases, deterministic', () {
      final strokes = SyntheticHandwriting.lines(pageId: 'p1', seed: 7);
      expect(strokes, isNotEmpty);
      final idPattern = RegExp(r'^syn_7_l(\d\d)_(\d{4})$');
      final lines = <int>{};
      for (var i = 0; i < strokes.length; i++) {
        final s = strokes[i];
        final m = idPattern.firstMatch(s.id);
        expect(m, isNotNull, reason: s.id);
        expect(int.parse(m!.group(2)!), i); // n = stroke number on the page
        lines.add(int.parse(m.group(1)!));
        expect(s.pageId, 'p1');
        expect(s.id.length, lessThanOrEqualTo(64));
        if (i > 0) {
          expect(s.createdAt, greaterThan(strokes[i - 1].createdAt));
          // line numbers never go back
          expect(
            int.parse(idPattern.firstMatch(s.id)!.group(1)!),
            greaterThanOrEqualTo(
              int.parse(idPattern.firstMatch(strokes[i - 1].id)!.group(1)!),
            ),
          );
        }
      }
      expect(lines, {0, 1, 2, 3, 4}); // lineCount default 5

      final again = SyntheticHandwriting.lines(pageId: 'p1', seed: 7);
      expect(again.map((s) => s.id), strokes.map((s) => s.id));
      expect(
        again.map((s) => s.points.rawData.toList()),
        strokes.map((s) => s.points.rawData.toList()),
      );
      final other = SyntheticHandwriting.lines(pageId: 'p1', seed: 8);
      expect(other.first.id, startsWith('syn_8_l00_'));
    });

    test('lineCount, ballpoint style, points in page pt with 8 ms spacing', () {
      final strokes = SyntheticHandwriting.lines(pageId: 'p2', lineCount: 12);
      final lineOf = strokes.map((s) => s.id.substring(7, 9)).toSet();
      expect(lineOf, hasLength(12));
      for (final s in strokes) {
        expect(s.style, core.StrokeStyle.defaultsFor(core.PenTool.ballpoint));
        for (var i = 0; i < s.points.length; i++) {
          expect(s.points.x(i), inInclusiveRange(40, 555));
          expect(s.points.t(i), i * 8);
        }
      }
      expect(SyntheticHandwriting.lines(pageId: 'p', lineCount: 0), isEmpty);
      expect(
        () => SyntheticHandwriting.lines(pageId: 'p', lineCount: 100),
        throwsArgumentError,
      );
    });
  });
}
