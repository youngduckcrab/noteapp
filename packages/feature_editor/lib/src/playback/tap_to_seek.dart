// lib/src/playback/tap_to_seek.dart — m5-7/04-editor 6.3.5 (the tap-to-seek
// state), 6.15.3 (contract 7.2.4 R-5 (v2.1)) — E2-17.
//
// tapToSeekActive is the whole R-5 (v2.1) condition as one pure function
// (unit/tap_to_seek_state_test.dart checks every combination). Every value
// it gets is read synchronously by the caller: the recorder's and the
// player's `status` getters (not a stream value — same reason as R-1), the
// panel provider and the note's recording ids (empty before they load → no
// tap-to-seek).
import 'package:note_core/note_core.dart' as core;

/// finger = a one-finger tap (pen-only mode) or a finger dot in finger
/// drawing; penDot = a pen (or mouse) dot: moved ≤ 4 px in ≤ 200 ms.
enum TapKind { finger, penDot }

/// R-5 (v2.1): tapToSeek on + recorder idle + (finger: panel open OR playing/paused;
/// pen dot: playing/paused only) + the open recording belongs to this note.
///
/// 'The open recording' = playback.recordingId while the player is neither
/// idle nor failed (nothing to play from there).
bool tapToSeekActive({
  required TapKind kind,
  required bool tapToSeekSetting,
  required core.RecorderPhase recorderPhase,
  required bool panelOpen,
  required core.PlaybackStatus playback,
  required Set<String> noteRecordingIds,
}) {
  if (!tapToSeekSetting) return false;
  // Recording (starting … finishing): media ignores play() (CP-PDF-10), so a
  // taken tap would only make a dot disappear without sound.
  if (recorderPhase != core.RecorderPhase.idle) return false;
  final id = playback.recordingId;
  if (id == null || !noteRecordingIds.contains(id)) return false;
  final phase = playback.phase;
  if (phase == core.PlaybackPhase.idle || phase == core.PlaybackPhase.failed) {
    return false;
  }
  final playingOrPaused =
      phase == core.PlaybackPhase.playing || phase == core.PlaybackPhase.paused;
  return switch (kind) {
    // Panel open → even `ready` (the panel opens the latest recording
    // without playing it — 06-pdf 6.13.3).
    TapKind.finger => panelOpen || playingOrPaused,
    // A dot with only the panel open stays a dot (a full stop is kept).
    TapKind.penDot => playingOrPaused,
  };
}

/// The position tap-to-seek seeks to: `max(0, offset − preRollMs)` (R-5).
int tapToSeekPositionMs(int recordingOffsetMs, int preRollMs) {
  final position = recordingOffsetMs - preRollMs;
  return position < 0 ? 0 : position;
}
