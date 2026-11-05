// Internal (exported by testing.dart): FakeAudioRecorder, FakeAudioPlayback — 2nd-round
// contract 7.6 '기반 단계 시험 도우미' / 02-core 4.9, 6.8.3, 6.8.4. B2-α declares them; the
// behaviour is CORE T23b (02-core 8.1 'B2 상태').
// Contract comments are kept verbatim (they contain <placeholders>).
// ignore_for_file: unintended_html_in_doc_comment
import '../common/ids.dart';
import '../common/pending.dart';
import '../media/audio_ports.dart';
import '../model/asset.dart';
import '../repo/note_store.dart';
import '../repo/recording_repository.dart';

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

  // The CORE T23b body reads these.
  // ignore: unused_field
  final NoteStore _store;
  // ignore: unused_field
  final AudioSupport _support;

  // recorder clock; offsetNowMs() follows (pauses excluded)
  void advance(Duration elapsed) => notYet('T23b', 'FakeAudioRecorder.advance');

  // system / hidden-tab pause → interrupted = true
  void interrupt() => notYet('T23b', 'FakeAudioRecorder.interrupt');

  int stopDurationErrorMs = 0; // durationMs = clock + this (R-3)
  /// (v2.1, CP-8) Closed tab / killed app: in-memory state dropped, phase idle, the draft written
  /// so far stays for pendingDrafts() / recoverDraft() of a new recorder (V16 shape).
  Future<void> abandon() async => notYet('T23b', 'FakeAudioRecorder.abandon');

  @override
  RecorderStatus get status => notYet('T23b', 'FakeAudioRecorder.status');

  @override
  Stream<RecorderStatus> get statusStream =>
      notYet('T23b', 'FakeAudioRecorder.statusStream');

  @override
  Future<AudioSupport> checkSupport({bool requestPermission = false}) async =>
      notYet('T23b', 'FakeAudioRecorder.checkSupport');

  @override
  Future<void> start({
    required RecordingId recordingId,
    required NoteId noteId,
  }) async => notYet('T23b', 'FakeAudioRecorder.start');

  @override
  Future<void> pause() async => notYet('T23b', 'FakeAudioRecorder.pause');

  @override
  Future<void> resume() async => notYet('T23b', 'FakeAudioRecorder.resume');

  @override
  Future<Recording?> stop() async => notYet('T23b', 'FakeAudioRecorder.stop');

  @override
  Future<void> cancel() async => notYet('T23b', 'FakeAudioRecorder.cancel');

  @override
  int? offsetNowMs() => notYet('T23b', 'FakeAudioRecorder.offsetNowMs');

  @override
  Future<List<RecordingDraft>> pendingDrafts() async =>
      notYet('T23b', 'FakeAudioRecorder.pendingDrafts');

  @override
  Future<Recording?> recoverDraft(String draftId) async =>
      notYet('T23b', 'FakeAudioRecorder.recoverDraft');
}

final class FakeAudioPlayback implements AudioPlaybackService {
  FakeAudioPlayback();

  // positionMs() returns it; seekMs() also sets it
  void setPositionMs(int positionMs) =>
      notYet('T23b', 'FakeAudioPlayback.setPositionMs');

  /// (v2.1, CP-8) Calls in order: 'open:<recordingId>', 'play', 'pause', 'seek:<ms>', 'speed:<x>', 'close'.
  List<String> get calls => notYet('T23b', 'FakeAudioPlayback.calls');

  @override
  PlaybackStatus get status => notYet('T23b', 'FakeAudioPlayback.status');

  @override
  Stream<PlaybackStatus> get statusStream =>
      notYet('T23b', 'FakeAudioPlayback.statusStream');

  @override
  Future<void> open(Recording recording) async =>
      notYet('T23b', 'FakeAudioPlayback.open');

  @override
  Future<void> play() async => notYet('T23b', 'FakeAudioPlayback.play');

  @override
  Future<void> pause() async => notYet('T23b', 'FakeAudioPlayback.pause');

  @override
  Future<void> seekMs(int positionMs) async =>
      notYet('T23b', 'FakeAudioPlayback.seekMs');

  @override
  Future<void> setSpeed(double speed) async =>
      notYet('T23b', 'FakeAudioPlayback.setSpeed');

  @override
  int positionMs() => notYet('T23b', 'FakeAudioPlayback.positionMs');

  @override
  Future<void> close() async => notYet('T23b', 'FakeAudioPlayback.close');
}
