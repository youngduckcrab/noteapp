// lib/src/ondevice/on_device_math_recognizer.dart — (internal) the
// on-device math engine (MathRecognizer): handwritten strokes → LaTeX with
// the downloaded model, nothing leaves the device (no consent gate — G-3 is
// about the external service).
//
// One call: the traces → pixel values ([preprocess] — a background isolate
// in the app, mfr_raster.dart) → encoder once + greedy decoder
// (mfr_runtime.dart; the runtime runs the model off the UI thread) → ids →
// text (mfr_tokenizer.dart) → normalised LaTeX (latex_normalizer.dart, with
// InkMathRenderer.validate). A result that still does not render is
// returned all the same: the sheets put it in the field for the user to
// edit (6.14.4).
//
// Calls run one at a time (the pad cancels the older one — 6.11.6): a call
// waits for the one before it. `cancel` is checked before every model call
// → RecognizerCancelled. Failures: no ink / nothing decoded →
// RecognizerEngineError('empty'); the model files cannot be opened →
// RecognizerEngineError('model-load') (the next call tries again); any
// other engine error → RecognizerEngineError('ondevice'). The runtime and
// the tokenizer are opened on the first call and kept until [dispose].
import 'dart:async';
import 'dart:typed_data';

import 'package:ink_engine/ink_engine.dart' show InkMathRenderer;

import '../common/engine_ids.dart';
import '../model/failures.dart';
import '../model/handwriting_trace.dart';
import '../model/math_types.dart';
import '../ports/math_recognizer.dart';
import 'latex_normalizer.dart';
import 'mfr_runtime.dart';
import 'mfr_tokenizer.dart';

/// The pixel values of the traces (null = no point at all).
typedef MfrPreprocess = Future<Float32List?> Function(
  List<HandwritingTrace> traces,
);

final class OnDeviceMathRecognizer implements MathRecognizer {
  OnDeviceMathRecognizer({
    required this._openRuntime,
    required this._loadTokenizer,
    required this._preprocess,
    this._validate = InkMathRenderer.validate,
    this.maxNewTokens = kMfrMaxNewTokens,
  });

  final Future<MfrRuntime> Function() _openRuntime;
  final Future<MfrTokenizer> Function() _loadTokenizer;
  final MfrPreprocess _preprocess;
  final String? Function(String latex)? _validate;
  final int maxNewTokens;

  Future<MfrRuntime>? _runtime;
  Future<MfrTokenizer>? _tokenizer;
  Future<void> _queue = Future<void>.value();
  bool _disposed = false;

  @override
  String get engineId => kOnDeviceMathEngineId;

  @override
  bool get isAvailable => !_disposed;

  @override
  Future<MathResult> recognize(MathInput input, {Future<void>? cancel}) {
    final stopwatch = Stopwatch()..start();
    var cancelled = false;
    if (cancel != null) {
      unawaited(
        cancel.then<void>(
          (_) => cancelled = true,
          onError: (_) {
            cancelled = true;
          },
        ),
      );
    }
    final previous = _queue;
    final done = Completer<void>();
    _queue = done.future;
    Future<MathResult> run() async {
      try {
        await previous;
      } on Object {
        // the previous call's failure is its own
      }
      try {
        return await _recognize(input, () => cancelled, stopwatch);
      } finally {
        done.complete();
      }
    }

    return run();
  }

  Future<MathResult> _recognize(
    MathInput input,
    bool Function() cancelled,
    Stopwatch stopwatch,
  ) async {
    if (_disposed) throw RecognizerEngineError('disposed', 'engine disposed');
    if (cancelled()) throw RecognizerCancelled();
    final pixels = await _preprocess(input.traces);
    if (pixels == null) {
      throw RecognizerEngineError('empty', 'no ink to recognize');
    }
    if (cancelled()) throw RecognizerCancelled();
    final (runtime, tokenizer) = await _open();
    if (cancelled()) throw RecognizerCancelled();
    final MfrDecoded decoded;
    try {
      decoded = await runMfrGreedy(
        runtime,
        pixels,
        cancelled: () => cancelled() || _disposed,
        maxNewTokens: maxNewTokens,
      );
    } on MfrCancelled {
      throw RecognizerCancelled();
    } on RecognitionFailure {
      rethrow;
    } on Object catch (e) {
      throw RecognizerEngineError('ondevice', '$e');
    }
    final raw = tokenizer.decode(decoded.ids);
    final latex = normalizeMfrLatex(raw, validate: _validate);
    if (latex.isEmpty) {
      throw RecognizerEngineError('empty', 'the model wrote nothing');
    }
    return MathResult(
      latex: latex,
      confidence: decoded.confidence,
      engineId: engineId,
      latency: stopwatch.elapsed,
    );
  }

  Future<(MfrRuntime, MfrTokenizer)> _open() async {
    final runtime = _runtime ??= _openRuntime();
    final tokenizer = _tokenizer ??= _loadTokenizer();
    try {
      return (await runtime, await tokenizer);
    } on Object catch (e) {
      // the next call opens the files again
      if (identical(_runtime, runtime)) _runtime = null;
      if (identical(_tokenizer, tokenizer)) _tokenizer = null;
      unawaited(runtime.then<void>((r) => r.close(), onError: (Object _) {}));
      throw RecognizerEngineError('model-load', '$e');
    }
  }

  /// Closes the model sessions (after the running call); later calls fail.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _queue;
    } on Object {
      // ignored
    }
    final runtime = _runtime;
    _runtime = null;
    _tokenizer = null;
    if (runtime == null) return;
    try {
      await (await runtime).close();
    } on Object {
      // a runtime that failed to open has nothing to close
    }
  }
}
