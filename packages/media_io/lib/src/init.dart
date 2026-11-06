// lib/src/init.dart — initializeMediaIo, MediaIoRuntime (internal), mediaIoOverrides
// (contract 7.2.12, m5-7/06-pdf 4.2.1, 4.2.2).
//
// 2차 foundation step R2-B4 (T30, contract 7.6.2): initializeMediaIo keeps the first config
// and does nothing else; mediaIoOverrides() returns no override, so CORE's defaults
// (UnsupportedAudioRecorder / UnsupportedAudioPlayback — 'not supported') stay. From PDF T31
// it returns exactly the two audio overrides (4.2.2) and initializeMediaIo also prepares the
// platform (Android FlutterForegroundTask.init, the web MIME table — 4.2.1).
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'config.dart';

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
/// R2-B4: keeps the config only.
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
}

/// Overrides core.audioRecorderServiceProvider and core.audioPlaybackServiceProvider.
///
/// (06-pdf 4.2.2) From PDF T31 exactly these two, built with config ?? MediaIoRuntime.config;
/// the services read core.noteStoreProvider / clockProvider / remoteAssetFetcherProvider on
/// first use, so reading the two providers in a container without a store never throws.
/// R2-B4 (contract 7.6.2): no override — CORE's defaults ('not supported') stay.
List<Override> mediaIoOverrides({MediaIoConfig? config}) => const [];
