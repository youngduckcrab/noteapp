/// Runs the startup modules and assembles the root overrides
/// (docs/plans/01-infra.md 4.5.4, 6.4, 6.7; 2nd round
/// docs/plans/m5-7/01-infra.md 4.6.2, 6.4).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:note_core/note_core.dart'
    show NoteStore, NoteStoreOpenException, NoteStoreOpenFailure, OwnerId;

import '../app/appearance.dart';
import '../app/strings.dart';
import '../errors/app_error_log.dart';
import '../features/app_features.dart';
import '../providers.dart';
import '../runtime/build_info.dart';
import '../runtime/runtime_info.dart';
import '../settings/settings_sections.dart' show shellContributionsProvider;
import '../web/web_platform.dart';
import 'app_module.dart';
import 'idle_tasks.dart';
import 'startup_report.dart';

sealed class BootstrapResult {
  const BootstrapResult({required this.report});
  final StartupReport report;
}

final class BootstrapSuccess extends BootstrapResult {
  const BootstrapSuccess({
    required super.report,
    required this.overrides,
    required this.startedModules,
    this.idleTasks = const [],
    this.contributions = const [],
    this.features = AppFeatures.all,
  });

  /// Shell overrides first, then module overrides in module order.
  final List<Override> overrides;
  final List<AppModule> startedModules;

  /// Started modules' tasks in module order (the runner orders by priority).
  final List<AppIdleTask> idleTasks;
  final List<ShellContribution> contributions;

  /// resolveFeatures() result of this attempt.
  final AppFeatures features;
}

final class BootstrapFailure extends BootstrapResult {
  const BootstrapFailure({
    required super.report,
    required this.moduleId,
    required this.moduleLabel,
    required this.error,
    required this.stackTrace,
    this.resetLocalData,
  });

  final String moduleId;
  final String moduleLabel;
  final Object error;
  final StackTrace stackTrace;

  /// failedModule.resetLocalData when failedModule.canResetAfter(error), else null.
  final Future<void> Function()? resetLocalData;

  /// Korean message (해요체) chosen by error type (6.7).
  String get userMessage => switch (error) {
    NoteStoreOpenException(:final reason) => switch (reason) {
      NoteStoreOpenFailure.storageUnavailable =>
        AppStrings.startupStorageUnavailable,
      NoteStoreOpenFailure.migrationFailed => AppStrings.startupMigrationFailed,
      NoteStoreOpenFailure.corrupted => AppStrings.startupCorrupted,
      NoteStoreOpenFailure.newerSchema => AppStrings.startupNewerSchema,
      NoteStoreOpenFailure.unknown => AppStrings.startupStoreUnknown,
    },
    TimeoutException() => AppStrings.startupTimedOut(moduleLabel),
    _ => AppStrings.startupGeneric,
  };

  /// True for NoteStoreOpenException(newerSchema) on web: offer "새로고침".
  ///
  /// The "on web" half is BootstrapApp's: it passes onReload only when
  /// WebPlatform.isSupported.
  bool get offersReload =>
      error is NoteStoreOpenException &&
      (error as NoteStoreOpenException).reason ==
          NoteStoreOpenFailure.newerSchema;
}

/// How long [AppBootstrapper.notifyAppHidden] gives each module.
const Duration _hiddenTimeout = Duration(milliseconds: 500);

/// How long [AppBootstrapper.shutdown] gives each module's stop().
const Duration _stopTimeout = Duration(seconds: 2);

/// How long [AppBootstrapper.shutdown] waits for late-start cleanups in total.
const Duration _abandonTimeout = Duration(seconds: 2);

/// How long AppModule.isEnabled may take (timeout → enabled).
const Duration _isEnabledTimeout = Duration(seconds: 1);

final class AppBootstrapper {
  AppBootstrapper({
    required List<AppModule> modules,
    required this.buildInfo,
    required this.runtimeInfo,
    required this.web,
    required this.errorLog,
    required this.ownerId,
    this.slowStageThreshold = const Duration(seconds: 3),
    this.features = AppFeatures.all,
  }) : _modules = List<AppModule>.unmodifiable(modules);
  final List<AppModule> _modules;

  final BuildInfo buildInfo;
  final RuntimeInfo runtimeInfo;
  final WebPlatform web;
  final AppErrorLog errorLog;

  /// See AppModuleContext.ownerId (new database only).
  final OwnerId ownerId;
  final Duration slowStageThreshold;

  /// The build's switches (runNoteApp: AppFeatures.compileTime) —
  /// AppModuleContext.compileTimeFeatures.
  final AppFeatures features;

  final ValueNotifier<String> _stageLabel = ValueNotifier<String>('');
  final ValueNotifier<bool> _isSlow = ValueNotifier<bool>(false);

  /// Modules whose start succeeded and that were not stopped yet, in start
  /// order.
  final List<AppModule> _started = [];

  /// onStartAbandoned() futures of modules whose start timed out.
  final List<Future<void>> _abandoned = [];

  Future<BootstrapResult>? _run;
  Future<void>? _shutdown;

  /// Current stage label for the splash screen.
  ValueListenable<String> get stageLabel => _stageLabel;

  /// True while the current stage exceeded [slowStageThreshold].
  ValueListenable<bool> get isSlow => _isSlow;

  /// Runs once; repeated calls return the same future.
  Future<BootstrapResult> run() => _run ??= _runOnce();

  Future<BootstrapResult> _runOnce() async {
    final stopwatch = Stopwatch()..start();
    // INFRA never requests persist(): CORE does it inside openNoteStore
    // (계약 7.2.12).
    final context = AppModuleContext(
      buildInfo: buildInfo,
      runtimeInfo: runtimeInfo,
      web: web,
      ownerId: ownerId,
      errorLog: errorLog,
      compileTimeFeatures: features,
    );
    final steps = <StartupStep>[];
    final moduleOverrides = <Override>[];
    final idleTasks = <AppIdleTask>[];

    for (final module in _modules) {
      final attempt = await _startModule(module, context);
      context.recordOutcome(
        module.id,
        attempt.outcome,
        fallback: switch (attempt.outcome) {
          StartupStepOutcome.failedNonCritical ||
          StartupStepOutcome.timedOut => _fallbackOf(module),
          _ => null,
        },
      );
      steps.add(
        StartupStep(
          id: module.id,
          elapsed: attempt.elapsed,
          outcome: attempt.outcome,
          error: attempt.error,
        ),
      );

      if (attempt.outcome == StartupStepOutcome.ok) {
        _started.add(module);
        moduleOverrides.addAll(attempt.overrides!);
        idleTasks.addAll(attempt.idleTasks);
        continue;
      }
      // Switched off: no start, no overrides, no contribution, no error.
      if (attempt.outcome == StartupStepOutcome.skipped) continue;
      final error = attempt.error!;
      final stackTrace = attempt.stackTrace ?? StackTrace.empty;
      if (!module.critical) {
        // Left out of the overrides; later modules see isStarted == false.
        _log(
          error,
          stackTrace,
          AppErrorSource.module,
          'module "${module.id}" (non-critical): ${attempt.outcome.name}',
        );
        continue;
      }
      _log(
        error,
        stackTrace,
        AppErrorSource.bootstrap,
        'module "${module.id}": ${attempt.outcome.name}; startup aborted',
        fatal: true,
      );
      await _stopStarted();
      return BootstrapFailure(
        report: _report(stopwatch, steps, context),
        moduleId: module.id,
        moduleLabel: module.label,
        error: error,
        stackTrace: stackTrace,
        resetLocalData: _canReset(module, error) ? module.resetLocalData : null,
      );
    }

    final resolved = await context.resolveFeatures();
    final appearance = await context.resolveAppearance();
    final contributions = context.contributions;
    final report = _report(stopwatch, steps, context);
    return BootstrapSuccess(
      report: report,
      overrides: [
        buildInfoProvider.overrideWithValue(buildInfo),
        webPlatformProvider.overrideWithValue(web),
        runtimeInfoProvider.overrideWithValue(runtimeInfo),
        appErrorLogProvider.overrideWithValue(errorLog),
        startupReportProvider.overrideWithValue(report),
        appBootstrapperProvider.overrideWithValue(this),
        appFeaturesProvider.overrideWithValue(resolved),
        initialAppearanceProvider.overrideWithValue(appearance),
        shellContributionsProvider.overrideWithValue(contributions),
        ...moduleOverrides,
      ],
      startedModules: List<AppModule>.unmodifiable(_started),
      idleTasks: List<AppIdleTask>.unmodifiable(idleTasks),
      contributions: contributions,
      features: resolved,
    );
  }

  /// isEnabled() with its 1 s limit; a throw or a timeout counts as enabled
  /// (logged, source module) so a slow settings read never hides a feature.
  Future<bool> _isEnabled(AppModule module, AppModuleContext context) async {
    try {
      return await Future<bool>.sync(() => module.isEnabled(context))
          .timeout(_isEnabledTimeout);
    } on Object catch (error, stackTrace) {
      _log(
        error,
        stackTrace,
        AppErrorSource.module,
        'module "${module.id}" isEnabled failed; treated as enabled',
      );
      return true;
    }
  }

  ShellContribution? _fallbackOf(AppModule module) {
    try {
      return module.fallbackContribution();
    } on Object catch (error, stackTrace) {
      _log(
        error,
        stackTrace,
        AppErrorSource.module,
        'module "${module.id}" fallbackContribution failed',
      );
      return null;
    }
  }

  /// idleTasks() of a started module; a throw → none (logged).
  List<AppIdleTask> _idleTasksOf(AppModule module) {
    try {
      return module.idleTasks();
    } on Object catch (error, stackTrace) {
      _log(
        error,
        stackTrace,
        AppErrorSource.module,
        'module "${module.id}" idleTasks failed',
      );
      return const [];
    }
  }

  /// start → overrides() of one module, with the timeout and the slow flag.
  Future<_ModuleAttempt> _startModule(
    AppModule module,
    AppModuleContext context,
  ) async {
    _stageLabel.value = module.label;
    _isSlow.value = false;
    final enabledWatch = Stopwatch()..start();
    if (!await _isEnabled(module, context)) {
      return _ModuleAttempt(StartupStepOutcome.skipped, enabledWatch.elapsed);
    }
    final slowTimer = Timer(slowStageThreshold, () => _isSlow.value = true);
    final stopwatch = Stopwatch()..start();
    var timedOut = false;
    var started = false;
    try {
      await Future<void>.sync(() => module.start(context)).timeout(
        module.startTimeout,
        onTimeout: () {
          timedOut = true;
          throw TimeoutException(
            'module "${module.id}" did not start within '
            '${module.startTimeout.inMilliseconds} ms',
            module.startTimeout,
          );
        },
      );
      started = true;
      final overrides = module.overrides();
      return _ModuleAttempt(
        StartupStepOutcome.ok,
        stopwatch.elapsed,
        overrides: overrides,
        idleTasks: _idleTasksOf(module),
      );
    } on Object catch (error, stackTrace) {
      if (timedOut) _abandoned.add(_abandon(module));
      // start() worked but overrides() threw: release what start() opened.
      if (started) {
        await _guarded(module, 'stop', module.stop, _stopTimeout);
      }
      final outcome = timedOut
          ? StartupStepOutcome.timedOut
          : module.critical
          ? StartupStepOutcome.failedCritical
          : StartupStepOutcome.failedNonCritical;
      return _ModuleAttempt(
        outcome,
        stopwatch.elapsed,
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      slowTimer.cancel();
      _isSlow.value = false;
    }
  }

  /// onStartAbandoned(), which must not throw; a throw is logged anyway.
  Future<void> _abandon(AppModule module) async {
    try {
      await module.onStartAbandoned();
    } on Object catch (error, stackTrace) {
      _log(
        error,
        stackTrace,
        AppErrorSource.module,
        'module "${module.id}" onStartAbandoned failed',
      );
    }
  }

  bool _canReset(AppModule module, Object error) {
    if (module.resetLocalData == null) return false;
    try {
      return module.canResetAfter(error);
    } on Object catch (e, stackTrace) {
      _log(
        e,
        stackTrace,
        AppErrorSource.module,
        'module "${module.id}" canResetAfter failed',
      );
      return false;
    }
  }

  StartupReport _report(
    Stopwatch stopwatch,
    List<StartupStep> steps,
    AppModuleContext context,
  ) {
    final sinceNavigationStart = web.millisecondsSinceNavigationStart;
    return StartupReport(
      steps: List<StartupStep>.unmodifiable(steps),
      bootstrapElapsed: stopwatch.elapsed,
      sinceNavigationStart: sinceNavigationStart == null
          ? null
          : Duration(microseconds: (sinceNavigationStart * 1000).round()),
      storage: context.maybe<NoteStore>()?.storageInfo,
    );
  }

  /// Calls onAppHidden() on started modules in parallel, 500 ms timeout each.
  /// Errors are logged (source: module), never thrown.
  Future<void> notifyAppHidden() async {
    await Future.wait([
      for (final module in List<AppModule>.of(_started))
        _guarded(module, 'onAppHidden', module.onAppHidden, _hiddenTimeout),
    ]);
  }

  /// Stops started modules in reverse order (2 s timeout each), then awaits
  /// the onStartAbandoned() cleanups of modules whose start timed out (2 s
  /// max in total; a cleanup still running after that is logged, source:
  /// module). BootstrapApp's "다시 시도" creates the next bootstrapper only
  /// after this completes (6.4 2-2).
  Future<void> shutdown() => _shutdown ??= _shutdownOnce();

  Future<void> _shutdownOnce() async {
    final running = _run;
    if (running != null) await running;
    await _stopStarted();
    if (_abandoned.isEmpty) return;
    final finished = Completer<bool>();
    final timer = Timer(_abandonTimeout, () {
      if (!finished.isCompleted) finished.complete(false);
    });
    unawaited(
      Future.wait(_abandoned).then((_) {
        if (!finished.isCompleted) finished.complete(true);
      }),
    );
    final inTime = await finished.future;
    timer.cancel();
    if (!inTime) {
      _log(
        TimeoutException(
          'late-start cleanup still running after '
          '${_abandonTimeout.inSeconds} s',
          _abandonTimeout,
        ),
        null,
        AppErrorSource.module,
        'shutdown continues without waiting for onStartAbandoned',
      );
    }
  }

  /// stop() on every started module, newest first, 2 s each.
  Future<void> _stopStarted() async {
    while (_started.isNotEmpty) {
      final module = _started.removeLast();
      await _guarded(module, 'stop', module.stop, _stopTimeout);
    }
  }

  Future<void> _guarded(
    AppModule module,
    String what,
    Future<void> Function() call,
    Duration timeout,
  ) async {
    try {
      await Future<void>.sync(call).timeout(timeout);
    } on Object catch (error, stackTrace) {
      _log(
        error,
        stackTrace,
        AppErrorSource.module,
        'module "${module.id}" $what failed',
      );
    }
  }

  void _log(
    Object error,
    StackTrace? stackTrace,
    AppErrorSource source,
    String details, {
    bool fatal = false,
  }) {
    final record = AppErrorRecord.fromError(
      error,
      stackTrace,
      source: source,
      fatal: fatal,
    );
    errorLog.add(
      AppErrorRecord(
        time: record.time,
        source: record.source,
        summary: record.summary,
        details: details,
        stackTrace: record.stackTrace,
        fatal: record.fatal,
      ),
    );
  }
}

final class _ModuleAttempt {
  _ModuleAttempt(
    this.outcome,
    this.elapsed, {
    this.overrides,
    this.idleTasks = const [],
    this.error,
    this.stackTrace,
  });

  final StartupStepOutcome outcome;
  final Duration elapsed;
  final List<Override>? overrides;
  final List<AppIdleTask> idleTasks;
  final Object? error;
  final StackTrace? stackTrace;
}
