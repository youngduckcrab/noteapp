// lib/src/playback/playback_highlighter.dart — m5-7/04-editor 6.15.2
// (contract 7.2.4 R-4, R-5 (v2.1); I-9) — E2-17.
//
// The decision (PlaybackHighlightLogic — pure, output injected) and its
// driver (PlaybackHighlightDriver — a widget with a Ticker in EditorBody).
// INK computes the emphasis from the focus; the editor only hands over the
// position (R-4).
//
// Active rule (R-5 (v2.1), PDF review M-8): a recording of this note gets a
// focus only after it has been playing at least once since it was opened, or
// a seek happened (tap-to-seek calls markSeek; the media panel's seek bar
// shows up as positionMs() != the position at open). Before that (`loading`
// / `ready` — the panel's or the recorder's automatic open) the output is
// null, so writing right after a recording stops is not dimmed.
import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../document/mounted_pages.dart';
import '../scope/editor_scope.dart';
import '../state/panel.dart';
import '../state/settings/editor_settings_notifier.dart';

typedef PlaybackFocusSink = void Function(ink.InkPlaybackFocus? focus);

/// Pure decision (no widgets, no Ticker) — unit/playback_highlight_logic_test.dart.
final class PlaybackHighlightLogic {
  PlaybackHighlightLogic({
    required this.output,
    required this._noteRecordingIds,
    required this._style,
  });

  final PlaybackFocusSink
  output; // widget: every mounted controller (I-9); tests: a recorder
  final Set<String> Function() _noteRecordingIds;
  final ink.InkPlaybackStyle Function() _style;

  /// The open recording of this note (null: none, another note's, idle, failed).
  String? _openId;

  /// The position seen at the open (the first status after `loading`);
  /// null until then.
  int? _openPositionMs;
  bool _active = false;
  core.PlaybackPhase _phase = core.PlaybackPhase.idle;
  ink.InkPlaybackFocus? _current;

  /// The last output.
  ink.InkPlaybackFocus? get current => _current;

  /// A recording of this note is open and not active yet: the driver polls
  /// positionMs() every 250 ms while the panel is open (a seek from the
  /// panel may send no status event).
  bool get awaitingActivation => _openId != null && !_active;

  /// Status event. Tracks the open recording and whether it is ACTIVE (R-5 v2.1): since it was
  /// opened it has been playing at least once, or a seek happened (EDITOR's own tap-to-seek calls
  /// markSeek; a seek from the media panel shows up as positionMs != the value at open).
  /// Returns true when the Ticker should run (phase playing and active).
  bool onStatus(core.PlaybackStatus status, {required int positionMs}) {
    final id = status.recordingId;
    final phase = status.phase;
    _phase = phase;
    if (id == null ||
        phase == core.PlaybackPhase.idle ||
        phase == core.PlaybackPhase.failed ||
        !_noteRecordingIds().contains(id)) {
      _openId = null;
      _openPositionMs = null;
      _active = false;
      _emit(null);
      return false;
    }
    if (id != _openId) {
      // Another recording (or the first one): not active again.
      _openId = id;
      _openPositionMs = null;
      _active = false;
    }
    if (phase != core.PlaybackPhase.loading) {
      final atOpen = _openPositionMs;
      if (atOpen == null) {
        _openPositionMs = positionMs;
      } else if (positionMs != atOpen) {
        _active = true; // a seek from outside the editor
      }
    }
    if (phase == core.PlaybackPhase.playing) _active = true;
    if (!_active) {
      _emit(null);
      return false;
    }
    switch (phase) {
      case core.PlaybackPhase.playing:
        _emit(_focus(id, positionMs));
        return true;
      case core.PlaybackPhase.ready ||
          core.PlaybackPhase.paused ||
          core.PlaybackPhase.completed:
        // The emphasis stays (paused, after a seek).
        _emit(_focus(id, positionMs));
        return false;
      case core.PlaybackPhase.loading ||
          core.PlaybackPhase.idle ||
          core.PlaybackPhase.failed:
        return false; // loading: as it is
    }
  }

  /// same position as last time → no output
  void onTick(int positionMs) {
    final id = _openId;
    if (id == null || !_active || _phase != core.PlaybackPhase.playing) {
      return;
    }
    if (_current?.positionMs == positionMs) return;
    _emit(_focus(id, positionMs));
  }

  /// called by tap-to-seek right after seekMs
  void markSeek() {
    if (_openId != null) _active = true;
  }

  ink.InkPlaybackFocus _focus(String id, int positionMs) =>
      ink.InkPlaybackFocus(
        recordingId: id,
        positionMs: positionMs,
        style: _style(),
      );

  void _emit(ink.InkPlaybackFocus? focus) {
    if (focus == _current) return;
    _current = focus;
    output(focus);
  }
}

/// The ids of this note's recordings (core.noteRecordingsProvider); empty
/// until they load. Kept alive by PlaybackHighlightDriver, read synchronously
/// by tap-to-seek and the logic.
final editorNoteRecordingIdsProvider = Provider<Set<String>>(
  (ref) {
    final noteId = ref.watch(editorNoteIdProvider);
    final recordings = ref.watch(core.noteRecordingsProvider(noteId)).value;
    return {for (final r in recordings ?? const <core.Recording>[]) r.id};
  },
  dependencies: [editorNoteIdProvider],
  name: 'editorNoteRecordingIdsProvider',
);

/// The player's status events for the highlight driver (tap-to-seek reads the
/// service's `status` getter synchronously instead — 6.3.5).
final editorPlaybackStatusProvider = StreamProvider<core.PlaybackStatus>(
  (ref) {
    ref.watch(editorNoteIdProvider);
    return ref.watch(core.audioPlaybackServiceProvider).statusStream;
  },
  dependencies: [editorNoteIdProvider],
  name: 'editorPlaybackStatusProvider',
);

/// The note's highlight logic: the driver and tap-to-seek (markSeek) share it.
/// Output = setPlaybackFocus on every mounted page controller (I-9); a page
/// mounted later gets `current` with its first content (PageMount).
final editorPlaybackHighlightProvider = Provider<PlaybackHighlightLogic>(
  (ref) {
    final MountedPages pages = ref.watch(editorMountedPagesProvider);
    return PlaybackHighlightLogic(
      output: (focus) {
        for (final mount in pages.all) {
          if (!mount.isDisposed) mount.controller.setPlaybackFocus(focus);
        }
      },
      noteRecordingIds: () => ref.read(editorNoteRecordingIdsProvider),
      style: () => ref.read(editorSettingsProvider).playbackHighlight,
    );
  },
  dependencies: [editorMountedPagesProvider, editorNoteRecordingIdsProvider],
  name: 'editorPlaybackHighlightProvider',
);

/// How often the driver compares positionMs() while a recording of this note
/// is open but not active and the panel is open (a seek from the panel).
const Duration kPlaybackActivationPoll = Duration(milliseconds: 250);

/// Listens to the player's status, runs the Ticker while playing (one
/// onTick(positionMs()) per frame), stops it when the app is hidden (media
/// may keep playing; it starts again when shown).
class PlaybackHighlightDriver extends ConsumerStatefulWidget {
  const PlaybackHighlightDriver({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PlaybackHighlightDriver> createState() =>
      _PlaybackHighlightDriverState();
}

class _PlaybackHighlightDriverState
    extends ConsumerState<PlaybackHighlightDriver>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final AppLifecycleListener _lifecycle;
  Timer? _poll;
  bool _shouldTick = false;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _lifecycle = AppLifecycleListener(onHide: _onHide, onShow: _onShow);
  }

  PlaybackHighlightLogic get _logic =>
      ref.read(editorPlaybackHighlightProvider);

  core.AudioPlaybackService get _playback =>
      ref.read(core.audioPlaybackServiceProvider);

  void _onTick(Duration _) {
    if (!mounted) return;
    _logic.onTick(_playback.positionMs());
  }

  /// A status event, a recording list / style / panel change or a poll:
  /// the logic decides from the service's current status and position.
  void _update() {
    if (!mounted) return;
    final playback = _playback;
    _shouldTick = _logic.onStatus(
      playback.status,
      positionMs: playback.positionMs(),
    );
    _applyTicker();
    _applyPoll();
  }

  void _applyTicker() {
    final run = _shouldTick && !_hidden;
    if (run && !_ticker.isActive) {
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _applyPoll() {
    final poll = _logic.awaitingActivation && ref.read(editorPanelProvider);
    if (poll && _poll == null) {
      _poll = Timer.periodic(kPlaybackActivationPoll, (_) => _update());
    } else if (!poll) {
      _poll?.cancel();
      _poll = null;
    }
  }

  void _onHide() {
    _hidden = true;
    _applyTicker();
  }

  void _onShow() {
    _hidden = false;
    _update();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _lifecycle.dispose();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(editorPlaybackStatusProvider, (_, _) => _update());
    ref.listen(editorNoteRecordingIdsProvider, (_, _) => _update());
    ref.listen(
      editorSettingsProvider.select((s) => s.playbackHighlight),
      (_, _) => _update(),
    );
    ref.listen(editorPanelProvider, (_, _) => _applyPoll());
    return widget.child;
  }
}
