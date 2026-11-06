// lib/src/testing/fake_recognizers.dart — body of package:ink_recognition/
// testing.dart (contract m5-7/00-overview 7.6 '기반 단계 시험 도우미',
// m5-7/05-library 4.3). Web safe, no flutter_test import, no real time
// unless a latency is given.
//
// 2차 foundation step R2-B6. (L2-10a) FakeHandwritingRecognizer also
// implements the internal RecognizerModelAdmin (6.7.4 — no new public name):
// modelChanges after ensureModel / deleteModel, enforcesWifiOnly settable
// (true = Android; false = iOS, where the indexer never downloads itself).
import 'dart:async';

import '../model/candidates.dart';
import '../model/failures.dart';
import '../model/handwriting_trace.dart';
import '../model/math_types.dart';
import '../ports/handwriting_recognizer.dart';
import '../ports/math_recognizer.dart';
import '../ports/model_admin.dart';

/// Waits [latency] (no timer when zero). With [cancel], the wait ends early
/// with [RecognizerCancelled] when [cancel] completes first.
Future<void> _wait(Duration latency, {Future<void>? cancel}) async {
  if (cancel == null) {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return;
  }
  final done = Completer<bool>();
  Timer? timer;
  if (latency > Duration.zero) {
    timer = Timer(latency, () {
      if (!done.isCompleted) done.complete(false);
    });
  } else {
    scheduleMicrotask(() {
      if (!done.isCompleted) done.complete(false);
    });
  }
  unawaited(
    cancel.then(
      (_) {
        if (!done.isCompleted) done.complete(true);
      },
      onError: (Object _) {
        if (!done.isCompleted) done.complete(true);
      },
    ),
  );
  final cancelled = await done.future;
  timer?.cancel();
  if (cancelled) throw RecognizerCancelled();
}

final class FakeHandwritingRecognizer
    implements HandwritingRecognizer, RecognizerModelAdmin {
  /// [answer] default: `'줄 <n>'` for the n-th call; engineId 'fake'.
  FakeHandwritingRecognizer({
    this._answer, // answer:
    this._isAvailable = true, // isAvailable:
    this._latency = Duration.zero, // latency:
  });

  final String Function(HandwritingLineInput line)? _answer;
  final bool _isAvailable;
  final Duration _latency;
  bool _disposed = false;

  /// Every recognizeLine call in order (line, languageTag).
  final List<(HandwritingLineInput, String)> calls = [];

  /// Thrown by the next recognizeLine (then cleared). Lets tests drive ModelNotReady etc.
  RecognitionFailure? failNext;

  /// modelState answers; a tag that is missing → RecognitionModelState.ready.
  final Map<String, RecognitionModelState> modelStates = {};
  int ensureModelCalls = 0;

  bool get disposed => _disposed;

  final StreamController<String> _modelChanges =
      StreamController<String>.broadcast();

  /// (internal RecognizerModelAdmin) true = Android (honours wifiOnly);
  /// false = iOS (the indexer waits for a download the user starts).
  @override
  bool enforcesWifiOnly = true;

  /// (internal RecognizerModelAdmin) the tag after every successful
  /// ensureModel and deleteModel; closed by dispose.
  @override
  Stream<String> get modelChanges => _modelChanges.stream;

  /// (internal RecognizerModelAdmin) the model of [languageTag] becomes
  /// notDownloaded; then modelChanges.
  @override
  Future<void> deleteModel(String languageTag) async {
    if (!_isAvailable) throw RecognizerUnsupported();
    modelStates[languageTag] = RecognitionModelState.notDownloaded;
    _modelChanged(languageTag);
  }

  void _modelChanged(String languageTag) {
    if (!_modelChanges.isClosed) _modelChanges.add(languageTag);
  }

  @override
  String get engineId => 'fake';

  @override
  bool get isAvailable => _isAvailable;

  /// Not available → RecognitionModelState.unsupported for every tag.
  @override
  Future<RecognitionModelState> modelState(String languageTag) async {
    if (!_isAvailable) return RecognitionModelState.unsupported;
    return modelStates[languageTag] ?? RecognitionModelState.ready;
  }

  /// Counts the call; then the model of [languageTag] is ready (and
  /// modelChanges gets the tag). Not available → RecognizerUnsupported (like
  /// the real engines).
  @override
  Future<void> ensureModel(String languageTag, {bool wifiOnly = true}) async {
    ensureModelCalls++;
    if (!_isAvailable) throw RecognizerUnsupported();
    modelStates[languageTag] = RecognitionModelState.ready;
    _modelChanged(languageTag);
  }

  /// Records the call first (failed calls too), then: not available →
  /// RecognizerUnsupported, [failNext] → thrown once, otherwise waits the
  /// latency and answers `answer(line)` plus two variants (`'<text>?'`,
  /// `'<text>!'`) with a null score.
  @override
  Future<List<TextCandidate>> recognizeLine(
    HandwritingLineInput line, {
    required String languageTag,
  }) async {
    calls.add((line, languageTag));
    final n = calls.length;
    if (!_isAvailable) throw RecognizerUnsupported();
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
    await _wait(_latency);
    final text = _answer?.call(line) ?? '줄 $n';
    return [
      TextCandidate(text, languageTag: languageTag),
      TextCandidate('$text?', languageTag: languageTag),
      TextCandidate('$text!', languageTag: languageTag),
    ];
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    unawaited(_modelChanges.close());
  }
}

final class FakeMathRecognizer implements MathRecognizer {
  FakeMathRecognizer({
    this._latex = r'x^2', // latex:
    this._failWith, // failWith:
    this._latency = Duration.zero, // latency:
  });

  final String _latex;
  final RecognitionFailure? _failWith;
  final Duration _latency;

  /// Every recognize call in order (failed calls too).
  final List<MathInput> calls = [];

  /// copied into MathResult.alternatives
  List<String> alternatives = const [];

  /// false → like ManualOnlyMathRecognizer
  @override
  bool isAvailable = true;

  @override
  String get engineId => 'fake';

  /// Records the call, then: not available → RecognizerUnsupported, failWith
  /// → thrown (every call), otherwise waits the latency (a completed [cancel]
  /// ends it with RecognizerCancelled) and answers MathResult(latex,
  /// engineId 'fake/1' — the functions/ fake engine's app id, 7.6).
  @override
  Future<MathResult> recognize(MathInput input, {Future<void>? cancel}) async {
    calls.add(input);
    if (!isAvailable) throw RecognizerUnsupported();
    final failure = _failWith;
    if (failure != null) throw failure;
    await _wait(_latency, cancel: cancel);
    return MathResult(
      latex: _latex,
      alternatives: List.unmodifiable(alternatives),
      engineId: 'fake/1',
      latency: _latency,
    );
  }
}
