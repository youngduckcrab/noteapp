// lib/src/providers.dart — media_io internals (m5-7/06-pdf 4.4, 4.6). Not exported.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart' as core;

import 'platform/file_download.dart';
import 'platform/file_download_factory.dart';
import 'record/recover_attempts.dart';
import 'tuning.dart';
import 'ui/strings_ko.dart';

/// The media.* setting keys (contract 7.4.4 prefix, 06-pdf 4.6).
abstract final class MediaSettingKeys {
  /// The recording consent notice was shown on this device (7.4.4: device).
  static final core.SettingKey<bool> consentShown = core.SettingKey.boolean(
    'media.consentShown',
    false,
    scope: core.SettingScope.device,
  );

  /// Last playback speed (applied on the next open).
  static final core.SettingKey<double> playbackSpeed = core.SettingKey.number(
    'media.playbackSpeed',
    1.0,
    scope: core.SettingScope.device,
  );

  /// (v2.1) Recovery attempts per draft {draftId: n} (6.10.3).
  static final core.SettingKey<Map<String, Object?>> recoverAttempts =
      core.SettingKey.jsonMap(
        'media.recoverAttempts',
        scope: core.SettingScope.device,
      );

  /// Recording bit rate (bps); 0 = not set → MediaIoConfig.bitRate (4.6).
  static final core.SettingKey<int> bitRate = core.SettingKey.integer(
    'media.bitRate',
    0,
  );
}

/// (T36a) The recorder status as a stream (statusStream emits the current value on listen).
final recorderStatusProvider = StreamProvider.autoDispose<core.RecorderStatus>(
  (ref) => ref.watch(core.audioRecorderServiceProvider).statusStream,
  name: 'recorderStatusProvider',
);

/// (T36a) The playback status as a stream.
final playbackStatusProvider = StreamProvider.autoDispose<core.PlaybackStatus>(
  (ref) => ref.watch(core.audioPlaybackServiceProvider).statusStream,
  name: 'playbackStatusProvider',
);

/// No automatic retry (a failed read shows as an empty list until the next refresh).
Duration? _noRetry(int retryCount, Object error) => null;

/// (T36b) The web '파일로 내려받기' port (6.10.4) — (T32b) the platform's: Blob + `<a download>` on
/// the web, NoFileDownloads elsewhere; tests override it with a fake.
final fileDownloadsProvider = Provider<FileDownloads>(
  (ref) => createPlatformFileDownloads(),
  name: 'fileDownloadsProvider',
);

/// (T36b) One row of the recordings list: the recording, its display name ('녹음 N' by startedAt
/// order when untitled — 7.2.4) and its asset metadata (size / MIME even without local bytes).
typedef RecordingListRow = ({
  core.Recording recording,
  String name,
  bool recovered,
  int sizeBytes,
  String? mimeType,
});

/// (T36b) The list of [noteId] newest first + Σ Asset.size (audioBytesOf — 6.13.1).
final recordingListProvider = FutureProvider.autoDispose
    .family<({List<RecordingListRow> rows, int totalBytes}), core.NoteId>(
      (ref, noteId) async {
        final recordings = await ref.watch(
          core.noteRecordingsProvider(noteId).future,
        );
        final store = ref.read(core.noteStoreProvider);
        final names = recordingDisplayNames(recordings);
        final rows = <RecordingListRow>[];
        for (final r in recordings) {
          final asset = await store.assets.getAsset(r.assetId);
          rows.add((
            recording: r,
            name: names[r.id]!,
            recovered: r.title == MediaTuning.recoveredTitle,
            sizeBytes: asset?.size ?? 0,
            mimeType: asset?.mimeType,
          ));
        }
        rows.sort(
          (a, b) => b.recording.startedAt.compareTo(a.recording.startedAt),
        );
        final total = await store.recordings.audioBytesOf(noteId);
        return (
          rows: List<RecordingListRow>.unmodifiable(rows),
          totalBytes: total,
        );
      },
      retry: _noRetry,
      name: 'recordingListProvider',
    );

/// title, or '녹음 N' where N is the position by startedAt (then id) among all of [recordings]
/// (7.2.4 — the numbering counts titled recordings too, so a rename does not shift the others).
Map<core.RecordingId, String> recordingDisplayNames(
  List<core.Recording> recordings,
) {
  final ordered = [...recordings]
    ..sort((a, b) {
      final c = a.startedAt.compareTo(b.startedAt);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  return {
    for (final (i, r) in ordered.indexed)
      r.id: r.title ?? MediaStringsKo.defaultTitle(i + 1),
  };
}

/// (T36b) The drafts of [noteId] out of automatic recovery (attempts ≥ recoverMaxAttempts —
/// 6.10.3): read from the store and media.recoverAttempts directly, so the panel shows them with
/// any recorder (the CORE fake has no attempt rule). Refreshed by the panel after an action.
final stuckDraftsProvider = FutureProvider.autoDispose
    .family<List<core.RecordingDraft>, core.NoteId>(
      (ref, noteId) async {
        final store = ref.read(core.noteStoreProvider);
        final attempts = await RecoverAttempts(store.settings).read();
        if (attempts.isEmpty) return const [];
        final drafts = await store.recordingDrafts.listDrafts();
        return List.unmodifiable([
          for (final d in drafts)
            if (d.noteId == noteId &&
                RecoverAttempts.isStuck(attempts[d.draftId] ?? 0))
              d,
        ]);
      },
      retry: _noRetry,
      name: 'stuckDraftsProvider',
    );
