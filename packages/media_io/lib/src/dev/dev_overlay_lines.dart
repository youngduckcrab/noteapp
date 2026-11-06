// lib/src/dev/dev_overlay_lines.dart — mediaDevOverlayLinesProvider (contract 7.2.12,
// m5-7/06-pdf 6.14 — PDF T37).
//
// The lines (English abbreviations + numbers, for developers):
//   rec: recording 00:12.3 audio/webm;codecs=opus br=64k(config) bg=no intr=no [err=<code>]
//   enc: mp4a=no mp4=yes webm/opus=yes            (native: aacLc=yes — the engine's encoderNote)
//   last: audio/webm file=2040ms clock=2001ms diff=+39ms src=webm [clock diff > 150 ms]
//         [duration from clock] [duration patch skipped]
//   drafts: 1 (12 chunks, 96 KB) recovered=1 stuck=0 dropped=0 backlog=0 B unsaved=0 B locks=held
//   buf: peak=2 (172 MB) now=0
//   web: wakeLock=held watchdog=0 hidden-pauses=1 / native: config applied … (developerNote)
//   play: playing 1.5x 03:12.4/45:00.0 src=blob
// Only `rec:` and `play:` for recorders that are not media_io's (CORE's fakes / 'not supported').
// The provider listens to both status streams: each status rebuilds the lines; a new recorder
// phase also re-reads the drafts (store.recordingDrafts + media.recoverAttempts — skipped when
// the container has no store). Nothing here throws into the overlay.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart' as core;

import '../errors.dart';
import '../record/recorder_service.dart';
import '../record/recording_output.dart';
import '../tuning.dart';

/// Developer overlay lines: encoder support table, last recording MIME / duration / clock error (R-3).
final mediaDevOverlayLinesProvider = Provider<ValueListenable<List<String>>>((
  ref,
) {
  final lines = ValueNotifier<List<String>>(const []);
  ref.onDispose(lines.dispose);
  final source = MediaDevLineSource(
    recorder: ref.watch(core.audioRecorderServiceProvider),
    playback: ref.watch(core.audioPlaybackServiceProvider),
    onLines: (next) {
      if (!listEquals(next, lines.value)) lines.value = next;
    },
  )..start();
  ref.onDispose(source.dispose);
  return lines;
}, name: 'mediaDevOverlayLinesProvider');

typedef DraftsSummary = ({int count, int chunks, int bytes, int stuck});

/// Listens to the recorder and the player and hands fresh lines to [onLines].
final class MediaDevLineSource {
  MediaDevLineSource({
    required this.recorder,
    required this.playback,
    required this.onLines,
    this.web = kIsWeb,
  });

  final core.AudioRecorderService recorder;
  final core.AudioPlaybackService playback;
  final void Function(List<String> lines) onLines;
  final bool web;

  StreamSubscription<core.RecorderStatus>? _recorderSub;
  StreamSubscription<core.PlaybackStatus>? _playbackSub;
  core.RecorderPhase? _phase;
  DraftsSummary? _drafts;
  int _draftsGen = 0;
  bool _disposed = false;

  void start() {
    _recorderSub = recorder.statusStream.listen(
      _onRecorder,
      onError: (Object _) {},
    );
    _playbackSub = playback.statusStream.listen(
      (_) => _publish(),
      onError: (Object _) {},
    );
    _publish();
  }

  void _onRecorder(core.RecorderStatus status) {
    if (status.phase != _phase) {
      _phase = status.phase;
      unawaited(_refreshDrafts());
    }
    _publish();
  }

  Future<void> _refreshDrafts() async {
    final service = recorder;
    if (service is! MediaRecorderService) return;
    final gen = ++_draftsGen;
    DraftsSummary? summary;
    try {
      summary = await service.draftsSummary();
    } on Object {
      summary = null; // no store in this container, or the read failed
    }
    if (_disposed || gen != _draftsGen) return;
    _drafts = summary;
    _publish();
  }

  void _publish() {
    if (_disposed) return;
    List<String> next;
    try {
      next = mediaDevLines(
        recorder: recorder,
        playback: playback,
        drafts: _drafts,
        web: web,
      );
    } on Object catch (e) {
      next = ['media: lines failed (${e.runtimeType})'];
    }
    onLines(List.unmodifiable(next));
  }

  void dispose() {
    _disposed = true;
    // not awaited: a broadcast subscription's cancel future may belong to another zone
    unawaited(_recorderSub?.cancel());
    unawaited(_playbackSub?.cancel());
  }
}

/// The 6.14 lines for this moment.
List<String> mediaDevLines({
  required core.AudioRecorderService recorder,
  required core.AudioPlaybackService playback,
  DraftsSummary? drafts,
  bool web = kIsWeb,
}) {
  final status = recorder.status;
  final service = recorder is MediaRecorderService ? recorder : null;
  final lines = <String>[_recLine(status, service)];
  if (service != null) {
    final engine = service.engine;
    final d = service.diagnostics;
    if (engine.encoderNote case final enc?) lines.add('enc: $enc');
    if (d.lastRecording case final last?) lines.add(_lastLine(last));
    final w = service.devWriterState;
    final draftPart = drafts == null
        ? 'drafts: ?'
        : 'drafts: ${drafts.count} (${drafts.chunks} chunks, '
              '${formatDevBytes(drafts.bytes)})';
    lines.add(
      '$draftPart recovered=${d.recovered} stuck=${drafts?.stuck ?? '?'} '
      'dropped=${d.dropped} backlog=${formatDevBytes(w.backlogBytes)} '
      'unsaved=${formatDevBytes(w.unsavedBytes)} locks=${w.locks}',
    );
    final ledger = service.ledger;
    lines.add(
      'buf: peak=${ledger.peakCount} (${formatDevBytes(ledger.peakBytes)}) '
      'now=${ledger.count}',
    );
    if (engine.developerNote case final note?) {
      lines.add('${engine.writesDraftChunks ? 'web' : 'native'}: $note');
    }
  }
  lines.add(_playLine(playback, web: web));
  return lines;
}

String _recLine(core.RecorderStatus s, MediaRecorderService? service) {
  final b = StringBuffer('rec: ${s.phase.name}');
  if (s.phase != core.RecorderPhase.idle) {
    b.write(' ${formatDevClock(s.activeMs)} ${s.mimeType ?? '-'}');
  }
  if (service != null) {
    final d = service.diagnostics;
    final rate = d.lastBitRate ?? service.config.bitRate;
    final source = switch (d.lastBitRateSource) {
      BitRateSource.config => 'config',
      BitRateSource.setting => 'setting',
      BitRateSource.settingIgnored => 'config, setting ignored',
    };
    b.write(' br=${rate ~/ 1000}k($source)');
  }
  b.write(' bg=${_yn(s.backgroundCapable)} intr=${_yn(s.interrupted)}');
  if (s.error case final e?) {
    b.write(' err=${e is MediaIoException ? e.code.name : e.runtimeType}');
  }
  return b.toString();
}

String _lastLine(
  ({
    String mimeType,
    int durationMs,
    DurationSource source,
    int clockMs,
    bool patched,
  })
  last,
) {
  final diff = last.durationMs - last.clockMs;
  final b = StringBuffer(
    'last: ${last.mimeType} file=${last.durationMs}ms clock=${last.clockMs}ms '
    'diff=${diff >= 0 ? '+' : ''}${diff}ms src=${last.source.name}',
  );
  if (diff.abs() > MediaTuning.clockWarnErrorMs) {
    b.write(' clock diff > ${MediaTuning.clockWarnErrorMs} ms');
  }
  if (last.source == DurationSource.clock) b.write(' duration from clock');
  if (isWebmMime(last.mimeType) && !last.patched) {
    b.write(' duration patch skipped');
  }
  return b.toString();
}

String _playLine(core.AudioPlaybackService playback, {required bool web}) {
  final s = playback.status;
  if (s.phase == core.PlaybackPhase.idle) return 'play: idle';
  final position = playback.positionMs();
  return 'play: ${s.phase.name} ${formatDevSpeed(s.speed)}x ${formatDevClock(position)}/'
      '${formatDevClock(s.durationMs)} src=${web ? 'blob' : 'file'}';
}

String _yn(bool b) => b ? 'yes' : 'no';

/// 'mm:ss.d' (minutes past 59 keep counting: '125:00.0').
String formatDevClock(int ms) {
  final v = ms < 0 ? 0 : ms;
  final m = v ~/ 60000, s = v ~/ 1000 % 60, d = v % 1000 ~/ 100;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.$d';
}

/// '1.5', '1', '0.75' — the same text on the VM and the web (a JS number prints 1.0 as '1').
String formatDevSpeed(double speed) {
  var t = speed.toStringAsFixed(2);
  while (t.endsWith('0')) {
    t = t.substring(0, t.length - 1);
  }
  return t.endsWith('.') ? t.substring(0, t.length - 1) : t;
}

/// '0 B', '96 KB', '172 MB' (rounded).
String formatDevBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).round()} MB';
}
