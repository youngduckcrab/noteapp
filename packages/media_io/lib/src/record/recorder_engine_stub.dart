// lib/src/record/recorder_engine_stub.dart — recorder_engine_factory.dart where there is neither
// dart:io nor the browser (m5-7/06-pdf 6.18): no recorder (checkSupport → unsupported; start
// throws UnsupportedError). Internal.
import 'package:note_core/note_core.dart' as core;

import '../config.dart';
import 'recorder_engine.dart';

RecorderEngine createPlatformRecorderEngine(MediaIoConfig config) =>
    const UnsupportedRecorderEngine();

/// Nothing to prepare.
void preparePlatformRecording(MediaIoConfig config) {}

/// No playback session to set up.
Future<void> Function()? platformPlaybackSessionSetup() => null;

final class UnsupportedRecorderEngine implements RecorderEngine {
  const UnsupportedRecorderEngine();

  @override
  bool get writesDraftChunks => false;

  @override
  String get draftMimeType => 'audio/mp4';

  @override
  String? get developerNote => null;

  @override
  Future<core.AudioSupport> checkSupport({
    required bool requestPermission,
  }) async => core.AudioSupport.unsupported;

  @override
  Future<RecorderEngineSession> start(RecorderEngineRequest request) =>
      Future.error(UnsupportedError('Recording is not supported here'));

  @override
  Future<RecorderEngineFile?> leftoverFile(
    core.RecordingId recordingId,
  ) async => null;

  @override
  Future<void> deleteOrphanFiles(Set<core.RecordingId> keep) async {}

  @override
  Future<void> dispose() async {}
}
