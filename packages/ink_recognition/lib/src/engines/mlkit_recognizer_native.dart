// lib/src/engines/mlkit_recognizer_native.dart — (internal) the native side
// of platform_recognizer.dart (m5-7/05-library 6.7.1, 6.7.2). The ONLY file
// that may import ML Kit (native_only_imports, `as mlkit` — R4).
//
// L2-07: the choice by platform (defaultTargetPlatform, never dart:io
// Platform — 7.4.1). L2-08: MlKitHandwritingRecognizer on Android / iOS.
//
// The adapter (6.7.2 – 6.7.4):
// - recognizeLine: the line's points moved so the line box's top-left is
//   (0, 0) (6.4 v2.1 — the writing area is measured from there), `t` =
//   ts[i].round() (13-digit int ms), context only with a preContext or a
//   writing area; candidates in engine order without blanks / duplicates;
//   10 s per line → RecognizerEngineError('timeout'); one native call at a
//   time (FIFO — the indexer and the conversion sheet share the instance).
// - modelState: a downloaded model is `ready` even while a request of this
//   instance still runs (a cellular download may finish before the Wi-Fi one
//   — L2-18); then `downloading` while a request runs, else `notDownloaded`;
//   an invalid tag or no plugin → `unsupported`.
// - ensureModel: a ready model ends at once (no download call); requests of
//   one tag with the same wifiOnly join; a request with the other wifiOnly
//   starts its own download (6.7.4 S-9) and the first success ends every
//   request of the tag, then modelChanges gets the tag. A failed request
//   fails alone. The iOS plugin ignores wifiOnly, so there every request of a
//   tag joins.
// - iOS model manager (google_mlkit_commons 0.13.0 GenericModelManager
//   .swift, checked): every vision#manageInkModels call makes a new manager,
//   and the replaced one answers its pending download 'cancelled' (ML Kit
//   goes on downloading); a second download of a model in progress answers
//   'download_in_progress'. Both → the request polls the model state until
//   the model is there (2 s, at most 20 min). While a request of a tag runs,
//   modelState on iOS answers `downloading` without asking (a check would
//   cancel that request's answer).
// - dispose: every cached recognizer close()d, not awaited (the Android
//   plugin never answers close — DigitalInkRecognizer.kt closeDetector);
//   running downloads are not awaited — their requests fail 'disposed', and
//   every later call throws RecognizerEngineError('disposed').
import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart'
    as mlkit;

import '../common/engine_ids.dart';
import '../model/candidates.dart';
import '../model/failures.dart';
import '../model/handwriting_trace.dart';
import '../ports/handwriting_recognizer.dart';
import '../ports/line_origin.dart';
import '../ports/model_admin.dart';
import 'mlkit_errors.dart';

/// Whether [platform] has an ML Kit handwriting engine (Android, iOS); the
/// desktops (development only) do not (6.7.1).
bool platformHasMlKit(TargetPlatform platform) =>
    platform == TargetPlatform.android || platform == TargetPlatform.iOS;

/// Native: ML Kit on Android / iOS, the unsupported engine on the desktops.
HandwritingRecognizer createPlatformHandwritingRecognizer() {
  final platform = defaultTargetPlatform;
  if (platformHasMlKit(platform)) {
    return MlKitHandwritingRecognizer(platform: platform);
  }
  return const UnsupportedHandwritingRecognizer();
}

/// Time limit of one line's native call (6.7.2).
const Duration kMlKitLineTimeout = Duration(seconds: 10);

/// iOS: how often a request that the plugin's model manager does not track
/// any more asks whether the model is there, and for how long.
const Duration kMlKitModelPollInterval = Duration(seconds: 2);
const Duration kMlKitModelPollLimit = Duration(minutes: 20);

/// The callers of one model's downloads: per download condition (wifiOnly;
/// always `true` on iOS, where the flag is ignored).
final class _TagDownloads {
  final Map<bool, Completer<void>> requests = {};
}

/// The ML Kit digital ink engine (google_mlkit_digital_ink_recognition).
final class MlKitHandwritingRecognizer
    implements
        HandwritingRecognizer,
        RecognizerModelAdmin,
        PageOriginLineRecognizer {
  /// [platform] defaults to defaultTargetPlatform (iOS → the iOS engine id
  /// and model rules, anything else → Android's). The durations are for
  /// tests (fake_async).
  MlKitHandwritingRecognizer({
    TargetPlatform? platform,
    this._lineTimeout = kMlKitLineTimeout, // lineTimeout:
    this._pollInterval = kMlKitModelPollInterval, // pollInterval:
    this._pollLimit = kMlKitModelPollLimit, // pollLimit:
  }) : _ios = (platform ?? defaultTargetPlatform) == TargetPlatform.iOS;

  final bool _ios;
  final Duration _lineTimeout, _pollInterval, _pollLimit;
  final mlkit.DigitalInkRecognizerModelManager _models =
      mlkit.DigitalInkRecognizerModelManager();
  final Map<String, mlkit.DigitalInkRecognizer> _recognizers = {};
  final Map<String, _TagDownloads> _downloads = {};
  final StreamController<String> _modelChanges =
      StreamController<String>.broadcast();

  /// The end of the last queued native recognition (FIFO).
  Future<void> _tail = Future<void>.value();
  bool _disposed = false;

  /// (v2.1) constants in common/engine_ids.dart only — provenance only.
  @override
  String get engineId => _ios ? kMlKitIosEngineId : kMlKitAndroidEngineId;

  @override
  bool get isAvailable => true;

  /// Android true (the download waits for Wi-Fi), iOS false (the plugin
  /// ignores the flag — the app asks before downloading, 6.7.4).
  @override
  bool get enforcesWifiOnly => !_ios;

  @override
  Stream<String> get modelChanges => _modelChanges.stream;

  RecognizerEngineError _disposedError() =>
      RecognizerEngineError('disposed', 'the ML Kit engine was disposed');

  void _checkNotDisposed() {
    if (_disposed) throw _disposedError();
  }

  void _emit(String languageTag) {
    if (!_modelChanges.isClosed) _modelChanges.add(languageTag);
  }

  // ---- models ------------------------------------------------------------

  @override
  Future<RecognitionModelState> modelState(String languageTag) async {
    _checkNotDisposed();
    if (_ios && _downloads.containsKey(languageTag)) {
      return RecognitionModelState.downloading;
    }
    final bool downloaded;
    try {
      downloaded = await _models.isModelDownloaded(languageTag);
    } on Object catch (e, s) {
      final failure = mlkitFailureOf(e, languageTag: languageTag);
      if (failure is RecognizerUnsupported || isUnsupportedLanguageError(e)) {
        return RecognitionModelState.unsupported;
      }
      Error.throwWithStackTrace(failure, s);
    }
    if (downloaded) return RecognitionModelState.ready;
    return _downloads.containsKey(languageTag)
        ? RecognitionModelState.downloading
        : RecognitionModelState.notDownloaded;
  }

  @override
  Future<void> ensureModel(String languageTag, {bool wifiOnly = true}) async {
    _checkNotDisposed();
    final condition = _ios || wifiOnly;
    final downloads = _downloads.putIfAbsent(languageTag, _TagDownloads.new);
    var request = downloads.requests[condition];
    if (request == null) {
      request = Completer<void>();
      downloads.requests[condition] = request;
      unawaited(_download(languageTag, wifiOnly, condition, downloads));
    }
    await request.future;
  }

  Future<void> _download(
    String tag,
    bool wifiOnly,
    bool condition,
    _TagDownloads downloads,
  ) async {
    try {
      if (await _models.isModelDownloaded(tag)) {
        _downloaded(tag, downloads, changed: false);
        return;
      }
      if (!await _models.downloadModel(tag, isWifiRequired: wifiOnly)) {
        throw RecognizerEngineError(
          'download-failed',
          'model $tag: the download did not succeed',
        );
      }
      _downloaded(tag, downloads, changed: true);
    } on Object catch (e, s) {
      if (!_disposed && isDownloadElsewhere(e)) {
        try {
          await _waitUntilDownloaded(tag);
          _downloaded(tag, downloads, changed: true);
        } on Object catch (e2, s2) {
          _failed(tag, downloads, condition, e2, s2);
        }
        return;
      }
      _failed(tag, downloads, condition, e, s);
    }
  }

  /// Polls until [tag]'s model is downloaded (iOS — see the file comment).
  Future<void> _waitUntilDownloaded(String tag) async {
    var waited = Duration.zero;
    while (true) {
      await Future<void>.delayed(_pollInterval);
      waited += _pollInterval;
      _checkNotDisposed();
      if (await _models.isModelDownloaded(tag)) return;
      if (waited >= _pollLimit) {
        throw RecognizerEngineError(
          'download-failed',
          'model $tag: not downloaded after ${waited.inSeconds} s',
        );
      }
    }
  }

  /// The model of [tag] is there: every request of the tag ends (the first
  /// to finish wins — 6.7.4), then modelChanges if a download ran.
  void _downloaded(
    String tag,
    _TagDownloads downloads, {
    required bool changed,
  }) {
    if (_disposed) return;
    if (identical(_downloads[tag], downloads)) _downloads.remove(tag);
    final requests = [...downloads.requests.values];
    downloads.requests.clear();
    if (requests.isEmpty) return; // ended by an earlier request
    for (final r in requests) {
      if (!r.isCompleted) r.complete();
    }
    if (changed) _emit(tag);
  }

  /// One request failed; the other condition's request goes on.
  void _failed(
    String tag,
    _TagDownloads downloads,
    bool condition,
    Object error,
    StackTrace stack,
  ) {
    if (_disposed) return;
    final request = downloads.requests.remove(condition);
    if (downloads.requests.isEmpty && identical(_downloads[tag], downloads)) {
      _downloads.remove(tag);
    }
    if (request == null || request.isCompleted) return;
    var failure = mlkitFailureOf(error, languageTag: tag);
    if (failure case RecognizerEngineError(code: 'unknown')) {
      failure = RecognizerEngineError('download-failed', '$error');
    }
    request.completeError(failure, stack);
  }

  @override
  Future<void> deleteModel(String languageTag) async {
    _checkNotDisposed();
    final bool deleted;
    try {
      deleted = await _models.deleteModel(languageTag);
    } on Object catch (e, s) {
      Error.throwWithStackTrace(mlkitFailureOf(e, languageTag: languageTag), s);
    }
    if (!deleted) {
      throw RecognizerEngineError(
        'delete-failed',
        'model $languageTag: the delete did not succeed',
      );
    }
    _emit(languageTag);
  }

  // ---- recognition -------------------------------------------------------

  @override
  Future<List<TextCandidate>> recognizeLine(
    HandwritingLineInput line, {
    required String languageTag,
  }) => _recognize(line, languageTag, shiftToLineBox: true);

  @override
  Future<List<TextCandidate>> recognizeLineInPageCoordinates(
    HandwritingLineInput line, {
    required String languageTag,
  }) => _recognize(line, languageTag, shiftToLineBox: false);

  Future<List<TextCandidate>> _recognize(
    HandwritingLineInput line,
    String tag, {
    required bool shiftToLineBox,
  }) async {
    _checkNotDisposed();
    final ink = mlkitInkOf(line.traces, shiftToLineBox: shiftToLineBox);
    if (ink.strokes.isEmpty) return const <TextCandidate>[];
    final context = mlkitContextOf(line);
    return _serial(() async {
      _checkNotDisposed();
      final recognizer = _recognizerFor(tag);
      final List<mlkit.RecognitionCandidate> raw;
      try {
        raw = await recognizer
            .recognize(ink, context: context)
            .timeout(_lineTimeout);
      } on TimeoutException {
        throw RecognizerEngineError(
          'timeout',
          'the line was not recognized within ${_lineTimeout.inSeconds} s',
        );
      } on Object catch (e, s) {
        Error.throwWithStackTrace(mlkitFailureOf(e, languageTag: tag), s);
      }
      _checkNotDisposed();
      return mlkitCandidatesOf(raw, tag);
    });
  }

  /// Runs [body] after every earlier queued call has ended (one native
  /// recognition at a time).
  Future<T> _serial<T>(Future<T> Function() body) {
    final previous = _tail;
    final turn = Completer<void>();
    _tail = turn.future;
    return previous.then((_) => body()).whenComplete(turn.complete);
  }

  /// The cached recognizer of [tag]. The plugin's instance id is its
  /// creation time in µs: two made within one µs would share one native
  /// recognizer (and its model), so a clashing id is made again.
  mlkit.DigitalInkRecognizer _recognizerFor(String tag) {
    final cached = _recognizers[tag];
    if (cached != null) return cached;
    final ids = {for (final r in _recognizers.values) r.id};
    var recognizer = mlkit.DigitalInkRecognizer(languageCode: tag);
    while (ids.contains(recognizer.id)) {
      recognizer = mlkit.DigitalInkRecognizer(languageCode: tag);
    }
    return _recognizers[tag] = recognizer;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final recognizer in _recognizers.values) {
      // Never awaited: the Android plugin does not answer close; a failed
      // close has nothing left to release here.
      unawaited(recognizer.close().then<void>((_) {}, onError: (Object _) {}));
    }
    _recognizers.clear();
    final requests = [for (final d in _downloads.values) ...d.requests.values];
    _downloads.clear();
    for (final r in requests) {
      if (!r.isCompleted) r.completeError(_disposedError());
    }
    unawaited(_modelChanges.close());
  }
}

/// The line as ML Kit ink (6.7.2, 6.4): traces without points are left out;
/// with [shiftToLineBox] every point is moved by the line box's top-left
/// (the smallest x and y of the line), `t` = ts[i].round().
mlkit.Ink mlkitInkOf(
  List<HandwritingTrace> traces, {
  required bool shiftToLineBox,
}) {
  var dx = 0.0, dy = 0.0;
  if (shiftToLineBox) {
    var minX = double.infinity, minY = double.infinity;
    for (final trace in traces) {
      for (var i = 0; i < trace.xs.length; i++) {
        if (trace.xs[i] < minX) minX = trace.xs[i];
        if (trace.ys[i] < minY) minY = trace.ys[i];
      }
    }
    if (minX.isFinite && minY.isFinite) {
      dx = minX;
      dy = minY;
    }
  }
  final ink = mlkit.Ink();
  for (final trace in traces) {
    final n = trace.xs.length;
    if (n == 0) continue;
    final stroke = mlkit.Stroke();
    for (var i = 0; i < n; i++) {
      stroke.points.add(
        mlkit.StrokePoint(
          x: trace.xs[i] - dx,
          y: trace.ys[i] - dy,
          t: trace.ts[i].round(),
        ),
      );
    }
    ink.strokes.add(stroke);
  }
  return ink;
}

/// The recognition context: only with a preContext or a writing area
/// (6.7.2), else null.
mlkit.DigitalInkRecognitionContext? mlkitContextOf(HandwritingLineInput line) {
  final preContext = line.preContext;
  final area = line.writingAreaPt;
  if (preContext.isEmpty && area == null) return null;
  return mlkit.DigitalInkRecognitionContext(
    preContext: preContext.isEmpty ? null : preContext,
    writingArea: area == null
        ? null
        : mlkit.WritingArea(width: area.width, height: area.height),
  );
}

/// Candidates in engine order without blank or repeated texts. The score is
/// passed on as it comes: the plugin fills 0.0 when the model gives none, so
/// 0.0 may mean 'no score' — nothing picks by score (contract
/// TextCandidate.score, 6.7.2 S-14).
List<TextCandidate> mlkitCandidatesOf(
  List<mlkit.RecognitionCandidate> raw,
  String languageTag,
) {
  final seen = <String>{};
  return [
    for (final c in raw)
      if (c.text.trim().isNotEmpty && seen.add(c.text))
        TextCandidate(c.text, score: c.score, languageTag: languageTag),
  ];
}
