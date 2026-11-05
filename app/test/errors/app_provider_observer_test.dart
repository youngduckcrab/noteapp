// AppProviderObserver (docs/plans/01-infra.md 4.5.3, 6.7 and 9.1).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/errors/app_provider_observer.dart';

final _failing = Provider<int>(
  (ref) => throw StateError('provider broke'),
  name: 'failingProvider',
);

final _working = Provider<int>((ref) => 1, name: 'workingProvider');

void main() {
  test('a failing provider is logged with source provider and its name', () {
    final log = AppErrorLog();
    final container = ProviderContainer.test(
      observers: [AppProviderObserver(log)],
      retry: (retryCount, error) => null,
    );
    expect(container.read(_working), 1);
    expect(log.records, isEmpty);

    expect(() => container.read(_failing), throwsA(anything));
    final record = log.records.single;
    expect(record.source, AppErrorSource.provider);
    expect(record.summary, 'Bad state: provider broke');
    expect(record.details, 'provider: failingProvider');
    expect(record.stackTrace, isNotNull);
  });
}
