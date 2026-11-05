/// Global error hooks of the app shell (docs/plans/01-infra.md 4.5.3, 6.7).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app_error_log.dart';
import 'app_error_widget.dart';

/// Installs FlutterError.onError, PlatformDispatcher.instance.onError and,
/// in release mode, ErrorWidget.builder = appErrorWidgetBuilder.
/// Previous handlers are chained (called after logging).
/// Returns a callback that restores the previous handlers (for tests).
///
/// With [presentToConsole] the Flutter error is also dumped with
/// FlutterError.presentError (the previous handler is not called a second
/// time when it is that same default).
VoidCallback installGlobalErrorHandlers(
  AppErrorLog log, {
  bool presentToConsole = true,
}) {
  final dispatcher = PlatformDispatcher.instance;
  final previousFlutter = FlutterError.onError;
  final previousPlatform = dispatcher.onError;
  final previousErrorWidget = ErrorWidget.builder;

  FlutterError.onError = (details) {
    log.add(AppErrorRecord.fromFlutterErrorDetails(details));
    if (presentToConsole) FlutterError.presentError(details);
    if (previousFlutter != null &&
        !identical(previousFlutter, FlutterError.presentError)) {
      previousFlutter(details);
    }
  };
  dispatcher.onError = (error, stack) {
    log.add(
      AppErrorRecord.fromError(error, stack, source: AppErrorSource.platform),
    );
    previousPlatform?.call(error, stack);
    // Handled: keep the app running.
    return true;
  };
  if (kReleaseMode) ErrorWidget.builder = appErrorWidgetBuilder;

  return () {
    FlutterError.onError = previousFlutter;
    dispatcher.onError = previousPlatform;
    ErrorWidget.builder = previousErrorWidget;
  };
}
