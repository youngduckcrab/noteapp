import 'dart:async';

import 'package:feature_editor/feature_editor.dart'
    show
        StylusExtraEvent,
        StylusExtrasSource,
        editorSettingsProvider,
        stylusExtrasProvider;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';

import '../app/strings.dart';
import '../bootstrap/startup_report.dart';
import '../errors/app_error_log.dart';
import '../errors/diagnostic_report.dart';
import '../features/app_features.dart';
import '../features/feature_status.dart';
import '../pencil/pencil_stylus_extras.dart';
import '../providers.dart';
import '../update/update_checker.dart';
import 'backup_export.dart';
import 'backup_sheet.dart';
import 'developer_mode.dart';

/// '앱 정보': build label, renderer, standalone, startup times, error count
/// + list, "진단 정보 복사", "새 버전 확인", "백업 내보내기",
/// "오픈소스 라이선스" (showLicensePage). (v2.14-ui, UI stage 1) The 빌드 row
/// tapped [DeveloperModeTapCounter.tapsToToggle] times toggles developer mode
/// (snack bar '개발자 모드를 켰어요' / '껐어요'); the renderer, standalone and
/// startup-time rows and "진단 정보 복사" show only in developer mode.
/// "백업 내보내기": prepareBackup() with a progress row (button disabled):
/// spinner + '백업을 만드는 중…' + [취소]. [취소] calls
/// BackupCancelToken.cancel() → prepareBackup returns null at once, the
/// button is enabled again, no snackbar, no errorLog record (only the wait
/// ends; CORE's write queue keeps retrying — 계약 7.2.9 v1.2, C12-09).
/// While waiting, if storageWarningOf(storageInfoProvider,
/// persistenceStatusProvider) == StorageWarning.writeFailing the row adds
/// '저장이 늦어지고 있어요. 저장 공간을 확인해 주세요.'.
/// On a BackupFile → BackupReadySheet; the sheet's buttons call
/// deliverBackup() from their own tap (fresh user activation for share /
/// download).
/// 2차 (6.12.3, 6.18): when stylusExtrasProvider.isSupported, an 'Apple
/// Pencil' row — 'iOS 17.5 · 더블탭 · 호버' from the start-time capabilities,
/// '· 스퀴즈(받음)' / '· 롤(받음)' only after this run has received one. While
/// shown, the section listens to the stylus events itself, so a squeeze on
/// the settings screen counts too.
/// 2차 (6.18): a '기능' row (key app.about.features) — '녹음 켬 · 인식
/// 꺼짐(개발자 메뉴) · 수식 엔진 꺼짐(빌드)' from [compileTime],
/// appFeaturesProvider (what the modules saw at this start) and the feature
/// modules' startup steps ('시작 실패'); the same line goes into "진단 정보
/// 복사".
class AboutSection extends ConsumerStatefulWidget {
  const AboutSection({super.key, this.compileTime = AppFeatures.compileTime});

  /// The FEATURE_* build values (tests pass other builds).
  final AppFeatures compileTime;

  /// (v2.14-ui) The 빌드 row (7 taps → developer mode).
  static const buildRowKey = ValueKey<String>('app.about.build');

  @override
  ConsumerState<AboutSection> createState() => _AboutSectionState();
}

/// Newest error records listed in the section.
const int _shownErrors = 5;

class _AboutSectionState extends ConsumerState<AboutSection> {
  final DeveloperModeTapCounter _devTaps = DeveloperModeTapCounter();

  AppErrorLog? _errorLog;
  bool _errorRebuildScheduled = false;
  BackupCancelToken? _backup;
  bool _checking = false;
  StylusExtrasSource? _pencil;
  StreamSubscription<StylusExtraEvent>? _pencilEvents;

  @override
  void dispose() {
    _errorLog?.removeListener(_onErrorsChanged);
    unawaited(_pencilEvents?.cancel());
    // Leaving the screen ends the wait (nothing is shown afterwards).
    _backup?.cancel();
    super.dispose();
  }

  /// AppErrorLog notifies synchronously, possibly during a build
  /// (FlutterError.onError): rebuild after the frame.
  void _onErrorsChanged() {
    if (_errorRebuildScheduled) return;
    _errorRebuildScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _errorRebuildScheduled = false;
      if (mounted) setState(() {});
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _listenTo(AppErrorLog log) {
    if (identical(log, _errorLog)) return;
    _errorLog?.removeListener(_onErrorsChanged);
    _errorLog = log..addListener(_onErrorsChanged);
  }

  /// Keeps one subscription to the supported stylus source while shown: the
  /// pencil adapter notes squeeze / roll for every listener (its `seen`).
  void _listenToPencil(StylusExtrasSource source) {
    if (identical(source, _pencil)) return;
    unawaited(_pencilEvents?.cancel());
    _pencil = source;
    _pencilEvents = source.isSupported
        ? source.events.listen((_) {}, onError: (Object _) {})
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final build = ref.watch(buildInfoProvider);
    final runtime = ref.watch(runtimeInfoProvider);
    final report = ref.watch(startupReportProvider);
    final errorLog = ref.watch(appErrorLogProvider);
    _listenTo(errorLog);
    final update = ref.watch(updateCheckerProvider);
    final pencil = ref.watch(stylusExtrasProvider);
    _listenToPencil(pencil);
    // Keeps the re-queried StorageInfo alive for "진단 정보 복사" (6.8: the
    // diagnostics copy reads latestStorageInfoProvider; no await before the
    // clipboard write).
    ref.listen(latestStorageInfoProvider, (_, _) {});

    final backup = _backup;
    var slowWrites = false;
    if (backup != null) {
      final status =
          ref.watch(persistenceStatusProvider).value ??
          ref.watch(noteStoreProvider).persistenceStatus;
      slowWrites =
          storageWarningOf(ref.watch(storageInfoProvider), status) ==
          StorageWarning.writeFailing;
    }

    final theme = Theme.of(context);
    final developer = ref.watch(developerModeProvider);
    final records = errorLog.records;
    final shown = records.length <= _shownErrors
        ? records
        : records.sublist(records.length - _shownErrors);
    final steps = [for (final step in report.steps) _stepText(step)];
    final features = _featureStates(report, ref.watch(appFeaturesProvider));
    final featuresOff = features.values.any((s) => s != AppFeatureState.on);
    final remote = switch (update) {
      UpdateAvailable(:final remote) ||
      UpdateDismissed(:final remote) => remote,
      _ => null,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: AboutSection.buildRowKey,
          onTap: _onBuildRowTap,
          child: _InfoRow(
            label: AppStrings.aboutBuild,
            value: build.displayLabel,
          ),
        ),
        if (developer) ...[
          _InfoRow(
            label: AppStrings.aboutRenderer,
            value: runtime.rendererLabel,
          ),
          _InfoRow(
            label: AppStrings.aboutStandalone,
            value: runtime.isStandalone ? AppStrings.yes : AppStrings.no,
          ),
        ],
        if (pencil.isSupported)
          switch (pencil) {
            final PencilStylusExtrasSource adapter => ValueListenableBuilder(
              valueListenable: adapter.seen,
              builder: (context, seen, _) => _InfoRow(
                key: const ValueKey<String>('app.about.pencil'),
                label: AppStrings.aboutPencil,
                value: _pencilLine(pencil, os: adapter.os, seen: seen),
              ),
            ),
            _ => _InfoRow(
              key: const ValueKey<String>('app.about.pencil'),
              label: AppStrings.aboutPencil,
              value: _pencilLine(pencil),
            ),
          },
        _InfoRow(
          key: const ValueKey<String>('app.about.features'),
          label: AppStrings.aboutFeatures,
          value: appFeatureStatusLine(features),
          warn: featuresOff,
        ),
        if (developer)
          _InfoRow(
            label: AppStrings.aboutStartup,
            value: [
              AppStrings.aboutStartupTimes(
                report.sinceNavigationStart?.inMilliseconds,
                report.bootstrapElapsed.inMilliseconds,
              ),
              if (steps.isNotEmpty) steps.join(' · '),
            ].join('\n'),
          ),
        _InfoRow(
          label: AppStrings.aboutErrors,
          value: errorLog.totalCount == 0
              ? AppStrings.none
              : AppStrings.aboutErrorCount(errorLog.totalCount),
          warn: errorLog.totalCount > 0,
        ),
        for (var i = shown.length - 1; i >= 0; i--)
          Padding(
            key: ValueKey<String>('about-error-$i'),
            padding: const EdgeInsets.only(left: 172, bottom: 4),
            child: Text(
              '${_clockTime(shown[i].time)} ${shown[i].source.name}'
              '${shown[i].fatal ? ' (fatal)' : ''} — ${shown[i].summary}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
        _InfoRow(
          label: AppStrings.aboutUpdate,
          value: switch (update) {
            UpdateDisabled() => AppStrings.updateDisabled,
            UpdateUnknown() => AppStrings.updateUnknown,
            UpdateUpToDate(:final checkedAt) => AppStrings.updateUpToDate(
              _clockTime(checkedAt),
            ),
            UpdateAvailable(:final remote) || UpdateDismissed(:final remote) =>
              AppStrings.updateFound(remote.buildNumber, remote.shortSha),
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (developer)
              OutlinedButton.icon(
                key: const Key('about-copy-diagnostics'),
                onPressed: _copyDiagnostics,
                icon: const Icon(Icons.copy),
                label: const Text(AppStrings.copyDiagnostics),
              ),
            OutlinedButton.icon(
              key: const Key('about-check-update'),
              onPressed: update is UpdateDisabled || _checking
                  ? null
                  : _checkForUpdate,
              icon: const Icon(Icons.system_update_alt),
              label: const Text(AppStrings.checkForUpdate),
            ),
            if (remote != null)
              FilledButton.icon(
                key: const Key('about-apply-update'),
                onPressed: () => unawaited(
                  ref.read(updateCheckerProvider.notifier).applyUpdate(),
                ),
                icon: const Icon(Icons.refresh),
                label: const Text(AppStrings.reload),
              ),
            OutlinedButton.icon(
              key: const Key('about-backup'),
              onPressed: backup == null ? _startBackup : null,
              icon: const Icon(Icons.save_alt),
              label: const Text(AppStrings.backupExport),
            ),
            OutlinedButton.icon(
              key: const Key('about-licenses'),
              onPressed: () => showLicensePage(
                context: context,
                applicationName: AppStrings.appName,
                applicationVersion: build.displayLabel,
              ),
              icon: const Icon(Icons.description_outlined),
              label: const Text(AppStrings.licenses),
            ),
          ],
        ),
        if (backup != null)
          _BackupProgress(
            slowWrites: slowWrites,
            onCancel: () => _cancelBackup(backup),
          ),
      ],
    );
  }

  Map<AppFeature, AppFeatureState> _featureStates(
    StartupReport report,
    AppFeatures started,
  ) => appFeatureStatesOf(
    compileTime: widget.compileTime,
    started: started,
    steps: report.steps,
  );

  /// (v2.14-ui) The 7th quick tap on the 빌드 row flips the stored switch.
  /// (review) From the [DeveloperModeTapCounter.hintFrom]th tap a snackbar
  /// counts the taps left; after the flip it says the effective state — still
  /// on while the developer overlay or `?dev=1` keeps it on.
  Future<void> _onBuildRowTap() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    // remove (not hide): quick taps replace the snack bar at once instead of
    // queueing behind the one sliding out.
    void show(String text) => messenger
      ?..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
    if (!_devTaps.tap()) {
      final left = DeveloperModeTapCounter.tapsToToggle - _devTaps.count;
      if (_devTaps.count >= DeveloperModeTapCounter.hintFrom) {
        show(AppStrings.developerModeTapsLeft(left));
      }
      return;
    }
    final on = await toggleStoredDeveloperMode(
      ref.read(settingsRepositoryProvider),
    );
    if (!mounted) return;
    final keptOn =
        ref.read(editorSettingsProvider.select((s) => s.showDevOverlay)) ||
        ref.read(appDevUrlFlagProvider);
    show(
      on
          ? AppStrings.developerModeOn
          : keptOn
          ? AppStrings.developerModeStillOn
          : AppStrings.developerModeOff,
    );
  }

  Future<void> _copyDiagnostics() async {
    final messenger = ScaffoldMessenger.of(context);
    final startup = ref.read(startupReportProvider);
    final text = DiagnosticReport.format(
      build: ref.read(buildInfoProvider),
      runtime: ref.read(runtimeInfoProvider),
      startup: startup,
      features: _featureStates(startup, ref.read(appFeaturesProvider)),
      storage:
          ref.read(latestStorageInfoProvider).value ??
          ref.read(storageInfoProvider),
      persistence:
          ref.read(persistenceStatusProvider).value ??
          ref.read(noteStoreProvider).persistenceStatus,
      errors: ref.read(appErrorLogProvider).records,
    );
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(
      const SnackBar(content: Text(AppStrings.diagnosticsCopied)),
    );
  }

  Future<void> _checkForUpdate() async {
    setState(() => _checking = true);
    try {
      await ref.read(updateCheckerProvider.notifier).checkNow();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _cancelBackup(BackupCancelToken token) {
    token.cancel();
    if (identical(_backup, token)) setState(() => _backup = null);
  }

  Future<void> _startBackup() async {
    if (_backup != null) return;
    final messenger = ScaffoldMessenger.of(context);
    final store = ref.read(noteStoreProvider);
    final errorLog = ref.read(appErrorLogProvider);
    final web = ref.read(webPlatformProvider);
    final token = BackupCancelToken();
    setState(() => _backup = token);

    final file = await prepareBackup(
      store: store,
      errorLog: errorLog,
      cancel: token,
    );
    if (token.isCancelled || !mounted) return;
    setState(() => _backup = null);
    if (file == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text(AppStrings.backupFailed)),
      );
      return;
    }

    final outcome = await showModalBottomSheet<BackupExportOutcome>(
      context: context,
      builder: (context) =>
          BackupReadySheet(file: file, web: web, errorLog: errorLog),
    );
    final message = switch (outcome) {
      BackupExportOutcome.downloaded => AppStrings.backupDownloaded,
      BackupExportOutcome.shared => AppStrings.backupShared,
      BackupExportOutcome.unsupported => AppStrings.backupUnsupported,
      BackupExportOutcome.failed => AppStrings.backupFailed,
      BackupExportOutcome.cancelled || null => null,
    };
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

/// Spinner + '백업을 만드는 중…' + [취소], and the slow-write note.
class _BackupProgress extends StatelessWidget {
  const _BackupProgress({required this.slowWrites, required this.onCancel});

  final bool slowWrites;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const Key('about-backup-progress'),
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Text(AppStrings.backupPreparing)),
              TextButton(
                key: const Key('about-backup-cancel'),
                onPressed: onCancel,
                child: const Text(AppStrings.cancel),
              ),
            ],
          ),
          if (slowWrites)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 32),
              child: Text(
                AppStrings.backupSlowWrites,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One `label · value` line. The value wraps; the label column is fixed.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.warn = false,
  });

  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: warn ? scheme.error : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `core 120ms`, `pdf 30ms (failedNonCritical)`.
String _stepText(StartupStep step) {
  final ms = AppStrings.groupDigits(step.elapsed.inMilliseconds);
  final outcome = step.outcome == StartupStepOutcome.ok
      ? ''
      : ' (${step.outcome.name})';
  return '${step.id} ${ms}ms$outcome';
}

/// `18:20:31` (local time).
/// 'iOS 17.5 · 더블탭 · 호버 · 스퀴즈(받음)' (6.12.3): the start-time
/// capabilities, squeeze / roll only once received (they are OS
/// availability, not the pencil model). os '?' = the capabilities read
/// failed (kPencilFallbackCapabilities).
String _pencilLine(
  StylusExtrasSource source, {
  String os = '',
  ({bool squeeze, bool roll}) seen = (squeeze: false, roll: false),
}) {
  final capabilities = source.capabilities;
  return [
    if (os == '?')
      AppStrings.aboutPencilUnread
    else if (os.isNotEmpty)
      AppStrings.aboutPencilOs(os),
    if (capabilities.doubleTap) AppStrings.aboutPencilDoubleTap,
    if (capabilities.hoverPose) AppStrings.aboutPencilHover,
    if (seen.squeeze) AppStrings.aboutPencilSqueezeSeen,
    if (seen.roll) AppStrings.aboutPencilRollSeen,
  ].join(' · ');
}

String _clockTime(DateTime time) {
  final t = time.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}
