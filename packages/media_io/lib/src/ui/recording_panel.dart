// lib/src/ui/recording_panel.dart — RecordingPanel (contract 7.2.12, m5-7/06-pdf 4.2.5, 6.13).
//
// The public widget is the contract's ConsumerWidget; its state lives in the internal
// _RecordingPanelBody (4.2.5). It reads the CORE ports only (audioRecorderServiceProvider,
// audioPlaybackServiceProvider, noteRecordingsProvider, idGeneratorProvider,
// settingsRepositoryProvider) — no EDITOR type (INFRA adapts EditorPanelContext, X29).
//
// T36a: the recording row, the status line (6.13.2), the playback row, '열 때·정지 뒤 열기만'
// (PDF-M8 — open(), never seekMs / play), the tap-to-seek toggle and the narrow layout. T36b
// adds the recordings list, the name / delete sheets, the sizes, the badge and the stuck-draft
// row in the space under the divider.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../errors.dart';
import '../providers.dart';
import 'playback_bar.dart';
import 'record_controls.dart';
import 'sheets.dart';

/// Below this width the playback row puts speed and tap-to-seek on a second line (6.13.1).
const double recordingPanelNarrowWidth = 600;

/// Recording + playback panel for EditorExtensions.recordingPanel (INFRA adapts EditorPanelContext).
/// Record / pause / stop, recordings list (rename, delete, size), play / pause, ±10 s, speed
/// 0.5–2.0, scrubber, tap-to-seek toggle, consent notice on first record (F-16), web hidden-tab notice,
/// '복구된 녹음' badge on recordings made by recoverDraft().
class RecordingPanel extends ConsumerWidget {
  const RecordingPanel({
    super.key,
    required this.noteId,
    required this.tapToSeek,
    required this.onTapToSeekChanged,
    required this.onClose,
  });
  final String noteId;
  final ValueListenable<bool> tapToSeek;
  final ValueChanged<bool> onTapToSeekChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _RecordingPanelBody(panel: this);
}

class _RecordingPanelBody extends ConsumerStatefulWidget {
  const _RecordingPanelBody({required this.panel});
  final RecordingPanel panel;

  @override
  ConsumerState<_RecordingPanelBody> createState() =>
      _RecordingPanelBodyState();
}

class _RecordingPanelBodyState extends ConsumerState<_RecordingPanelBody> {
  core.AudioSupport? _support;
  Object? _localError;
  bool _openChecked = false;
  bool _acting = false;

  String get _noteId => widget.panel.noteId;
  core.AudioRecorderService get _recorder =>
      ref.read(core.audioRecorderServiceProvider);
  core.AudioPlaybackService get _playback =>
      ref.read(core.audioPlaybackServiceProvider);

  @override
  void initState() {
    super.initState();
    _checkSupport();
  }

  Future<void> _checkSupport() async {
    try {
      final support = await _recorder.checkSupport();
      if (mounted) setState(() => _support = support);
    } on Object catch (e, s) {
      _report(e, s, 'checkSupport');
    }
  }

  /// 6.13.3 '열 때': once per panel, when the list first arrives — open (never play / seek) the
  /// most recent recording unless the player already holds one of this note's or the recorder
  /// is active.
  void _openLatestOnce(List<core.Recording> recordings) {
    if (_openChecked) return;
    _openChecked = true;
    if (recordings.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_recorder.status.phase != core.RecorderPhase.idle) return;
      final open = _playback.status.recordingId;
      if (open != null && recordings.any((r) => r.id == open)) return;
      final latest = recordings.reduce(
        (a, b) => b.startedAt >= a.startedAt ? b : a,
      );
      try {
        await _playback.open(latest);
      } on Object catch (e, s) {
        _report(e, s, 'open');
      }
    });
  }

  Future<void> _act(Future<void> Function() body) async {
    if (_acting) return;
    _acting = true;
    try {
      await body();
    } finally {
      _acting = false;
    }
  }

  /// 6.13.3 '녹음 시작' ① consent ② checkSupport(requestPermission) ③ pause playback ④ id → start.
  Future<void> _record() => _act(() async {
    setState(() => _localError = null);
    final settings = ref.read(core.settingsRepositoryProvider);
    var shown = false;
    try {
      shown = await settings.get(MediaSettingKeys.consentShown);
    } on Object catch (e, s) {
      _report(e, s, 'consent read');
    }
    if (!shown) {
      if (!mounted) return;
      if (!await showConsentSheet(context)) return;
      try {
        await settings.set(MediaSettingKeys.consentShown, true);
      } on Object catch (e, s) {
        _report(e, s, 'consent write');
      }
    }
    if (!mounted) return;
    final recorder = _recorder;
    final support = await recorder.checkSupport(requestPermission: true);
    if (!mounted) return;
    setState(() => _support = support);
    if (support != core.AudioSupport.supported) return;
    final playback = _playback;
    if (playback.status.phase == core.PlaybackPhase.playing) {
      await playback.pause();
    }
    final id = ref.read(core.idGeneratorProvider).newId();
    try {
      await recorder.start(recordingId: id, noteId: _noteId);
    } on Object catch (e, s) {
      if (e is! MediaIoException &&
          e is! StateError &&
          e is! UnsupportedError) {
        _report(e, s, 'start');
      }
      if (mounted) setState(() => _localError = e);
    }
  });

  /// 6.13.3 '정지': stop → open the new recording (no play / seek — R-5 v2.1, PDF-M8).
  Future<void> _stop() => _act(() async {
    setState(() => _localError = null);
    try {
      final recording = await _recorder.stop();
      if (recording != null && recording.noteId == _noteId) {
        await _playback.open(recording);
      }
    } on Object catch (e, s) {
      if (e is! MediaIoException) _report(e, s, 'stop');
      if (mounted) {
        setState(
          () => _localError = e is MediaIoException
              ? e
              : MediaIoException(MediaErrorCode.saveFailed, cause: e),
        );
      }
    }
  });

  Future<void> _pause() => _act(() => _recorder.pause());
  Future<void> _resume() => _act(() => _recorder.resume());

  void _report(Object e, StackTrace s, String what) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: e,
        stack: s,
        library: 'media_io',
        context: ErrorDescription('recording panel: $what'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recorder = ref.watch(core.audioRecorderServiceProvider);
    final playback = ref.watch(core.audioPlaybackServiceProvider);
    final rec = ref.watch(recorderStatusProvider).value ?? recorder.status;
    final play = ref.watch(playbackStatusProvider).value ?? playback.status;
    final recordings = ref.watch(core.noteRecordingsProvider(_noteId)).value;
    if (recordings != null) _openLatestOnce(recordings);

    final mode = recordRowMode(rec, _noteId, _support);
    final line = statusLineFor(
      status: rec,
      noteId: _noteId,
      support: _support,
      localError: _localError,
      web: kIsWeb,
    );
    final openId = play.recordingId;
    final showsPlayback =
        openId != null && (recordings?.any((r) => r.id == openId) ?? false);
    final recorderActive = rec.phase != core.RecorderPhase.idle;
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: LayoutBuilder(
        builder: (context, constraints) => Padding(
          padding: const EdgeInsetsDirectional.only(start: 12, end: 4, top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RecordControls(
                mode: mode,
                activeMs: rec.activeMs,
                onRecord: _record,
                onPause: _pause,
                onResume: _resume,
                onStop: _stop,
                onClose: widget.panel.onClose,
              ),
              StatusLine(line: line, onResume: _resume),
              if (showsPlayback)
                PlaybackBar(
                  playback: playback,
                  status: play,
                  recorderActive: recorderActive,
                  tapToSeek: widget.panel.tapToSeek,
                  onTapToSeekChanged: widget.panel.onTapToSeekChanged,
                  narrow: constraints.maxWidth < recordingPanelNarrowWidth,
                ),
              const Divider(height: 1),
              // T36b: the recordings list (scrolls inside the EDITOR slot — 4.2.5)
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
  }
}
