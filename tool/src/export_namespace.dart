/// The analyzer half of R14 (`export_names.dart`): resolves each entry point
/// with `package:analyzer` 13.3.0 (`AnalysisContextCollection` →
/// `getResolvedLibrary` → `exportNamespace.definedNames2`, docs/plans/
/// 01-infra.md 6.2) and writes an [ExportNamesReport]. Runs only in the
/// resolver process `dart run tool/export_names.dart` — `ws` itself never
/// imports this file (it would make every `ws` command ~12 s slower).
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'export_names.dart';

/// Resolves the export namespace of every file in [paths] (absolute). An
/// entry point is unresolved when it is not a library, or when its own
/// units have errors (an unresolved `export` URI makes the namespace
/// incomplete — e.g. `flutter pub get` was not run).
Future<ExportNamesReport> resolveExportNames(
  List<String> paths, {
  String? sdkPath,
}) async {
  final files = [for (final path in paths) p.normalize(p.absolute(path))];
  final names = <String, Set<String>>{};
  final unresolved = <String, String>{};
  final existing = <String>[];
  for (final file in files) {
    if (File(file).existsSync()) {
      existing.add(file);
    } else {
      unresolved[file] = 'file not found';
    }
  }
  if (existing.isEmpty) {
    return ExportNamesReport(names: names, unresolved: unresolved);
  }
  final collection = AnalysisContextCollection(
    includedPaths: existing,
    sdkPath: sdkPath,
  );
  try {
    for (final file in existing) {
      final session = collection.contextFor(file).currentSession;
      final result = await session.getResolvedLibrary(file);
      if (result is! ResolvedLibraryResult) {
        unresolved[file] = switch (result) {
          NotLibraryButPartResult() => 'a part file, not a library',
          _ => 'not resolved (${result.runtimeType})',
        };
        continue;
      }
      final errors = [
        for (final unit in result.units)
          for (final diagnostic in unit.diagnostics)
            if (diagnostic.severity == Severity.error) diagnostic,
      ];
      if (errors.isNotEmpty) {
        unresolved[file] = [
          for (final error in errors.take(3))
            '${error.diagnosticCode.lowerCaseName}: ${error.message}',
        ].join('; ');
        continue;
      }
      names[file] = publicExportNames(
        result.element.exportNamespace.definedNames2.keys,
      );
    }
  } finally {
    await collection.dispose();
  }
  return ExportNamesReport(names: names, unresolved: unresolved);
}

/// `dart run tool/export_names.dart --out <file> <entry.dart>...`: writes
/// the [ExportNamesReport] JSON to `--out`. Exit codes: 0 every entry point
/// resolved, 2 usage error, 3 an entry point could not be resolved (the
/// report lists it).
Future<int> exportNamesMain(
  List<String> arguments, {
  StringSink? out,
  StringSink? err,
  String? sdkPath,
}) async {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;
  final parser = ArgParser()
    ..addOption('out', help: 'JSON report file.', valueHelp: 'file');
  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderrSink.writeln('export_names: ${e.message}\n${parser.usage}');
    return 2;
  }
  final outPath = args['out'] as String?;
  if (outPath == null || outPath.isEmpty || args.rest.isEmpty) {
    stderrSink.writeln(
      'usage: dart run tool/export_names.dart --out <file> <entry.dart>...\n'
      '${parser.usage}',
    );
    return 2;
  }
  final stopwatch = Stopwatch()..start();
  final report = await resolveExportNames(args.rest, sdkPath: sdkPath);
  File(outPath)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(report.encode());
  stdoutSink.writeln(
    'export_names: ${report.names.length} resolved, '
    '${report.unresolved.length} unresolved '
    '(${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s)',
  );
  for (final MapEntry(:key, :value) in report.unresolved.entries) {
    stderrSink.writeln('export_names: cannot resolve $key: $value');
  }
  return report.unresolved.isEmpty ? 0 : exportNamesUnresolvedExitCode;
}
