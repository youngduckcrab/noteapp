// Fakes behind media_io's internal ports (m5-7/06-pdf 6.5 '시험은 test/support/fake_engines.dart의
// 가짜를 생성자로 넣는다'): the recorder engine (web-like chunks or a native-like file), its
// files and the Web Locks port. PDF T34–T35b add the player and picker fakes here.
import 'dart:async';
import 'dart:typed_data';

import 'package:media_io/src/errors.dart';
import 'package:media_io/src/platform/web_locks.dart';
import 'package:media_io/src/record/recorder_engine.dart';
import 'package:note_core/note_core.dart' as core;

/// A recorder engine without a microphone. Web-like by default (chunks → the draft); with
/// `writesDraftChunks: false` native-like (the recording is a [FakeEngineFile]).
final class FakeRecorderEngine implements RecorderEngine {
  FakeRecorderEngine({
    this.writesDraftChunks = true,
    String? draftMimeType,
    this.support = core.AudioSupport.supported,
    this.crossPlatformPlayable,
    this.backgroundCapable = false,
  }) : draftMimeType =
           draftMimeType ??
           (writesDraftChunks ? 'audio/webm;codecs=opus' : 'audio/mp4');

  @override
  final bool writesDraftChunks;

  @override
  String draftMimeType;

  core.AudioSupport support;

  /// null → true unless the MIME is WebM.
  bool? crossPlatformPlayable;
  bool backgroundCapable;

  /// Every call, in order ('checkSupport', 'start', 'pause', 'resume', 'stop', 'cancel',
  /// 'abandon', 'dispose', 'leftoverFile', 'deleteOrphanFiles').
  final List<String> calls = [];

  /// Every start request.
  final List<RecorderEngineRequest> requests = [];

  /// While set, start() waits for it (the permission prompt / a slow start).
  Completer<void>? startGate;

  /// start() throws this (after the gate).
  Object? startError;

  /// The session emits EngineFailed(this) instead of EngineStarted.
  Object? failInsteadOfStarted;

  /// false: the test emits EngineStarted itself ([FakeEngineSession.started]).
  bool autoStarted = true;

  /// While set, every session's stop() waits for it (set before the session exists).
  Completer<void>? stopGate;

  /// The last session.
  FakeEngineSession? session;

  /// Native: the recording files by recording id (finished or left over).
  final Map<core.RecordingId, FakeEngineFile> files = {};

  /// What deleteOrphanFiles was given (null = never called).
  Set<core.RecordingId>? orphanKeep;

  bool disposed = false;

  int count(String call) => calls.where((c) => c == call).length;

  @override
  Future<core.AudioSupport> checkSupport({
    required bool requestPermission,
  }) async {
    calls.add('checkSupport');
    return support;
  }

  @override
  Future<RecorderEngineSession> start(RecorderEngineRequest request) async {
    calls.add('start');
    requests.add(request);
    final gate = startGate;
    if (gate != null) await gate.future;
    final error = startError;
    if (error != null) Error.throwWithStackTrace(error, StackTrace.current);
    final s = FakeEngineSession._(this, request);
    session = s;
    if (!writesDraftChunks) {
      files[request.recordingId] = FakeEngineFile();
    }
    final fail = failInsteadOfStarted;
    if (fail != null) {
      s._events.add(EngineFailed(fail));
    } else if (autoStarted) {
      s._events.add(const EngineStarted());
    }
    return s;
  }

  @override
  Future<RecorderEngineFile?> leftoverFile(core.RecordingId recordingId) async {
    calls.add('leftoverFile');
    return files[recordingId];
  }

  @override
  Future<void> deleteOrphanFiles(Set<core.RecordingId> keep) async {
    calls.add('deleteOrphanFiles');
    orphanKeep = keep;
    files.removeWhere((id, _) => !keep.contains(id));
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    disposed = true;
  }
}

final class FakeEngineSession implements RecorderEngineSession {
  FakeEngineSession._(this.engine, this.request);

  final FakeRecorderEngine engine;
  final RecorderEngineRequest request;
  final StreamController<RecorderEngineEvent> _events = StreamController();

  /// Web: resume() throws StateError while true (hidden tab — M-2).
  bool hidden = false;

  /// Web: handed to onChunk when stop() / abandon() is called (the last dataavailable).
  final List<Uint8List> stopChunks = [];
  final List<Uint8List> abandonChunks = [];

  /// stop() throws this.
  Object? stopError;

  /// While set, stop() waits for it (the engine finishing its last chunk / file).
  Completer<void>? stopGate;

  @override
  String get mimeType => engine.draftMimeType;

  @override
  bool get crossPlatformPlayable =>
      engine.crossPlatformPlayable ?? !engine.draftMimeType.contains('webm');

  @override
  bool get backgroundCapable => engine.backgroundCapable;

  @override
  Stream<RecorderEngineEvent> get events => _events.stream;

  /// A web chunk (dataavailable).
  void chunk(Uint8List bytes) => request.onChunk(bytes);

  void started() => _events.add(const EngineStarted());

  /// The system / a hidden tab / the microphone paused the recording.
  void systemPause([MediaErrorCode? reason]) =>
      _events.add(EnginePaused(bySystem: true, reason: reason));

  void systemResume() => _events.add(const EngineResumed());

  void fail(Object error) => _events.add(EngineFailed(error));

  /// Native: the file of this recording.
  FakeEngineFile? get file => engine.files[request.recordingId];

  @override
  Future<void> pause() async => engine.calls.add('pause');

  @override
  Future<void> resume() async {
    engine.calls.add('resume');
    if (hidden) throw StateError('The tab is hidden');
  }

  @override
  void requestData() => engine.calls.add('requestData');

  @override
  Future<RecorderEngineResult> stop() async {
    engine.calls.add('stop');
    final gate = stopGate ?? engine.stopGate;
    if (gate != null) await gate.future;
    for (final c in stopChunks) {
      request.onChunk(c);
    }
    final error = stopError;
    if (error != null) Error.throwWithStackTrace(error, StackTrace.current);
    return RecorderEngineResult(file: file);
  }

  @override
  Future<void> cancel() async {
    engine.calls.add('cancel');
    engine.files.remove(request.recordingId);
  }

  @override
  Future<void> abandon() async {
    engine.calls.add('abandon');
    for (final c in abandonChunks) {
      request.onChunk(c);
    }
  }
}

/// A native recording file: its bytes and what the decoder probe reads.
final class FakeEngineFile implements RecorderEngineFile {
  FakeEngineFile({Uint8List? bytes, this.probeMs})
    : bytes = bytes ?? Uint8List(0);

  Uint8List bytes;

  /// null → the probe cannot read a length.
  int? probeMs;
  bool deleted = false;
  int reads = 0;

  @override
  Future<Uint8List> read() async {
    reads++;
    return bytes;
  }

  @override
  Future<int?> probeDurationMs() async => probeMs;

  @override
  Future<void> delete() async => deleted = true;
}

/// Web Locks shared by the 'tabs' of one origin: [others] are held by another context.
final class FakeWebLocks implements WebLocks {
  FakeWebLocks({this.available = true});

  @override
  bool available;

  /// Held by another context (another tab).
  final Set<String> others = {};

  /// Held through this port now.
  final Set<String> held = {};

  /// `acquire <name>` / `release <name>`, in order.
  final List<String> log = [];

  @override
  Future<WebLockHold?> acquire(String name) async {
    if (!available) return null;
    held.add(name);
    log.add('acquire $name');
    return _FakeHold(this, name);
  }

  @override
  Future<Set<String>?> heldNames() async =>
      available ? {...others, ...held} : null;
}

final class _FakeHold implements WebLockHold {
  _FakeHold(this._locks, this.name);

  final FakeWebLocks _locks;
  bool _released = false;

  @override
  final String name;

  @override
  void release() {
    if (_released) return;
    _released = true;
    _locks.held.remove(name);
    _locks.log.add('release $name');
  }
}
