/// Shell-level providers (docs/plans/01-infra.md 4.5.10, 6.8). Names are
/// unique in the whole workspace (계약 7.4.4).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
