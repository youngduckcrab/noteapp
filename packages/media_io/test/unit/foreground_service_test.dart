// (P-B, M6-2) The Android microphone foreground service around a native recording
// (m5-7/06-pdf 6.9.4 — 8.2 T33), through the real MediaRecorderService + NativeRecorderEngine
// on FakeRecordPlatform and a fake flutter_foreground_task port: only on Android,
// startService before record.start; a failure keeps recording (backgroundCapable false, the
// developer note says 'FGS failed'); stop / cancel / abandon → stopService; the notification
// permission asked once in a run; initializeMediaIo's init step.
@TestOn('vm')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/src/config.dart';
import 'package:media_io/src/record/foreground_service_native.dart';
import 'package:media_io/src/record/recorder_engine_native.dart';
import 'package:media_io/src/record/recorder_service.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/native_world.dart';

/// flutter_foreground_task as the service sees it.
final class FakeForegroundPort implements ForegroundTaskPort {
  FakeForegroundPort(this.recordCalls);

  /// FakeRecordPlatform.calls, to see what record had done when the service started.
  final List<String> Function() recordCalls;

  final List<String> calls = [];

  /// record's calls at each startService.
  final List<List<String>> recordCallsAtStart = [];

  bool notificationDenied = false;

  /// startService answers this failure (ServiceRequestFailure) …
  Object? failure;

  /// … or throws this.
  Object? throwOnStart;

  @override
  void init() => calls.add('init');

  @override
  Future<bool> notificationPermissionDenied() async {
    calls.add('checkNotificationPermission');
    return notificationDenied;
  }

  @override
  Future<void> requestNotificationPermission() async {
    calls.add('requestNotificationPermission');
  }

  @override
  Future<Object?> startService() async {
    calls.add('startService');
    recordCallsAtStart.add(recordCalls());
    if (throwOnStart case final e?) {
      Error.throwWithStackTrace(e, StackTrace.current);
    }
    return failure;
  }

  @override
  Future<void> stopService() async => calls.add('stopService');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NativeWorld w;
  late FakeForegroundPort port;
  late NotificationAskMemo memo;
  setUp(() async {
    w = NativeWorld();
    await w.init();
    port = FakeForegroundPort(() => w.record.calls);
    memo = NotificationAskMemo();
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await w.dispose();
  });

  NativeRecorderEngine engine() => NativeRecorderEngine(
    foreground: RecordingForegroundService(port: port, memo: memo),
  );

  Future<void> start(MediaRecorderService s) =>
      s.start(recordingId: w.store.ids.newId(), noteId: w.noteId);

  test('Android: startService before record.start; backgroundCapable; stop → stopService', () async {
    final s = w.service(engine: engine());
    await start(s);
    expect(port.calls, ['checkNotificationPermission', 'startService']);
    final before = port.recordCallsAtStart.single;
    expect(before.where((c) => c.startsWith('start(')), isEmpty);
    expect(w.record.calls.where((c) => c.startsWith('start(')), hasLength(1));
    expect(s.status.phase, core.RecorderPhase.recording);
    expect(s.status.backgroundCapable, isTrue);

    w.record.fileBytes = fileOf(32);
    w.recorded = const Duration(seconds: 1);
    await s.stop();
    expect(port.calls.last, 'stopService');
    expect(port.calls.where((c) => c == 'stopService'), hasLength(1));
  });

  test('cancel and abandon (dispose while recording) → stopService', () async {
    final s = w.service(engine: engine());
    await start(s);
    await s.cancel();
    expect(port.calls.last, 'stopService');

    await start(s);
    expect(port.calls.where((c) => c == 'startService'), hasLength(2));
    await s.dispose();
    expect(port.calls.last, 'stopService');
    expect(port.calls.where((c) => c == 'stopService'), hasLength(2));
  });

  test('a failed start keeps recording: backgroundCapable false, FGS failed, no stopService', () async {
    port.failure = StateError('ForegroundServiceStartNotAllowedException');
    final e = engine();
    final s = w.service(engine: e);
    await start(s);
    expect(s.status.phase, core.RecorderPhase.recording);
    expect(s.status.backgroundCapable, isFalse);
    expect(e.developerNote, contains('FGS failed: StateError'));
    w.record.fileBytes = fileOf(32);
    w.recorded = const Duration(seconds: 1);
    expect(await s.stop(), isNotNull);
    expect(port.calls, isNot(contains('stopService')));

    // a throwing port is the same
    port
      ..failure = null
      ..throwOnStart = UnsupportedError('no service');
    await start(s);
    expect(s.status.phase, core.RecorderPhase.recording);
    expect(s.status.backgroundCapable, isFalse);
    expect(e.developerNote, contains('FGS failed: UnsupportedError'));

    // and a working one clears the note
    port.throwOnStart = null;
    await s.cancel();
    await start(s);
    expect(s.status.backgroundCapable, isTrue);
    expect(e.developerNote, isNull);
  });

  test('a failed record.start lets the service go (stopService) and nothing is left', () async {
    w.record.startError = StateError('busy');
    final s = w.service(engine: engine());
    await expectLater(start(s), throwsA(anything));
    expect(port.calls, [
      'checkNotificationPermission',
      'startService',
      'stopService',
    ]);
  });

  test('the notification permission is asked once in a run (denied → request), not when granted', () async {
    port.notificationDenied = true;
    final s = w.service(engine: engine());
    await start(s);
    await s.cancel();
    await start(s);
    await s.cancel();
    // a new engine (a rebuilt provider) in the same run asks no more
    final s2 = w.service(engine: engine());
    await start(s2);
    expect(
      port.calls.where((c) => c == 'requestNotificationPermission'),
      hasLength(1),
    );
    expect(port.calls.where((c) => c == 'startService'), hasLength(3));
    expect(
      port.calls.indexOf('requestNotificationPermission'),
      lessThan(port.calls.indexOf('startService')),
    );
  });

  test('granted notifications: no request', () async {
    final s = w.service(engine: engine());
    await start(s);
    expect(port.calls, isNot(contains('requestNotificationPermission')));
  });

  test('iOS and other platforms: no service (iOS backgroundCapable, else foreground only)', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final s = w.service(engine: engine());
    await start(s);
    expect(s.status.backgroundCapable, isTrue);
    await s.cancel();

    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await start(s);
    expect(s.status.backgroundCapable, isFalse);
    await s.cancel();
    expect(port.calls, isEmpty);
  });

  test(
    'MediaIoConfig.androidForegroundService false: no service, foreground only',
    () async {
      final s = w.service(
        engine: engine(),
        config: const MediaIoConfig(androidForegroundService: false),
      );
      await start(s);
      expect(port.calls, isEmpty);
      expect(s.status.backgroundCapable, isFalse);
    },
  );

  test('initializeMediaIo step: init on Android when enabled only', () {
    prepareForegroundService(const MediaIoConfig(), port: port);
    expect(port.calls, ['init']);
    prepareForegroundService(
      const MediaIoConfig(androidForegroundService: false),
      port: port,
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    prepareForegroundService(const MediaIoConfig(), port: port);
    expect(port.calls, ['init']);
  });
}
