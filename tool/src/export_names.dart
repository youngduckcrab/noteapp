/// R14 — export name overlap (integration step G3, docs/plans/01-infra.md
/// 6.2, contract 00-overview 7.4.2): the public names exported by the
/// entry points (every `lib/*.dart` directly in `lib/`) of the workspace
/// packages — every member except the apps of `app_members` — must not
/// overlap between two packages. Entry points of the same package may share
/// names (`testing.dart` re-exporting a type of the barrel is fine). No
/// exception list.
///
/// The export namespaces are resolved with `package:analyzer` 13.3.0 in a
/// separate process (`dart run tool/export_names.dart`, see
/// `export_namespace.dart`): importing the analyzer into `ws` itself would
/// add about 12 s of compile time to every `ws` command. This file has the
/// analyzer-free half: entry point discovery, the process protocol and the
/// overlap rule.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'flutter_runner.dart';
import 'rules.dart';
import 'workspace.dart';

/// Repo-relative path of the resolver script run by `ws check`.
const String exportNamesScript = 'tool/export_names.dart';

/// Time limit of the resolver process (7 members resolve in about a minute
/// on the container).
const Duration exportNamesTimeout = Duration(minutes: 10);

/// Exit code of the resolver when an entry point cannot be resolved.
const int exportNamesUnresolvedExitCode = 3;

/// Thrown when the export namespaces cannot be computed (the resolver is
/// missing, crashed, timed out or could not resolve an entry point). `ws`
/// reports it as an environment error (exit code 3).
final class ExportNamesException implements Exception {
  const ExportNamesException(this.message);

  final String message;

  @override
  String toString() => 'ExportNamesException: $message';
}

/// One public entry point: a `.dart` file directly in a package's `lib/`.
final class ExportEntryPoint implements Comparable<ExportEntryPoint> {
  const ExportEntryPoint({required this.package, required this.path});

  /// Package (member) name.
  final String package;

  /// Repo-relative path with `/` separators.
  final String path;

  /// `<package>/<file>`, as printed by R14.
  String get label => '$package/${p.posix.basename(path)}';

  @override
  int compareTo(ExportEntryPoint other) {
    final byPackage = package.compareTo(other.package);
    return byPackage != 0 ? byPackage : path.compareTo(other.path);
  }

  @override
  bool operator ==(Object other) =>
      other is ExportEntryPoint &&
      other.package == package &&
      other.path == path;

  @override
  int get hashCode => Object.hash(package, path);

  @override
  String toString() => label;
}

/// The entry points R14 compares: for every member not in
/// [WorkspaceRules.appMembers], each `*.dart` file directly in its `lib/`
/// (sorted by package, then path).
List<ExportEntryPoint> exportEntryPoints(
  Workspace workspace,
  WorkspaceRules rules,
) {
  final entries = <ExportEntryPoint>[];
  for (final member in workspace.members) {
    if (rules.appMembers.contains(member.name)) continue;
    final lib = Directory(p.join(member.directory, 'lib'));
    if (!lib.existsSync()) continue;
    for (final file in lib.listSync(followLinks: false)) {
      if (file is File && file.path.endsWith('.dart')) {
        entries.add(
          ExportEntryPoint(
            package: member.name,
            path: toPosixRelative(file.path, workspace.root),
          ),
        );
      }
    }
  }
  return entries..sort();
}

/// R14: every public name exported by entry points of two or more different
/// packages, one violation per name (on the first entry point that exports
/// it, line 1): `<name>: <pkgA>/<entry> & <pkgB>/<entry>[ & …]`, listing
/// every entry point that exports the name. Names shared only by entry
/// points of one package are not reported. Sorted by name.
List<RuleViolation> exportOverlaps(
  Map<ExportEntryPoint, Set<String>> namesByEntry,
) {
  final owners = <String, List<ExportEntryPoint>>{};
  final entries = namesByEntry.keys.toList()..sort();
  for (final entry in entries) {
    for (final name in namesByEntry[entry]!) {
      (owners[name] ??= []).add(entry);
    }
  }
  final names = owners.keys.toList()..sort();
  return [
    for (final name in names)
      if (owners[name]!.map((e) => e.package).toSet().length > 1)
        RuleViolation(
          rule: 'R14',
          path: owners[name]!.first.path,
          line: 1,
          message: '$name: ${owners[name]!.map((e) => e.label).join(' & ')}',
        ),
  ];
}

/// The public names of one export namespace: setter keys (`name=`) count as
/// their name, private names (never exported) are dropped.
Set<String> publicExportNames(Iterable<String> namespaceKeys) => {
  for (final key in namespaceKeys)
    if (!key.startsWith('_'))
      key.endsWith('=') ? key.substring(0, key.length - 1) : key,
};

/// Output file of the resolver, a JSON object with two maps keyed by the
/// absolute entry point path: `names` (the sorted public names) and
/// `unresolved` (the reason).
final class ExportNamesReport {
  const ExportNamesReport({required this.names, required this.unresolved});

  /// Decodes the resolver output [json].
  factory ExportNamesReport.decode(String json) {
    final Object? data;
    try {
      data = jsonDecode(json);
    } on FormatException catch (e) {
      throw ExportNamesException('resolver output is not JSON: ${e.message}');
    }
    if (data is! Map || data['names'] is! Map || data['unresolved'] is! Map) {
      throw const ExportNamesException(
        'resolver output has no `names` / `unresolved` maps',
      );
    }
    return ExportNamesReport(
      names: {
        for (final MapEntry(:key, :value) in (data['names'] as Map).entries)
          '$key': {for (final name in value as List) '$name'},
      },
      unresolved: {
        for (final MapEntry(:key, :value)
            in (data['unresolved'] as Map).entries)
          '$key': '$value',
      },
    );
  }

  /// Public export names per entry point file (absolute path).
  final Map<String, Set<String>> names;

  /// Entry points that could not be resolved, with the reason.
  final Map<String, String> unresolved;

  String encode() => const JsonEncoder.withIndent('  ').convert({
    'names': {
      for (final MapEntry(:key, :value) in names.entries)
        key: (value.toList()..sort()),
    },
    'unresolved': unresolved,
  });
}

/// R14 on [workspace]: runs the resolver script of the workspace
/// ([exportNamesScript]) with [dart] through [processes] and compares the
/// names. Throws [ExportNamesException] when the names cannot be computed.
Future<List<RuleViolation>> checkExports(
  Workspace workspace,
  WorkspaceRules rules, {
  required ProcessRunner processes,
  required String dart,
}) async {
  final entries = exportEntryPoints(workspace, rules);
  if (entries.isEmpty) return const [];
  final script = p.join(workspace.root, exportNamesScript);
  if (!File(script).existsSync()) {
    throw ExportNamesException(
      '$exportNamesScript not found in ${workspace.root} (skip R14 with '
      '--no-exports)',
    );
  }
  final temp = Directory.systemTemp.createTempSync('ws_r14_');
  try {
    final outFile = p.join(temp.path, 'export_names.json');
    // Normalized like the resolver's report keys.
    final absolute = {
      for (final entry in entries)
        entry: p.normalize(p.join(workspace.root, entry.path)),
    };
    final result = await processes.run(
      dart,
      ['run', exportNamesScript, '--out', outFile, ...absolute.values],
      workingDirectory: workspace.root,
      timeout: exportNamesTimeout,
      echo: false,
    );
    final file = File(outFile);
    final report = file.existsSync()
        ? ExportNamesReport.decode(file.readAsStringSync())
        : null;
    if (report != null && report.unresolved.isNotEmpty) {
      final lines = [
        for (final MapEntry(:key, :value) in report.unresolved.entries)
          '  ${toPosixRelative(key, workspace.root)}: $value',
      ];
      throw ExportNamesException(
        'R14 cannot resolve ${lines.length} entry point(s) (run `flutter '
        'pub get` first):\n${lines.join('\n')}',
      );
    }
    if (result.timedOut || result.exitCode != 0 || report == null) {
      final reason = result.timedOut
          ? 'timed out after ${exportNamesTimeout.inMinutes} min'
          : 'exit code ${result.exitCode}';
      throw ExportNamesException(
        '`dart run $exportNamesScript` failed ($reason):\n'
        '${result.output.trim()}',
      );
    }
    final namesByEntry = <ExportEntryPoint, Set<String>>{};
    for (final MapEntry(key: entry, value: path) in absolute.entries) {
      final names = report.names[path];
      if (names == null) {
        throw ExportNamesException(
          'resolver output has no names for ${entry.path}',
        );
      }
      namesByEntry[entry] = names;
    }
    return exportOverlaps(namesByEntry);
  } finally {
    temp.deleteSync(recursive: true);
  }
}
