// lib/src/playback/recording_link.dart — m5-7/04-editor 6.15.1 (contract
// 7.2.4 R-1, R-2; E-5).
//
// The recording meta of a new stroke, read synchronously at pen down (the
// web: at the contact move — 6.3.2). The recorder's status stream (the mic
// button) is not used here: a stream value can be one event late.
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

abstract final class RecordingLink {
  /// R-1, read synchronously inside pen-down handling (E-5). Laser → empty meta.
  ///
  /// Linked only while `recorder.status` is `recording` for [noteId] and
  /// `offsetNowMs()` has a value (the audio-timeline position — R-2: no wall
  /// clock difference). Paused, another note's recording, idle / starting /
  /// finishing → empty meta (U12).
  static ink.InkStrokeMeta metaFor(
    core.AudioRecorderService recorder,
    String noteId,
    core.PenTool tool,
  ) {
    if (tool == core.PenTool.laser) return const ink.InkStrokeMeta();
    final status = recorder.status;
    final recordingId = status.recordingId;
    if (status.phase != core.RecorderPhase.recording ||
        status.noteId != noteId ||
        recordingId == null) {
      return const ink.InkStrokeMeta();
    }
    final offset = recorder.offsetNowMs();
    if (offset == null) return const ink.InkStrokeMeta();
    return ink.InkStrokeMeta(
      recordingId: recordingId,
      recordingOffsetMs: offset,
    );
  }

  /// (v2.13-rec) [object] linked to the recording [meta] names (PageObject.withRecording);
  /// [object] itself when [meta] is empty.
  static T linkObjectTo<T extends core.PageObject>(
    T object,
    ink.InkStrokeMeta meta,
  ) {
    final id = meta.recordingId;
    final offset = meta.recordingOffsetMs;
    if (id == null || offset == null) return object;
    return object.withRecording(recordingId: id, recordingOffsetMs: offset)
        as T;
  }

  /// (v2.13-rec) An object made now (the shape tool, a new text box, an inserted image):
  /// linked like a stroke whose pen went down now (R-1 — the same synchronous read of
  /// the recorder); not linked when this note is not being recorded.
  static T linkObject<T extends core.PageObject>(
    core.AudioRecorderService recorder,
    String noteId,
    T object,
  ) => linkObjectTo(object, metaFor(recorder, noteId, core.PenTool.ballpoint));
}
