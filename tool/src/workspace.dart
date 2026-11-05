/// Workspace model: the root pubspec, its members and their dependency graph
/// (docs/plans/01-infra.md 3.5, 4.2).
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Thrown when the workspace cannot be read (missing or broken root pubspec,
/// dependency cycle ...). `ws` reports it as an environment error.
final class WorkspaceException implements Exception {
  const WorkspaceException(this.message);

  final String message;

  @override
  String toString() => 'WorkspaceException: $message';
}

/// Converts a path to the repo-relative, `/`-separated form used in reports.
String toPosixRelative(String path, String root) =>
    p.split(p.relative(path, from: root)).join('/');

/// One workspace member (a directory listed under `workspace:` in the root
/// pubspec that has a readable `pubspec.yaml`).
final class WorkspaceMember {
  WorkspaceMember({
    required this.name,
    required this.path,
    required this.directory,
    required this.pubspec,
  });

  /// Reads the member at [path] (repo-relative) under [root].
  factory WorkspaceMember.load(String root, String path) {
    final directory = p.normalize(p.join(root, path));
    final file = File(p.join(directory, 'pubspec.yaml'));
    final yaml = loadYaml(file.readAsStringSync(), sourceUrl: file.uri);
    if (yaml is! YamlMap) {
      throw WorkspaceException('$path/pubspec.yaml is not a YAML map');
    }
    final name = yaml['name'];
    if (name is! String) {
      throw WorkspaceException('$path/pubspec.yaml has no `name`');
    }
    return WorkspaceMember(
      name: name,
      path: path,
      directory: directory,
      pubspec: yaml,
    );
  }

  /// Package name (`name:` in the pubspec).
  final String name;

  /// Repo-relative path with `/` separators, e.g. `packages/note_core`.
  final String path;

  /// Absolute directory.
  final String directory;

  final YamlMap pubspec;

  /// Repo-relative path of the member pubspec.
  String get pubspecPath => '$path/pubspec.yaml';

  YamlMap get dependencies => _map('dependencies');

  YamlMap get devDependencies => _map('dev_dependencies');

  YamlMap _map(String key) {
    final value = pubspec[key];
    return value is YamlMap ? value : YamlMap();
  }

  /// Whether the member declares an `sdk: flutter` dependency (the `flutter`
  /// package itself or e.g. `flutter_test`).
  bool get dependsOnFlutterSdk => [
    dependencies,
    devDependencies,
  ].any((deps) => deps.values.any(isFlutterSdkDependency));

  /// Names of [memberNames] that this member depends on (main or dev).
  Set<String> siblingDependencies(Set<String> memberNames) => {
    for (final deps in [dependencies, devDependencies])
      for (final key in deps.keys)
        if (key is String && memberNames.contains(key) && key != name) key,
  };

  @override
  String toString() => '$name ($path)';
}

/// Whether a dependency value is `{sdk: flutter}`.
bool isFlutterSdkDependency(Object? value) =>
    value is Map && value['sdk'] == 'flutter';

/// Whether a dependency value is an SDK dependency (`{sdk: ...}`).
bool isSdkDependency(Object? value) => value is Map && value['sdk'] != null;

/// The 1-based line of [key] inside [map], or of the map itself when the key
/// is missing (`1` when no span is available).
int lineOfKey(YamlMap map, Object key) {
  for (final node in map.nodes.keys) {
    if (node is YamlNode && node.value == key) return node.span.start.line + 1;
  }
  return map.span.start.line + 1;
}

/// The whole workspace: root pubspec and members.
final class Workspace {
  Workspace._({
    required this.root,
    required this.rootPubspec,
    required this.declaredMemberPaths,
    required this.members,
  });

  /// Loads the workspace rooted at [root] (the directory of the root
  /// pubspec). Listed paths without a pubspec are kept in
  /// [declaredMemberPaths] but not in [members] (R1 reports them).
  factory Workspace.load(String root) {
    final normalizedRoot = p.normalize(p.absolute(root));
    final file = File(p.join(normalizedRoot, 'pubspec.yaml'));
    if (!file.existsSync()) {
      throw WorkspaceException('no pubspec.yaml in $normalizedRoot');
    }
    final Object? yaml;
    try {
      yaml = loadYaml(file.readAsStringSync(), sourceUrl: file.uri);
    } on YamlException catch (e) {
      throw WorkspaceException('cannot parse root pubspec.yaml: ${e.message}');
    }
    if (yaml is! YamlMap) {
      throw const WorkspaceException('root pubspec.yaml is not a YAML map');
    }
    final list = yaml['workspace'];
    if (list is! YamlList) {
      throw const WorkspaceException(
        'root pubspec.yaml has no `workspace:` list',
      );
    }
    final declared = <String>[
      for (final entry in list)
        if (entry is String) p.posix.normalize(entry),
    ];
    final members = <WorkspaceMember>[];
    for (final path in declared) {
      if (File(p.join(normalizedRoot, path, 'pubspec.yaml')).existsSync()) {
        try {
          members.add(WorkspaceMember.load(normalizedRoot, path));
        } on YamlException catch (e) {
          throw WorkspaceException(
            'cannot parse $path/pubspec.yaml: ${e.message}',
          );
        }
      }
    }
    return Workspace._(
      root: normalizedRoot,
      rootPubspec: yaml,
      declaredMemberPaths: List.unmodifiable(declared),
      members: List.unmodifiable(members),
    );
  }

  /// Finds the workspace root: the nearest directory at or above [start]
  /// whose pubspec.yaml has a `workspace:` key.
  static String? findRoot(String start) {
    var dir = p.normalize(p.absolute(start));
    while (true) {
      final file = File(p.join(dir, 'pubspec.yaml'));
      if (file.existsSync()) {
        try {
          final yaml = loadYaml(file.readAsStringSync());
          if (yaml is YamlMap && yaml.containsKey('workspace')) return dir;
        } on YamlException {
          // Not a usable pubspec; keep walking up.
        }
      }
      final parent = p.dirname(dir);
      if (parent == dir) return null;
      dir = parent;
    }
  }

  /// Absolute root directory.
  final String root;

  final YamlMap rootPubspec;

  /// Paths listed under `workspace:` (normalized, `/` separators).
  final List<String> declaredMemberPaths;

  /// Members in `workspace:` order.
  final List<WorkspaceMember> members;

  Set<String> get memberNames => {for (final m in members) m.name};

  WorkspaceMember? memberNamed(String name) {
    for (final m in members) {
      if (m.name == name) return m;
    }
    return null;
  }

  /// Members in topological order: every member comes after the members it
  /// depends on (main and dev dependencies). Ties keep `workspace:` order.
  List<WorkspaceMember> topologicalOrder() {
    final names = memberNames;
    final remaining = <String, Set<String>>{
      for (final m in members) m.name: m.siblingDependencies(names),
    };
    final ordered = <WorkspaceMember>[];
    while (remaining.isNotEmpty) {
      final next = members.firstWhere(
        (m) => remaining.containsKey(m.name) && remaining[m.name]!.isEmpty,
        orElse: () => throw WorkspaceException(
          'dependency cycle between ${remaining.keys.join(', ')}',
        ),
      );
      ordered.add(next);
      remaining.remove(next.name);
      for (final deps in remaining.values) {
        deps.remove(next.name);
      }
    }
    return ordered;
  }
}
