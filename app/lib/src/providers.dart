/// Shell-level providers (docs/plans/01-infra.md 4.5.10, 6.8). Names are
/// unique in the whole workspace (계약 7.4.4).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:note_core/note_core.dart';

import 'bootstrap/app_bootstrapper.dart';
import 'bootstrap/startup_report.dart';
import 'errors/app_error_log.dart';
import 'routing/app_navigator.dart';
import 'routing/app_router.dart';
import 'routing/screen_builders.dart';
import 'runtime/build_info.dart';
import 'runtime/runtime_info.dart';
import 'web/web_platform.dart';

// Overridden by BootstrapApp with values created before the scope
// (계약 7.3.3 '셸 provider').
final buildInfoProvider = Provider<BuildInfo>(
  (ref) => BuildInfo.fromEnvironment(),
  name: 'buildInfoProvider',
);
final webPlatformProvider = Provider<WebPlatform>(
  (ref) => createWebPlatform(),
  name: 'webPlatformProvider',
);
final runtimeInfoProvider = Provider<RuntimeInfo>(
  (ref) => RuntimeInfo.detect(ref.watch(webPlatformProvider)),
  name: 'runtimeInfoProvider',
);
final appErrorLogProvider = Provider<AppErrorLog>(
  (ref) => throw UnimplementedError(
    'appErrorLogProvider must be overridden by the app shell',
  ),
  name: 'appErrorLogProvider',
);
final startupReportProvider = Provider<StartupReport>(
  (ref) => throw UnimplementedError(
    'startupReportProvider must be overridden by the app shell',
  ),
  name: 'startupReportProvider',
);
final appBootstrapperProvider = Provider<AppBootstrapper>(
  (ref) => throw UnimplementedError(
    'appBootstrapperProvider must be overridden by the app shell',
  ),
  name: 'appBootstrapperProvider',
);

// Not overridden in production (tests override appScreenBuildersProvider).
final appScreenBuildersProvider = Provider<AppScreenBuilders>(
  (ref) => AppScreenBuilders.production(),
  name: 'appScreenBuildersProvider',
);
final appRouterProvider = Provider<GoRouter>((ref) {
  final router = createAppRouter(screens: ref.watch(appScreenBuildersProvider));
  ref.onDispose(router.dispose);
  return router;
}, name: 'appRouterProvider');
final appNavigatorProvider = Provider<AppNavigator>(
  (ref) => GoRouterAppNavigator(ref.watch(appRouterProvider)),
  name: 'appNavigatorProvider',
);

/// CORE StorageInfo re-queried (persisted() / estimate() inside CORE) each
/// time the storage section or a diagnostics copy needs it. The app shell's
/// ONLY caller of refreshStorageInfo(). 계약 7.2.12 (v1.1, C11-10): after it
/// returns, invalidate storageInfoProvider (a plain Provider that never
/// re-reads by itself) so other screens — LIBRARY / EDITOR banners,
/// diagnostics — see the new persistGranted / usage; this provider's own
/// readers use the returned value. backend / isDurable never change at
/// runtime, so the notDurable banner decision is unaffected.
/// `ref.mounted` guards the case where the section was closed during the
/// await — that value then reaches other screens with the next refresh.
final latestStorageInfoProvider = FutureProvider.autoDispose<StorageInfo>(
  (ref) async {
    final info = await ref.watch(noteStoreProvider).refreshStorageInfo();
    if (ref.mounted) ref.invalidate(storageInfoProvider);
    return info;
  },
  retry: noRetry,
  name: 'latestStorageInfoProvider',
);
