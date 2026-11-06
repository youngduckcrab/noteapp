// lib/src/tuning.dart — m5-7/06-pdf 4.5.2. Every numeric constant of media_io lives here;
// change 06-pdf 4.5.2 together with a value. Values that follow MediaIoConfig.webDraftChunkMs
// are functions of it.

abstract final class MediaTuning {
  /// Native activeMs status refresh.
  static const Duration statusTick = Duration(seconds: 1);

  /// Ask MediaRecorder for data when no chunk came for this long (Safari — 6.8.2).
  static int webRequestDataWatchdogMs(int webDraftChunkMs) =>
      (2.5 * webDraftChunkMs).round();

  /// 7.4.5 '웹 녹음 메모리 조각 ≤ 8 MB': queued chunks + unsaved (6.8.5).
  static const int webMemoryBacklogMaxBytes = 8 * 1024 * 1024;

  /// CORE RecordingDraftStore.append takes chunks of at most 4 MiB (contract 7.2.4); the
  /// draft writer splits a bigger chunk and keeps unsaved chunks at this size (6.8.5).
  static const int draftChunkMaxBytes = 4 * 1024 * 1024;

  /// Wait for the last dataavailable on stop.
  static const Duration webStopFlushTimeout = Duration(seconds: 3);

  /// Keep the stream from checkSupport(requestPermission: true).
  static const Duration micStreamKeepAlive = Duration(seconds: 30);

  /// (v2.1, S-6) A track mute this long while visible = the microphone is lost (6.8.3).
  static const int micMuteLostMs = 1000;

  /// (v2.1, S-6) After the tab becomes visible again, wait this long for unmute.
  static const int micUnmuteGraceMs = 3000;

  /// Native decoder length probe limit (6.6.4).
  static const Duration durationProbeTimeout = Duration(seconds: 5);

  /// Clock − file length beyond this → developer overlay warning (R-3, A-5).
  static const int clockWarnErrorMs = 150;

  /// F-16.
  static const List<double> playbackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  /// F-16 '10초 앞뒤'.
  static const int seekStepMs = 10000;

  /// Native play cache file LRU.
  static const int playCacheMaxBytes = 256 * 1024 * 1024;

  /// Wait before showing the image preparing sheet.
  static const Duration importProgressDelay = Duration(milliseconds: 400);

  /// Tried in order when the JPEG is over 8 MiB (6.12.3).
  static const List<double> jpegQualities = [0.85, 0.75, 0.6];

  /// Long side factor when even the lowest quality is over the limit.
  static const double downscaleStep = 0.85;

  /// Recording.title (7.2.4).
  static const int maxTitleLength = 100;

  /// (v2.1) pendingDrafts 'recently updated' window = max(this, 5 × webDraftChunkMs) (7.2.4).
  static const int recentDraftWindowMinMs = 10000;

  /// The 'recently updated' window for [webDraftChunkMs].
  static int recentDraftWindowMs(int webDraftChunkMs) {
    final five = 5 * webDraftChunkMs;
    return five > recentDraftWindowMinMs ? five : recentDraftWindowMinMs;
  }

  /// (v2.1) Empty-chunk append interval while paused = webDraftChunkMs (≤ 1/5 of the window —
  /// 6.8.5).
  static int pausedKeepAliveMs(int webDraftChunkMs) => webDraftChunkMs;

  /// (v2.1, 7.2.12) Unfinished recovery attempts at which a draft leaves automatic recovery.
  static const int recoverMaxAttempts = 2;

  /// (v2.1, P-B) Web recordings this large hand the same Blob to the player right after stop.
  static const int stopHandoffMinBytes = 32 * 1024 * 1024;

  /// (v2.1) Look for the last WebM Cluster in this many bytes from the end (6.8.7).
  static const int webmTailScanBytes = 256 * 1024;

  /// (v2.1) Opus packet length when the TOC cannot be read.
  static const int opusDefaultPacketMs = 20;

  /// 7.2.12.
  static const String recoveredTitle = '복구된 녹음';

  /// Foreground service notification channel.
  static const String androidChannelId = 'noteapp_recording';

  /// Under the app support directory / the cache directory.
  static const String nativeRecordingDir = 'media_io/rec';
  static const String playCacheDir = 'media_io/play';
}
