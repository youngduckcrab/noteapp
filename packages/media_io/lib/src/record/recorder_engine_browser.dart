// lib/src/record/recorder_engine_browser.dart — the web recorder engine (m5-7/06-pdf 6.8 — D13,
// P-A): own MediaRecorder over getUserMedia (record's web path is not used). Written anew with
// record_web's MediaRecorderDelegate as a reference (BSD-3 — THIRD_PARTY_NOTICES, T41).
//
// - MIME (6.8.1): the candidate table probed once (preparePlatformRecording — initializeMediaIo's
//   web step) or on first use; WebMimeTable.choose with config.allowNonAacOnWeb. No candidate →
//   checkSupport unsupported.
// - checkSupport (4.2.3): no MediaRecorder / mediaDevices.getUserMedia or no candidate →
//   unsupported. requestPermission → getUserMedia once (NotAllowedError / SecurityError →
//   permissionDenied; other failures → supported — start reports them precisely); the stream is
//   kept micStreamKeepAlive (30 s) for the next start, then its tracks stop. Without a request,
//   navigator.permissions.query('microphone') == 'denied' → permissionDenied.
// - start: the kept stream or getUserMedia({audio: {channelCount: 1, echoCancellation /
//   noiseSuppression / autoGainControl: MediaTuning.webMicProcessing}}) — NotAllowedError →
//   permissionDenied, NotFoundError → microphoneNotFound, NotReadableError → microphoneBusy, else
//   engineFailed (MediaIoException); MediaRecorder(stream, {mimeType, audioBitsPerSecond:
//   request.bitRate}) → WebRecorderSession (web_recorder_session.dart — chunks, watchdog,
//   visibility, microphone, wake lock, stop).
// - The draft holds the bytes: writesDraftChunks, no leftover files, stop's result has no file.
// Internal; behind record/recorder_engine_factory.dart.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:web/web.dart' as web;

import '../config.dart';
import '../errors.dart';
import '../platform/page_events.dart';
import '../platform/page_events_browser.dart';
import '../tuning.dart';
import 'recorder_engine.dart';
import 'web_mime.dart';
import 'web_recorder_session.dart';

/// recorder_engine_factory.dart on the web.
RecorderEngine createPlatformRecorderEngine(MediaIoConfig config) =>
    BrowserRecorderEngine(config: config);

/// recorder_engine_factory.dart: initializeMediaIo's web step — the MIME table (4.2.1). Sync.
void preparePlatformRecording(MediaIoConfig config) {
  _probedTable ??= probeBrowserMimeTable();
}

/// recorder_engine_factory.dart: no playback session on the web.
Future<void> Function()? platformPlaybackSessionSetup() => null;

WebMimeTable? _probedTable;

/// MediaRecorder.isTypeSupported for every 6.8.1 candidate (no MediaRecorder → none supported).
WebMimeTable probeBrowserMimeTable() {
  if (!_hasGlobal('MediaRecorder')) return WebMimeTable(const {});
  // an external interop member cannot be torn off
  bool isTypeSupported(String mimeType) =>
      web.MediaRecorder.isTypeSupported(mimeType);
  return WebMimeTable.probe(isTypeSupported);
}

/// Opens a microphone stream (tests: a WebAudio stream — no microphone in headless Chrome).
typedef OpenMicrophoneStream = Future<web.MediaStream> Function();

/// The permission state of the microphone ('granted' / 'denied' / 'prompt'), null = unknown.
typedef MicrophonePermissionState = Future<String?> Function();

final class BrowserRecorderEngine implements RecorderEngine {
  BrowserRecorderEngine({
    required this.config,
    PageEvents? page,
    WebMimeTable? mimeTable,
    OpenMicrophoneStream? openStream,
    MicrophonePermissionState? permissionState,
    this._timer = Timer.new,
    this._apiAvailable,
  }) : page = page ?? BrowserPageEvents(),
       _table = mimeTable,
       _openStream = openStream ?? openBrowserMicrophone,
       _permissionState = permissionState ?? queryMicrophonePermission;

  final MediaIoConfig config;
  final PageEvents page;
  WebMimeTable? _table;
  final OpenMicrophoneStream _openStream;
  final MicrophonePermissionState _permissionState;
  final StartTimer _timer;
  final bool? _apiAvailable;

  /// The developer overlay's web counters (6.14 `web:`).
  final WebRecorderCounters counters = WebRecorderCounters();

  web.MediaStream? _keptStream;
  Timer? _keptTimer;
  WebRecorderSession? _session;
  bool _disposed = false;

  /// The candidate table (probed on first use when initializeMediaIo did not).
  WebMimeTable get mimeTable =>
      _table ??= _probedTable ??= probeBrowserMimeTable();

  /// The 6.8.1 choice for this browser and config; null = nothing to record.
  WebMimeChoice? get choice =>
      mimeTable.choose(allowNonAacOnWeb: config.allowNonAacOnWeb);

  /// The developer overlay's `enc:` part (6.14).
  String get encoderLine => mimeTable.encoderLine;

  /// The open session (tests).
  @visibleForTesting
  WebRecorderSession? get session => _session;

  /// The capture of the latest start (tests).
  @visibleForTesting
  MediaRecorderCapture? get lastCapture => _lastCapture;
  MediaRecorderCapture? _lastCapture;

  /// A stream from checkSupport(requestPermission: true) is waiting for start (tests).
  bool get keepsStream => _keptStream != null;

  bool get _hasApi =>
      _apiAvailable ??
      (_hasGlobal('MediaRecorder') &&
          (web.window.navigator as JSObject).has('mediaDevices') &&
          (web.window.navigator.mediaDevices as JSObject).has('getUserMedia'));

  @override
  bool get writesDraftChunks => true;

  @override
  String get draftMimeType => choice?.mimeType ?? webMimeCandidates[3];

  @override
  String? get developerNote {
    final kept = keepsStream ? ' mic=kept' : '';
    return '${counters.line}$kept';
  }

  @override
  Future<core.AudioSupport> checkSupport({
    required bool requestPermission,
  }) async {
    if (_disposed || !_hasApi || choice == null) {
      return core.AudioSupport.unsupported;
    }
    if (requestPermission) {
      if (_keptStream != null) return core.AudioSupport.supported;
      try {
        _keep(await _openStream());
        return core.AudioSupport.supported;
      } on Object catch (e) {
        final name = _domErrorName(e);
        return name == 'NotAllowedError' || name == 'SecurityError'
            ? core.AudioSupport.permissionDenied
            : core.AudioSupport.supported; // start says what is wrong
      }
    }
    try {
      return await _permissionState() == 'denied'
          ? core.AudioSupport.permissionDenied
          : core.AudioSupport.supported;
    } on Object {
      return core.AudioSupport.supported;
    }
  }

  @override
  Future<RecorderEngineSession> start(RecorderEngineRequest request) async {
    if (_disposed) throw StateError('The recorder engine was disposed');
    if (_session != null) {
      throw StateError('A web recording is already running');
    }
    final chosen = choice;
    if (!_hasApi || chosen == null) {
      throw UnsupportedError('Recording is not supported in this browser');
    }
    final web.MediaStream stream;
    final kept = _takeKeptStream();
    if (kept != null) {
      stream = kept;
    } else {
      try {
        stream = await _openStream();
      } on Object catch (e) {
        throw MediaIoException(
          switch (_domErrorName(e)) {
            'NotAllowedError' ||
            'SecurityError' => MediaErrorCode.permissionDenied,
            'NotFoundError' ||
            'OverconstrainedError' => MediaErrorCode.microphoneNotFound,
            'NotReadableError' || 'AbortError' => MediaErrorCode.microphoneBusy,
            _ => MediaErrorCode.engineFailed,
          },
          detail: 'getUserMedia',
          cause: e,
        );
      }
    }
    if (_disposed) {
      _stopTracks(stream);
      throw StateError('The recorder engine was disposed');
    }
    final MediaRecorderCapture capture;
    try {
      capture = _lastCapture = MediaRecorderCapture(
        stream,
        web.MediaRecorder(
          stream,
          web.MediaRecorderOptions(
            mimeType: chosen.mimeType,
            audioBitsPerSecond: request.bitRate,
          ),
        ),
      );
    } on Object catch (e) {
      _stopTracks(stream);
      throw MediaIoException(
        MediaErrorCode.engineFailed,
        detail: 'MediaRecorder',
        cause: e,
      );
    }
    late final WebRecorderSession session;
    session = WebRecorderSession(
      capture: capture,
      page: page,
      choice: chosen,
      timesliceMs: request.config.webDraftChunkMs,
      onChunk: request.onChunk,
      timer: _timer,
      counters: counters,
      onEnded: () {
        if (identical(_session, session)) _session = null;
      },
    );
    _session = session;
    try {
      session.begin();
    } on Object catch (e) {
      _session = null;
      await session.cancel();
      throw MediaIoException(
        MediaErrorCode.engineFailed,
        detail: 'MediaRecorder.start',
        cause: e,
      );
    }
    return session;
  }

  @override
  Future<RecorderEngineFile?> leftoverFile(
    core.RecordingId recordingId,
  ) async => null; // the draft holds the bytes

  @override
  Future<void> deleteOrphanFiles(Set<core.RecordingId> keep) async {}

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final s = _session;
    if (s != null) await s.abandon();
    final kept = _takeKeptStream();
    if (kept != null) _stopTracks(kept);
  }

  void _keep(web.MediaStream stream) {
    final old = _takeKeptStream();
    if (old != null) _stopTracks(old);
    _keptStream = stream;
    _keptTimer = _timer(MediaTuning.micStreamKeepAlive, () {
      final s = _takeKeptStream();
      if (s != null) _stopTracks(s); // the microphone indicator goes off
    });
  }

  web.MediaStream? _takeKeptStream() {
    _keptTimer?.cancel();
    _keptTimer = null;
    final s = _keptStream;
    _keptStream = null;
    if (s == null) return null;
    final live = s.getAudioTracks().toDart.any((t) => t.readyState == 'live');
    if (!live) return null;
    return s;
  }
}

/// getUserMedia with the 6.8.1 audio constraints.
Future<web.MediaStream> openBrowserMicrophone() => web
    .window
    .navigator
    .mediaDevices
    .getUserMedia(
      web.MediaStreamConstraints(
        audio: web.MediaTrackConstraints(
          channelCount: MediaTuning.webChannelCount.toJS,
          echoCancellation: MediaTuning.webMicProcessing.toJS,
          noiseSuppression: MediaTuning.webMicProcessing.toJS,
          autoGainControl: MediaTuning.webMicProcessing.toJS,
        ),
      ),
    )
    .toDart;

/// navigator.permissions.query({name: 'microphone'}).state; null when there is no query (Safari
/// before 16) or it throws (Firefox before 'microphone').
Future<String?> queryMicrophonePermission() async {
  final navigator = web.window.navigator as JSObject;
  if (!navigator.has('permissions')) return null;
  try {
    final status = await web.window.navigator.permissions
        .query(JSObject()..setProperty('name'.toJS, 'microphone'.toJS))
        .toDart;
    return status.state;
  } on Object {
    return null;
  }
}

/// The capture over a real MediaRecorder: dataavailable → Blob.arrayBuffer in event order (a
/// chain, so the stop event comes after the last bytes), stop, error; the first audio track's
/// mute / unmute / ended.
final class MediaRecorderCapture implements WebCapture {
  MediaRecorderCapture(this.stream, this.recorder);

  final web.MediaStream stream;
  final web.MediaRecorder recorder;

  WebCaptureCallbacks? _callbacks;
  Future<void> _chain = Future<void>.value();
  final List<(web.EventTarget, String, JSFunction)> _listeners = [];

  web.MediaStreamTrack? get _track {
    final tracks = stream.getAudioTracks().toDart;
    return tracks.isEmpty ? null : tracks.first;
  }

  @override
  String get mimeType => recorder.mimeType;

  @override
  bool get trackMuted => _track?.muted ?? false;

  /// MediaRecorder.state (tests).
  String get state => recorder.state;

  void _on(web.EventTarget target, String type, void Function(web.Event) f) {
    final js = f.toJS;
    target.addEventListener(type, js);
    _listeners.add((target, type, js));
  }

  @override
  void listen(WebCaptureCallbacks callbacks) {
    _callbacks = callbacks;
    _on(recorder, 'dataavailable', (e) {
      final cb = _callbacks;
      if (cb == null) return;
      cb.onDataEvent();
      final blob = (e as web.BlobEvent).data;
      if (blob.size == 0) return;
      _chain = _chain.then((_) async {
        try {
          final buffer = await blob.arrayBuffer().toDart;
          _callbacks?.onData(buffer.toDart.asUint8List());
        } on Object {
          // a Blob that cannot be read is lost (never seen in Chrome / Safari)
        }
      });
    });
    _on(recorder, 'stop', (_) {
      _chain = _chain.then((_) => _callbacks?.onStopped());
    });
    _on(recorder, 'error', (e) => _callbacks?.onError(e));
    final track = _track;
    if (track != null) {
      _on(track, 'mute', (_) => _callbacks?.onMute());
      _on(track, 'unmute', (_) => _callbacks?.onUnmute());
      _on(track, 'ended', (_) => _callbacks?.onEnded());
    }
  }

  @override
  void start(int timesliceMs) => recorder.start(timesliceMs);

  @override
  void pause() {
    if (recorder.state == 'recording') recorder.pause();
  }

  @override
  void resume() {
    if (recorder.state == 'paused') recorder.resume();
  }

  @override
  void requestData() {
    if (recorder.state != 'inactive') recorder.requestData();
  }

  @override
  void stop() {
    if (recorder.state != 'inactive') {
      recorder.stop();
    } else {
      _chain = _chain.then((_) => _callbacks?.onStopped());
    }
  }

  @override
  void stopTracks() => _stopTracks(stream);

  @override
  void detach() {
    for (final (target, type, f) in _listeners) {
      target.removeEventListener(type, f);
    }
    _listeners.clear();
    _callbacks = null;
  }
}

void _stopTracks(web.MediaStream stream) {
  for (final t in stream.getTracks().toDart) {
    t.stop();
  }
}

bool _hasGlobal(String name) =>
    globalContext.has(name) &&
    globalContext.getProperty<JSAny?>(name.toJS) != null;

/// DOMException.name of a getUserMedia failure; null for other errors.
String? _domErrorName(Object e) {
  try {
    final name = (e as JSObject).getProperty<JSAny?>('name'.toJS);
    if (name != null && name.isA<JSString>()) return (name as JSString).toDart;
  } on Object {
    // not a JS object
  }
  return null;
}
