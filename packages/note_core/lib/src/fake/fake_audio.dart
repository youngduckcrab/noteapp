// Internal (exported by testing.dart): FakeAudioRecorder, FakeAudioPlayback — 2nd-round
// contract 7.6 '기반 단계 시험 도우미' / 02-core 4.9, 6.8.3, 6.8.4. No timers and no real
// time (7.4.8): the recorder clock moves only by advance(); the 'recently updated' window of
// pendingDrafts() is measured on store.clock.
// Contract comments are kept verbatim (they contain <placeholders>).
// ignore_for_file: unintended_html_in_doc_comment
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../common/ids.dart';
import '../media/audio_ports.dart';
import '../model/asset.dart';
import '../repo/note_store.dart';
import '../repo/recording_repository.dart';

/// The fake's chunk interval: one 16-byte chunk per advanced second of recording (6.8.3).
const int _chunkIntervalMs = 1000;

/// pendingDrafts() leaves out drafts updated within max(10 s, 5 × the chunk interval).
const int _recentMs = 10000;

/// Controllable recorder: no real time, no plugin. stop() writes Asset(audio, 'audio/mp4',
/// silent bytes) then Recording (M-1) into [store]. (v2.1) start() with support != supported
/// throws UnsupportedError (as the real recorder); recording writes drafts to
/// store.recordingDrafts; pendingDrafts() follows the 7.2.4 exclusion rule. With the real
/// in-memory CORE inside testWidgets, asset writes go through idb_shim timers — pump / runAsync.
///
/// CORE 4.9: abandon() completes after the draft chunks queued by advance() are stored.
/// Chunk interval of the fake = 1 s (one 16-byte chunk per advanced second), so the 7.2.4
/// 'recently updated' window is max(10 s, 5 × 1 s) = 10 s measured on store.clock (6.8.3).
final class FakeAudioRecorder implements AudioRecorderService {
  FakeAudioRecorder({
    required this._store,
    this._support = AudioSupport.supported,
  });

  final NoteStore _store;
  final AudioSupport _support;

  RecorderStatus _status = const RecorderStatus();
  final StreamController<RecorderStatus> _ctrl = StreamController.broadcast(
    sync: true,
  );

  String? _draftId;
  EpochMillis _startedAt = 0;
  int _activeMs = 0;
  int _pausedMs = 0;
  Future<void> _chain = Future<void>.value();
  final Set<String> _recovering = {};

  RecordingDraftStore get _drafts => _store.recordingDrafts;
  EpochMillis get _now => _store.clock.now().millisecondsSinceEpoch;

  void _set(RecorderStatus next) {
    if (next == _status) return;
    _status = next;
    _ctrl.add(next);
  }

  void _reset({Object? error}) {
    _draftId = null;
    _activeMs = 0;
    _pausedMs = 0;
    _chain = Future<void>.value();
    _set(RecorderStatus(error: error));
  }

  /// Draft appends run one after the other, in call order (an append failure — e.g. the
  /// draft was recovered elsewhere — goes to status.error).
  void _enqueue(String draftId, Uint8List chunk, int activeMs) {
    _chain = _chain.then((_) async {
      try {
        await _drafts.append(draftId, chunk, activeMs: activeMs);
      } on Object catch (e) {
        if (_draftId == draftId) _set(_status.copyWith(error: e));
      }
    });
  }

  // recorder clock; offsetNowMs() follows (pauses excluded)
  /// (CORE 6.8.3) Recording: active time += [elapsed]; one 16-byte chunk per crossed second.
  /// Paused: an empty keep-alive chunk per crossed second of pause (activeMs / updatedAt only).
  void advance(Duration elapsed) {
    final draftId = _draftId;
    if (draftId == null) return;
    final ms = elapsed.inMilliseconds;
    if (ms <= 0) return;
    switch (_status.phase) {
      case RecorderPhase.recording:
        final before = _activeMs;
        _activeMs += ms;
        for (
          var k = before ~/ _chunkIntervalMs + 1;
          k <= _activeMs ~/ _chunkIntervalMs;
          k++
        ) {
          _enqueue(
            draftId,
            Uint8List.fromList(List.filled(16, k % 256)),
            k * _chunkIntervalMs,
          );
        }
        _set(_status.copyWith(activeMs: _activeMs));
      case RecorderPhase.paused:
        final before = _pausedMs;
        _pausedMs += ms;
        for (
          var k = before ~/ _chunkIntervalMs + 1;
          k <= _pausedMs ~/ _chunkIntervalMs;
          k++
        ) {
          _enqueue(draftId, Uint8List(0), _activeMs);
        }
      default:
        break;
    }
  }

  // system / hidden-tab pause → interrupted = true
  void interrupt() {
    if (_status.phase != RecorderPhase.recording) return;
    _set(_status.copyWith(phase: RecorderPhase.paused, interrupted: true));
  }

  int stopDurationErrorMs = 0; // durationMs = clock + this (R-3)
  /// (v2.1, CP-8) Closed tab / killed app: in-memory state dropped, phase idle, the draft written
  /// so far stays for pendingDrafts() / recoverDraft() of a new recorder (V16 shape).
  Future<void> abandon() async {
    await _chain;
    _reset();
  }

  @override
  RecorderStatus get status => _status;

  @override
  Stream<RecorderStatus> get statusStream => Stream.multi((c) {
    c.add(_status);
    final sub = _ctrl.stream.listen(c.add);
    c.onCancel = sub.cancel;
  });

  @override
  Future<AudioSupport> checkSupport({bool requestPermission = false}) async =>
      _support;

  @override
  Future<void> start({
    required RecordingId recordingId,
    required NoteId noteId,
  }) async {
    if (_support != AudioSupport.supported) {
      throw UnsupportedError('Recording is not supported here ($_support)');
    }
    if (_status.phase != RecorderPhase.idle) {
      throw StateError('Another recording is active');
    }
    _set(
      RecorderStatus(
        phase: RecorderPhase.starting,
        recordingId: recordingId,
        noteId: noteId,
        mimeType: 'audio/mp4',
      ),
    );
    try {
      final draft = await _drafts.begin(
        recordingId: recordingId,
        noteId: noteId,
        mimeType: 'audio/mp4',
        startedAt: _now,
      );
      _draftId = draft.draftId;
      _startedAt = draft.startedAt;
      _activeMs = 0;
      _pausedMs = 0;
      _set(_status.copyWith(phase: RecorderPhase.recording));
    } on Object catch (e) {
      _reset(error: e);
      rethrow;
    }
  }

  @override
  Future<void> pause() async {
    if (_status.phase != RecorderPhase.recording) return;
    _set(_status.copyWith(phase: RecorderPhase.paused, interrupted: false));
  }

  @override
  Future<void> resume() async {
    if (_status.phase != RecorderPhase.paused) return;
    _set(_status.copyWith(phase: RecorderPhase.recording, interrupted: false));
  }

  /// Deterministic 'silent' bytes naming the recording (distinct per recording, so the
  /// asset ids differ).
  static Uint8List _silentBytes(RecordingId id) =>
      Uint8List.fromList(utf8.encode('fake-audio/mp4 silent:$id'));

  @override
  Future<Recording?> stop() async {
    final draftId = _draftId;
    if (!_status.isActive || draftId == null) return null;
    final recordingId = _status.recordingId!;
    final noteId = _status.noteId!;
    _set(_status.copyWith(phase: RecorderPhase.finishing));
    await _chain;
    if (_activeMs == 0) {
      await _drafts.discard(draftId);
      _reset();
      return null;
    }
    try {
      final asset = await _store.assets.put(
        _silentBytes(recordingId),
        type: AssetType.audio,
        mimeType: 'audio/mp4',
      );
      final recording = await _store.recordings.createRecording(
        id: recordingId,
        noteId: noteId,
        assetId: asset.id,
        durationMs: _activeMs + stopDurationErrorMs,
        startedAt: _startedAt,
      );
      await _drafts.discard(draftId);
      _reset();
      return recording;
    } on Object catch (e) {
      // The draft stays for the next start-up recovery (CP-PDF-5).
      _reset(error: e);
      rethrow;
    }
  }

  @override
  Future<void> cancel() async {
    final draftId = _draftId;
    if (draftId == null) return;
    await _chain;
    await _drafts.discard(draftId);
    _reset();
  }

  @override
  int? offsetNowMs() =>
      _status.phase == RecorderPhase.recording ? _activeMs : null;

  bool _excluded(RecordingDraft d) =>
      (_status.phase != RecorderPhase.idle && d.draftId == _draftId) ||
      _recovering.contains(d.draftId) ||
      _now - d.updatedAt < _recentMs;

  @override
  Future<List<RecordingDraft>> pendingDrafts() async => List.unmodifiable([
    for (final d in await _drafts.listDrafts())
      if (!_excluded(d)) d,
  ]);

  @override
  Future<Recording?> recoverDraft(String draftId) async {
    final draft = (await _drafts.listDrafts())
        .where((d) => d.draftId == draftId)
        .firstOrNull;
    if (draft == null) throw StateError('Unknown recording draft $draftId');
    if (_excluded(draft)) {
      throw StateError(
        'Draft $draftId is active, being recovered or recently updated',
      );
    }
    _recovering.add(draftId);
    try {
      final bytes = await _drafts.readAll(draftId);
      if (bytes.isEmpty) {
        await _drafts.discard(draftId);
        return null;
      }
      final asset = await _store.assets.put(
        bytes,
        type: AssetType.audio,
        mimeType: draft.mimeType,
      );
      final recording = await _store.recordings.createRecording(
        id: draft.recordingId,
        noteId: draft.noteId,
        assetId: asset.id,
        durationMs: draft.activeMs,
        startedAt: draft.startedAt,
        title: '복구된 녹음',
      );
      await _drafts.discard(draftId);
      return recording;
    } finally {
      _recovering.remove(draftId);
    }
  }
}

final class FakeAudioPlayback implements AudioPlaybackService {
  FakeAudioPlayback();

  PlaybackStatus _status = const PlaybackStatus();
  final StreamController<PlaybackStatus> _ctrl = StreamController.broadcast(
    sync: true,
  );
  int _position = 0;
  final List<String> _calls = [];

  void _set(PlaybackStatus next) {
    if (next == _status) return;
    _status = next;
    _ctrl.add(next);
  }

  int _clamp(int p) => p.clamp(0, _status.durationMs);

  // positionMs() returns it; seekMs() also sets it
  void setPositionMs(int positionMs) => _position = _clamp(positionMs);

  /// (v2.1, CP-8) Calls in order: 'open:<recordingId>', 'play', 'pause', 'seek:<ms>', 'speed:<x>', 'close'.
  List<String> get calls => List.unmodifiable(_calls);

  @override
  PlaybackStatus get status => _status;

  @override
  Stream<PlaybackStatus> get statusStream => Stream.multi((c) {
    c.add(_status);
    final sub = _ctrl.stream.listen(c.add);
    c.onCancel = sub.cancel;
  });

  /// loading → ready, durationMs of [recording], position 0. Reads no bytes.
  @override
  Future<void> open(Recording recording) async {
    _calls.add('open:${recording.id}');
    _set(
      PlaybackStatus(
        phase: PlaybackPhase.loading,
        recordingId: recording.id,
        speed: _status.speed,
      ),
    );
    _position = 0;
    _set(
      _status.copyWith(
        phase: PlaybackPhase.ready,
        durationMs: recording.durationMs,
      ),
    );
  }

  @override
  Future<void> play() async {
    _calls.add('play');
    if (_status.phase
        case PlaybackPhase.ready ||
            PlaybackPhase.paused ||
            PlaybackPhase.completed) {
      _set(_status.copyWith(phase: PlaybackPhase.playing));
    }
  }

  @override
  Future<void> pause() async {
    _calls.add('pause');
    if (_status.phase == PlaybackPhase.playing) {
      _set(_status.copyWith(phase: PlaybackPhase.paused));
    }
  }

  @override
  Future<void> seekMs(int positionMs) async {
    _calls.add('seek:$positionMs');
    _position = _clamp(positionMs);
  }

  @override
  Future<void> setSpeed(double speed) async {
    _calls.add('speed:$speed');
    _set(_status.copyWith(speed: speed.clamp(0.5, 2.0).toDouble()));
  }

  @override
  int positionMs() => _position;

  @override
  Future<void> close() async {
    _calls.add('close');
    _position = 0;
    _set(PlaybackStatus(speed: _status.speed));
  }
}
