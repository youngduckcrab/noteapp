// (P-B) The iOS audio session around a native recording and the playback speech session
// (m5-7/06-pdf 6.9.3, 6.11.1 — 8.2 T33), through the real MediaRecorderService +
// NativeRecorderEngine on FakeRecordPlatform (AudioRecorder.ios is its recording fake while the
// target platform is iOS) and a fake audio_session port: record's own session management off
// (manageAudioSession(false)) and playAndRecord active before record.start; after stop /
// cancel / abandon the session is deactivated notifying the other apps; nothing on Android;
// a failed take-over gives the session back to record and recording goes on.
@TestOn('vm')
library;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/src/record/audio_session_native.dart';
import 'package:media_io/src/record/recorder_engine_native.dart';
import 'package:media_io/src/record/recorder_service.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/native_world.dart';

/// package:audio_session as the engine sees it.
final class FakeSessionPort implements AudioSessionPort {
  FakeSessionPort(this.recordCalls);

  final List<String> Function() recordCalls;
  final List<String> calls = [];
  final List<AudioSessionConfiguration> configurations = [];

  /// record's calls when each session call came.
  final List<List<String>> recordCallsAt = [];

  Object? configureError;

  @override
  Future<void> configure(AudioSessionConfiguration configuration) async {
    calls.add('configure');
    configurations.add(configuration);
    recordCallsAt.add(recordCalls());
    if (configureError case final e?) {
      Error.throwWithStackTrace(e, StackTrace.current);
    }
  }

  @override
  Future<bool> setActive(
    bool active, {
    AVAudioSessionSetActiveOptions? options,
  }) async {
    calls.add(
      'setActive($active${options == null ? '' : ', options: ${options.value}'})',
    );
    recordCallsAt.add(recordCalls());
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NativeWorld w;
  late FakeSessionPort port;
  setUp(() async {
    w = NativeWorld();
    await w.init();
    port = FakeSessionPort(() => w.record.calls);
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await w.dispose();
  });

  NativeRecorderEngine engine() =>
      NativeRecorderEngine(audioSession: RecordingAudioSession(port: port));

  Future<void> start(MediaRecorderService s) =>
      s.start(recordingId: w.store.ids.newId(), noteId: w.noteId);

  List<String> iosCalls() => [
    for (final c in w.record.calls)
      if (c.startsWith('ios.')) c,
  ];

  test('iOS: manageAudioSession(false), then playAndRecord active before record.start', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final s = w.service(engine: engine());
    await start(s);
    expect(iosCalls(), ['ios.manageAudioSession(false)']);
    expect(port.calls, ['configure', 'setActive(true)']);
    // both before record.start, after record's session management was turned off
    for (final before in port.recordCallsAt) {
      expect(before, contains('ios.manageAudioSession(false)'));
      expect(before.where((c) => c.startsWith('start(')), isEmpty);
    }
    final c = port.configurations.single;
    expect(c.avAudioSessionCategory, AVAudioSessionCategory.playAndRecord);
    expect(
      c.avAudioSessionCategoryOptions,
      AVAudioSessionCategoryOptions.defaultToSpeaker |
          AVAudioSessionCategoryOptions.allowBluetooth |
          AVAudioSessionCategoryOptions.allowBluetoothA2dp,
    );
    expect(c.avAudioSessionMode, AVAudioSessionMode.spokenAudio);
    expect(s.status.phase, core.RecorderPhase.recording);
  });

  test('iOS: stop, cancel and abandon deactivate notifying the other apps (once each)', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    const deactivate =
        'setActive(false, options: 1)'; // notifyOthersOnDeactivation
    expect(AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation.value, 1);
    final s = w.service(engine: engine());

    await start(s);
    w.record.fileBytes = fileOf(32);
    w.recorded = const Duration(seconds: 1);
    await s.stop();
    expect(port.calls.last, deactivate);
    // after record stopped
    expect(port.recordCallsAt.last, contains('stop'));

    await start(s);
    await s.cancel();
    expect(port.calls.last, deactivate);

    await start(s);
    await s.dispose();
    expect(port.calls.last, deactivate);
    expect(port.calls.where((c) => c == deactivate), hasLength(3));
    expect(port.calls.where((c) => c == 'setActive(true)'), hasLength(3));
  });

  test('Android: the session is record\'s (no session calls)', () async {
    final s = w.service(engine: engine());
    await start(s);
    w.record.fileBytes = fileOf(32);
    w.recorded = const Duration(seconds: 1);
    await s.stop();
    expect(port.calls, isEmpty);
    expect(iosCalls(), isEmpty);
  });

  test('iOS: a failed take-over gives the session back to record; recording goes on, no deactivate', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    port.configureError = StateError('session busy');
    final e = engine();
    final s = w.service(engine: e);
    await start(s);
    expect(iosCalls(), [
      'ios.manageAudioSession(false)',
      'ios.manageAudioSession(true)',
    ]);
    expect(s.status.phase, core.RecorderPhase.recording);
    expect(e.developerNote, contains('audio session failed: StateError'));
    await s.cancel();
    expect(port.calls, ['configure']);
  });

  test('playback: the speech configuration (iOS spokenAudio, Android speech/media)', () async {
    await configureSpeechSession(port: port);
    final c = port.configurations.single;
    expect(c.avAudioSessionCategory, AVAudioSessionCategory.playback);
    expect(c.avAudioSessionMode, AVAudioSessionMode.spokenAudio);
    expect(
      c.androidAudioAttributes?.contentType,
      AndroidAudioContentType.speech,
    );
    expect(c.androidAudioAttributes?.usage, AndroidAudioUsage.media);
  });
}
