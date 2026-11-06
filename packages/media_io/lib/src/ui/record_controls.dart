// lib/src/ui/record_controls.dart — the recording row and the status line of the panel
// (m5-7/06-pdf 6.13.1, 6.13.2). Internal.
//
// recordRowMode / statusLineFor are pure: the 6.13.2 table from the recorder status, the last
// checkSupport result and the error of the panel's own last start / stop call.
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../errors.dart';
import 'format.dart';
import 'strings_ko.dart';

/// What the recording row offers (6.13.2 '녹음 줄').
enum RecordRowMode {
  /// checkSupport → unsupported: the record button is disabled.
  unsupported,

  /// [● 녹음] (also after a refused permission — pressing asks again).
  idle,

  /// starting / finishing: a progress indicator.
  busy,

  /// [❚❚][■], clock, red dot.
  recording,

  /// Paused by the user or by a hidden tab: [▶ 이어서][■].
  pausedResumable,

  /// Paused by a lost microphone / storage backlog / engine failure: [■] only.
  pausedStopOnly,

  /// Another note records: record disabled + [■ 그 녹음 정지].
  otherNote,
}

enum StatusLineAction { none, resumeRecording }

typedef PanelStatusLine = ({String? text, StatusLineAction action});

MediaErrorCode? mediaErrorCodeOf(Object? error) =>
    error is MediaIoException ? error.code : null;

RecordRowMode recordRowMode(
  core.RecorderStatus status,
  String noteId,
  core.AudioSupport? support,
) {
  final mine = status.noteId == null || status.noteId == noteId;
  switch (status.phase) {
    case core.RecorderPhase.idle:
      return support == core.AudioSupport.unsupported
          ? RecordRowMode.unsupported
          : RecordRowMode.idle;
    case core.RecorderPhase.starting || core.RecorderPhase.finishing:
      return mine ? RecordRowMode.busy : RecordRowMode.otherNote;
    case core.RecorderPhase.recording:
      return mine ? RecordRowMode.recording : RecordRowMode.otherNote;
    case core.RecorderPhase.paused:
      if (!mine) return RecordRowMode.otherNote;
      if (!status.interrupted) return RecordRowMode.pausedResumable;
      return switch (mediaErrorCodeOf(status.error)) {
        null || MediaErrorCode.hiddenTab => RecordRowMode.pausedResumable,
        _ => RecordRowMode.pausedStopOnly,
      };
  }
}

/// The status line (6.13.2 '상황 줄'). [localError] = what the panel's last start() / stop()
/// threw (cleared by the next call); [web] chooses the web texts.
PanelStatusLine statusLineFor({
  required core.RecorderStatus status,
  required String noteId,
  required core.AudioSupport? support,
  required Object? localError,
  required bool web,
}) {
  PanelStatusLine line(
    String text, [
    StatusLineAction a = StatusLineAction.none,
  ]) => (text: text, action: a);
  const PanelStatusLine none = (text: null, action: StatusLineAction.none);
  final mode = recordRowMode(status, noteId, support);
  switch (mode) {
    case RecordRowMode.otherNote:
      return line(MediaStringsKo.otherNoteRecording);
    case RecordRowMode.busy:
      return line(
        status.phase == core.RecorderPhase.starting
            ? MediaStringsKo.starting
            : MediaStringsKo.finishing,
      );
    case RecordRowMode.recording:
      return web && !status.crossPlatformPlayable
          ? line(MediaStringsKo.webFormatWarning)
          : none;
    case RecordRowMode.pausedResumable:
      return status.interrupted
          ? line(MediaStringsKo.hiddenTab, StatusLineAction.resumeRecording)
          : none;
    case RecordRowMode.pausedStopOnly:
      return line(switch (mediaErrorCodeOf(status.error)) {
        MediaErrorCode.storageBacklog => MediaStringsKo.storageBacklog,
        // microphoneLost, engineFailed — the closest text (6.16 '가장 가까운 것')
        _ => MediaStringsKo.microphoneLost,
      });
    case RecordRowMode.unsupported:
      return line(
        web ? MediaStringsKo.unsupportedWeb : MediaStringsKo.unsupportedDevice,
      );
    case RecordRowMode.idle:
      break;
  }
  // idle: the panel's own error first, then the recorder's, then the support, then consent
  final local = _idleErrorText(localError, web, fromStart: true);
  if (local != null) return line(local);
  final fromStatus = _idleErrorText(status.error, web, fromStart: false);
  if (fromStatus != null) return line(fromStatus);
  if (support == core.AudioSupport.permissionDenied ||
      support == core.AudioSupport.permissionPermanentlyDenied) {
    return line(
      web ? MediaStringsKo.permissionWeb : MediaStringsKo.permissionNative,
    );
  }
  return line(MediaStringsKo.consent);
}

String? _idleErrorText(Object? error, bool web, {required bool fromStart}) {
  if (error == null) return null;
  return switch (mediaErrorCodeOf(error)) {
    MediaErrorCode.permissionDenied =>
      web ? MediaStringsKo.permissionWeb : MediaStringsKo.permissionNative,
    MediaErrorCode.microphoneNotFound => MediaStringsKo.microphoneNotFound,
    MediaErrorCode.microphoneBusy => MediaStringsKo.microphoneBusy,
    MediaErrorCode.draftLost => MediaStringsKo.draftLost,
    MediaErrorCode.saveFailed => MediaStringsKo.saveFailed,
    // a failed start vs. an engine that died while recording (the draft stays for recovery)
    MediaErrorCode.engineFailed =>
      fromStart ? MediaStringsKo.microphoneNotFound : MediaStringsKo.saveFailed,
    MediaErrorCode.storageFailed || MediaErrorCode.storageBacklog => null,
    // UnsupportedError from start(): checkSupport changed in between
    null when error is UnsupportedError =>
      web ? MediaStringsKo.unsupportedWeb : MediaStringsKo.unsupportedDevice,
    // stop() failures that are not MediaIoException (CORE fakes rethrow the store error)
    _ => fromStart ? null : MediaStringsKo.saveFailed,
  };
}

/// The recording row: buttons for [mode], the clock and the close button.
class RecordControls extends StatelessWidget {
  const RecordControls({
    super.key,
    required this.mode,
    required this.activeMs,
    required this.onRecord,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onClose,
  });

  final RecordRowMode mode;
  final int activeMs;
  final VoidCallback onRecord, onPause, onResume, onStop, onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final children = <Widget>[];
    void gap() => children.add(const SizedBox(width: 8));

    Widget recordButton({required bool enabled}) => Semantics(
      label: MediaStringsKo.recordSemantics,
      excludeSemantics: true,
      button: true,
      enabled: enabled,
      child: FilledButton.icon(
        onPressed: enabled ? onRecord : null,
        icon: const Icon(Icons.fiber_manual_record),
        label: const Text(MediaStringsKo.record),
      ),
    );
    Widget stopButton(String label) => OutlinedButton.icon(
      onPressed: onStop,
      icon: const Icon(Icons.stop),
      label: Text(label),
    );

    switch (mode) {
      case RecordRowMode.unsupported:
        children.add(recordButton(enabled: false));
      case RecordRowMode.idle:
        children.add(recordButton(enabled: true));
      case RecordRowMode.busy:
        children.add(
          const SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        );
      case RecordRowMode.recording:
        children.add(
          OutlinedButton.icon(
            onPressed: onPause,
            icon: const Icon(Icons.pause),
            label: const Text(MediaStringsKo.pause),
          ),
        );
        gap();
        children.add(stopButton(MediaStringsKo.stop));
      case RecordRowMode.pausedResumable:
        children.add(
          OutlinedButton.icon(
            onPressed: onResume,
            icon: const Icon(Icons.play_arrow),
            label: const Text(MediaStringsKo.resume),
          ),
        );
        gap();
        children.add(stopButton(MediaStringsKo.stop));
      case RecordRowMode.pausedStopOnly:
        children.add(stopButton(MediaStringsKo.stop));
      case RecordRowMode.otherNote:
        children.add(recordButton(enabled: false));
        gap();
        children.add(stopButton(MediaStringsKo.stopOther));
    }
    final showsClock =
        mode == RecordRowMode.recording ||
        mode == RecordRowMode.pausedResumable ||
        mode == RecordRowMode.pausedStopOnly;
    if (showsClock) {
      children
        ..add(const SizedBox(width: 16))
        ..add(
          Text(
            formatClock(activeMs),
            style: theme.textTheme.titleMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
      if (mode == RecordRowMode.recording) {
        children
          ..add(const SizedBox(width: 12))
          ..add(Icon(Icons.circle, size: 12, color: scheme.error))
          ..add(const SizedBox(width: 4))
          ..add(
            Text(
              MediaStringsKo.recordingNow,
              style: theme.textTheme.bodyMedium,
            ),
          );
      }
    }
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: children),
          ),
        ),
        IconButton(
          tooltip: MediaStringsKo.close,
          icon: const Icon(Icons.close),
          onPressed: onClose,
        ),
      ],
    );
  }
}

/// The status line under the recording row; empty when [line] has no text.
class StatusLine extends StatelessWidget {
  const StatusLine({super.key, required this.line, required this.onResume});

  final PanelStatusLine line;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final text = line.text;
    if (text == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (line.action == StatusLineAction.resumeRecording)
          TextButton(
            onPressed: onResume,
            child: const Text(MediaStringsKo.resumeRecording),
          ),
      ],
    );
  }
}
