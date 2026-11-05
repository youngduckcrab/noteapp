// A scriptable fake ProcessRunner for the ws command tests: no real process
// is started.

import '../../src/flutter_runner.dart';

/// One recorded call.
final class FakeCall {
  FakeCall(
    this.executable,
    this.arguments,
    this.workingDirectory,
    this.environment,
    this.echo,
  );

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final Map<String, String> environment;
  final bool echo;

  @override
  String toString() => '$executable ${arguments.join(' ')} @ $workingDirectory';
}

/// Answers each call with [handler] (default: exit code 0, no output).
final class FakeProcesses implements ProcessRunner {
  FakeProcesses([RunResult Function(FakeCall call)? handler])
    : handler = handler ?? ((_) => const RunResult(exitCode: 0));

  RunResult Function(FakeCall call) handler;

  final calls = <FakeCall>[];

  @override
  Future<RunResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    Map<String, String> environment = const {},
    Duration? timeout,
    bool echo = true,
  }) async {
    final call = FakeCall(
      executable,
      List.unmodifiable(arguments),
      workingDirectory,
      environment,
      echo,
    );
    calls.add(call);
    return handler(call);
  }
}
