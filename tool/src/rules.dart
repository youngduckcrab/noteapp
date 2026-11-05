/// `ws check` rules (docs/plans/01-infra.md 6.2, contract 00-overview 7.4.2).
///
/// Foundation step B1 checks R1–R3, R7–R9 and R15 (contract 7.6 B1 v1.2).
/// R4–R6 and R10–R13 are added in I1 and R14 at the integration step G3; the
/// data they need is already part of [WorkspaceRules].
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'dart_imports.dart';
import 'rule_violation.dart';
import 'test_tags.dart';
import 'workspace.dart';

export 'rule_violation.dart';

/// The rules `checkWorkspace` runs in this version of the tool.
const List<String> implementedRules = [
  'R1',
  'R2',
  'R3',
  'R7',
  'R8',
  'R9',
  'R15',
];

/// Thrown when `tool/workspace_rules.yaml` is missing or malformed.
final class RulesFormatException implements Exception {
  const RulesFormatException(this.message);

  final String message;

  @override
  String toString() => 'RulesFormatException: $message';
}

/// The content of `tool/workspace_rules.yaml` (docs/plans/01-infra.md 4.3).
final class WorkspaceRules {
  const WorkspaceRules({
    required this.allowedDependencies,
    required this.pureDartMembers,
    required this.pinnedExternal,
    required this.forbiddenImportsLib,
    required this.forbiddenImportsLibAndTest,
    required this.nativeOnlyImports,
    required this.testOnlyEntrypoints,
    required this.libExceptions,
    required this.webOnlyImports,
    required this.nativeSuffixes,
    required this.webSuffixes,
    required this.generatedFiles,
    required this.fixtureDirs,
    required this.skipByDefaultTags,
    required this.globalTriggers,
  });

  /// Reads the rules file at [path].
  factory WorkspaceRules.load(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw RulesFormatException('rules file not found: $path');
    }
    return WorkspaceRules.parse(file.readAsStringSync(), sourceUrl: file.uri);
  }

  /// Parses the YAML [text] of a rules file.
  factory WorkspaceRules.parse(String text, {Uri? sourceUrl}) {
    final Object? yaml;
    try {
      yaml = loadYaml(text, sourceUrl: sourceUrl);
    } on YamlException catch (e) {
      throw RulesFormatException(e.toString());
    }
    if (yaml is! YamlMap) {
      throw const RulesFormatException('rules file is not a YAML map');
    }

    List<String> strings(Object? value, String key) {
      if (value == null) return const [];
      if (value is! YamlList) {
        throw RulesFormatException('`$key` must be a list');
      }
      return List.unmodifiable(value.map((e) => '$e'));
    }

    final allowedRaw = yaml['allowed_dependencies'];
    if (allowedRaw is! YamlMap) {
      throw const RulesFormatException('`allowed_dependencies` must be a map');
    }
    final allowed = <String, List<String>>{
      for (final entry in allowedRaw.entries)
        '${entry.key}': strings(
          entry.value,
          'allowed_dependencies.${entry.key}',
        ),
    };

    final pinnedRaw = yaml['pinned_external'];
    if (pinnedRaw is! YamlMap) {
      throw const RulesFormatException('`pinned_external` must be a map');
    }
    final pinned = <String, String>{
      for (final entry in pinnedRaw.entries) '${entry.key}': '${entry.value}',
    };

    final forbidden = yaml['forbidden_imports'];
    if (forbidden != null && forbidden is! YamlMap) {
      throw const RulesFormatException('`forbidden_imports` must be a map');
    }
    final forbiddenMap = forbidden is YamlMap ? forbidden : YamlMap();

    return WorkspaceRules(
      allowedDependencies: Map.unmodifiable(allowed),
      pureDartMembers: strings(yaml['pure_dart_members'], 'pure_dart_members'),
      pinnedExternal: Map.unmodifiable(pinned),
      forbiddenImportsLib: strings(
        forbiddenMap['lib'],
        'forbidden_imports.lib',
      ),
      forbiddenImportsLibAndTest: strings(
        forbiddenMap['lib_and_test'],
        'forbidden_imports.lib_and_test',
      ),
      nativeOnlyImports: strings(
        yaml['native_only_imports'],
        'native_only_imports',
      ),
      testOnlyEntrypoints: strings(
        yaml['test_only_entrypoints'],
        'test_only_entrypoints',
      ),
      libExceptions: strings(yaml['lib_exceptions'], 'lib_exceptions'),
      webOnlyImports: strings(yaml['web_only_imports'], 'web_only_imports'),
      nativeSuffixes: strings(yaml['native_suffixes'], 'native_suffixes'),
      webSuffixes: strings(yaml['web_suffixes'], 'web_suffixes'),
      generatedFiles: strings(yaml['generated_files'], 'generated_files'),
      fixtureDirs: strings(yaml['fixture_dirs'], 'fixture_dirs'),
      skipByDefaultTags: strings(
        yaml['skip_by_default_tags'],
        'skip_by_default_tags',
      ),
      globalTriggers: strings(yaml['global_triggers'], 'global_triggers'),
    );
  }

  /// R8: allowed workspace sibling dependencies per member name.
  final Map<String, List<String>> allowedDependencies;

  /// R2: members that must stay pure Dart.
  final List<String> pureDartMembers;

  /// R9: exact versions of the external packages of contract 7.5.
  final Map<String, String> pinnedExternal;

  /// R4 (I1): imports forbidden in `lib/`.
  final List<String> forbiddenImportsLib;

  /// R7: imports forbidden in `lib/` and `test/`.
  final List<String> forbiddenImportsLibAndTest;

  /// R4 (I1): packages importable only from native-suffixed files.
  final List<String> nativeOnlyImports;

  /// R4 (I1): test-only entry points.
  final List<String> testOnlyEntrypoints;

  /// R4 (I1): exempt files / directories (trailing `/`).
  final List<String> libExceptions;

  /// R5 (I1): web-only imports.
  final List<String> webOnlyImports;

  final List<String> nativeSuffixes;

  final List<String> webSuffixes;

  /// R11 (I1): generated file patterns skipped by the format check.
  final List<String> generatedFiles;

  /// R11 (I1): checker fixture directories skipped by the format check.
  final List<String> fixtureDirs;

  /// R15: tags that must have `skip:` in the member `dart_test.yaml`.
  final List<String> skipByDefaultTags;

  /// `affected` (I1): paths that make every member affected.
  final List<String> globalTriggers;
}

/// Runs every implemented rule on [workspace]. The result is sorted by path,
/// line and rule. Warnings (`isWarning`) are included.
List<RuleViolation> checkWorkspace(Workspace workspace, WorkspaceRules rules) {
  final violations = <RuleViolation>[
    ..._checkR1(workspace),
    ..._checkR2(workspace, rules),
    ..._checkR3(workspace),
    ..._checkR7(workspace, rules),
    ..._checkR8(workspace, rules),
    ..._checkR9(workspace, rules),
    for (final member in workspace.members)
      ...checkMemberTestTags(
        root: workspace.root,
        member: member,
        skipByDefaultTags: rules.skipByDefaultTags.toSet(),
      ),
  ]..sort();
  return violations;
}

// ---------------------------------------------------------------------------
// R1 — workspace list matches the member directories; resolution: workspace

Iterable<RuleViolation> _checkR1(Workspace ws) sync* {
  final list = ws.rootPubspec.nodes['workspace'];
  final listNodes = list is YamlList ? list.nodes : const <YamlNode>[];
  for (var i = 0; i < ws.declaredMemberPaths.length; i++) {
    final path = ws.declaredMemberPaths[i];
    if (!File(p.join(ws.root, path, 'pubspec.yaml')).existsSync()) {
      yield RuleViolation(
        rule: 'R1',
        path: 'pubspec.yaml',
        line: i < listNodes.length ? listNodes[i].span.start.line + 1 : 1,
        message: 'workspace member `$path` has no pubspec.yaml',
      );
    }
  }
  for (final member in ws.members) {
    if (member.pubspec['resolution'] != 'workspace') {
      yield RuleViolation(
        rule: 'R1',
        path: member.pubspecPath,
        line: lineOfKey(member.pubspec, 'resolution'),
        message: '${member.name}: missing `resolution: workspace`',
      );
    }
  }
  final declared = ws.declaredMemberPaths.toSet();
  for (final path in _discoverMemberDirectories(ws.root)) {
    if (!declared.contains(path)) {
      yield RuleViolation(
        rule: 'R1',
        path: '$path/pubspec.yaml',
        line: 1,
        message:
            'package `$path` is not listed under `workspace:` in the root '
            'pubspec.yaml',
      );
    }
  }
}

/// Package directories that must be workspace members: `app/`, every direct
/// child of `packages/` with a pubspec, and any other pubspec under `app/` or
/// `packages/` that declares `resolution: workspace`.
List<String> _discoverMemberDirectories(String root) {
  final found = <String>{};
  if (File(p.join(root, 'app', 'pubspec.yaml')).existsSync()) found.add('app');
  final packages = Directory(p.join(root, 'packages'));
  if (packages.existsSync()) {
    for (final entry in packages.listSync(followLinks: false)) {
      if (entry is Directory &&
          File(p.join(entry.path, 'pubspec.yaml')).existsSync()) {
        found.add(toPosixRelative(entry.path, root));
      }
    }
  }
  void walk(Directory dir) {
    for (final entry in dir.listSync(followLinks: false)) {
      if (entry is! Directory) continue;
      final name = p.basename(entry.path);
      if (name.startsWith('.') || name == 'build') continue;
      final pubspec = File(p.join(entry.path, 'pubspec.yaml'));
      if (pubspec.existsSync()) {
        try {
          final yaml = loadYaml(pubspec.readAsStringSync());
          if (yaml is YamlMap && yaml['resolution'] == 'workspace') {
            found.add(toPosixRelative(entry.path, root));
          }
        } on YamlException {
          // A broken nested pubspec is not a workspace member candidate.
        }
      }
      walk(entry);
    }
  }

  for (final top in ['app', 'packages']) {
    final dir = Directory(p.join(root, top));
    if (dir.existsSync()) walk(dir);
  }
  return found.toList()..sort();
}

// ---------------------------------------------------------------------------
// R2 — same environment as the root; pure Dart members stay pure

Iterable<RuleViolation> _checkR2(Workspace ws, WorkspaceRules rules) sync* {
  final rootEnv = ws.rootPubspec['environment'];
  final rootEnvMap = rootEnv is YamlMap ? rootEnv : YamlMap();
  for (final key in const ['sdk', 'flutter']) {
    if (rootEnvMap[key] == null) {
      yield RuleViolation(
        rule: 'R2',
        path: 'pubspec.yaml',
        line: lineOfKey(ws.rootPubspec, 'environment'),
        message: 'root pubspec has no `environment.$key`',
      );
    }
  }
  for (final member in ws.members) {
    final env = member.pubspec['environment'];
    if (env is! YamlMap) {
      yield RuleViolation(
        rule: 'R2',
        path: member.pubspecPath,
        line: 1,
        message: '${member.name}: missing `environment:`',
      );
    } else {
      for (final key in const ['sdk', 'flutter']) {
        final expected = rootEnvMap[key];
        final actual = env[key];
        if (expected != null && '$actual' != '$expected') {
          yield RuleViolation(
            rule: 'R2',
            path: member.pubspecPath,
            line: actual == null
                ? lineOfKey(member.pubspec, 'environment')
                : lineOfKey(env, key),
            message: actual == null
                ? '${member.name}: missing `environment.$key: $expected` '
                      '(same as the root pubspec — pure Dart members too)'
                : '${member.name}: `environment.$key` is `$actual`, expected '
                      '`$expected` (same as the root pubspec)',
          );
        }
      }
    }

    if (!rules.pureDartMembers.contains(member.name)) continue;
    for (final section in const ['dependencies', 'dev_dependencies']) {
      final deps = member.pubspec[section];
      if (deps is! YamlMap) continue;
      for (final entry in deps.entries) {
        if (isFlutterSdkDependency(entry.value)) {
          yield RuleViolation(
            rule: 'R2',
            path: member.pubspecPath,
            line: lineOfKey(deps, entry.key as Object),
            message:
                '${member.name} is a pure Dart member: no `sdk: flutter` '
                'dependency allowed (${entry.key} in $section)',
          );
        }
      }
    }
    for (final dir in const ['lib', 'test']) {
      for (final file in listDartFiles(
        ws.root,
        p.join(member.directory, dir),
      )) {
        for (final directive in _directivesOf(ws.root, file)) {
          for (final uri in directive.allUris) {
            if (uri.startsWith('package:flutter/') ||
                uri.startsWith('package:flutter_test/')) {
              yield RuleViolation(
                rule: 'R2',
                path: file,
                line: directive.line,
                message:
                    '${member.name} is a pure Dart member: `$uri` is not '
                    'allowed',
              );
            }
          }
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// R3 — no analysis_options.yaml inside members

Iterable<RuleViolation> _checkR3(Workspace ws) sync* {
  for (final member in ws.members) {
    if (File(p.join(member.directory, 'analysis_options.yaml')).existsSync()) {
      yield RuleViolation(
        rule: 'R3',
        path: '${member.path}/analysis_options.yaml',
        line: 1,
        message:
            '${member.name}: members must not have analysis_options.yaml '
            '(the root file applies)',
      );
    }
  }
}

// ---------------------------------------------------------------------------
// R7 — no SDK Material / Cupertino; no other member's src/

Iterable<RuleViolation> _checkR7(Workspace ws, WorkspaceRules rules) sync* {
  final names = ws.memberNames;
  for (final member in ws.members) {
    for (final dir in const ['lib', 'test']) {
      for (final file in listDartFiles(
        ws.root,
        p.join(member.directory, dir),
      )) {
        for (final directive in _directivesOf(ws.root, file)) {
          for (final uri in directive.allUris) {
            if (_matchesAny(uri, rules.forbiddenImportsLibAndTest)) {
              yield RuleViolation(
                rule: 'R7',
                path: file,
                line: directive.line,
                message:
                    '`$uri` is forbidden in lib/ and test/: use '
                    'package:material_ui/material_ui.dart',
              );
              continue;
            }
            final other = _packageOf(uri);
            if (other != null &&
                other != member.name &&
                names.contains(other) &&
                uri.startsWith('package:$other/src/')) {
              yield RuleViolation(
                rule: 'R7',
                path: file,
                line: directive.line,
                message:
                    '`$uri` reaches into $other/lib/src/: import its lib/ '
                    'entry point instead',
              );
            }
          }
        }
      }
    }
  }
}

/// An entry ending with `/` matches as a prefix, otherwise exactly.
bool _matchesAny(String uri, List<String> entries) => entries.any(
  (entry) => entry.endsWith('/') ? uri.startsWith(entry) : uri == entry,
);

String? _packageOf(String uri) {
  if (!uri.startsWith('package:')) return null;
  final slash = uri.indexOf('/');
  return slash < 0 ? null : uri.substring('package:'.length, slash);
}

// ---------------------------------------------------------------------------
// R8 — sibling dependencies: allowed edges only, version `any`

Iterable<RuleViolation> _checkR8(Workspace ws, WorkspaceRules rules) sync* {
  final names = ws.memberNames;
  for (final member in ws.members) {
    final allowed = rules.allowedDependencies[member.name];
    if (allowed == null) {
      yield RuleViolation(
        rule: 'R8',
        path: member.pubspecPath,
        line: lineOfKey(member.pubspec, 'name'),
        message:
            '${member.name} is not listed in allowed_dependencies '
            '(tool/workspace_rules.yaml)',
      );
    }
    for (final section in const ['dependencies', 'dev_dependencies']) {
      final deps = member.pubspec[section];
      if (deps is! YamlMap) continue;
      for (final entry in deps.entries) {
        final dep = entry.key;
        if (dep is! String || !names.contains(dep) || dep == member.name) {
          continue;
        }
        final line = lineOfKey(deps, dep);
        if (allowed != null && !allowed.contains(dep)) {
          yield RuleViolation(
            rule: 'R8',
            path: member.pubspecPath,
            line: line,
            message:
                '${member.name} must not depend on $dep (allowed: '
                '${allowed.isEmpty ? 'none' : allowed.join(', ')} — '
                '00-overview 7.1)',
          );
        }
        if (entry.value != 'any') {
          yield RuleViolation(
            rule: 'R8',
            path: member.pubspecPath,
            line: line,
            message:
                '${member.name}: workspace sibling $dep must be declared as '
                '`$dep: any` (no path:, no version)',
          );
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// R9 — external dependencies: exact versions, equal to pinned_external

final RegExp _exactVersion = RegExp(
  r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$',
);

Iterable<RuleViolation> _checkR9(Workspace ws, WorkspaceRules rules) sync* {
  final names = ws.memberNames;
  final pubspecs = <(String, String, YamlMap)>[
    ('pubspec.yaml', 'workspace root', ws.rootPubspec),
    for (final m in ws.members) (m.pubspecPath, m.name, m.pubspec),
  ];
  for (final (path, owner, pubspec) in pubspecs) {
    for (final section in const ['dependencies', 'dev_dependencies']) {
      final deps = pubspec[section];
      if (deps is! YamlMap) continue;
      for (final entry in deps.entries) {
        final dep = entry.key;
        if (dep is! String || names.contains(dep)) continue;
        final value = entry.value;
        if (isSdkDependency(value)) continue;
        final line = lineOfKey(deps, dep);
        final version = switch (value) {
          final String v => v,
          final Map<Object?, Object?> m
              when m['version'] != null &&
                  m['path'] == null &&
                  m['git'] == null =>
            '${m['version']}',
          _ => null,
        };
        if (version == null || !_exactVersion.hasMatch(version)) {
          yield RuleViolation(
            rule: 'R9',
            path: path,
            line: line,
            message:
                '$owner: external dependency $dep must use an exact '
                'version (got `${value ?? 'any'}`)',
          );
          continue;
        }
        final pinned = rules.pinnedExternal[dep];
        if (pinned == null) {
          yield RuleViolation(
            rule: 'R9w',
            path: path,
            line: line,
            isWarning: true,
            message:
                '$owner: $dep $version is not in pinned_external (contract '
                '7.5) — report it as a dependency addition',
          );
        } else if (pinned != version) {
          yield RuleViolation(
            rule: 'R9',
            path: path,
            line: line,
            message:
                '$owner: $dep is $version but contract 7.5 pins $pinned '
                '(tool/workspace_rules.yaml pinned_external)',
          );
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------

List<DartDirective> _directivesOf(String root, String file) =>
    scanDirectives(File(p.join(root, file)).readAsStringSync());
