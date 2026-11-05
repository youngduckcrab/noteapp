// lib/src/media/unsupported_audio.dart — (v2.0) the provider defaults (web / VM without
// media_io, and every build where AppFeatures turned recording off — D14·D17). Behaviour
// table: 02-core 6.8.2 (contract: 'Unsupported* behaviour table: 02-core 6.8.2').
// Reading never throws, so an editor with recording switched off still opens (V15).
import '../common/ids.dart';
import '../model/asset.dart';
import '../repo/recording_repository.dart';
import 'audio_ports.dart';

final class UnsupportedAudioRecorder implements AudioRecorderService {
  const UnsupportedAudioRecorder();

  @override
  RecorderStatus get status => const RecorderStatus();

  /// The idle status once (02-core 6.8.2).
  @override
  Stream<RecorderStatus> get statusStream =>
      Stream<RecorderStatus>.value(const RecorderStatus());

  @override
  Future<AudioSupport> checkSupport({bool requestPermission = false}) async =>
      AudioSupport.unsupported;

  @override
  Future<void> start({
    required RecordingId recordingId,
    required NoteId noteId,
  }) async => throw UnsupportedError('Recording is not supported here');

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<Recording?> stop() async => null;

  @override
  Future<void> cancel() async {}

  @override
  int? offsetNowMs() => null;

  /// Does not read the draft store: a build without recording does not recover either (D17).
  @override
  Future<List<RecordingDraft>> pendingDrafts() async => const [];

  @override
  Future<Recording?> recoverDraft(String draftId) async => null;
}

final class UnsupportedAudioPlayback implements AudioPlaybackService {
  const UnsupportedAudioPlayback();

  @override
  PlaybackStatus get status => const PlaybackStatus();

  /// The idle status once (02-core 6.8.2).
  @override
  Stream<PlaybackStatus> get statusStream =>
      Stream<PlaybackStatus>.value(const PlaybackStatus());

  @override
  Future<void> open(Recording recording) async =>
      throw UnsupportedError('Audio playback is not supported here');

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seekMs(int positionMs) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  int positionMs() => 0;

  @override
  Future<void> close() async {}
}
