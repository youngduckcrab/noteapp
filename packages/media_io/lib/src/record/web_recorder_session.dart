// lib/src/record/web_recorder_session.dart — one web recording (m5-7/06-pdf 6.8.2, 6.8.3, 6.8.4,
// 6.8.6) as pure Dart over two ports: WebCapture (one MediaRecorder over one microphone stream —
// bound to the browser in recorder_engine_browser.dart, a fake in tests) and PageEvents
// (visibility, pagehide, Screen Wake Lock — platform/page_events.dart). Timers go through
// [StartTimer] (Timer.new by default, so VM tests run it in fake_async; Chrome tests fire them by
// hand). Internal.
//
// - Chunks (6.8.2): capture.start(timeslice); every non-empty chunk to onChunk in order. The
//   watchdog asks requestData() when no dataavailable came for 2.5 × timeslice while recording;
//   three answers in a row that only the watchdog asked for → 'timeslice ignored'. pause() asks
//   requestData() first too.
// - Visibility (6.8.3, M-2): hidden while recording → requestData, pause, EnginePaused(bySystem,
//   hiddenTab). Visible → nothing (no automatic resume). resume() while hidden → StateError.
//   pagehide → requestData (best effort).
// - Microphone (6.8.3, S-6): track ended → lost. A mute counts only while recording and visible:
//   muted for micMuteLostMs → lost. A mute while hidden is remembered but not judged; once
//   visible again the session waits micUnmuteGraceMs for unmute (iOS Safari mutes the capture
//   track in the background) and only then judges. Lost → EnginePaused(bySystem,
//   microphoneLost) and resume() → StateError (one MediaRecorder cannot move to another stream).
// - Wake Lock (6.8.4): requested while recording and visible, released on pause / stop / cancel /
//   hidden; a system release while recording and visible asks once more.
// - Stop (6.8.6): capture.stop() → the last chunk → the stop event (≤ webStopFlushTimeout — past it
//   what came is what there is) → tracks stopped, wake lock released, listeners gone. abandon()
//   flushes the same way (its last chunk reaches the draft — 4.2.3 dispose) without finishing
//   anything else; cancel() drops what is still on the way.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../errors.dart';
import '../platform/page_events.dart';
import '../tuning.dart';
import 'recorder_engine.dart';
import 'web_mime.dart';

/// Timer.new, or a test's hand-fired timers.
typedef StartTimer = Timer Function(
  Duration duration,
  void Function() callback,
);

/// What a capture tells its session. The browser binding calls these on the event loop.
final class WebCaptureCallbacks {
  const WebCaptureCallbacks({
    required this.onDataEvent,
    required this.onData,
    required this.onStopped,
    required this.onError,
    required this.onMute,
    required this.onUnmute,
    required this.onEnded,
  });

  /// Every dataavailable, empty or not, when it fires (the watchdog's signal).
  final void Function() onDataEvent;

  /// The bytes of a non-empty dataavailable, in event order (after Blob.arrayBuffer).
  final void Function(Uint8List bytes) onData;

  /// MediaRecorder's stop event, after every [onData] before it.
  final void Function() onStopped;

  /// MediaRecorder's error event.
  final void Function(Object error) onError;

  /// The audio track's mute / unmute / ended events.
  final void Function() onMute;
  final void Function() onUnmute;
  final void Function() onEnded;
}

/// One MediaRecorder over one microphone stream.
abstract interface class WebCapture {
  /// MediaRecorder.mimeType ('' when the browser does not say).
  String get mimeType;

  /// MediaStreamTrack.muted of the audio track now.
  bool get trackMuted;

  /// Starts delivering [callbacks] (once, before [start]).
  void listen(WebCaptureCallbacks callbacks);

  /// MediaRecorder.start(timeslice). Throws when the recorder cannot start.
  void start(int timesliceMs);

  /// MediaRecorder.pause() / resume() / requestData() — no-ops in a state that does not allow
  /// them.
  void pause();
  void resume();
  void requestData();

  /// MediaRecorder.stop(): the last data, then the stop event (at once when already stopped).
  void stop();

  /// Stops every track of the stream (the microphone indicator goes off).
  void stopTracks();

  /// Removes every listener.
  void detach();
}

/// The developer overlay's web line (6.14 `web: wakeLock=held watchdog=0 hidden-pauses=1`) of the
/// engine's recordings. One per engine.
final class WebRecorderCounters {
  /// 'held', 'released' or 'none' (missing or refused — 6.8.4 'wake lock: none').
  String wakeLock = 'none';

  /// requestData() calls the watchdog made (6.8.2).
  int watchdog = 0;

  /// Recordings paused because the tab was hidden (6.8.3).
  int hiddenPauses = 0;

  /// The watchdog was needed [MediaTuning.webWatchdogIgnoredStreak] times in a row.
  bool timesliceIgnored = false;

  String get line =>
      'wakeLock=$wakeLock watchdog=$watchdog hidden-pauses=$hiddenPauses'
      '${timesliceIgnored ? ' timeslice ignored' : ''}';
}

final class WebRecorderSession implements RecorderEngineSession {
  WebRecorderSession({
    required this._capture,
    required this._page,
    required this._choice,
    required this._timesliceMs,
    required this._onChunk,
    this._timer = Timer.new,
    WebRecorderCounters? counters,
    void Function()? onEnded,
  }) : counters = counters ?? WebRecorderCounters(),
       _onEndedCallback = onEnded;

  final WebCapture _capture;
  final PageEvents _page;
  final WebMimeChoice _choice;
  final int _timesliceMs;
  final void Function(Uint8List chunk) _onChunk;
  final StartTimer _timer;
  final void Function()? _onEndedCallback;

  /// The engine's developer counters.
  final WebRecorderCounters counters;

  /// Single subscription: buffers until the service listens (EngineStarted first).
  final StreamController<RecorderEngineEvent> _events = StreamController();

  WebMimeChoice? _actual;
  bool _started = false;
  bool _userPaused = false;
  bool _hiddenPaused = false;
  bool _micLost = false;
  bool _failed = false;

  /// stop / cancel / abandon began: no more pauses, resumes or system events.
  bool _ending = false;

  /// Everything let go: chunks still on the way are dropped.
  bool _closed = false;

  bool _muted = false;
  bool _captureStopped = false;
  Completer<void>? _stopped;
  Future<void>? _finishing;

  Timer? _watchdog;
  bool _watchdogAsked = false;
  int _watchdogStreak = 0;
  Timer? _muteTimer;
  Timer? _graceTimer;

  ScreenWakeLock? _wakeLock;
  StreamSubscription<void>? _wakeLockReleases;
  bool _wakeLockWanted = false;
  bool _wakeLockPending = false;

  StreamSubscription<bool>? _visibility;
  StreamSubscription<void>? _pageHides;

  /// Recording now (not paused by anybody, not lost, not ending).
  bool get isRecording =>
      _started &&
      !_userPaused &&
      !_hiddenPaused &&
      !_micLost &&
      !_failed &&
      !_ending;

  /// The microphone was lost (resume → StateError).
  bool get microphoneLost => _micLost;

  /// Whether a mute is being judged right now (tests).
  @visibleForTesting
  bool get judgingMute => _muteTimer != null;

  /// Whether the post-visible unmute grace runs (tests).
  @visibleForTesting
  bool get inUnmuteGrace => _graceTimer != null;

  @override
  String get mimeType => (_actual ?? _choice).mimeType;

  @override
  bool get crossPlatformPlayable => (_actual ?? _choice).crossPlatformPlayable;

  /// '.webm' / '.m4a' of what is recorded.
  String get extension => (_actual ?? _choice).extension;

  @override
  bool get backgroundCapable => false; // a hidden tab pauses (M-2)

  @override
  Stream<RecorderEngineEvent> get events => _events.stream;

  /// Listens to the capture and the page, starts MediaRecorder and emits EngineStarted (then, if
  /// the tab is already hidden, the hidden pause). Throws what capture.start throws.
  void begin() {
    _capture.listen(
      WebCaptureCallbacks(
        onDataEvent: _onDataEvent,
        onData: _onData,
        onStopped: _onStopped,
        onError: _onCaptureError,
        onMute: _onMute,
        onUnmute: _onUnmute,
        onEnded: _onTrackEnded,
      ),
    );
    _muted = _capture.trackMuted;
    _capture.start(_timesliceMs);
    _started = true;
    _actual = choiceForActual(_choice, _capture.mimeType);
    _visibility = _page.visibilityChanges.listen(_onVisibility);
    _pageHides = _page.pageHides.listen((_) => requestData());
    _emit(const EngineStarted());
    if (_page.hidden) {
      _hide();
    } else {
      _enterRecording();
    }
  }

  // ---- user actions ------------------------------------------------------------------------

  @override
  Future<void> pause() async {
    if (_ending) throw StateError('The web recording has ended');
    if (!isRecording) {
      _userPaused = true;
      return;
    }
    _capture.requestData(); // what came so far is saved even if the tab closes while paused
    _capture.pause();
    _userPaused = true;
    _leaveRecording();
  }

  @override
  Future<void> resume() async {
    if (_ending) throw StateError('The web recording has ended');
    if (_page.hidden) {
      throw StateError('The tab is hidden: no recording nobody sees (M-2)');
    }
    if (_micLost || _failed) {
      throw StateError('The microphone was lost: stop to save the recording');
    }
    if (isRecording) return;
    _capture.resume();
    _userPaused = false;
    _hiddenPaused = false;
    _enterRecording();
  }

  @override
  void requestData() {
    if (_closed || _captureStopped || !_started) return;
    _capture.requestData();
  }

  @override
  Future<RecorderEngineResult> stop() async {
    await _flush();
    return const RecorderEngineResult();
  }

  @override
  Future<void> abandon() => _flush();

  @override
  Future<void> cancel() async {
    if (_closed) return;
    _ending = true;
    _quiet();
    _close(); // what is still on the way is dropped
    try {
      _capture.stop();
    } on Object {
      // the tracks are stopped either way
    }
  }

  // ---- recording / not recording -------------------------------------------------------------

  void _enterRecording() {
    _armWatchdog();
    _wantWakeLock(true);
    _judgeMute();
  }

  void _leaveRecording() {
    _watchdog?.cancel();
    _watchdog = null;
    _watchdogAsked = false;
    _wantWakeLock(false);
    _judgeMute();
  }

  // ---- visibility (6.8.3) ------------------------------------------------------------------

  void _onVisibility(bool hidden) {
    if (_ending) return;
    if (hidden) {
      _hide();
    } else {
      _show();
    }
  }

  void _hide() {
    _cancelGrace();
    if (isRecording) {
      _capture.requestData();
      _capture.pause();
      _hiddenPaused = true;
      counters.hiddenPauses++;
      _leaveRecording();
      _emit(
        const EnginePaused(bySystem: true, reason: MediaErrorCode.hiddenTab),
      );
    } else {
      _leaveRecording();
    }
  }

  void _show() {
    // no automatic resume (M-2): the panel offers [이어서 녹음]
    if (_muted && !_micLost && !_failed) {
      _cancelGrace();
      _graceTimer = _timer(
        const Duration(milliseconds: MediaTuning.micUnmuteGraceMs),
        _onGraceEnd,
      );
    }
    _judgeMute();
  }

  void _cancelGrace() {
    _graceTimer?.cancel();
    _graceTimer = null;
  }

  // ---- the microphone track (6.8.3, S-6) ---------------------------------------------------

  void _onMute() {
    if (_ending) return;
    _muted = true;
    _judgeMute();
  }

  void _onUnmute() {
    if (_ending) return;
    _muted = false;
    _cancelGrace();
    _judgeMute();
  }

  void _onTrackEnded() {
    if (_ending) return;
    _loseMicrophone();
  }

  /// The mute watch runs only while recording and visible, outside the post-visible grace.
  void _judgeMute() {
    final watch = _muted && isRecording && !_page.hidden && _graceTimer == null;
    if (watch) {
      _muteTimer ??= _timer(
        const Duration(milliseconds: MediaTuning.micMuteLostMs),
        () {
          _muteTimer = null;
          if (_muted && isRecording && !_page.hidden) _loseMicrophone();
        },
      );
    } else {
      _muteTimer?.cancel();
      _muteTimer = null;
    }
  }

  void _onGraceEnd() {
    _graceTimer = null;
    if (_ending) return;
    if (_muted && !_page.hidden) {
      _loseMicrophone();
    } else {
      _judgeMute();
    }
  }

  void _loseMicrophone() {
    if (_micLost || _failed || _ending) return;
    final wasRecording = isRecording;
    _micLost = true;
    _cancelGrace();
    if (wasRecording) {
      _capture.requestData();
      _capture.pause();
    }
    _leaveRecording();
    _emit(
      const EnginePaused(bySystem: true, reason: MediaErrorCode.microphoneLost),
    );
  }

  void _onCaptureError(Object error) {
    if (_ending || _failed) return;
    _failed = true;
    _cancelGrace();
    _leaveRecording();
    _emit(EngineFailed(error));
  }

  // ---- chunks and the watchdog (6.8.2) -----------------------------------------------------

  void _onDataEvent() {
    if (_closed) return;
    if (_watchdogAsked) {
      _watchdogAsked = false;
    } else {
      _watchdogStreak = 0;
    }
    if (isRecording) _armWatchdog();
  }

  void _onData(Uint8List bytes) {
    if (_closed || bytes.isEmpty) return;
    _onChunk(bytes);
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = _timer(
      Duration(
        milliseconds: MediaTuning.webRequestDataWatchdogMs(_timesliceMs),
      ),
      _onWatchdog,
    );
  }

  void _onWatchdog() {
    _watchdog = null;
    if (!isRecording) return;
    _watchdogAsked = true;
    _watchdogStreak++;
    counters.watchdog++;
    if (_watchdogStreak >= MediaTuning.webWatchdogIgnoredStreak) {
      counters.timesliceIgnored = true;
    }
    _capture.requestData();
    _armWatchdog();
  }

  // ---- the Screen Wake Lock (6.8.4) --------------------------------------------------------

  void _wantWakeLock(bool want) {
    _wakeLockWanted = want && !_page.hidden;
    if (_wakeLockWanted) {
      if (_wakeLock == null && !_wakeLockPending) unawaited(_requestWakeLock());
      return;
    }
    final held = _wakeLock;
    if (held == null) return;
    _wakeLock = null;
    unawaited(_wakeLockReleases?.cancel());
    _wakeLockReleases = null;
    counters.wakeLock = 'released';
    unawaited(held.release());
  }

  Future<void> _requestWakeLock() async {
    _wakeLockPending = true;
    final ScreenWakeLock? lock;
    try {
      lock = await _page.requestWakeLock();
    } finally {
      _wakeLockPending = false;
    }
    if (lock == null) {
      counters.wakeLock = 'none';
      return;
    }
    if (!_wakeLockWanted || _closed) {
      unawaited(lock.release());
      return;
    }
    _wakeLock = lock;
    counters.wakeLock = 'held';
    _wakeLockReleases = lock.systemReleases.listen((_) {
      if (!identical(_wakeLock, lock)) return;
      _wakeLock = null;
      unawaited(_wakeLockReleases?.cancel());
      _wakeLockReleases = null;
      counters.wakeLock = 'released';
      // once more while recording and visible
      if (isRecording && !_page.hidden && _wakeLockWanted) {
        unawaited(_requestWakeLock());
      }
    });
  }

  // ---- the end -----------------------------------------------------------------------------

  /// stop / abandon: the last chunk, then everything goes (≤ webStopFlushTimeout).
  Future<void> _flush() => _finishing ??= () async {
    if (_closed) return;
    _ending = true;
    _quiet();
    final stopped = _stopped = Completer<void>();
    if (_captureStopped || !_started) {
      stopped.complete();
    } else {
      try {
        _capture.stop();
      } on Object {
        if (!stopped.isCompleted) stopped.complete();
      }
    }
    // past the limit, what came is what there is
    final limit = _timer(MediaTuning.webStopFlushTimeout, () {
      if (!stopped.isCompleted) stopped.complete();
    });
    await stopped.future;
    limit.cancel();
    _close();
  }();

  void _onStopped() {
    _captureStopped = true;
    final stopped = _stopped;
    if (stopped != null) {
      if (!stopped.isCompleted) stopped.complete();
      return;
    }
    // stopped by itself (all tracks ended, an encoder error) while recording
    if (!_ending && !_micLost && !_failed) {
      _onCaptureError(StateError('MediaRecorder stopped by itself'));
    }
  }

  /// Timers and the wake lock off; no more system events.
  void _quiet() {
    _watchdog?.cancel();
    _watchdog = null;
    _muteTimer?.cancel();
    _muteTimer = null;
    _cancelGrace();
    _wantWakeLock(false);
    _wakeLockWanted = false;
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _quiet();
    // not awaited: a broadcast subscription's cancel future may belong to another zone
    unawaited(_visibility?.cancel());
    unawaited(_pageHides?.cancel());
    _visibility = null;
    _pageHides = null;
    try {
      _capture.stopTracks();
    } on Object {
      // already stopped
    }
    _capture.detach();
    unawaited(_events.close());
    _onEndedCallback?.call();
  }

  void _emit(RecorderEngineEvent e) {
    if (!_closed) _events.add(e);
  }
}
