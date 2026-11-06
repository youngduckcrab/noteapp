// lib/src/config.dart — MediaIoConfig (contract 7.2.12, m5-7/06-pdf 4.2.1).
import 'package:flutter/foundation.dart';

@immutable
final class MediaIoConfig {
  /// Asserts (06-pdf 4.2.1): bitRate ∈ [32000, 128000], sampleRate ∈ {22050, 44100, 48000},
  /// webDraftChunkMs ∈ [250, 5000].
  const MediaIoConfig({
    this.bitRate = 64000,
    this.sampleRate = 44100,
    this.allowNonAacOnWeb = true,
    this.webDraftChunkMs = 1000,
    this.androidForegroundService = true,
  }) : assert(
         bitRate >= 32000 && bitRate <= 128000,
         'MediaIoConfig.bitRate must be in [32000, 128000]',
       ),
       assert(
         sampleRate == 22050 || sampleRate == 44100 || sampleRate == 48000,
         'MediaIoConfig.sampleRate must be 22050, 44100 or 48000',
       ),
       assert(
         webDraftChunkMs >= 250 && webDraftChunkMs <= 5000,
         'MediaIoConfig.webDraftChunkMs must be in [250, 5000]',
       );
  final int bitRate; // AAC-LC mono (U8)
  final int sampleRate;
  final bool allowNonAacOnWeb; // Chrome: opus/webm with a warning (crossPlatformPlayable false)
  final int webDraftChunkMs; // web: MediaRecorder timeslice; each chunk appended to RecordingDraftStore (loss ≤ 1 s)
  final bool androidForegroundService; // microphone FGS while recording (M6-2)

  /// Value equality over every field (1차 7.4.4; initializeMediaIo's "second call with a
  /// different config" check uses it).
  @override
  bool operator ==(Object other) =>
      other is MediaIoConfig &&
      other.bitRate == bitRate &&
      other.sampleRate == sampleRate &&
      other.allowNonAacOnWeb == allowNonAacOnWeb &&
      other.webDraftChunkMs == webDraftChunkMs &&
      other.androidForegroundService == androidForegroundService;

  @override
  int get hashCode => Object.hash(
    bitRate,
    sampleRate,
    allowNonAacOnWeb,
    webDraftChunkMs,
    androidForegroundService,
  );

  @override
  String toString() =>
      'MediaIoConfig(bitRate: $bitRate, sampleRate: $sampleRate, '
      'allowNonAacOnWeb: $allowNonAacOnWeb, webDraftChunkMs: $webDraftChunkMs, '
      'androidForegroundService: $androidForegroundService)';
}
