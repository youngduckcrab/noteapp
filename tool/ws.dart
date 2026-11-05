/// Workspace tool: `dart run tool/ws.dart <command>` from the repository root
/// (INFRA, docs/plans/01-infra.md 4.2). See `src/cli.dart` for the commands.
library;

import 'dart:io';

import 'src/cli.dart';

Future<void> main(List<String> arguments) async {
  final code = await runWs(arguments);
  await Future.wait([stdout.flush(), stderr.flush()]);
  exit(code);
}
