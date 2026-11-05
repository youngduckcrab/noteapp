/// R14 resolver process (INFRA, integration step G3, docs/plans/01-infra.md
/// 6.2): `dart run tool/export_names.dart --out <file> <entry.dart>...`.
/// `ws check` runs it (see `src/export_names.dart`); it is a separate script
/// so that only R14 pays for compiling `package:analyzer`.
library;

import 'dart:io';

import 'src/export_namespace.dart';

Future<void> main(List<String> arguments) async {
  final code = await exportNamesMain(arguments);
  await Future.wait([stdout.flush(), stderr.flush()]);
  exit(code);
}
