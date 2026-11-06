// lib/src/errors.dart — MediaIoException, MediaErrorCode (m5-7/06-pdf 4.2.5). Internal: not in
// the barrel — other areas see CORE's RecorderStatus.error / PlaybackStatus.error as Object?.
// The panel (6.13) maps a code to the 해요체 text of 6.16. Messages never carry recording or
// image bytes or file paths (6.16).

/// Why a media operation failed or the recorder stopped by itself.
enum MediaErrorCode {
  /// Playback: the asset bytes are not on this device (and no fetcher brought them).
  assetMissing,

  /// stop() / recoverDraft(): the asset or the recording row could not be written; the draft is
  /// kept for the next start-up recovery (contract 7.2.4 v2.1, CP-PDF-5).
  saveFailed,

  /// Playback: the format does not play here (webm on iOS native).
  unsupportedFormat,

  /// Image import: the image could not be decoded.
  decodeFailed,

  /// Image import: too large even after normalising.
  tooLarge,

  /// Image import from the clipboard: no image there.
  clipboardEmpty,

  /// Image import from the clipboard: the browser refused the read.
  clipboardDenied,

  /// Image import: no camera.
  cameraUnavailable,

  /// The recorder engine failed (start or while recording).
  engineFailed,

  /// (v2.1) Another window recovered or discarded this recording's draft (append StateError —
  /// 6.8.5): the recorder stopped; what was saved is in that window's list.
  draftLost,

  /// Paused by the system: the tab was hidden (web — 6.8.3). Resumable.
  hiddenTab,

  /// Paused by the system: the microphone track ended or stayed muted (6.8.3). Not resumable —
  /// the panel only offers stop.
  microphoneLost,

  /// Paused by the recorder: queued + unsaved chunks over 8 MiB (6.8.5).
  storageBacklog,

  /// A draft chunk could not be written (kept in memory and retried — 6.8.5). Recording goes on.
  storageFailed,

  /// Start: the microphone permission was refused (web NotAllowedError).
  permissionDenied,

  /// Start: no microphone (web NotFoundError).
  microphoneNotFound,

  /// Start: another app holds the microphone (web NotReadableError).
  microphoneBusy,
}

/// The error media_io puts in status.error or throws (06-pdf 4.2.5).
final class MediaIoException implements Exception {
  const MediaIoException(this.code, {this.detail, this.cause});

  final MediaErrorCode code;

  /// Developer detail (English, no bytes or paths).
  final String? detail;

  /// The underlying error, when there is one.
  final Object? cause;

  @override
  String toString() {
    final d = detail == null ? '' : ': $detail';
    final c = cause == null ? '' : ' (cause: ${cause.runtimeType})';
    return 'MediaIoException(${code.name})$d$c';
  }
}
