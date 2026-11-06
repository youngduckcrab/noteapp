// lib/src/record/recorder_engine.dart — the recorder engine port (m5-7/06-pdf 6.6.2). Internal:
// the test seam of MediaRecorderService. Platform bodies: recorder_engine_browser.dart (own
// MediaRecorder — 6.8, PDF T32b), recorder_engine_native.dart (record + file — 6.9, PDF T33),
// recorder_engine_stub.dart (no plugin) behind a conditional export; tests use
// test/support/fake_engines.dart.
import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

import '../config.dart';
import '../errors.dart';

abstract interface class RecorderEngine {
  /// Web: true — every chunk goes to [RecorderEngineRequest.onChunk] and from there to the
  /// recording draft (DraftWriter, 6.8.5). Native: false — the engine writes a file and the draft
  /// is a row only (0 chunks — 6.9.5).
  bool get writesDraftChunks;

  /// The MIME the next [start] records — the draft's mimeType (web: the 6.8.1 candidate chosen
  /// for this browser; native 'audio/mp4'). The session's [RecorderEngineSession.mimeType] is
  /// what was actually written.
  String get draftMimeType;

  /// 06-pdf 4.2.3 checkSupport.
  Future<core.AudioSupport> checkSupport({required bool requestPermission});

  /// Starts capturing. The session's [RecorderEngineSession.events] then begin with
  /// [EngineStarted] (or [EngineFailed]); the recording clock starts on that event, not here.
  Future<RecorderEngineSession> start(RecorderEngineRequest request);

  /// Native (6.9.5): the file a recording that did not finish left (`media_io/rec/<id>.m4a`);
  /// `null` when there is none. Web: always `null` (the draft holds the bytes).
  Future<RecorderEngineFile?> leftoverFile(core.RecordingId recordingId);

  /// Native (6.9.5): deletes the files under `media_io/rec/` whose recording has no draft row
  /// (the first pendingDrafts() after start-up). Web: nothing.
  Future<void> deleteOrphanFiles(Set<core.RecordingId> keep);

  /// (T33) What the engine adds to the developer overlay (6.14 — native: the config the device
  /// applied, 'FGS failed: …'); null = nothing.
  String? get developerNote;

  Future<void> dispose();
}

@immutable
final class RecorderEngineRequest {
  const RecorderEngineRequest({
    required this.recordingId,
    required this.noteId,
    required this.config,
    required this.bitRate,
    required this.onChunk,
  });

  final core.RecordingId recordingId;
  final core.NoteId noteId;
  final MediaIoConfig config;

  /// (수정 2회차) Effective bit rate for this recording: media.bitRate when non-zero and in
  /// [32000, 128000], else config.bitRate (4.6). Engines use this, not config.bitRate.
  final int bitRate;

  /// Web: every chunk goes here, in order (DraftWriter). Native: unused (file).
  final void Function(Uint8List chunk) onChunk;
}

abstract interface class RecorderEngineSession {
  /// Actual (web: MediaRecorder.mimeType).
  String get mimeType;

  bool get crossPlatformPlayable;

  /// Web false, android = FGS running, iOS true.
  bool get backgroundCapable;

  /// Started, paused(bySystem), resumed, failed(error). Single subscription: the service
  /// listens right after [RecorderEngine.start] returned (events before that are buffered).
  Stream<RecorderEngineEvent> get events;

  /// The user paused: completes once the engine is paused (no event is needed for it).
  Future<void> pause();

  /// The user resumed: completes once the engine records again. Web: StateError while hidden
  /// (M-2) or after the microphone was lost.
  Future<void> resume();

  /// Web: flush the current chunk now; native: no-op.
  void requestData();

  /// Web: after the last chunk was handed to onChunk. Native: the finished file.
  Future<RecorderEngineResult> stop();

  /// Discard (native: delete the file).
  Future<void> cancel();

  /// App/scope teardown while recording: stop capturing WITHOUT finishing (web: requestData then
  /// stop tracks; native: stop the recorder, keep the file) → recoverable next launch (6.10).
  Future<void> abandon();
}

@immutable
final class RecorderEngineResult {
  const RecorderEngineResult({this.file});

  /// Native: the finished file. Web: `null` — the bytes are the draft (readAll — 6.6.3).
  final RecorderEngineFile? file;
}

/// A recording file on the device (native — 6.9.1, 6.9.5).
abstract interface class RecorderEngineFile {
  /// The whole file (one full-size buffer — 6.6.5).
  Future<Uint8List> read();

  /// The decoder's length in ms (a separate player, at most durationProbeTimeout — 6.6.4);
  /// `null` (or ≤ 0) when it could not be read.
  Future<int?> probeDurationMs();

  Future<void> delete();
}

sealed class RecorderEngineEvent {
  const RecorderEngineEvent();
}

final class EngineStarted extends RecorderEngineEvent {
  const EngineStarted();
}

final class EnginePaused extends RecorderEngineEvent {
  const EnginePaused({required this.bySystem, this.reason});

  /// true = the system / a hidden tab / the microphone, not the user (status.interrupted).
  final bool bySystem;
  final MediaErrorCode? reason;
}

final class EngineResumed extends RecorderEngineEvent {
  const EngineResumed();
}

final class EngineFailed extends RecorderEngineEvent {
  const EngineFailed(this.error);
  final Object error;
}
