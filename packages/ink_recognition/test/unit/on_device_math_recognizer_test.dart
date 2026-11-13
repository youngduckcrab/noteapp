// OnDeviceMathRecognizer + runMfrGreedy (ondevice/on_device_math_recognizer
// .dart, mfr_runtime.dart) with a fake model runtime: the encoder input
// shape, the encoder once, the decoder fed the whole sequence each step,
// argmax of the last position, </s> ends, the 200-token cap, shape errors,
// cancellation (before and between steps), the encoder output always
// released, the tokenizer + normaliser on the result (with the matrix ink
// gutters), one call at a time, model-load failures retried, dispose.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/src/common/engine_ids.dart';
import 'package:ink_recognition/src/model/failures.dart';
import 'package:ink_recognition/src/model/handwriting_trace.dart';
import 'package:ink_recognition/src/model/math_types.dart';
import 'package:ink_recognition/src/ondevice/mfr_raster.dart';
import 'package:ink_recognition/src/ondevice/mfr_runtime.dart';
import 'package:ink_recognition/src/ondevice/mfr_tokenizer.dart';
import 'package:ink_recognition/src/ondevice/on_device_math_recognizer.dart';

const int _pixels = 3 * kMfrImageSize * kMfrImageSize;

final class _Hidden implements MfrHidden {
  _Hidden(this.shape);
  @override
  final List<int> shape;
}

/// Answers script[t − 1] for a sequence of t ids (the last position's
/// argmax); records every call.
final class FakeRuntime implements MfrRuntime {
  FakeRuntime(
    this.script, {
    this.hiddenShape = kMfrHiddenShape,
    this.badLogitsAt,
    this.stepGate,
  });

  final List<int> script;
  final List<int> hiddenShape;
  final int? badLogitsAt;

  /// Awaited before each decode step (tests hold the loop).
  final Future<void> Function(int step)? stepGate;
  final List<int> encodeLengths = [];
  final List<List<int>> decodeInputs = [];
  int releases = 0, closes = 0;

  @override
  Future<MfrHidden> encode(Float32List pixelValues) async {
    encodeLengths.add(pixelValues.length);
    return _Hidden(hiddenShape);
  }

  @override
  Future<({Float32List logits, List<int> shape})> decode(
    Int64List ids,
    MfrHidden hidden,
  ) async {
    final step = decodeInputs.length;
    await stepGate?.call(step);
    decodeInputs.add(List.of(ids));
    final t = ids.length;
    if (badLogitsAt == step) {
      return (logits: Float32List(10), shape: [1, t, 10]);
    }
    final logits = Float32List(t * kMfrVocabSize);
    // earlier positions point elsewhere: only the last one counts
    for (var p = 0; p < t; p++) {
      logits[p * kMfrVocabSize + 7] = 5;
    }
    final position = t - 1; // the script restarts with every formula
    final next = position < script.length ? script[position] : 3;
    logits[(t - 1) * kMfrVocabSize + 7] = 0;
    logits[(t - 1) * kMfrVocabSize + next] = 10;
    return (logits: logits, shape: [1, t, kMfrVocabSize]);
  }

  @override
  Future<void> release(MfrHidden hidden) async => releases++;

  @override
  Future<void> close() async => closes++;
}

/// ids 10.. → tokens: 10 'x', 11 'Ġ^', 12 'Ġ{', 13 'Ġ2', 14 'Ġ}'.
final MfrTokenizer _tokenizer = MfrTokenizer.fromJson(
  jsonEncode({
    'added_tokens': [
      for (final (i, t) in ['<pad>', '<s>', '</s>', '<unk>', '<mask>'].indexed)
        {'id': i, 'content': t, 'special': true},
    ],
    'model': {
      'vocab': {
        '<pad>': 0,
        '<s>': 1,
        '</s>': 2,
        '<unk>': 3,
        '<mask>': 4,
        'x': 10,
        'Ġ^': 11,
        'Ġ{': 12,
        'Ġ2': 13,
        'Ġ}': 14,
      },
    },
  }),
);

final MathInput _input = MathInput(
  traces: [
    HandwritingTrace(
      xs: Float32List.fromList([0, 10]),
      ys: Float32List.fromList([0, 10]),
      ts: Float64List.fromList([0, 8]),
    ),
  ],
);

Future<Float32List?> _preprocess(List<HandwritingTrace> traces) async =>
    traces.isEmpty ? null : Float32List(_pixels);

OnDeviceMathRecognizer _engine(
  FakeRuntime runtime, {
  Future<MfrRuntime> Function()? open,
  int maxNewTokens = kMfrMaxNewTokens,
}) => OnDeviceMathRecognizer(
  openRuntime: open ?? () async => runtime,
  loadTokenizer: () async => _tokenizer,
  preprocess: _preprocess,
  maxNewTokens: maxNewTokens,
);

void main() {
  group('runMfrGreedy', () {
    test('encoder once; decoder gets the whole sequence; argmax of the last '
        'position; </s> ends', () async {
      final runtime = FakeRuntime([10, 11, 12, 13, 14, kMfrEndId]);
      final out = await runMfrGreedy(runtime, Float32List(_pixels));
      expect(runtime.encodeLengths, [_pixels]);
      expect(runtime.decodeInputs, [
        [1],
        [1, 10],
        [1, 10, 11],
        [1, 10, 11, 12],
        [1, 10, 11, 12, 13],
        [1, 10, 11, 12, 13, 14],
      ]);
      expect(out.ids, [1, 10, 11, 12, 13, 14, 2]);
      expect(out.ended, isTrue);
      // softmax of 10 against 1867 zeros
      expect(out.confidence, closeTo(0.9219, 1e-3));
      expect(runtime.releases, 1);
    });

    test('at most maxNewTokens new ids without </s>', () async {
      final runtime = FakeRuntime(List.filled(500, 10));
      final out = await runMfrGreedy(runtime, Float32List(_pixels));
      expect(runtime.decodeInputs, hasLength(kMfrMaxNewTokens));
      expect(out.ids, hasLength(kMfrMaxNewTokens + 1));
      expect(out.ended, isFalse);
      final short = await runMfrGreedy(
        FakeRuntime(List.filled(10, 10)),
        Float32List(_pixels),
        maxNewTokens: 3,
      );
      expect(short.ids, [1, 10, 10, 10]);
    });

    test('wrong shapes: input size, encoder output, logits', () async {
      await expectLater(
        runMfrGreedy(FakeRuntime(const [2]), Float32List(10)),
        throwsArgumentError,
      );
      final badHidden = FakeRuntime(const [2], hiddenShape: const [1, 578]);
      await expectLater(
        runMfrGreedy(badHidden, Float32List(_pixels)),
        throwsA(isA<MfrShapeError>()),
      );
      expect(badHidden.releases, 1);
      final badLogits = FakeRuntime(const [10, 2], badLogitsAt: 1);
      await expectLater(
        runMfrGreedy(badLogits, Float32List(_pixels)),
        throwsA(isA<MfrShapeError>()),
      );
      expect(badLogits.releases, 1);
    });

    test('cancelled before the encoder / between steps', () async {
      final before = FakeRuntime(const [2]);
      await expectLater(
        runMfrGreedy(before, Float32List(_pixels), cancelled: () => true),
        throwsA(isA<MfrCancelled>()),
      );
      expect(before.encodeLengths, isEmpty);
      var stop = false;
      final between = FakeRuntime(
        List.filled(50, 10),
        stepGate: (step) async {
          if (step == 3) stop = true;
        },
      );
      await expectLater(
        runMfrGreedy(between, Float32List(_pixels), cancelled: () => stop),
        throwsA(isA<MfrCancelled>()),
      );
      expect(between.decodeInputs, hasLength(4));
      expect(between.releases, 1);
    });
  });

  group('OnDeviceMathRecognizer', () {
    test(
      'MathResult: normalised LaTeX, engine id, confidence, latency',
      () async {
        final runtime = FakeRuntime([10, 11, 12, 13, 14, kMfrEndId]);
        final engine = _engine(runtime);
        expect(engine.isAvailable, isTrue);
        expect(engine.engineId, kOnDeviceMathEngineId);
        final result = await engine.recognize(_input);
        expect(result.latex, 'x^{2}'); // raw 'x ^ { 2 }'
        expect(result.engineId, kOnDeviceMathEngineId);
        expect(result.confidence, greaterThan(0.9));
        expect(result.alternatives, isEmpty);
        expect(result.latency, isNot(Duration.zero));
      },
    );

    test('no ink / nothing decoded → RecognizerEngineError(empty)', () async {
      final engine = _engine(FakeRuntime(const [kMfrEndId]));
      await expectLater(
        engine.recognize(const MathInput(traces: [])),
        throwsA(
          isA<RecognizerEngineError>().having((e) => e.code, 'code', 'empty'),
        ),
      );
      await expectLater(
        engine.recognize(_input),
        throwsA(
          isA<RecognizerEngineError>().having((e) => e.code, 'code', 'empty'),
        ),
      );
    });

    test('cancel: done before → RecognizerCancelled without a model call; '
        'during the loop → RecognizerCancelled', () async {
      final runtime = FakeRuntime(List.filled(50, 10));
      final engine = _engine(runtime);
      await expectLater(
        engine.recognize(_input, cancel: Future<void>.value()),
        throwsA(isA<RecognizerCancelled>()),
      );
      expect(runtime.encodeLengths, isEmpty);

      final gate = Completer<void>();
      final cancel = Completer<void>();
      final held = FakeRuntime(
        List.filled(50, 10),
        stepGate: (step) => step == 2 ? gate.future : Future.value(),
      );
      final e2 = _engine(held);
      final call = e2.recognize(_input, cancel: cancel.future);
      await pumpEventQueue();
      cancel.complete();
      await pumpEventQueue();
      gate.complete();
      await expectLater(call, throwsA(isA<RecognizerCancelled>()));
      expect(held.decodeInputs.length, lessThanOrEqualTo(4));
      expect(held.releases, 1);
    });

    test(
      'engine errors → RecognizerEngineError(ondevice); a model that '
      'cannot be opened → model-load, opened again on the next call',
      () async {
        final bad = FakeRuntime(const [10, 2], badLogitsAt: 0);
        await expectLater(
          _engine(bad).recognize(_input),
          throwsA(
            isA<RecognizerEngineError>().having(
              (e) => e.code,
              'code',
              'ondevice',
            ),
          ),
        );
        var opens = 0;
        final good = FakeRuntime([10, kMfrEndId]);
        final engine = _engine(
          good,
          open: () async {
            opens++;
            if (opens == 1) throw StateError('no such file');
            return good;
          },
        );
        await expectLater(
          engine.recognize(_input),
          throwsA(
            isA<RecognizerEngineError>().having(
              (e) => e.code,
              'code',
              'model-load',
            ),
          ),
        );
        expect((await engine.recognize(_input)).latex, 'x');
        expect((await engine.recognize(_input)).latex, 'x');
        expect(opens, 2, reason: 'kept open after the first success');
      },
    );

    test('a preprocessing or decoding error → RecognizerEngineError'
        '(ondevice), not an unexpected error', () async {
      final runtime = FakeRuntime([10, kMfrEndId]);
      final engine = OnDeviceMathRecognizer(
        openRuntime: () async => runtime,
        loadTokenizer: () async => _tokenizer,
        preprocess: (_) async => throw StateError('isolate died'),
      );
      await expectLater(
        engine.recognize(_input),
        throwsA(
          isA<RecognizerEngineError>().having(
            (e) => e.code,
            'code',
            'ondevice',
          ),
        ),
      );
      expect(runtime.encodeLengths, isEmpty);

      final e2 = OnDeviceMathRecognizer(
        openRuntime: () async => FakeRuntime([10, kMfrEndId]),
        loadTokenizer: () async => _tokenizer,
        preprocess: _preprocess,
        validate: (_) => throw StateError('renderer broke'),
      );
      await expectLater(
        e2.recognize(_input),
        throwsA(
          isA<RecognizerEngineError>().having(
            (e) => e.code,
            'code',
            'ondevice',
          ),
        ),
      );
    });

    test('the token cap without </s> → still a result, confidence 0', () async {
      final engine = _engine(FakeRuntime(List.filled(50, 10)), maxNewTokens: 5);
      final result = await engine.recognize(_input);
      expect(result.latex, isNotEmpty);
      expect(result.confidence, 0.0);
      final ended = await _engine(
        FakeRuntime([10, kMfrEndId]),
        maxNewTokens: 5,
      ).recognize(_input);
      expect(ended.confidence, greaterThan(0.9));
    });

    test('one call at a time: the second waits for the first', () async {
      final gate = Completer<void>();
      final runtime = FakeRuntime([
        10,
        kMfrEndId,
      ], stepGate: (step) => step == 0 ? gate.future : Future.value());
      final engine = _engine(runtime);
      final first = engine.recognize(_input);
      final second = engine.recognize(_input);
      await pumpEventQueue();
      expect(runtime.encodeLengths, hasLength(1));
      gate.complete();
      expect((await first).latex, 'x');
      expect((await second).latex, 'x');
      expect(runtime.encodeLengths, hasLength(2));
      expect(runtime.releases, 2);
    });

    test('the ink gutters reach the normaliser: a one-column matrix of '
        'digits splits only when the ink shows its columns', () async {
      // ids 20.. → `\left[ \begin{matrix} { 1 2 } \\ { 3 4 } \end{matrix}
      // \right]`
      const pieces = [
        r'\left', 'Ġ[', r'Ġ\begin{matrix}', 'Ġ{', 'Ġ1', 'Ġ2', 'Ġ}', //
        r'Ġ\\', 'Ġ3', 'Ġ4', r'Ġ\end{matrix}', r'Ġ\right', 'Ġ]',
      ];
      final tokenizer = MfrTokenizer.fromJson(
        jsonEncode({
          'added_tokens': [
            for (final (i, t) in ['<pad>', '<s>', '</s>'].indexed)
              {'id': i, 'content': t, 'special': true},
          ],
          'model': {
            'vocab': {
              '<pad>': 0,
              '<s>': 1,
              '</s>': 2,
              for (final (i, t) in pieces.indexed) t: 20 + i,
            },
          },
        }),
      );
      final script = [
        20, 21, 22, 23, 24, 25, 26, 27, 23, 28, 29, 26, 30, 31, 32, //
        kMfrEndId,
      ];
      HandwritingTrace stroke(List<double> xy) => HandwritingTrace(
        xs: Float32List.fromList([
          for (var i = 0; i < xy.length; i += 2) xy[i],
        ]),
        ys: Float32List.fromList([
          for (var i = 1; i < xy.length; i += 2) xy[i],
        ]),
        ts: Float64List.fromList([
          for (var i = 0; i < xy.length ~/ 2; i++) i * 10.0,
        ]),
      );
      // `[`, two rows of 8 × 10 glyphs at the x positions, `]`
      MathInput ink(double second, double close) => MathInput(
        traces: [
          stroke([0, 0, 0, 40]),
          stroke([0, 0, 5, 0]),
          stroke([0, 40, 5, 40]),
          for (final y in [5.0, 25.0])
            for (final x in [10.0, second])
              stroke([x, y, x + 8, y, x + 8, y + 10, x, y + 10, x, y + 2]),
          stroke([close, 0, close, 40]),
          stroke([close - 5, 0, close, 0]),
          stroke([close - 5, 40, close, 40]),
        ],
      );
      OnDeviceMathRecognizer? last;
      Future<String> latex(MathInput input) async =>
          (await (last = OnDeviceMathRecognizer(
            openRuntime: () async => FakeRuntime(script),
            loadTokenizer: () async => tokenizer,
            preprocess: _preprocess,
          )).recognize(input)).latex;

      // a gap of half the glyph height: two columns
      expect(await latex(ink(23, 41)), r'\begin{bmatrix}1&2\\3&4\end{bmatrix}');
      // the developer overlay's record of the run: raw, cleaned, gutters
      final run = last!.lastRun.value!;
      expect(run.raw, contains(r'\begin{matrix}'));
      expect(run.latex, r'\begin{bmatrix}1&2\\3&4\end{bmatrix}');
      expect(run.gutters, 1);
      // digits written close: two-digit numbers
      expect(
        await latex(ink(19, 37)),
        r'\begin{bmatrix}{12}\\{34}\end{bmatrix}',
      );
    });

    test('dispose closes the runtime; later calls fail', () async {
      final runtime = FakeRuntime([10, kMfrEndId]);
      final engine = _engine(runtime);
      await engine.recognize(_input);
      await engine.dispose();
      await engine.dispose();
      expect(runtime.closes, 1);
      expect(engine.isAvailable, isFalse);
      await expectLater(
        engine.recognize(_input),
        throwsA(isA<RecognizerEngineError>()),
      );
    });
  });
}
