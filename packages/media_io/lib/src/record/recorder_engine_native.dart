// lib/src/record/recorder_engine_native.dart — the native recorder engine (m5-7/06-pdf 6.9):
// record 7.1.2 writes AAC-LC mono to `<app support dir>/media_io/rec/<recordingId>.m4a` (not the
// temp dir — iOS may empty tmp while the app is closed, 6.9.1); the draft is a row only (0 chunks
// — 6.9.5). Around each recording: (P-B) the Android microphone foreground service before
// record.start (foreground_service_native.dart — 6.9.4) and the iOS audio session
// (audio_session_native.dart — 6.9.3).
//
// Events (6.9.2): record's onStateChanged becomes engine events. The states this engine asked for
// (start → record, pause, resume → record, stop / cancel → stop) are expected and swallowed; a
// pause nobody asked for (iOS call / Siri, Android audio focus loss — AudioInterruptionMode.pause)
// is EnginePaused(bySystem: true, reason: systemInterruption), a record after it is
// EngineResumed, a stop nobody asked for is EngineFailed. No automatic resume (the user taps
// [이어서 녹음] — like the web).
//
// Stop reads the finished file whole (File.readAsBytes — 3 h ≈ 86 MB once, 6.9.1) through
// RecorderEngineFile; its length comes from the decoder (duration_probe.dart — 6.6.4).
// leftoverFile / deleteOrphanFiles serve the recovery of a recording the app did not finish
// (6.9.5). Internal; behind record/recorder_engine_factory.dart.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart' as rec;

import '../config.dart';
import '../errors.dart';
import '../playback/duration_probe.dart';
import '../testing/test_hooks.dart';
import '../tuning.dart';
import 'audio_session_native.dart';
import 'foreground_service_native.dart';
import 'recorder_engine.dart';

/// recorder_engine_factory.dart on the VM / native platforms (the config comes with each
/// start request).
RecorderEngine createPlatformRecorderEngine(MediaIoConfig config) =>
    NativeRecorderEngine();

/// recorder_engine_factory.dart: initializeMediaIo's platform step (Android FGS init — 6.9.4).
void preparePlatformRecording(MediaIoConfig config) =>
    prepareForegroundService(config);

/// recorder_engine_factory.dart: the playback session set-up (6.11.1 — the speech session).
Future<void> Function()? platformPlaybackSessionSetup() =>
    configureSpeechSession;

/// The native MIME (6.9.1).
const String nativeRecordingMimeType = 'audio/mp4';

/// The record configuration of one native recording (6.9.1): AAC-LC mono, the config's sample
/// rate, the request's bit rate (media.bitRate rule — 4.6), pause on interruptions.
rec.RecordConfig nativeRecordConfig(RecorderEngineRequest request) =>
    rec.RecordConfig(
      encoder: rec.AudioEncoder.aacLc,
      numChannels: 1,
      sampleRate: request.config.sampleRate,
      bitRate: request.bitRate,
      audioInterruption: rec.AudioInterruptionMode.pause,
      iosConfig: const rec.IosRecordConfig(
        categoryOptions: [
          rec.IosAudioCategoryOption.defaultToSpeaker,
          rec.IosAudioCategoryOption.allowBluetooth,
          rec.IosAudioCategoryOption.allowBluetoothA2DP,
        ],
      ),
    );

final class NativeRecorderEngine implements RecorderEngine {
  NativeRecorderEngine({
    rec.AudioRecorder Function()? recorder,
    Future<String> Function()? supportRoot,
    RecordingForegroundService? foreground,
    RecordingAudioSession? audioSession,
    Future<int?> Function(String path)? probe,
  }) : _createRecorder = recorder ?? rec.AudioRecorder.new,
       _supportRoot = supportRoot ?? _defaultSupportRoot,
       foreground = foreground ?? RecordingForegroundService(),
       audioSession = audioSession ?? RecordingAudioSession(),
       _probe = probe ?? probeDurationMs;

  final rec.AudioRecorder Function() _createRecorder;
  final Future<String> Function() _supportRoot;
  final Future<int?> Function(String path) _probe;

  /// (P-B, 6.9.4) Android microphone service.
  final RecordingForegroundService foreground;

  /// (P-B, 6.9.3) iOS session.
  final RecordingAudioSession audioSession;

  rec.AudioRecorder? _recorder;
  _NativeSession? _session;
  bool _disposed = false;

  /// (6.9.1) What the device applied when it changed the requested config (setOnConfigChanged —
  /// e.g. a lower bit rate); null when it took the request as is.
  rec.RecordConfig? appliedConfig;

  static Future<String> _defaultSupportRoot() async =>
      MediaTestHooks.directory ?? (await getApplicationSupportDirectory()).path;

  /// One record recorder for the engine's life (made on first use, so building the engine
  /// never touches the plugin).
  rec.AudioRecorder get _rec => _recorder ??= _createRecorder();

  @override
  bool get writesDraftChunks => false;

  @override
  String get draftMimeType => nativeRecordingMimeType;

  /// (T37) AAC encoder support from the last checkSupport; null before.
  bool? _aacLc;

  @override
  String? get encoderNote => switch (_aacLc) {
    null => null,
    final yes => 'aacLc=${yes ? 'yes' : 'no'}',
  };

  @override
  String? get developerNote {
    final notes = [
      if (appliedConfig case final c?)
        'config applied: ${c.encoder.name} ${c.bitRate} bps ${c.sampleRate} Hz',
      if (foreground.lastFailure case final f?) 'FGS failed: ${f.runtimeType}',
      if (audioSession.lastFailure case final f?)
        'audio session failed: ${f.runtimeType}',
    ];
    return notes.isEmpty ? null : notes.join(' · ');
  }

  /// `<support>/media_io/rec`.
  Future<Directory> recordingsDirectory() async =>
      Directory('${await _supportRoot()}/${MediaTuning.nativeRecordingDir}');

  /// `<support>/media_io/rec/<recordingId>.m4a` (6.9.1).
  Future<String> recordingPath(core.RecordingId recordingId) async =>
      '${(await recordingsDirectory()).path}/${nativeRecordingFileName(recordingId)}';

  /// 06-pdf 4.2.3: no AAC encoder → unsupported; hasPermission(request:) false →
  /// permissionDenied; a missing plugin (a VM without the fake) → unsupported.
  @override
  Future<core.AudioSupport> checkSupport({
    required bool requestPermission,
  }) async {
    if (_disposed) return core.AudioSupport.unsupported;
    try {
      final r = _rec;
      final aac = _aacLc = await r.isEncoderSupported(rec.AudioEncoder.aacLc);
      if (!aac) return core.AudioSupport.unsupported;
      return await r.hasPermission(request: requestPermission)
          ? core.AudioSupport.supported
          : core.AudioSupport.permissionDenied;
    } on Object {
      return core.AudioSupport.unsupported;
    }
  }

  @override
  Future<RecorderEngineSession> start(RecorderEngineRequest request) async {
    if (_disposed) throw StateError('The recorder engine was disposed');
    if (_session != null) {
      throw StateError('A native recording is already running');
    }
    final r = _rec;
    final path = await recordingPath(request.recordingId);
    final session = _NativeSession(this, r, path);
    _session = session;
    try {
      Directory(path).parent.createSync(recursive: true);
      // 6.9.4: the service before record.start, while the app is in front
      final service = await foreground.start(request.config);
      session.backgroundCapable = switch (defaultTargetPlatform) {
        TargetPlatform.android => service,
        TargetPlatform.iOS => true,
        _ => false,
      };
      await audioSession.beforeRecording(
        recorderManagesSession: (manage) async =>
            r.ios?.manageAudioSession(manage),
      );
      await r.setOnConfigChanged((c) => appliedConfig = c);
      session.listen();
      await session.expect(
        rec.RecordState.record,
        () => r.start(nativeRecordConfig(request), path: path),
      );
    } on Object catch (e) {
      await session.end();
      try {
        await r.cancel();
      } on Object {
        // nothing was started
      }
      _deleteQuietly(path);
      throw MediaIoException(
        MediaErrorCode.engineFailed,
        detail: 'native start',
        cause: e,
      );
    }
    session.emit(const EngineStarted());
    return session;
  }

  @override
  Future<RecorderEngineFile?> leftoverFile(core.RecordingId recordingId) async {
    final path = await recordingPath(recordingId);
    if (path == _session?.path || !File(path).existsSync()) {
      return null;
    }
    return NativeRecordingFile(path, _probe);
  }

  @override
  Future<void> deleteOrphanFiles(Set<core.RecordingId> keep) async {
    final dir = await recordingsDirectory();
    if (!dir.existsSync()) return;
    final kept = {for (final id in keep) nativeRecordingFileName(id)};
    final active = _session?.path;
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      if (entity.path == active) continue;
      final name = entity.uri.pathSegments.last;
      if (kept.contains(name)) continue;
      try {
        entity.deleteSync();
      } on FileSystemException {
        // tried again on the next start-up
      }
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final s = _session;
    if (s != null) await s.abandon();
    final r = _recorder;
    _recorder = null;
    if (r != null) {
      try {
        await r.dispose();
      } on Object {
        // the plugin goes with the process
      }
    }
  }

  void _ended(_NativeSession s) {
    if (identical(_session, s)) _session = null;
  }
}

/// `<recordingId>.m4a` with anything but [A-Za-z0-9_-] replaced.
String nativeRecordingFileName(core.RecordingId recordingId) =>
    '${recordingId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.m4a';

void _deleteQuietly(String path) {
  try {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  } on FileSystemException {
    // deleteOrphanFiles removes it later
  }
}

/// A recording file on the device (6.9.1, 6.9.5).
final class NativeRecordingFile implements RecorderEngineFile {
  NativeRecordingFile(this.path, this._probe);

  final String path;
  final Future<int?> Function(String path) _probe;

  @override
  Future<Uint8List> read() => File(path).readAsBytes();

  @override
  Future<int?> probeDurationMs() => _probe(path);

  @override
  Future<void> delete() async => _deleteQuietly(path);

  @override
  String toString() => 'NativeRecordingFile';
}

final class _NativeSession implements RecorderEngineSession {
  _NativeSession(this._engine, this._recorder, this.path);

  final NativeRecorderEngine _engine;
  final rec.AudioRecorder _recorder;
  final String path;

  /// Single subscription: buffers until the service listens (EngineStarted first).
  final StreamController<RecorderEngineEvent> _events = StreamController();
  StreamSubscription<rec.RecordState>? _states;

  /// The states this engine asked for and has not seen yet, oldest first.
  final List<rec.RecordState> _own = [];
  rec.RecordState _last = rec.RecordState.stop;
  bool _systemPaused = false;
  bool _ended = false;

  @override
  bool backgroundCapable = false;

  @override
  String get mimeType => nativeRecordingMimeType;

  @override
  bool get crossPlatformPlayable => true;

  @override
  Stream<RecorderEngineEvent> get events => _events.stream;

  void emit(RecorderEngineEvent e) {
    if (!_ended) _events.add(e);
  }

  void listen() {
    _states = _recorder.onStateChanged().listen(
      _onState,
      onError: (Object e) => emit(EngineFailed(e)),
    );
  }

  /// Runs [call], expecting the state it leads to.
  Future<void> expect(rec.RecordState state, Future<void> Function() call) {
    _own.add(state);
    return call();
  }

  void _onState(rec.RecordState state) {
    if (_ended) return;
    final i = _own.indexOf(state);
    if (i >= 0) {
      // ours (states we asked for that never came are dropped with it)
      _own.removeRange(0, i + 1);
      _last = state;
      return;
    }
    if (state == _last) return;
    _last = state;
    switch (state) {
      case rec.RecordState.pause:
        _systemPaused = true;
        emit(
          const EnginePaused(
            bySystem: true,
            reason: MediaErrorCode.systemInterruption,
          ),
        );
      case rec.RecordState.record:
        if (_systemPaused) {
          _systemPaused = false;
          emit(const EngineResumed());
        }
      case rec.RecordState.stop:
        emit(EngineFailed(StateError('The native recorder stopped by itself')));
    }
  }

  @override
  Future<void> pause() => expect(rec.RecordState.pause, _recorder.pause);

  @override
  Future<void> resume() {
    _systemPaused = false;
    return expect(rec.RecordState.record, _recorder.resume);
  }

  @override
  void requestData() {}

  @override
  Future<RecorderEngineResult> stop() async {
    _ended = true;
    try {
      final stopped = await _recorder.stop();
      return RecorderEngineResult(
        file: NativeRecordingFile(stopped ?? path, _engine._probe),
      );
    } finally {
      await end();
    }
  }

  @override
  Future<void> cancel() async {
    _ended = true;
    try {
      await _recorder.cancel();
    } finally {
      _deleteQuietly(path);
      await end();
    }
  }

  @override
  Future<void> abandon() async {
    _ended = true;
    try {
      await _recorder.stop(); // the file stays for the next start-up (6.9.5)
    } on Object {
      // what was written stays
    } finally {
      await end();
    }
  }

  /// The service, the session, the state subscription and the events go. Idempotent.
  Future<void> end() async {
    _ended = true;
    // not awaited: the done future of a cancelled subscription may belong to another zone
    unawaited(_states?.cancel());
    _states = null;
    _engine._ended(this);
    await _engine.foreground.stop();
    await _engine.audioSession.afterRecording();
    unawaited(_events.close());
  }
}
