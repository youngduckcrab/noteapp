// lib/src/indexer/handwriting_indexer.dart — contract m5-7/00-overview 7.2.11
// (m5-7/05-library 4.4.1, 4.4.7, 6.9).
//
// L2-10a — ① schedule, page jobs, errors and status:
//  - inputs: store.changes — stroke / page (a quiet timer per page: 3 s after
//    a local / undo / redo change, 30 s after a remote one), (v2.1, review
//    M-1) handwriting (the page of the job in flight, before it writes →
//    the job is dropped and the page goes to the very front; 5 drops in a
//    row → that page waits 30 s);
//  - one page at a time (requeued → quiet → catch-up), one line at a time;
//    a job: flush → stalePages (+ forPage for the language — no point
//    decode) → loadPage only when stale → lines → engine line by line →
//    HandwritingRepository.update (merge in the transform — line_reuse.dart);
//  - yields: every 200 converted strokes and after every line; > 1,500
//    strokes → the line grouping runs in compute (the indexer never runs on
//    the web);
//  - foreground false → no next line (the line in flight finishes);
//  - model: modelState when enabled / on a language change; not ready →
//    waitingModel: Android (and engines without RecognizerModelAdmin)
//    ensureModel(lang, wifiOnly: recog.modelWifiOnly) once, iOS
//    (enforcesWifiOnly false) waits for modelChanges; ModelNotReady from a
//    line → the page back to the front, the same wait;
//  - errors: RecognizerUnsupported → off for good; other engine errors →
//    failed[pageId] = rev (that ink is not retried), one report per
//    (pageId, rev); CORE write errors → one report, failed;
//    EntityNotFoundException → skipped silently;
//  - IndexerMetrics: our part of each job (Stopwatch — never a decision).
// L2-10b adds line reuse, the confirmed-line merge and the catch-up.
//
// Lifecycle: start() is idempotent (web / unavailable engine → stays off and
// subscribes to nothing); dispose() is idempotent, cancels every timer and
// subscription, closes its own AppLifecycleListener (a given `foreground` is
// not touched), leaves the engine open (the provider owns it) and writes
// nothing afterwards — an engine call in flight is answered into the void.
// The status ValueNotifier is NOT disposed: readers (the provider, INFRA's
// overlay) may still read `off` after dispose().
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleListener, AppLifecycleState, Size, WidgetsBinding;
import 'package:note_core/note_core.dart' as core;

import '../common/report_error.dart';
import '../lines/glyph_boxes.dart';
import '../lines/group_into_lines.dart';
import '../model/candidates.dart';
import '../model/failures.dart';
import '../model/handwriting_trace.dart';
import '../ports/handwriting_recognizer.dart';
import '../ports/model_admin.dart';
import '../settings/recognition_settings_keys.dart';
import 'indexer_metrics.dart';
import 'indexer_status.dart';
import 'line_reuse.dart';
import 'page_queue.dart';

/// (internal) The indexer's schedule and sizes (6.9.2, 6.9.7).
abstract final class IndexerTuning {
  static const Duration localQuiet = Duration(seconds: 3);
  static const Duration remoteQuiet = Duration(seconds: 30);

  /// A page whose job was dropped by handwriting changes this many times in
  /// a row waits [dropDeferral] (11 risk 16 — no endless loop).
  static const int maxDropsInRow = 5;
  static const Duration dropDeferral = Duration(seconds: 30);

  /// HandwritingTrace.fromStroke conversions between two yields.
  static const int strokesPerYield = 200;

  /// More input strokes than this → groupTraceIndices in compute.
  static const int computeAboveStrokes = 1500;

  /// Characters of the previous line given as preContext.
  static const int preContextChars = 20;

  /// Alternatives kept per line (contract: ≤ 5).
  static const int maxAlternatives = 5;

  /// writingAreaPt height: max(line height × 1.5, 24) (6.4).
  static const double writingAreaLineFactor = 1.5;
  static const double minWritingAreaHeight = 24;
}

/// (internal) The developer-overlay timings of [indexer] (4.4.9 — read by
/// recognitionDevOverlayLinesProvider; not a public member).
IndexerMetrics metricsOf(HandwritingIndexer indexer) => indexer._metrics;

/// (internal) groupTraceIndices in another isolate (pages above
/// IndexerTuning.computeAboveStrokes — 6.9.2). The indexer never runs on the
/// web, where compute would run inline anyway.
Future<List<List<int>>> groupTraceIndicesInBackground(
  List<HandwritingTrace> traces,
) => compute(_groupTraceIndices, traces, debugLabel: 'groupTraceIndices');

List<List<int>> _groupTraceIndices(List<HandwritingTrace> traces) =>
    groupTraceIndices(traces);

/// The last [count] characters of [text] (UTF-16, never half a surrogate
/// pair).
String _tail(String text, int count) {
  if (text.length <= count) return text;
  var start = text.length - count;
  final unit = text.codeUnitAt(start);
  if (unit >= 0xDC00 && unit <= 0xDFFF) start++;
  return text.substring(start);
}

/// One page job.
final class _Job {
  _Job(this.noteId, this.pageId, this.lang);

  final core.NoteId noteId;
  final core.PageId pageId;
  final String lang;

  /// Set by a stroke / handwriting change of the page, a language change,
  /// disable or dispose: the job ends at its next check without writing.
  bool dropped = false;

  /// Set right before the CORE write: later handwriting changes are the
  /// write's own (or merged by update — 6.9.2).
  bool writing = false;
}

final class HandwritingIndexer {
  // Private named parameters: callers write store: / recognizer: /
  // enabled: / foreground: (the contract constructor).
  HandwritingIndexer({
    required this._store, // store:
    required this._recognizer, // recognizer:
    required this._enabled, // enabled:
    ValueListenable<bool>?
    foreground, // (v2.1, CP-L10) default: AppLifecycleListener
  }) : _givenForeground = foreground;

  final core.NoteStore _store;
  final HandwritingRecognizer _recognizer;
  final ValueListenable<bool> _enabled;
  final ValueListenable<bool>? _givenForeground;

  final ValueNotifier<HandwritingIndexerStatus> _status =
      ValueNotifier<HandwritingIndexerStatus>(const HandwritingIndexerStatus());
  final IndexerMetrics _metrics = IndexerMetrics();

  bool _started = false;
  bool _disposed = false;

  /// RecognizerUnsupported (or an engine that is not available): off for
  /// good on this device.
  bool _unsupported = false;

  ValueListenable<bool>? _foreground;
  ValueNotifier<bool>? _ownForeground;
  AppLifecycleListener? _lifecycle;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  /// recog.language (null until the first settings value).
  String? _lang;
  bool _wifiOnly = true;

  /// The model of [_lang] is known to be ready.
  bool _modelReady = false;

  /// Set while waiting for the model: the status reason (4.4.1).
  String? _modelWait;

  /// Bumped by every model check: an older check's answer is ignored.
  int _modelEpoch = 0;
  final Set<String> _reportedModelFailures = {};

  final PageQueue _queue = PageQueue();
  final Map<core.PageId, Timer> _quiet = {};
  final Map<core.PageId, core.NoteId> _quietNotes = {};
  final Map<core.PageId, Timer> _deferred = {};
  final Map<core.PageId, int> _dropsInRow = {};

  /// pageId → sourceRev that failed in the engine or in the CORE write.
  final Map<core.PageId, String> _failed = {};
  final Set<String> _reportedFailures = {};
  int _indexed = 0;
  String? _lastError;

  _Job? _job;

  /// Completed when a paused job may look again (foreground / drop /
  /// dispose).
  Completer<void>? _wake;

  /// Watches NoteStore.changes (stroke → pageId; (v2.1) handwriting → abandon that page's job and
  /// requeue it), waits for idle (≥ 3 s no local input on that page, 30 s after a remote change),
  /// asks stalePages first (no point decode), recognizes line by line yielding between lines, writes
  /// with HandwritingRepository.update (merged with what is stored — G-4). (v2.1) Fresh = same
  /// sourceRev and language; another engine id / version / device is fresh. Start-up catch-up:
  /// notesWithStalePages(). Never runs on web. dispose() is idempotent.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    if (kIsWeb || !_recognizer.isAvailable) {
      _unsupported = true;
      _publish();
      return;
    }
    final foreground = _givenForeground ?? _createOwnForeground();
    _foreground = foreground;
    foreground.addListener(_onForegroundChanged);
    _enabled.addListener(_onEnabledChanged);
    final settings = _store.settings;
    _subscriptions
      ..add(
        settings
            .watch(RecognitionSettingsKeys.language)
            .listen(_onLanguage, onError: _onStreamError),
      )
      ..add(
        settings
            .watch(RecognitionSettingsKeys.modelWifiOnly)
            .listen(_onWifiOnly, onError: _onStreamError),
      )
      ..add(_store.changes.listen(_onChanges, onError: _onStreamError));
    if (_recognizer case final RecognizerModelAdmin admin) {
      _subscriptions.add(
        admin.modelChanges.listen(_onModelChanged, onError: _onStreamError),
      );
    }
    _publish();
  }

  /// Idempotent (INFRA R-3: the provider's onDispose and INFRA's idle task
  /// shutdown may both call it). Never disposes the recognizer (the provider
  /// owns it).
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _modelEpoch++;
    _dropJob();
    _clearWork();
    _foreground?.removeListener(_onForegroundChanged);
    if (_foreground != null) _enabled.removeListener(_onEnabledChanged);
    final subscriptions = List.of(_subscriptions);
    _subscriptions.clear();
    _lifecycle?.dispose();
    _lifecycle = null;
    _ownForeground?.dispose();
    _ownForeground = null;
    _foreground = null;
    _status.value = const HandwritingIndexerStatus();
    // Not awaited: a cancel may answer with a future of the root zone
    // (fake_async tests would never see it), and nothing waits on it.
    for (final s in subscriptions) {
      unawaited(s.cancel());
    }
  }

  ValueListenable<HandwritingIndexerStatus> get status => _status;

  // ---- state -------------------------------------------------------------

  /// Started, not disposed, the engine usable and recog.autoIndex on.
  bool get _active => _started && !_disposed && !_unsupported && _enabled.value;

  bool get _inForeground => _foreground?.value ?? true;

  bool get _canStartJob =>
      _active && _inForeground && _modelReady && _lang != null && _job == null;

  ValueListenable<bool> _createOwnForeground() {
    final binding = WidgetsBinding.instance;
    final state = binding.lifecycleState;
    final own = ValueNotifier<bool>(
      state == null || state == AppLifecycleState.resumed,
    );
    _ownForeground = own;
    _lifecycle = AppLifecycleListener(
      binding: binding,
      onStateChange: (s) => own.value = s == AppLifecycleState.resumed,
    );
    return own;
  }

  HandwritingIndexerPhase get _phase {
    if (!_started || _disposed || _unsupported) {
      return HandwritingIndexerPhase.off;
    }
    if (!_enabled.value) return HandwritingIndexerPhase.disabled;
    if (!_inForeground) return HandwritingIndexerPhase.paused;
    if (_modelWait != null) return HandwritingIndexerPhase.waitingModel;
    if (_job != null) return HandwritingIndexerPhase.recognizing;
    if (!_queue.isEmpty || _quiet.isNotEmpty || _deferred.isNotEmpty) {
      return HandwritingIndexerPhase.waitingInput;
    }
    return HandwritingIndexerPhase.idle;
  }

  void _publish() {
    if (_disposed) return;
    final phase = _phase;
    if (phase == HandwritingIndexerPhase.off) {
      _status.value = const HandwritingIndexerStatus();
      return;
    }
    _status.value = HandwritingIndexerStatus(
      phase: phase,
      languageTag: _lang,
      queuedPages: _queue.length + _quiet.length + _deferred.length,
      indexedPages: _indexed,
      failedPages: _failed.length,
      currentPageId: _job?.pageId,
      lastError: phase == HandwritingIndexerPhase.waitingModel
          ? _modelWait
          : _lastError,
    );
  }

  void _onStreamError(Object error, StackTrace stack) =>
      reportRecognitionError(error, stack, 'handwriting indexer input');

  // ---- inputs ------------------------------------------------------------

  void _onEnabledChanged() {
    if (_disposed || !_started || _unsupported) return;
    if (_enabled.value) {
      unawaited(_checkModel());
    } else {
      _modelEpoch++;
      _modelReady = false;
      _modelWait = null;
      _dropJob();
      _clearWork();
    }
    _publish();
  }

  void _onForegroundChanged() {
    if (_disposed) return;
    if (_inForeground) {
      _wakeUp();
      _pump();
    }
    _publish();
  }

  void _onLanguage(String value) {
    if (_disposed || _unsupported) return;
    final lang = recognitionLanguageOf(value);
    if (lang == _lang) return;
    _lang = lang;
    _modelEpoch++;
    _modelReady = false;
    _modelWait = null;
    _dropJob(); // a job of the old language writes nothing
    if (_active) unawaited(_checkModel());
    _publish();
  }

  void _onWifiOnly(bool value) {
    if (_disposed || _unsupported) return;
    final changed = value != _wifiOnly;
    _wifiOnly = value;
    // A download waiting under the old condition is asked again.
    if (changed && _active && !_modelReady) unawaited(_checkModel());
  }

  void _onModelChanged(String languageTag) {
    if (languageTag != _lang || !_active) return;
    unawaited(_checkModel());
  }

  void _onChanges(core.ChangeBatch batch) {
    if (!_active) return; // disabled: the catch-up finds stale pages later
    final quiet = batch.origin == core.ChangeOrigin.remote
        ? IndexerTuning.remoteQuiet
        : IndexerTuning.localQuiet;
    var touched = false;
    for (final c in batch.changes) {
      switch (c.kind) {
        case core.EntityKind.stroke:
          final noteId = c.noteId, pageId = c.pageId;
          if (noteId == null || pageId == null) continue;
          _markDirty(noteId, pageId, quiet);
          touched = true;
        case core.EntityKind.page:
          final noteId = c.noteId;
          if (c.deleted || c.purged) {
            _forgetPage(c.id);
          } else if (noteId != null) {
            _markDirty(noteId, c.id, quiet);
          }
          touched = true;
        case core.EntityKind.handwriting:
          final pageId = c.pageId;
          if (pageId != null && _onHandwritingChanged(pageId)) touched = true;
        default:
          break;
      }
    }
    if (touched) _publish();
  }

  /// A stroke or page change: the page waits [quiet] after its LAST change;
  /// a job of that page is dropped (it waits again).
  void _markDirty(core.NoteId noteId, core.PageId pageId, Duration quiet) {
    _queue.remove(pageId);
    _deferred.remove(pageId)?.cancel();
    _quiet.remove(pageId)?.cancel();
    _quietNotes[pageId] = noteId;
    _quiet[pageId] = Timer(quiet, () => _onQuiet(pageId));
    final job = _job;
    if (job != null && job.pageId == pageId && !job.writing) {
      job.dropped = true;
      _wakeUp();
    }
  }

  void _onQuiet(core.PageId pageId) {
    _quiet.remove(pageId);
    final noteId = _quietNotes.remove(pageId);
    if (noteId == null || !_active) return;
    _queue.add(noteId, pageId, QueueLane.ready);
    _publish();
    _pump();
  }

  /// A deleted page leaves the queue and its job.
  void _forgetPage(core.PageId pageId) {
    _queue.remove(pageId);
    _quiet.remove(pageId)?.cancel();
    _quietNotes.remove(pageId);
    _deferred.remove(pageId)?.cancel();
    _dropsInRow.remove(pageId);
    _failed.remove(pageId);
    final job = _job;
    if (job != null && job.pageId == pageId) {
      job.dropped = true;
      _wakeUp();
    }
  }

  /// (v2.1, review M-1) A handwriting change of the job's page before the
  /// job writes: drop the job and put the page first (no new quiet time —
  /// the strokes did not change). True when the queue changed.
  bool _onHandwritingChanged(core.PageId pageId) {
    final job = _job;
    if (job == null || job.pageId != pageId || job.writing || job.dropped) {
      return false;
    }
    job.dropped = true;
    _wakeUp();
    if (_quiet.containsKey(pageId)) return true; // dirty: waits anyway
    final drops = (_dropsInRow[pageId] ?? 0) + 1;
    if (drops >= IndexerTuning.maxDropsInRow) {
      _dropsInRow.remove(pageId);
      final noteId = job.noteId;
      _deferred.remove(pageId)?.cancel();
      _deferred[pageId] = Timer(IndexerTuning.dropDeferral, () {
        _deferred.remove(pageId);
        if (!_active) return;
        _queue.add(noteId, pageId, QueueLane.ready);
        _publish();
        _pump();
      });
    } else {
      _dropsInRow[pageId] = drops;
      _queue.add(job.noteId, pageId, QueueLane.front);
    }
    return true;
  }

  void _dropJob() {
    _job?.dropped = true;
    _wakeUp();
  }

  void _wakeUp() {
    final wake = _wake;
    _wake = null;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  /// Cancels every timer and empties the queue (disable, dispose, off).
  void _clearWork() {
    for (final t in _quiet.values) {
      t.cancel();
    }
    for (final t in _deferred.values) {
      t.cancel();
    }
    _quiet.clear();
    _quietNotes.clear();
    _deferred.clear();
    _queue.clear();
    _dropsInRow.clear();
  }

  /// RecognizerUnsupported: off on this device for good (6.9.6).
  void _goOff() {
    if (_unsupported) return;
    _unsupported = true;
    _modelEpoch++;
    _dropJob();
    _clearWork();
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    _subscriptions.clear();
    _publish();
  }

  // ---- model -------------------------------------------------------------

  Future<void> _checkModel() async {
    final lang = _lang;
    if (lang == null || !_active) return;
    final epoch = ++_modelEpoch;
    RecognitionModelState state;
    try {
      state = await _recognizer.modelState(lang);
    } on RecognizerUnsupported {
      if (epoch == _modelEpoch) _goOff();
      return;
    } on Object catch (e, s) {
      if (epoch != _modelEpoch || !_active) return;
      _reportModelFailure(lang, e, s);
      state = RecognitionModelState.notDownloaded;
    }
    if (epoch != _modelEpoch || !_active) return;
    switch (state) {
      case RecognitionModelState.ready:
        _modelReady = true;
        _modelWait = null;
        _publish();
        _pump();
      case RecognitionModelState.unsupported:
        _modelReady = false;
        _modelWait = 'model $lang: unsupported';
        _publish();
      case RecognitionModelState.notDownloaded:
      case RecognitionModelState.downloading:
        _modelReady = false;
        await _waitForModel(lang, epoch);
    }
  }

  /// 6.7.4: Android (and engines without RecognizerModelAdmin) download once
  /// with recog.modelWifiOnly and wait for it; iOS waits for modelChanges —
  /// the user starts the download (settings / conversion sheet).
  Future<void> _waitForModel(String lang, int epoch) async {
    if (_recognizer case RecognizerModelAdmin(enforcesWifiOnly: false)) {
      _modelWait = 'model $lang: not downloaded';
      _publish();
      return; // _onModelChanged → _checkModel
    }
    final wifiOnly = _wifiOnly;
    _modelWait = wifiOnly
        ? 'model $lang: waiting for Wi-Fi'
        : 'model $lang: downloading';
    _publish();
    try {
      await _recognizer.ensureModel(lang, wifiOnly: wifiOnly);
    } on RecognizerUnsupported {
      if (epoch == _modelEpoch) _goOff();
      return;
    } on Object catch (e, s) {
      if (epoch != _modelEpoch || !_active) return;
      _reportModelFailure(lang, e, s);
      _modelWait = 'model $lang: download failed';
      _publish();
      return; // modelChanges / a language, Wi-Fi or enabled change retries
    }
    if (epoch != _modelEpoch || !_active) return;
    _modelReady = true;
    _modelWait = null;
    _publish();
    _pump();
  }

  void _reportModelFailure(String lang, Object error, StackTrace stack) {
    if (_reportedModelFailures.add('$lang:${error.runtimeType}')) {
      reportRecognitionError(error, stack, 'handwriting model $lang');
    }
  }

  // ---- jobs --------------------------------------------------------------

  void _pump() {
    if (!_canStartJob) return;
    final next = _queue.takeFirst();
    if (next == null) {
      _publish();
      return;
    }
    final job = _Job(next.noteId, next.pageId, _lang!);
    _job = job;
    _publish();
    unawaited(
      _runJob(job).whenComplete(() {
        if (identical(_job, job)) _job = null;
        _publish();
        _pump();
      }),
    );
  }

  bool _alive(_Job job) =>
      !job.dropped && _active && identical(_job, job) && job.lang == _lang;

  /// Before each line: alive, and in the foreground (waits there).
  Future<bool> _gate(_Job job, JobClock clock) async {
    while (_alive(job) && !_inForeground) {
      final wake = _wake ??= Completer<void>();
      await clock.run(() => wake.future);
    }
    return _alive(job);
  }

  Future<void> _yield(JobClock clock) =>
      clock.run(() => Future<void>.delayed(Duration.zero));

  Future<void> _runJob(_Job job) async {
    final clock = JobClock()..start();
    try {
      await _page(job, clock);
    } on core.EntityNotFoundException {
      // The page went away meanwhile (6.9.3) — nothing to do.
    } on Object catch (e, s) {
      // A store read failed (the engine and the write have their own
      // handlers): reported once per page and error type, retried when the
      // page changes again.
      _reportOnce('read:${job.pageId}:${e.runtimeType}', e, s, 'page read');
    } finally {
      clock.stop();
    }
  }

  Future<void> _page(_Job job, JobClock clock) async {
    final repo = _store.handwriting;
    // (v2.1, review S-4) queued strokes are committed first.
    await clock.run(_store.flush);
    if (!_alive(job)) return;
    // ① Fresh? — DB columns only (G-2, review S-1).
    final stale = await clock.run(() => repo.stalePages(job.noteId));
    if (!_alive(job)) return;
    if (!stale.contains(job.pageId)) {
      final current = await clock.run(() => repo.forPage(job.pageId));
      if (!_alive(job)) return;
      if (current == null || languageOfEngineId(current.engineId) == job.lang) {
        _dropsInRow.remove(job.pageId);
        return; // fresh: another engine / version / device counts
      }
      // Only the language differs → stale.
    }
    // ② The committed strokes — read only when stale.
    final content = await clock.run(() => _store.content.loadPage(job.pageId));
    if (!_alive(job)) return;
    final inputs = [
      for (final s in content.strokes)
        if (core.HandwritingText.isRecognitionInput(s)) s,
    ];
    final rev = core.HandwritingText.sourceRevOf(inputs);
    if (inputs.isEmpty) {
      final existing = await clock.run(() => repo.forPage(job.pageId));
      if (!_alive(job) || existing == null) return;
      job.writing = true;
      await _write(job, rev, clock, () => repo.removeForPage(job.pageId));
      _record(job, clock, lines: 0, recognized: 0);
      return;
    }
    if (_failed[job.pageId] == rev) return; // same ink failed before
    final traces = <HandwritingTrace>[];
    for (var i = 0; i < inputs.length; i++) {
      if (i > 0 && i % IndexerTuning.strokesPerYield == 0) {
        await _yield(clock);
        if (!_alive(job)) return;
      }
      traces.add(HandwritingTrace.fromStroke(inputs[i]));
    }
    final groups = inputs.length > IndexerTuning.computeAboveStrokes
        ? await clock.run(() => groupTraceIndicesInBackground(traces))
        : groupTraceIndices(traces);
    final pageWidth = content.page.size.width;
    final lines = <core.HandwritingLine>[];
    final geometry = <LineGeometry>[];
    var previous = '';
    var recognized = 0;
    for (final group in groups) {
      if (!await _gate(job, clock)) return;
      final lineTraces = [for (final i in group) traces[i]];
      final boxes = <core.ElementId, core.PageRect>{
        for (final i in group) inputs[i].id: inputs[i].points.pointBounds,
      };
      final rect = boxes.values.reduce((a, b) => a.expandToInclude(b));
      final candidates = await _recognize(
        job,
        clock,
        rev,
        HandwritingLineInput(
          lineTraces,
          preContext: _tail(previous, IndexerTuning.preContextChars),
          writingAreaPt: Size(
            pageWidth,
            math.max(
              rect.height * IndexerTuning.writingAreaLineFactor,
              IndexerTuning.minWritingAreaHeight,
            ),
          ),
        ),
      );
      if (candidates == null || !_alive(job)) return;
      recognized++;
      final text = candidates.isEmpty ? '' : candidates.first.text;
      final alternatives = <String>[];
      for (final c in candidates.skip(1)) {
        if (alternatives.length == IndexerTuning.maxAlternatives) break;
        if (c.text != text && !alternatives.contains(c.text)) {
          alternatives.add(c.text);
        }
      }
      lines.add(
        core.HandwritingLine(
          text: text,
          alternatives: List.unmodifiable(alternatives),
          rect: rect,
          strokeIds: List.unmodifiable(boxes.keys),
          languageTag: job.lang,
        ),
      );
      geometry.add(
        LineGeometry(
          strokeBoxes: Map.unmodifiable(boxes),
          glyphHeight: estimateGlyphHeight(lineTraces),
        ),
      );
      previous = text;
      await _yield(clock);
      if (!_alive(job)) return;
    }
    final computed = IndexerResult(
      rev: rev,
      lang: job.lang,
      engineId: '${_recognizer.engineId}:${job.lang}',
      lines: List.unmodifiable(lines),
      geometry: List.unmodifiable(geometry),
      nowMs: _store.clock.now().millisecondsSinceEpoch,
    );
    job.writing = true; // later handwriting changes: update merges them
    var stored = false;
    await _write(
      job,
      rev,
      clock,
      () => repo.update(job.pageId, (current) {
        final next = mergeIndexerResult(
          current,
          computed,
          noteId: job.noteId,
          pageId: job.pageId,
        );
        stored = next != null;
        return next;
      }),
      counts: () => stored,
    );
    _record(job, clock, lines: lines.length, recognized: recognized);
  }

  /// One line through the engine; null when the job must end (the failure
  /// is handled here).
  Future<List<TextCandidate>?> _recognize(
    _Job job,
    JobClock clock,
    String rev,
    HandwritingLineInput input,
  ) async {
    try {
      return await clock.run(
        () => _recognizer.recognizeLine(input, languageTag: job.lang),
      );
    } on RecognizerUnsupported {
      if (!_disposed) _goOff();
    } on ModelNotReady catch (e) {
      if (!_alive(job)) return null;
      // The page goes back first; the same wait as a model that is not ready.
      _queue.add(job.noteId, job.pageId, QueueLane.front);
      _modelReady = false;
      final epoch = ++_modelEpoch;
      _lastError = '$e';
      unawaited(_waitForModel(job.lang, epoch));
    } on Object catch (e, s) {
      if (_disposed || job.dropped) return null;
      _fail(job, rev, e, s, 'handwriting engine');
    }
    return null;
  }

  /// A CORE write (update / removeForPage). [counts] says whether it stored
  /// a value (update with a null transform result does not count).
  Future<void> _write(
    _Job job,
    String rev,
    JobClock clock,
    Future<Object?> Function() write, {
    bool Function()? counts,
  }) async {
    if (_disposed) return;
    try {
      await clock.run(write);
    } on core.EntityNotFoundException {
      return; // the page was deleted meanwhile
    } on Object catch (e, s) {
      _fail(job, rev, e, s, 'handwriting write');
      return;
    }
    if (counts == null || counts()) _indexed++;
    _failed.remove(job.pageId);
    _dropsInRow.remove(job.pageId);
  }

  /// failed[pageId] = rev, one report per (pageId, rev) (6.9.6).
  void _fail(
    _Job job,
    String rev,
    Object error,
    StackTrace stack,
    String context,
  ) {
    _failed[job.pageId] = rev;
    _lastError = 'page ${job.pageId}: $error';
    _reportOnce('${job.pageId}:$rev', error, stack, context);
    _publish();
  }

  void _reportOnce(String key, Object error, StackTrace stack, String context) {
    if (_reportedFailures.add(key)) {
      reportRecognitionError(error, stack, context);
    }
  }

  void _record(
    _Job job,
    JobClock clock, {
    required int lines,
    required int recognized,
  }) {
    clock.stop();
    _metrics.record(
      IndexerJobRecord(
        pageId: job.pageId,
        ourMs: clock.totalMs,
        lines: lines,
        recognizedLines: recognized,
        longestSliceMs: clock.longestSliceMs,
        slices: clock.slices,
      ),
    );
  }
}
