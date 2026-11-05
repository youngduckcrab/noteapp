/// Locating and running `flutter`, `dart` and Chrome
/// (docs/plans/01-infra.md 4.2).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Names searched in `PATH` when `CHROME_EXECUTABLE` is not set, in order.
const List<String> chromeExecutableNames = [
  'google-chrome',
  'google-chrome-stable',
  'chromium',
  'chromium-browser',
];

/// Searches the `PATH` of [environment] for an executable called [name].
String? findOnPath(
  String name, {
  required Map<String, String> environment,
  required bool Function(String path) isFile,
  bool windows = false,
}) {
  final pathVariable = environment['PATH'] ?? environment['Path'] ?? '';
  final separator = windows ? ';' : ':';
  final candidates = windows ? ['$name.exe', '$name.bat', name] : [name];
  for (final dir in pathVariable.split(separator)) {
    if (dir.isEmpty) continue;
    for (final candidate in candidates) {
      final path = p.join(dir, candidate);
      if (isFile(path)) return path;
    }
  }
  return null;
}

/// Finds the `flutter` executable:
/// 1. `FLUTTER_BIN`
/// 2. `FLUTTER_ROOT/bin/flutter`
/// 3. `<root>/bin/flutter` when [resolvedExecutable] (the running Dart VM) is
///    `<root>/bin/cache/dart-sdk/bin/dart`
/// 4. `flutter` on `PATH`
///
/// Returns `null` when none exists.
String? locateFlutter({
  required Map<String, String> environment,
  required String resolvedExecutable,
  required bool Function(String path) isFile,
  bool windows = false,
}) {
  final executable = windows ? 'flutter.bat' : 'flutter';
  final fromEnv = environment['FLUTTER_BIN'];
  if (fromEnv != null && fromEnv.isNotEmpty && isFile(fromEnv)) return fromEnv;

  final flutterRoot = environment['FLUTTER_ROOT'];
  if (flutterRoot != null && flutterRoot.isNotEmpty) {
    final candidate = p.join(flutterRoot, 'bin', executable);
    if (isFile(candidate)) return candidate;
  }

  final parts = p.split(p.normalize(resolvedExecutable));
  final dartName = windows ? 'dart.exe' : 'dart';
  if (parts.length >= 6 &&
      parts[parts.length - 1] == dartName &&
      parts[parts.length - 2] == 'bin' &&
      parts[parts.length - 3] == 'dart-sdk' &&
      parts[parts.length - 4] == 'cache' &&
      parts[parts.length - 5] == 'bin') {
    final sdkRoot = p.joinAll(parts.sublist(0, parts.length - 5));
    final candidate = p.join(sdkRoot, 'bin', executable);
    if (isFile(candidate)) return candidate;
  }

  return findOnPath(
    'flutter',
    environment: environment,
    isFile: isFile,
    windows: windows,
  );
}

/// Finds Chrome for `flutter test --platform chrome`: `CHROME_EXECUTABLE` is
/// used as is when set; otherwise the first of [chromeExecutableNames] found
/// on `PATH`. Returns `null` when there is none.
String? locateChrome({
  required Map<String, String> environment,
  required bool Function(String path) isFile,
  bool windows = false,
}) {
  final fromEnv = environment['CHROME_EXECUTABLE'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  for (final name in chromeExecutableNames) {
    final found = findOnPath(
      name,
      environment: environment,
      isFile: isFile,
      windows: windows,
    );
    if (found != null) return found;
  }
  return null;
}

/// The outcome of one process run.
final class RunResult {
  const RunResult({
    required this.exitCode,
    this.output = '',
    this.timedOut = false,
  });

  final int exitCode;

  /// Captured stdout and stderr (interleaved as received).
  final String output;

  /// The process was killed because it exceeded its time limit.
  final bool timedOut;
}

/// Runs processes. `ws` uses [IoProcessRunner]; tests use a fake.
abstract interface class ProcessRunner {
  /// Runs [executable] with [arguments] in [workingDirectory].
  ///
  /// [environment] entries are added to the parent environment. When
  /// [timeout] passes the process is killed and the result has `timedOut`.
  Future<RunResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    Map<String, String> environment = const {},
    Duration? timeout,
  });
}

/// Runs real processes, streaming their output to [out] while capturing it.
final class IoProcessRunner implements ProcessRunner {
  IoProcessRunner({StringSink? out}) : _out = out ?? stdout;

  final StringSink _out;

  @override
  Future<RunResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    Map<String, String> environment = const {},
    Duration? timeout,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: Platform.isWindows,
    );
    final captured = StringBuffer();
    void forward(String chunk) {
      captured.write(chunk);
      _out.write(chunk);
    }

    final done = Future.wait([
      process.stdout.transform(utf8.decoder).forEach(forward),
      process.stderr.transform(utf8.decoder).forEach(forward),
    ]);
    var timedOut = false;
    Timer? timer;
    if (timeout != null) {
      timer = Timer(timeout, () {
        timedOut = true;
        process.kill();
      });
    }
    final exitCode = await process.exitCode;
    timer?.cancel();
    await done;
    return RunResult(
      exitCode: exitCode,
      output: captured.toString(),
      timedOut: timedOut,
    );
  }
}
