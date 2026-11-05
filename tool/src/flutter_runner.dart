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
    this.interrupted = false,
  });

  /// Exit code; negative on POSIX when a signal ended the process (`-15` =
  /// SIGTERM).
  final int exitCode;

  /// Captured stdout and stderr (interleaved as received).
  final String output;

  /// The process was killed because it exceeded its time limit.
  final bool timedOut;

  /// `ws` itself is stopping (SIGINT / SIGTERM, [ChildTerminator]): the
  /// process was killed, or not started at all.
  final bool interrupted;

  /// A signal from outside ended the process (not the time limit, not `ws`
  /// stopping) — someone killed it, so the run should not go on.
  bool get killedBySignal => exitCode < 0 && !timedOut && !interrupted;
}

/// Runs processes. `ws` uses [IoProcessRunner]; tests use a fake.
abstract interface class ProcessRunner {
  /// Runs [executable] with [arguments] in [workingDirectory].
  ///
  /// [environment] entries are added to the parent environment. When
  /// [timeout] passes the process is killed and the result has `timedOut`.
  /// With [echo] `false` the output is only captured, not shown.
  Future<RunResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    Map<String, String> environment = const {},
    Duration? timeout,
    bool echo = true,
  });
}

/// Stops every child process of `ws` (SIGINT / SIGTERM handling, see
/// [TerminationGuard]).
abstract interface class ChildTerminator {
  /// Kills the process trees of the running children and refuses to start
  /// new ones. Completes when they are gone (or after the grace time).
  Future<void> terminateAll();
}

/// How long a killed process tree gets between SIGTERM and SIGKILL.
const Duration killGraceTime = Duration(seconds: 5);

/// How long the output pipes may stay open after the process exited (a
/// left-over grandchild can hold them) before `ws` stops reading.
const Duration outputDrainTime = Duration(seconds: 10);

/// Runs real processes, streaming their output to [out] while capturing it.
///
/// A process that exceeds its time limit is killed with its whole process
/// tree (`flutter test` starts Chrome, `flutter_tester` and compilers that
/// would otherwise outlive it and keep the output pipes open).
final class IoProcessRunner implements ProcessRunner, ChildTerminator {
  IoProcessRunner({StringSink? out}) : _out = out ?? stdout;

  final StringSink _out;

  final _running = <Process>{};
  bool _terminating = false;

  @override
  Future<RunResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    Map<String, String> environment = const {},
    Duration? timeout,
    bool echo = true,
  }) async {
    if (_terminating) return const RunResult(exitCode: -1, interrupted: true);
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: Platform.isWindows,
    );
    if (_terminating) {
      await killProcessTree(process.pid, exited: process.exitCode);
      return const RunResult(exitCode: -1, interrupted: true);
    }
    _running.add(process);
    final captured = StringBuffer();
    void forward(String chunk) {
      captured.write(chunk);
      if (echo) _out.write(chunk);
    }

    const decoder = Utf8Decoder(allowMalformed: true);
    final out = process.stdout.transform(decoder).listen(forward);
    final err = process.stderr.transform(decoder).listen(forward);
    // Taken now: a stream that ends before asFuture is called never
    // completes that future.
    final drained = Future.wait([out.asFuture<void>(), err.asFuture<void>()]);
    var timedOut = false;
    Timer? timer;
    Future<void>? killing;
    if (timeout != null) {
      timer = Timer(timeout, () {
        timedOut = true;
        killing = killProcessTree(process.pid, exited: process.exitCode);
      });
    }
    final exitCode = await process.exitCode;
    timer?.cancel();
    _running.remove(process);
    await killing;
    await drained.timeout(outputDrainTime, onTimeout: () => const []);
    await Future.wait([out.cancel(), err.cancel()]);
    return RunResult(
      exitCode: exitCode,
      output: captured.toString(),
      timedOut: timedOut,
      interrupted: _terminating && !timedOut,
    );
  }

  @override
  Future<void> terminateAll() async {
    _terminating = true;
    await Future.wait([
      for (final process in _running.toList())
        killProcessTree(process.pid, exited: process.exitCode),
    ]);
  }
}

/// The process ids of [root] and all its descendants, from `ps` (parents
/// before children). Just `[root]` when `ps` is not available.
Future<List<int>> processTree(int root) async {
  final children = <int, List<int>>{};
  try {
    final result = await Process.run('ps', const ['-A', '-o', 'pid=,ppid=']);
    if (result.exitCode == 0) {
      for (final line in '${result.stdout}'.split('\n')) {
        final fields = line.trim().split(RegExp(r'\s+'));
        if (fields.length != 2) continue;
        final pid = int.tryParse(fields[0]);
        final ppid = int.tryParse(fields[1]);
        if (pid != null && ppid != null) (children[ppid] ??= []).add(pid);
      }
    }
  } on ProcessException {
    // No `ps`: only the root is known.
  }
  final tree = <int>[root];
  for (var i = 0; i < tree.length; i++) {
    for (final child in children[tree[i]] ?? const <int>[]) {
      if (!tree.contains(child)) tree.add(child);
    }
  }
  return tree;
}

/// Kills the process [pid] and its descendants: SIGTERM to the whole tree
/// at once (taken before anything dies, so re-parented grandchildren are
/// not missed), up to [grace] for [exited], then SIGKILL to whatever of the
/// tree is left. Windows: `taskkill /T /F`.
Future<void> killProcessTree(
  int pid, {
  required Future<int> exited,
  Duration grace = killGraceTime,
}) async {
  if (Platform.isWindows) {
    await Process.run('taskkill', ['/PID', '$pid', '/T', '/F']);
    return;
  }
  final tree = await processTree(pid);
  for (final id in tree) {
    Process.killPid(id, ProcessSignal.sigterm);
  }
  await exited.timeout(grace, onTimeout: () => -1);
  final left = {...tree, ...await processTree(pid)};
  for (final id in left) {
    // Fails quietly (false) for the ids that already exited.
    Process.killPid(id, ProcessSignal.sigkill);
  }
}

/// SIGINT / SIGTERM handling of `ws`: on the first signal the running child
/// process trees are killed ([ChildTerminator.terminateAll]) and `ws` exits
/// with `128 + signal number` (130 / 143) — it never goes on with the next
/// member. A second signal exits at once.
final class TerminationGuard {
  TerminationGuard({
    required Stream<ProcessSignal> signals,
    required ChildTerminator children,
    required void Function(int code) exit,
    required StringSink err,
  }) : _terminator = children,
       _exitProcess = exit,
       _log = err {
    _subscription = signals.listen(_onSignal);
  }

  /// Watches the real SIGINT (and SIGTERM, not on Windows) of this process.
  /// [beforeExit] runs after the children are stopped, right before `exit`
  /// (releases the heavy test lock).
  factory TerminationGuard.watch(
    ChildTerminator children, {
    void Function()? beforeExit,
  }) {
    final watched = [
      ProcessSignal.sigint,
      if (!Platform.isWindows) ProcessSignal.sigterm,
    ];
    final signals = Stream<ProcessSignal>.multi((controller) {
      final subscriptions = [
        for (final signal in watched) signal.watch().listen(controller.add),
      ];
      controller.onCancel = () => Future.wait([
        for (final subscription in subscriptions) subscription.cancel(),
      ]);
    });
    return TerminationGuard(
      signals: signals,
      children: children,
      exit: (code) {
        beforeExit?.call();
        exit(code);
      },
      err: stderr,
    );
  }

  final ChildTerminator _terminator;
  final void Function(int code) _exitProcess;
  final StringSink _log;
  late final StreamSubscription<ProcessSignal> _subscription;
  final _finished = Completer<void>();
  bool _stopping = false;

  /// Whether a signal arrived.
  bool get stopping => _stopping;

  /// Completes after the guard called `exit` (with the real `exit` it never
  /// completes). The command that was running may return before that — it
  /// sees its processes die — so `main` waits for this instead of exiting
  /// with the command's own code.
  Future<void> get finished => _finished.future;

  Future<void> _onSignal(ProcessSignal signal) async {
    final code = 128 + signal.signalNumber;
    if (_stopping) {
      _exitProcess(code);
      return;
    }
    _stopping = true;
    _log.writeln('ws: $signal — stopping the running processes');
    try {
      await _terminator.terminateAll();
    } on Object catch (e) {
      _log.writeln('ws: could not stop every process: $e');
    }
    _exitProcess(code);
    if (!_finished.isCompleted) _finished.complete();
  }

  /// Stops watching (the command finished).
  Future<void> cancel() => _subscription.cancel();
}
