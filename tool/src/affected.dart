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

/// The base of the comparison is missing: the ref names no commit in the
/// repository (e.g. `origin/main` while the remote has no `main`), or it
/// has no merge base with `HEAD` (unrelated or shallow history).
/// `ws test --all-if-no-base` tests every member then (01-infra 6.13).
final class MissingBaseException extends AffectedException {
  const MissingBaseException(super.message);

  @override
  String toString() => 'MissingBaseException: $message';
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
///   that depends on it, directly or not (main and dev dependencies). A path
///   inside a member nested in another member (the ink lab
///   `packages/ink_engine/example`) belongs to the innermost one only;
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
    for (final path in paths)
      if (memberOfPath(workspace, path) case final member?) member.name,
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

/// The member whose directory holds [path] (repo-relative, `/`): the one
/// with the longest directory prefix, so a file of a nested member is not
/// also a file of the outer member. `null` outside every member.
WorkspaceMember? memberOfPath(Workspace workspace, String path) {
  WorkspaceMember? best;
  for (final member in workspace.members) {
    final inside = path == member.path || path.startsWith('${member.path}/');
    if (inside && (best == null || member.path.length > best.path.length)) {
      best = member;
    }
  }
  return best;
}

/// The paths changed since [ref], relative to [root]: committed changes since
/// the merge base of [ref] and `HEAD`, uncommitted changes to tracked files
/// and untracked files that are not ignored.
///
/// Throws [MissingBaseException] when [ref] names no commit or has no merge
/// base with `HEAD`, and [AffectedException] when git fails otherwise (not a
/// repository, no `HEAD`).
Future<List<String>> changedPathsSince(
  String ref, {
  required ProcessRunner processes,
  required String git,
  required String root,
}) async {
  // [missingBase]: exit code 1 means the base is missing (`rev-parse
  // --verify --quiet`: not a commit; `merge-base`: no common ancestor).
  Future<String> runGit(List<String> arguments, {String? missingBase}) async {
    final result = await processes.run(
      git,
      arguments,
      workingDirectory: root,
      echo: false,
    );
    if (result.exitCode == 1 && missingBase != null) {
      throw MissingBaseException(missingBase);
    }
    if (result.exitCode != 0) {
      throw AffectedException(
        '`git ${arguments.join(' ')}` failed (exit code ${result.exitCode}): '
        '${result.output.trim()}',
      );
    }
    return result.output;
  }

  await runGit([
    'rev-parse',
    '--verify',
    '--quiet',
    '$ref^{commit}',
  ], missingBase: '`$ref` names no commit in this repository');
  final noMergeBase =
      'no merge base between `$ref` and HEAD (unrelated or shallow history)';
  final base = (await runGit([
    'merge-base',
    ref,
    'HEAD',
  ], missingBase: noMergeBase)).trim();
  if (base.isEmpty) throw MissingBaseException(noMergeBase);
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
