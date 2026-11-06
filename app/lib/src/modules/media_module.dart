/// Recording adapter (docs/plans/m5-7/01-infra.md 4.6.4, 6.4, 6.5.2, 6.7;
/// contract 7.2.12 / 7.3.3 — (v2.1, D2-15 / D17) recording only).
library;

import 'dart:async';

import 'package:feature_editor/feature_editor.dart' show EditorPanelBuilder;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:media_io/media_io.dart'
    show MediaIoConfig, initializeMediaIo, mediaIoOverrides;
import 'package:note_core/note_core.dart' show audioRecorderServiceProvider;

import '../bootstrap/app_module.dart';
import '../bootstrap/idle_tasks.dart';
import '../errors/app_error_log.dart';
import '../features/app_features.dart';
import 'media_wiring.dart';

/// (v2.1, D2-15 / D17) Recording only: FEATURE_MEDIA / app.features.media
/// turn exactly this off. Image import is NOT here
/// (FeatureWiringModule.imageImporter).
final class MediaModule extends AppModule {
  MediaModule({
    this._initialize = initializeMediaIo,
    this._mediaOverrides = mediaIoOverrides,
    this._recordingPanel = mediaRecordingPanel,
    this._config = const MediaIoConfig(),
  });

  static const String moduleId = 'media';

  /// How long onStartAbandoned waits for the late start.
  static const Duration lateStartWait = Duration(seconds: 10);

  final Future<void> Function({MediaIoConfig config}) _initialize;
  final List<Override> Function({MediaIoConfig? config}) _mediaOverrides;
  final EditorPanelBuilder _recordingPanel;
  final MediaIoConfig _config;

  Future<void>? _start;
  AppErrorLog? _errorLog;

  @override
  String get id => moduleId;

  @override
  String get label => '녹음 준비 중';

  @override
  bool get critical => false;

  @override
  Duration get startTimeout => const Duration(seconds: 5);

  /// context.featureOn(AppFeature.media)
  @override
  Future<bool> isEnabled(AppModuleContext context) =>
      context.featureOn(AppFeature.media);

  /// await initialize(config: config); context.contribute(ShellContribution(
  /// moduleId: 'media', recordingPanel: recordingPanel, devOverlaySections:
  /// [mediaDevOverlaySection]))
  @override
  Future<void> start(AppModuleContext context) {
    _errorLog = context.errorLog;
    return _start = _run(context);
  }

  Future<void> _run(AppModuleContext context) async {
    await _initialize(config: _config);
    context.contribute(
      ShellContribution(
        moduleId: moduleId,
        recordingPanel: _recordingPanel,
        devOverlaySections: const [mediaDevOverlaySection],
      ),
    );
  }

  /// mediaOverrides(config: config) — X28, the only audio override.
  @override
  List<Override> overrides() => _mediaOverrides(config: _config);

  /// ShellContribution(moduleId: 'media', recordingPanel: recordingPanel) —
  /// the panel then reads the default UnsupportedAudioRecorder and shows its
  /// '이 기기에서 녹음할 수 없어요' state.
  @override
  ShellContribution? fallbackContribution() =>
      ShellContribution(moduleId: moduleId, recordingPanel: _recordingPanel);

  /// (v2.1, C21-20) start() went past 5 s: waits for the late start future
  /// (≤ 10 s) and only logs 'media started late — ignored'. initializeMediaIo
  /// holds nothing to release (idempotent, no listener, no service started);
  /// its late contribute() is dropped by AppModuleContext and its overrides
  /// were never applied, so the app keeps the default 'cannot record'
  /// recorder.
  @override
  Future<void> onStartAbandoned() async {
    final start = _start;
    if (start == null) return;
    var late = false;
    try {
      await start.timeout(lateStartWait);
      late = true;
    } on Object {
      // Still running after 10 s, or failed late: nothing to release either.
    }
    if (late) {
      _errorLog?.add(
        AppErrorRecord(
          time: DateTime.now(),
          source: AppErrorSource.module,
          summary: 'media started late — ignored',
        ),
      );
    }
  }

  /// [AppIdleTask(id: 'media.leaveGuard', priority:
  /// AppIdlePriority.dataProtection, immediate: true, run: leave guard 6.17),
  /// AppIdleTask(id: 'media.recoverDrafts', priority:
  /// AppIdlePriority.dataProtection, run: 6.5.2)]
  @override
  List<AppIdleTask> idleTasks() => const [
    AppIdleTask(
      id: 'media.leaveGuard',
      priority: AppIdlePriority.dataProtection,
      immediate: true,
      run: _leaveGuard,
    ),
    AppIdleTask(
      id: 'media.recoverDrafts',
      priority: AppIdlePriority.dataProtection,
      run: _recoverDrafts,
    ),
  ];
}

/// The web leave guard while recording (6.17, D2-14): subscribes to
/// audioRecorderServiceProvider.statusStream (it emits the current status on
/// listen) and calls web.setLeaveGuard(status.isActive) on every status. The
/// clean-up cancels the subscription and turns the guard off. status.isActive
/// is a UI decision here only — draft recovery follows pendingDrafts().
Future<void> _leaveGuard(AppIdleContext context) async {
  final web = context.web;
  final errorLog = context.errorLog;
  final subscription = context
      .read(audioRecorderServiceProvider)
      .statusStream
      .listen(
        (status) => web.setLeaveGuard(status.isActive),
        onError: (Object error, StackTrace stackTrace) => errorLog.add(
          AppErrorRecord.fromError(
            error,
            stackTrace,
            source: AppErrorSource.module,
          ),
        ),
      );
  // Cancelling stops the events at once; nothing to wait for.
  context.onDispose(() {
    unawaited(subscription.cancel());
    web.setLeaveGuard(false);
  });
}

/// 6.5.2: every draft pendingDrafts() returns, oldest first, without asking.
Future<void> _recoverDrafts(AppIdleContext context) async {
  await recoverPendingRecordings(
    context.read(audioRecorderServiceProvider),
    context.errorLog,
  );
}
