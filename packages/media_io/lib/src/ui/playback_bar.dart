// lib/src/ui/playback_bar.dart — the playback row of the panel (m5-7/06-pdf 6.13.1, 6.13.3).
// Internal.
//
// ±10 s (MediaTuning.seekStepMs), play / pause, a scrubber that only moves its thumb while
// dragged and seeks on release, 'pos / length', the speed button (six steps in a cycle —
// MediaTuning.playbackSpeeds) and the tap-to-seek toggle (EDITOR owns the value). The position
// text follows positionMs() every 200 ms from a Ticker while playing. Narrow (< 600 px): speed
// and tap-to-seek go to a second line.
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../errors.dart';
import '../tuning.dart';
import 'format.dart';
import 'strings_ko.dart';

/// Position text refresh while playing (6.13.3 '200 ms마다').
const Duration playbackPositionRefresh = Duration(milliseconds: 200);

/// The next speed of the 6-step cycle (0.5 → … → 2.0 → 0.5); an off-list speed goes to the next
/// larger step.
double nextPlaybackSpeed(double current) {
  const steps = MediaTuning.playbackSpeeds;
  for (final s in steps) {
    if (s > current + 1e-6) return s;
  }
  return steps.first;
}

class PlaybackBar extends StatefulWidget {
  const PlaybackBar({
    super.key,
    required this.playback,
    required this.status,
    required this.recorderActive,
    required this.tapToSeek,
    required this.onTapToSeekChanged,
    required this.narrow,
  });

  final core.AudioPlaybackService playback;
  final core.PlaybackStatus status;

  /// The recorder is active (any note): playback is disabled (contract CP-PDF-10 — play() is a
  /// no-op then).
  final bool recorderActive;
  final ValueListenable<bool> tapToSeek;
  final ValueChanged<bool> onTapToSeekChanged;
  final bool narrow;

  @override
  State<PlaybackBar> createState() => _PlaybackBarState();
}

class _PlaybackBarState extends State<PlaybackBar>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  Duration _lastTick = Duration.zero;
  int _positionMs = 0;
  double? _dragMs;

  @override
  void initState() {
    super.initState();
    _positionMs = widget.playback.positionMs();
    _syncTicker();
  }

  @override
  void didUpdateWidget(PlaybackBar old) {
    super.didUpdateWidget(old);
    _positionMs = widget.playback.positionMs();
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _syncTicker() {
    final playing = widget.status.phase == core.PlaybackPhase.playing;
    if (playing && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    } else if (!playing && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    if (elapsed - _lastTick < playbackPositionRefresh) return;
    _lastTick = elapsed;
    final p = widget.playback.positionMs();
    if (p != _positionMs) setState(() => _positionMs = p);
  }

  Future<void> _seek(int ms) async {
    await widget.playback.seekMs(ms);
    if (mounted) setState(() => _positionMs = widget.playback.positionMs());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = widget.status;
    final duration = status.durationMs;
    final playing = status.phase == core.PlaybackPhase.playing;
    final usable =
        !widget.recorderActive &&
        switch (status.phase) {
          core.PlaybackPhase.ready ||
          core.PlaybackPhase.playing ||
          core.PlaybackPhase.paused ||
          core.PlaybackPhase.completed => true,
          _ => false,
        };
    final failed = status.phase == core.PlaybackPhase.failed;
    final shownMs = (_dragMs?.round() ?? _positionMs).clamp(0, duration);

    final playButton = IconButton(
      tooltip: widget.recorderActive
          ? MediaStringsKo.noPlayWhileRecording
          : playing
          ? MediaStringsKo.pausePlayback
          : MediaStringsKo.play,
      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
      onPressed: !usable
          ? null
          : () => playing ? widget.playback.pause() : widget.playback.play(),
    );
    final controls = <Widget>[
      IconButton(
        tooltip: MediaStringsKo.back10,
        icon: const Icon(Icons.replay_10),
        onPressed: usable
            ? () => _seek(_positionMs - MediaTuning.seekStepMs)
            : null,
      ),
      playButton,
      IconButton(
        tooltip: MediaStringsKo.forward10,
        icon: const Icon(Icons.forward_10),
        onPressed: usable
            ? () => _seek(_positionMs + MediaTuning.seekStepMs)
            : null,
      ),
    ];
    final Widget middle = failed
        ? Text(
            status.unsupportedFormat ||
                    mediaErrorCodeOfStatus(status) !=
                        MediaErrorCode.assetMissing
                ? MediaStringsKo.cannotPlay
                : MediaStringsKo.assetMissing,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          )
        : Semantics(
            label: MediaStringsKo.position,
            child: Slider(
              value: shownMs.toDouble(),
              max: duration <= 0 ? 1 : duration.toDouble(),
              onChanged: usable && duration > 0
                  ? (v) => setState(() => _dragMs = v)
                  : null,
              onChangeEnd: usable && duration > 0
                  ? (v) {
                      _dragMs = null;
                      _seek(v.round());
                    }
                  : null,
            ),
          );
    final time = Text(
      '${formatClock(shownMs)} / ${formatClock(duration)}',
      style: theme.textTheme.bodyMedium?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    final extras = <Widget>[
      Tooltip(
        message: MediaStringsKo.speed,
        child: TextButton(
          onPressed: usable
              ? () => widget.playback.setSpeed(nextPlaybackSpeed(status.speed))
              : null,
          style: TextButton.styleFrom(minimumSize: const Size(56, 48)),
          child: Text(MediaStringsKo.speedLabel(status.speed)),
        ),
      ),
      ValueListenableBuilder<bool>(
        valueListenable: widget.tapToSeek,
        builder: (context, on, _) => IconButton(
          tooltip: MediaStringsKo.tapToSeek,
          isSelected: on,
          icon: const Icon(Icons.touch_app_outlined),
          selectedIcon: const Icon(Icons.touch_app),
          onPressed: () => widget.onTapToSeekChanged(!on),
        ),
      ),
    ];
    final mainRow = Row(
      children: [
        ...controls,
        Expanded(child: middle),
        time,
        if (!widget.narrow) ...[const SizedBox(width: 8), ...extras],
      ],
    );
    if (!widget.narrow) return mainRow;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        mainRow,
        Row(mainAxisAlignment: MainAxisAlignment.end, children: extras),
      ],
    );
  }
}

MediaErrorCode? mediaErrorCodeOfStatus(core.PlaybackStatus status) {
  final e = status.error;
  return e is MediaIoException ? e.code : null;
}
