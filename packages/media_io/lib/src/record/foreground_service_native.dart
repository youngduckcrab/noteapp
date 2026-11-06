// lib/src/record/foreground_service_native.dart — (P-B, M6-2) the Android microphone foreground
// service while a native recording runs (m5-7/06-pdf 6.9.4): flutter_foreground_task's
// FlutterForegroundTask behind a small port (the test seam — unit/foreground_service_test.dart).
//
// | step              | what                                                                     |
// | initializeMediaIo | FlutterForegroundTask.init (sync, Android native only — PDF T37 calls     |
// |                   | prepareForegroundService; start() also makes sure it ran)               |
// | before record     | the app is in front (the user just tapped): notification permission       |
// |   .start          | denied → requestNotificationPermission() once in this run (a refusal only |
// |                   | hides the notification) → startService(microphone)                      |
// | failure           | ServiceRequestFailure → recording goes on in the foreground only          |
// |                   | (backgroundCapable false), developer overlay 'FGS failed: …'           |
// | stop/cancel/      | stopService()                                                            |
// |   abandon         |                                                                          |
//
// Internal; *_native.dart only (flutter_foreground_task is a native-only import — R4).
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../config.dart';
import '../testing/test_hooks.dart';
import '../tuning.dart';
import '../ui/strings_ko.dart';

/// What [RecordingForegroundService] asks of flutter_foreground_task.
abstract interface class ForegroundTaskPort {
  /// FlutterForegroundTask.init with the 6.9.4 options; idempotent.
  void init();

  /// checkNotificationPermission() == denied (permanently_denied is not asked again).
  Future<bool> notificationPermissionDenied();

  Future<void> requestNotificationPermission();

  /// startService(microphone): null when it runs, else the failure.
  Future<Object?> startService();

  Future<void> stopService();
}

/// The real port (FlutterForegroundTask's static API).
final class FlutterForegroundTaskPort implements ForegroundTaskPort {
  const FlutterForegroundTaskPort();

  static bool _initialized = false;

  @override
  void init() {
    if (_initialized) return;
    _initialized = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: MediaTuning.androidChannelId,
        channelName: MediaStringsKo.foregroundChannelName,
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
        allowAutoRestart: false,
        stopWithTask: true,
      ),
    );
  }

  @override
  Future<bool> notificationPermissionDenied() async =>
      await FlutterForegroundTask.checkNotificationPermission() ==
      NotificationPermission.denied;

  @override
  Future<void> requestNotificationPermission() async {
    await FlutterForegroundTask.requestNotificationPermission();
  }

  @override
  Future<Object?> startService() async {
    init();
    final result = await FlutterForegroundTask.startService(
      serviceTypes: const [ForegroundServiceTypes.microphone],
      notificationTitle: MediaStringsKo.foregroundTitle,
      notificationText: MediaStringsKo.foregroundText,
      callback: null,
    );
    return switch (result) {
      ServiceRequestSuccess() => null,
      ServiceRequestFailure(:final error) => error,
    };
  }

  @override
  Future<void> stopService() async {
    await FlutterForegroundTask.stopService();
  }
}

/// '이번 실행에서 한 번' (6.9.4): whether this run already asked for the notification permission.
final class NotificationAskMemo {
  bool asked = false;

  /// The process-wide memo the app uses.
  static final NotificationAskMemo run = NotificationAskMemo();
}

/// The foreground service around one native recording at a time.
final class RecordingForegroundService {
  RecordingForegroundService({this._port, NotificationAskMemo? memo})
    : _memo = memo ?? NotificationAskMemo.run;

  final ForegroundTaskPort? _port;
  final NotificationAskMemo _memo;
  ForegroundTaskPort? _running;

  /// Why the last start did not run the service ('FGS failed: …' on the developer overlay).
  Object? lastFailure;

  /// Whether the service runs now.
  bool get running => _running != null;

  /// [MediaTestHooks.noForegroundService] → none (installFakeMediaPlatforms).
  ForegroundTaskPort? get _portNow =>
      _port ??
      (MediaTestHooks.noForegroundService
          ? null
          : const FlutterForegroundTaskPort());

  /// Before record.start: on Android with [MediaIoConfig.androidForegroundService], starts the
  /// microphone service. Returns whether it runs (the session's backgroundCapable on Android).
  /// Never throws — a failure leaves recording in the foreground only.
  Future<bool> start(MediaIoConfig config) async {
    if (defaultTargetPlatform != TargetPlatform.android ||
        !config.androidForegroundService) {
      return false;
    }
    final port = _portNow;
    if (port == null) return false;
    if (_running != null) return true;
    try {
      if (!_memo.asked && await port.notificationPermissionDenied()) {
        _memo.asked = true;
        await port.requestNotificationPermission();
      }
    } on Object {
      // only the notification stays hidden
    }
    try {
      final failure = await port.startService();
      if (failure == null) {
        _running = port;
        lastFailure = null;
        return true;
      }
      lastFailure = failure;
    } on Object catch (e) {
      lastFailure = e;
    }
    return false;
  }

  /// After stop / cancel / abandon (and a failed start). Idempotent; never throws.
  Future<void> stop() async {
    final port = _running;
    _running = null;
    if (port == null) return;
    try {
      await port.stopService();
    } on Object {
      // the service ends with the task (stopWithTask) anyway
    }
  }
}

/// initializeMediaIo (PDF T37 — 6.9.4): FlutterForegroundTask.init on Android when the config
/// wants the service. Sync; never throws.
void prepareForegroundService(
  MediaIoConfig config, {
  ForegroundTaskPort? port,
}) {
  if (defaultTargetPlatform != TargetPlatform.android ||
      !config.androidForegroundService) {
    return;
  }
  final p =
      port ??
      (MediaTestHooks.noForegroundService
          ? null
          : const FlutterForegroundTaskPort());
  try {
    p?.init();
  } on Object {
    // start() tries again
  }
}
