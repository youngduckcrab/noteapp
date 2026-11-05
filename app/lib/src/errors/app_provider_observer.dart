/// Riverpod failures into the error log (docs/plans/01-infra.md 4.5.3, 6.7).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_error_log.dart';

/// Logs providerDidFail to [log] with source provider.
final class AppProviderObserver extends ProviderObserver {
  AppProviderObserver(this.log);
  final AppErrorLog log;

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    final record = AppErrorRecord.fromError(
      error,
      stackTrace,
      source: AppErrorSource.provider,
    );
    final provider = context.provider;
    log.add(
      AppErrorRecord(
        time: record.time,
        source: record.source,
        summary: record.summary,
        details: 'provider: ${provider.name ?? provider.runtimeType}',
        stackTrace: record.stackTrace,
      ),
    );
  }
}
