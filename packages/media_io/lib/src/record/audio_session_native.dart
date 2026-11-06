// lib/src/record/audio_session_native.dart — (P-B) the iOS audio session around a native recording
// and the speech session of playback (m5-7/06-pdf 6.9.3, 6.11.1): media_io manages the session
// itself — record's own management is off (AudioRecorder.ios?.manageAudioSession(false)), then
// before record.start: configure(playAndRecord, defaultToSpeaker | allowBluetooth |
// allowBluetoothA2dp, spokenAudio) → setActive(true); after stop / cancel / abandon:
// setActive(false, notifyOthersOnDeactivation) so another app's music comes back. Android: the
// recording side is record's; playback gets the speech attributes (AudioSessionConfiguration
// .speech() — contentType speech, usage media).
//
// If taking over the session fails, record manages it again (manageAudioSession(true)) — the
// recording still works, only the other app's music may not resume (6.9.3 'P-B가 잘리면').
// Internal; package:audio_session stays in *_native.dart (3.5 I-3).
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

/// What [RecordingAudioSession] asks of package:audio_session (the test seam —
/// unit/audio_session_test.dart).
abstract interface class AudioSessionPort {
  Future<void> configure(AudioSessionConfiguration configuration);

  Future<bool> setActive(
    bool active, {
    AVAudioSessionSetActiveOptions? options,
  });
}

/// The real port (AudioSession.instance).
final class PackageAudioSessionPort implements AudioSessionPort {
  const PackageAudioSessionPort();

  @override
  Future<void> configure(AudioSessionConfiguration configuration) async =>
      (await AudioSession.instance).configure(configuration);

  @override
  Future<bool> setActive(
    bool active, {
    AVAudioSessionSetActiveOptions? options,
  }) async => (await AudioSession.instance).setActive(
    active,
    avAudioSessionSetActiveOptions: options,
  );
}

/// The recording configuration (6.9.3).
final AudioSessionConfiguration recordingSessionConfiguration =
    AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
          AVAudioSessionCategoryOptions.defaultToSpeaker |
          AVAudioSessionCategoryOptions.allowBluetooth |
          AVAudioSessionCategoryOptions.allowBluetoothA2dp,
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
    );

/// The session of one native recording at a time (iOS; nothing elsewhere).
final class RecordingAudioSession {
  RecordingAudioSession({AudioSessionPort? port})
    : _port = port ?? const PackageAudioSessionPort();

  final AudioSessionPort _port;
  bool _active = false;

  /// Why taking over the session failed (developer overlay), or null.
  Object? lastFailure;

  /// Whether this recording's session is active (deactivated by [afterRecording]).
  bool get active => _active;

  /// Before record.start. [recorderManagesSession] is AudioRecorder.ios?.manageAudioSession
  /// (package:record stays in recorder_engine_native.dart — 3.5 I-3). Never throws.
  Future<void> beforeRecording({
    required Future<void> Function(bool manage) recorderManagesSession,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await recorderManagesSession(false);
      await _port.configure(recordingSessionConfiguration);
      await _port.setActive(true);
      _active = true;
      lastFailure = null;
    } on Object catch (e) {
      lastFailure = e;
      try {
        await recorderManagesSession(true);
      } on Object {
        // record's defaults then
      }
    }
  }

  /// After stop / cancel / abandon / a failed start. Idempotent; never throws.
  Future<void> afterRecording() async {
    if (!_active) return;
    _active = false;
    try {
      await _port.setActive(
        false,
        options: AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
      );
    } on Object catch (e) {
      lastFailure = e;
    }
  }
}

/// Playback (6.11.1 — JustAudioPlayerPort beforeFirstLoad, wired by PDF T37): the speech
/// configuration on iOS and Android.
Future<void> configureSpeechSession({AudioSessionPort? port}) =>
    (port ?? const PackageAudioSessionPort()).configure(
      const AudioSessionConfiguration.speech(),
    );
