// lib/src/ui/recording_panel.dart — RecordingPanel (contract 7.2.12, m5-7/06-pdf 4.2.5, 6.13).
//
// The public widget is the contract's ConsumerWidget; its state lives in the internal
// _RecordingPanelBody (4.2.5). It reads the CORE ports only (audioRecorderServiceProvider,
// audioPlaybackServiceProvider, noteRecordingsProvider, idGeneratorProvider,
// settingsRepositoryProvider) — no EDITOR type (INFRA adapts EditorPanelContext, X29).
//
// T36a: the recording row, the status line (6.13.2), the playback row, '열 때·정지 뒤 열기만'
// (PDF-M8 — open(), never seekMs / play), the tap-to-seek toggle and the narrow layout. T36b:
// the recordings list under the divider (names, badge, sizes, total — tap = open only), the
// rename / delete sheets, the stuck-draft lines at the bottom ([다시 시도], [⋯] → web download ·
// 지우기) and the web download of a failed save (6.10.4).
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../errors.dart';
import '../providers.dart';
import '../record/recover_attempts.dart';
import 'draft_download.dart';
import 'playback_bar.dart';
import 'record_controls.dart';
import 'recording_list.dart';
import 'sheets.dart';
import 'strings_ko.dart';
import 'stuck_drafts_row.dart';

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

  /// The last recording of this note seen in the status (the draft of a failed save — 6.10.4).
  core.RecordingId? _lastRecordingId;

  /// Stuck drafts with an action running ([다시 시도] / [지우기]).
  final Set<String> _draftBusy = {};

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
    _lastRecordingId = _recorder.status.recordingId ?? _lastRecordingId;
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

  // ---- T36b: list, sheets, stuck drafts ------------------------------------------------------

  core.NoteStore get _store => ref.read(core.noteStoreProvider);

  Future<void> _open(core.Recording recording) async {
    try {
      await _playback.open(recording); // open only (PDF-M8)
    } on Object catch (e, s) {
      _report(e, s, 'open');
    }
  }

  /// [⋯] of a recording: rename (1–100 chars, empty = default name) or delete (confirm; the open
  /// recording is closed first).
  Future<void> _recordingActions(RecordingListRow row) async {
    final action = await showRecordingActionsSheet(context);
    if (!mounted || action == null) return;
    final recording = row.recording;
    switch (action) {
      case RecordingAction.rename:
        final result = await showRenameSheet(context, current: recording.title);
        if (result == null) return;
        try {
          await _store.recordings.renameRecording(recording.id, result.title);
        } on Object catch (e, s) {
          _report(e, s, 'rename');
        }
      case RecordingAction.delete:
        final ok = await showConfirmSheet(
          context,
          message: MediaStringsKo.deleteRecordingQuestion,
          confirm: MediaStringsKo.delete,
        );
        if (!ok) return;
        final playback = _playback;
        try {
          if (playback.status.recordingId == recording.id) {
            await playback.close();
          }
          await _store.recordings.deleteRecording(recording.id);
        } on Object catch (e, s) {
          _report(e, s, 'delete');
        }
    }
  }

  Future<void> _draftAction(
    core.RecordingDraft draft,
    Future<void> Function() body,
  ) async {
    if (!_draftBusy.add(draft.draftId)) return;
    setState(() {});
    try {
      await body();
    } finally {
      _draftBusy.remove(draft.draftId);
      if (mounted) {
        setState(() {});
        ref.invalidate(stuckDraftsProvider(_noteId));
      }
    }
  }

  /// [다시 시도] (6.10.3): attempts back to 0, then pendingDrafts() → recoverDraft() once.
  Future<void> _retryDraft(core.RecordingDraft draft) =>
      _draftAction(draft, () async {
        final store = _store;
        final recorder = _recorder;
        try {
          await RecoverAttempts(store.settings).reset(draft.draftId);
          final pending = await recorder.pendingDrafts();
          if (pending.any((d) => d.draftId == draft.draftId)) {
            await recorder.recoverDraft(draft.draftId);
          }
        } on Object catch (e, s) {
          _report(e, s, 'retry draft');
        }
      });

  /// [⋯] of a stuck draft: (web) the two-step download in the sheet, '지우기' (confirm → discard).
  Future<void> _draftMenu(core.RecordingDraft draft) async {
    final downloads = ref.read(fileDownloadsProvider);
    final store = _store;
    final discard = await showStuckDraftSheet(
      context,
      download: downloads.available
          ? DraftDownloadButton(
              prepare: () => prepareDraftDownload(store, downloads, draft),
              onError: (e, s) => _report(e, s, 'draft download'),
            )
          : null,
    );
    if (!mounted || !discard) return;
    final ok = await showConfirmSheet(
      context,
      message: MediaStringsKo.discardDraftQuestion,
      confirm: MediaStringsKo.discardDraft,
    );
    if (!ok) return;
    await _draftAction(draft, () async {
      try {
        await store.recordingDrafts.discard(draft.draftId);
        await RecoverAttempts(store.settings).clear(draft.draftId);
      } on Object catch (e, s) {
        _report(e, s, 'discard draft');
      }
    });
  }

  /// The web download of a failed save (6.10.4): the draft of [recordingId], if it is still there.
  Widget? _saveFailedDownload(core.RecordingId? recordingId) {
    final downloads = ref.read(fileDownloadsProvider);
    if (!downloads.available || recordingId == null) return null;
    final store = _store;
    return DraftDownloadButton(
      key: ValueKey('save-failed-$recordingId'),
      prepare: () async {
        final drafts = await store.recordingDrafts.listDrafts();
        for (final d in drafts) {
          if (d.recordingId == recordingId) {
            return prepareDraftDownload(store, downloads, d);
          }
        }
        return null;
      },
      onError: (e, s) => _report(e, s, 'save-failed download'),
    );
  }

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

    if (rec.recordingId != null && rec.noteId == _noteId) {
      _lastRecordingId = rec.recordingId;
    }
    final list = ref.watch(recordingListProvider(_noteId)).value;
    final stuck =
        ref.watch(stuckDraftsProvider(_noteId)).value ??
        const <core.RecordingDraft>[];
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
              StatusLine(
                line: line,
                onResume: _resume,
                trailing: line.text == MediaStringsKo.saveFailed
                    ? _saveFailedDownload(rec.recordingId ?? _lastRecordingId)
                    : null,
              ),
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
              // the recordings list scrolls inside the EDITOR slot (4.2.5)
              Expanded(
                child: RecordingList(
                  rows: list?.rows ?? const [],
                  totalBytes: list?.totalBytes ?? 0,
                  openId: showsPlayback ? openId : null,
                  canOpen: !recorderActive,
                  onOpen: _open,
                  onActions: _recordingActions,
                ),
              ),
              for (final draft in stuck)
                StuckDraftRow(
                  draft: draft,
                  busy: _draftBusy.contains(draft.draftId),
                  onRetry: () => _retryDraft(draft),
                  onMenu: () => _draftMenu(draft),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
