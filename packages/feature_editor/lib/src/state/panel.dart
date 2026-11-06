// lib/src/state/panel.dart — m5-7/04-editor 6.15.4, 6.19 (E2-16).
//
// The bottom panel slot (EditorExtensions.recordingPanel — media_io's
// RecordingPanel): open / closed per note. The state is dropped when the
// note screen goes away (the per-note scope). Closing the panel does not stop
// a recording: the recorder belongs to media_io.
//
// Also the recorder status the mic button shows (a red dot while this note
// records, a grey one while another note does). Pen down never uses this
// stream — it reads the recorder's status synchronously (6.15.1, R-1).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart' as core;

import '../scope/editor_scope.dart';

class EditorPanelNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(editorNoteIdProvider);
    return false;
  }

  void open() => state = true;
  void close() => state = false;
  void toggle() => state = !state;
}

/// true while the bottom panel slot is open (this note only).
final editorPanelProvider = NotifierProvider<EditorPanelNotifier, bool>(
  EditorPanelNotifier.new,
  dependencies: [editorNoteIdProvider],
  name: 'editorPanelProvider',
);

/// The recorder's status for the mic button (statusStream emits the current
/// value on listen).
final editorRecorderStatusProvider = StreamProvider<core.RecorderStatus>(
  (ref) {
    ref.watch(editorNoteIdProvider);
    return ref.watch(core.audioRecorderServiceProvider).statusStream;
  },
  dependencies: [editorNoteIdProvider],
  name: 'editorRecorderStatusProvider',
);

/// What the mic button shows.
enum MicIndicator {
  /// Nothing is recording (or the recorder is idle / starting / finishing).
  none,

  /// This note records (recording or paused) — red dot.
  thisNote,

  /// Another note records — grey dot and '다른 노트에서 녹음 중이에요'.
  otherNote,
}

MicIndicator micIndicatorOf(core.RecorderStatus? status, String noteId) {
  if (status == null || !status.isActive) return MicIndicator.none;
  return status.noteId == noteId
      ? MicIndicator.thisNote
      : MicIndicator.otherNote;
}
