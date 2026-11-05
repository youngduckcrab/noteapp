/// The root widget before the ProviderScope exists, and the app entry
/// (docs/plans/01-infra.md 4.5.4, 6.4).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show kLocalOwnerId;

import '../app/lifecycle_bridge.dart';
import '../app/note_app.dart';
import '../app/strings.dart';
import '../errors/app_error_log.dart';
import '../errors/app_provider_observer.dart';
import '../errors/diagnostic_report.dart';
import '../errors/error_handlers.dart';
import '../modules/production_modules.dart';
import '../runtime/build_info.dart';
import '../runtime/runtime_info.dart';
import '../web/web_platform.dart';
import 'app_bootstrapper.dart';
import 'splash_view.dart';
import 'startup_error_screen.dart';

/// Root widget before the ProviderScope exists.
///
/// Splash while the bootstrapper runs; on success
/// `ProviderScope(key: ValueKey(attempt), overrides, observers:
/// [AppProviderObserver(errorLog)])` → AppLifecycleBridge → [appBuilder]; on
/// failure the StartupErrorScreen. "다시 시도" awaits the old bootstrapper's
/// shutdown() before it creates the next one; "데이터 지우기" does
/// shutdown() → resetLocalData() → retry.
class BootstrapApp extends StatefulWidget {
  const BootstrapApp({
    super.key,
    required this.createBootstrapper,
    required this.errorLog,
    this.appBuilder,
  });

  /// Called for the first attempt and for every retry — a retry calls it only
  /// after the previous bootstrapper's shutdown() completed (late-store
  /// cleanup included, 6.4 2-2).
  final AppBootstrapper Function() createBootstrapper;
  final AppErrorLog errorLog;

  /// Defaults to `(success) => const NoteApp()`. BootstrapApp puts an
  /// AppLifecycleBridge around it (6.4 step 3).
  final Widget Function(BootstrapSuccess success)? appBuilder;

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  late AppBootstrapper _bootstrapper;
  BootstrapResult? _result;
  int _attempt = 0;

  /// A retry or reset is running: further taps are ignored.
  bool _restarting = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    unawaited(_bootstrapper.shutdown());
    super.dispose();
  }

  void _start() {
    final bootstrapper = widget.createBootstrapper();
    _bootstrapper = bootstrapper;
    _result = null;
    unawaited(
      bootstrapper.run().then((result) {
        if (!mounted || !identical(bootstrapper, _bootstrapper)) return;
        setState(() => _result = result);
      }),
    );
  }

  Future<void> _retry() async {
    if (_restarting) return;
    _restarting = true;
    // Splash while the old attempt shuts down (late-start cleanup ≤ 2 s).
    setState(() => _result = null);
    try {
      await _bootstrapper.shutdown();
      if (!mounted) return;
      setState(() {
        _attempt++;
        _start();
      });
    } finally {
      _restarting = false;
    }
  }

  /// Throws when resetLocalData failed (the screen shows the message).
  Future<void> _reset(Future<void> Function() resetLocalData) async {
    if (_restarting) return;
    _restarting = true;
    try {
      // No open store while the data is erased (CORE 6.18).
      await _bootstrapper.shutdown();
      try {
        await resetLocalData();
      } on Object catch (error, stackTrace) {
        final record = AppErrorRecord.fromError(
          error,
          stackTrace,
          source: AppErrorSource.bootstrap,
        );
        widget.errorLog.add(
          AppErrorRecord(
            time: record.time,
            source: record.source,
            summary: record.summary,
            details: 'resetLocalData failed',
            stackTrace: record.stackTrace,
          ),
        );
        rethrow;
      }
      if (!mounted) return;
      setState(() {
        _attempt++;
        _start();
      });
    } finally {
      _restarting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_result) {
      null => _ShellFrame(
        child: SplashView(
          stageLabel: _bootstrapper.stageLabel,
          isSlow: _bootstrapper.isSlow,
        ),
      ),
      final BootstrapSuccess success => ProviderScope(
        key: ValueKey<int>(_attempt),
        overrides: success.overrides,
        observers: [AppProviderObserver(widget.errorLog)],
        child: AppLifecycleBridge(
          child: (widget.appBuilder ?? _defaultApp)(success),
        ),
      ),
      final BootstrapFailure failure => _ShellFrame(
        child: StartupErrorScreen(
          key: ValueKey<int>(_attempt),
          failure: failure,
          diagnostics: _diagnostics(failure),
          onRetry: () => unawaited(_retry()),
          onResetLocalData: switch (failure.resetLocalData) {
            null => null,
            final reset => () => _reset(reset),
          },
          onReload: _bootstrapper.web.isSupported
              ? _bootstrapper.web.reload
              : null,
        ),
      ),
    };
  }

  String _diagnostics(BootstrapFailure failure) => DiagnosticReport.format(
    build: _bootstrapper.buildInfo,
    runtime: _bootstrapper.runtimeInfo,
    startup: failure.report,
    storage: failure.report.storage,
    errors: widget.errorLog.records,
  );
}

Widget _defaultApp(BootstrapSuccess success) => const NoteApp();

/// MaterialApp for the splash and the startup error screen.
class _ShellFrame extends StatelessWidget {
  const _ShellFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      locale: const Locale('ko'),
      debugShowCheckedModeBanner: false,
      home: child,
    );
  }
}

/// Entry used by main.dart. Steps in 6.4.
Future<void> runNoteApp({
  AppBootstrapper Function()? createBootstrapper,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  final errorLog = AppErrorLog(capacity: 100);
  installGlobalErrorHandlers(errorLog);
  final buildInfo = BuildInfo.fromEnvironment();
  final web = createWebPlatform();
  final runtime = RuntimeInfo.detect(web);
  runApp(
    BootstrapApp(
      createBootstrapper:
          createBootstrapper ??
          () => AppBootstrapper(
            modules: productionModules(),
            buildInfo: buildInfo,
            runtimeInfo: runtime,
            web: web,
            errorLog: errorLog,
            ownerId: kLocalOwnerId,
          ),
      errorLog: errorLog,
    ),
  );
}
