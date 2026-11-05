// AppErrorLog / AppErrorRecord (docs/plans/01-infra.md 4.5.3 and 9.1).

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noteapp/src/errors/app_error_log.dart';

AppErrorRecord record(String summary) => AppErrorRecord(
  time: DateTime.utc(2026, 11, 4),
  source: AppErrorSource.manual,
  summary: summary,
);

void main() {
  test('keeps the newest records up to capacity; totalCount counts all', () {
    final log = AppErrorLog(capacity: 3);
    for (var i = 1; i <= 5; i++) {
      log.add(record('e$i'));
    }
    expect(log.records.map((r) => r.summary), ['e3', 'e4', 'e5']);
    expect(log.totalCount, 5);
    expect(log.capacity, 3);
    expect(AppErrorLog().capacity, 100);
  });

  test('records is an unmodifiable snapshot, oldest first', () {
    final log = AppErrorLog()..add(record('a'));
    final snapshot = log.records;
    expect(() => snapshot.add(record('x')), throwsUnsupportedError);
    log.add(record('b'));
    expect(snapshot.length, 1);
    expect(log.records.map((r) => r.summary), ['a', 'b']);
  });

  test('add and clear notify listeners; clear keeps totalCount', () {
    final log = AppErrorLog();
    var calls = 0;
    log.addListener(() => calls++);
    log
      ..add(record('a'))
      ..add(record('b'));
    expect(calls, 2);
    log.clear();
    expect(calls, 3);
    expect(log.records, isEmpty);
    expect(log.totalCount, 2);
    log.clear(); // already empty: no notification
    expect(calls, 3);
    log.dispose();
  });

  test('fromFlutterErrorDetails: summary, context + library, truncation', () {
    final now = DateTime.utc(2026, 11, 4, 9);
    final details = FlutterErrorDetails(
      exception: StateError('x' * 500),
      stack: StackTrace.fromString('#0 frame\n' * 1000),
      library: 'feature_editor',
      context: ErrorDescription('while building EditorScreen'),
    );
    final r = AppErrorRecord.fromFlutterErrorDetails(details, now: now);
    expect(r.time, now);
    expect(r.source, AppErrorSource.flutter);
    expect(r.summary.length, 300);
    expect(r.summary, startsWith('Bad state: xxx'));
    expect(r.summary, endsWith('…'));
    expect(r.details, 'while building EditorScreen (feature_editor)');
    expect(r.stackTrace!.length, 4000);
    expect(r.fatal, isFalse);

    final bare = AppErrorRecord.fromFlutterErrorDetails(
      FlutterErrorDetails(exception: Exception('short')),
    );
    expect(bare.summary, 'Exception: short');
    expect(bare.details, '(Flutter framework)'); // default library
    expect(bare.stackTrace, isNull);
  });

  test('fromError: summary from toString, source and fatal kept', () {
    final r = AppErrorRecord.fromError(
      ArgumentError('bad'),
      StackTrace.fromString('#0 main'),
      source: AppErrorSource.module,
      fatal: true,
      now: DateTime.utc(2026),
    );
    expect(r.summary, 'Invalid argument(s): bad');
    expect(r.stackTrace, '#0 main');
    expect(r.source, AppErrorSource.module);
    expect(r.fatal, isTrue);
    expect(
      AppErrorRecord.fromError(
        'boom',
        null,
        source: AppErrorSource.bootstrap,
      ).stackTrace,
      isNull,
    );
  });
}
