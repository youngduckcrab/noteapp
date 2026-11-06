// lib/src/init.dart — initializeMediaIo, MediaIoRuntime (internal), mediaIoOverrides
// (contract 7.2.12, m5-7/06-pdf 4.2.1, 4.2.2 — PDF T37).
//
// initializeMediaIo keeps the first config and runs the platform's recording step once
// (preparePlatformRecording — Android FlutterForegroundTask.init, the web MIME table; nothing on
// other platforms), never throwing. The orphan native recording files are removed by the first
// pendingDrafts() after start-up (INFRA MediaModule's idle recovery — 6.9.5), not here.
// mediaIoOverrides() returns exactly the two audio overrides (4.2.2): the services read
// core.noteStoreProvider / clockProvider / remoteAssetFetcherProvider on first use, so a container
// without a store can read both providers; both share one stop → player hand-off (P-B, 6.6.5 ③).
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:note_core/note_core.dart' as core;

import 'config.dart';
import 'platform/web_locks_factory.dart';
import 'playback/handoff_blob.dart';
import 'playback/playback_service.dart';
import 'playback/player_port.dart';
import 'record/recorder_engine_factory.dart';
import 'record/recorder_service.dart';
import 'record/recording_output.dart';

/// Process-wide state behind initializeMediaIo (internal, not exported).
abstract final class MediaIoRuntime {
  static MediaIoConfig? _config;

  /// The config given to the first initializeMediaIo; the default config before that.
  static MediaIoConfig get config => _config ?? const MediaIoConfig();

  /// Whether initializeMediaIo has run.
  static bool get isInitialized => _config != null;

  /// Tests only: forget the config.
  @visibleForTesting
  static void debugReset() => _config = null;
}

/// Idempotent and web-safe; completes within 10 ms and never throws, even when the platform
/// has no recorder or picker (missing features show as checkSupport() == unsupported and an
/// empty supportedImageSources() — 06-pdf 4.2.1). No network, no permission request. The
/// first call's [config] stays (MediaIoRuntime.config); a later call with a different config
/// asserts in debug builds and is ignored.
///
/// (T37) The first call also prepares the platform's recording (Android: the foreground
/// service options; web: the MIME candidate table — 6.8.1).
Future<void> initializeMediaIo({
  MediaIoConfig config = const MediaIoConfig(),
}) async {
  if (MediaIoRuntime._config case final first?) {
    assert(
      first == config,
      'initializeMediaIo was called again with a different MediaIoConfig; the first one '
      'stays in effect.',
    );
    return;
  }
  MediaIoRuntime._config = config;
  try {
    preparePlatformRecording(config);
  } on Object {
    // a missing platform feature shows as checkSupport() == unsupported later
  }
}

/// The stop path's Blob for the next open (P-B, 6.6.5 ③), shared by the two services of a
/// container.
final _playbackHandoffProvider = Provider<PlaybackHandoff>(
  (ref) => PlaybackHandoff(),
  name: 'mediaPlaybackHandoffProvider',
);

/// Overrides core.audioRecorderServiceProvider and core.audioPlaybackServiceProvider.
///
/// (06-pdf 4.2.2) Exactly these two, built with config ?? MediaIoRuntime.config; the services
/// read core.noteStoreProvider / clockProvider / remoteAssetFetcherProvider on first use, so
/// reading the two providers in a container without a store never throws.
List<Override> mediaIoOverrides({MediaIoConfig? config}) {
  final effective = config ?? MediaIoRuntime.config;
  return [
    core.audioRecorderServiceProvider.overrideWith((ref) {
      final service = MediaRecorderService(
        stores: () => RecorderStores.of(ref.read(core.noteStoreProvider)),
        now: () => ref.read(core.clockProvider).now(),
        config: effective,
        engine: createPlatformRecorderEngine(effective),
        locks: createPlatformWebLocks(),
        handoff: ref.read(_playbackHandoffProvider),
      );
      ref.onDispose(service.dispose);
      return service;
    }),
    core.audioPlaybackServiceProvider.overrideWith((ref) {
      final playback = JustAudioPlaybackService(
        assets: () => ref.read(core.noteStoreProvider).assets,
        settings: () => ref.read(core.noteStoreProvider).settings,
        fetcher: () => ref.read(core.remoteAssetFetcherProvider),
        recorderActive: () =>
            ref.read(core.audioRecorderServiceProvider).status.phase !=
            core.RecorderPhase.idle,
        player: () => JustAudioPlayerPort(
          beforeFirstLoad: platformPlaybackSessionSetup(),
        ),
        handoff: ref.read(_playbackHandoffProvider),
      );
      ref.onDispose(playback.dispose);
      return playback;
    }),
  ];
}
