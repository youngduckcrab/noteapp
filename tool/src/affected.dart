/// `ws affected` and `ws test --affected-since`: which members a change
/// touches (docs/plans/01-infra.md 4.2, 6.13).
library;

import 'flutter_runner.dart';
import 'workspace.dart';

/// Thrown when git cannot tell what changed (unknown ref, not a repository).
final class AffectedException implements Exception {
  const AffectedException(this.message);

  final String message;

  @override
  String toString() => 'AffectedException: $message';
}

/// Whether [path] (repo-relative, `/`) matches a global trigger: an entry
/// ending with `/` matches every path below it, any other entry exactly.
bool isGlobalTrigger(String path, List<String> globalTriggers) =>
    globalTriggers.any(
      (entry) => entry.endsWith('/') ? path.startsWith(entry) : path == entry,
    );

/// The members affected by [changedPaths] (repo-relative, `/` separators),
/// in topological order:
///
/// - a path matching [globalTriggers] (root `pubspec.yaml`, `pubspec.lock`,
///   `analysis_options.yaml`, `tool/`, `.github/workflows/`) affects every
///   member;
/// - a path inside a member directory affects that member and every member
///   that depends on it, directly or not (main and dev dependencies);
/// - any other path (e.g. `docs/`) affects nothing.
List<WorkspaceMember> affectedMembers(
  Workspace workspace,
  Iterable<String> changedPaths,
  List<String> globalTriggers,
) {
  final ordered = workspace.topologicalOrder();
  final paths = [for (final path in changedPaths) path.replaceAll(r'\', '/')];
  if (paths.any((path) => isGlobalTrigger(path, globalTriggers))) {
    return ordered;
  }
  final names = workspace.memberNames;
  final affected = <String>{
    for (final member in workspace.members)
      if (paths.any(
        (path) => path == member.path || path.startsWith('${member.path}/'),
      ))
        member.name,
  };
  // Members come after their dependencies, so one pass in topological order
  // reaches every transitive dependent.
  for (final member in ordered) {
    if (member.siblingDependencies(names).any(affected.contains)) {
      affected.add(member.name);
    }
  }
  return [
    for (final member in ordered)
      if (affected.contains(member.name)) member,
  ];
}

/// The paths changed since [ref], relative to [root]: committed changes since
/// the merge base of [ref] and `HEAD`, uncommitted changes to tracked files
/// and untracked files that are not ignored.
Future<List<String>> changedPathsSince(
  String ref, {
  required ProcessRunner processes,
  required String git,
  required String root,
}) async {
  Future<String> runGit(List<String> arguments) async {
    final result = await processes.run(
      git,
      arguments,
      workingDirectory: root,
      echo: false,
    );
    if (result.exitCode != 0) {
      throw AffectedException(
        '`git ${arguments.join(' ')}` failed (exit code ${result.exitCode}): '
        '${result.output.trim()}',
      );
    }
    return result.output;
  }

  final base = (await runGit(['merge-base', ref, 'HEAD'])).trim();
  if (base.isEmpty) {
    throw AffectedException('no merge base between $ref and HEAD');
  }
  final diff = await runGit(['diff', '--name-only', '--relative', base]);
  final untracked = await runGit([
    'ls-files',
    '--others',
    '--exclude-standard',
  ]);
  final paths = <String>{
    for (final line in '$diff\n$untracked'.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  };
  return paths.toList()..sort();
}
