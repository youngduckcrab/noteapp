// Helpers of the CORE T18 performance budget tests (9.1, `@Tags(['perf'])`, skipped by
// default; run with `flutter test --run-skipped -t perf`). Budgets are for a 4-CPU
// container; every measurement is printed as the record of the run.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:note_core/note_core.dart';
import 'package:note_core/testing_vm.dart';
import 'package:test/test.dart';

/// Milliseconds of [d] with two decimals.
String ms(Duration d) => (d.inMicroseconds / 1000).toStringAsFixed(2);

/// The median of [values] (sorted copy).
Duration median(List<Duration> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

/// The mean of [values].
Duration mean(List<Duration> values) => Duration(
  microseconds:
      values.fold<int>(0, (sum, d) => sum + d.inMicroseconds) ~/ values.length,
);

/// How long [action] takes.
Future<(T, Duration)> timed<T>(Future<T> Function() action) async {
  final sw = Stopwatch()..start();
  final value = await action();
  sw.stop();
  return (value, sw.elapsed);
}

/// Prints the measurement and, with [budget], expects it below the budget.
void record(String name, Duration value, {Duration? budget, String? note}) {
  final limit = budget == null ? 'record only' : 'budget < ${ms(budget)} ms';
  print(
    '[perf] $name: ${ms(value)} ms ($limit)${note == null ? '' : ' $note'}',
  );
  if (budget != null) {
    expect(value, lessThan(budget), reason: '$name over its budget (9.1)');
  }
}

/// A file database in a new temporary directory, deleted after the test.
Future<String> tempDatabasePath(String tag) async {
  final dir = await Directory.systemTemp.createTemp('note_core_perf_${tag}_');
  addTearDown(() => dir.delete(recursive: true));
  return '${dir.path}/notes.db';
}

/// The SQLite store on [path] (closed after the test).
Future<NoteStore> openFileStore(String path) async {
  final store = await openTestNoteStore(filePath: path);
  addTearDown(store.close);
  return store;
}

/// (v2, m5-7 T35) The native store of openNoteStore — a file database (WAL, background
/// isolate) plus file blobs (6.15.3) — in a new temporary directory, closed and deleted
/// after the test.
Future<NoteStore> openNativeFileStore(String tag) async {
  final dir = await Directory.systemTemp.createTemp('note_core_perf_${tag}_');
  addTearDown(() => dir.delete(recursive: true));
  final store = await openNoteStore(
    NoteStoreConfig(
      nativeDatabasePath: '${dir.path}/notes.db',
      nativeAssetDirectoryPath: '${dir.path}/assets',
    ),
  );
  addTearDown(store.close);
  return store;
}
