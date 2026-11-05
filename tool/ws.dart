/// Workspace tool: `dart run tool/ws.dart <command>` from the repository root
/// (INFRA, docs/plans/01-infra.md 4.2). See `src/cli.dart` for the commands.
library;

import 'dart:io';

import 'src/cli.dart';
import 'src/flutter_runner.dart';

Future<void> main(List<String> arguments) async {
  final processes = IoProcessRunner();
  // SIGINT / SIGTERM: kill the running flutter / Chrome process trees and
  // exit 130 / 143 instead of going on with the next member.
  final guard = TerminationGuard.watch(processes);
  final code = await runWs(arguments, context: WsContext(processes: processes));
  // A signal arrived: the guard exits with 130 / 143 once the process trees
  // are gone.
  if (guard.stopping) await guard.finished;
  await guard.cancel();
  await Future.wait([stdout.flush(), stderr.flush()]);
  exit(code);
}
