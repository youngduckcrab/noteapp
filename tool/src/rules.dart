/// `ws check` rules (docs/plans/01-infra.md 6.2 and docs/plans/m5-7/01-infra.md
/// 6.2, contract 00-overview 7.4.2 and 2차 7.4.1).
///
/// [checkWorkspace] runs the static rules R1–R10, R12, R13, R15 and R16; the
/// format rule R11 runs `dart format` and lives in [checkFormat]; the export
/// name rule R14 (integration step G3) resolves the entry points in a
/// separate process and lives in `export_names.dart` (`checkExports`).
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'dart_imports.dart';
import 'dart_tokens.dart';
import 'flutter_runner.dart';
import 'png_size.dart';
import 'rule_violation.dart';
import 'test_tags.dart';
import 'web_assets.dart';
import 'workspace.dart';

export 'rule_violation.dart';

/// The rules `ws check` runs in this version of the tool (R11 and R14 can be
/// skipped with `--no-format` / `--no-exports`).
const List<String> implementedRules = [
  'R1',
  'R2',
  'R3',
  'R4',
  'R5',
  'R6',
  'R7',
  'R8',
  'R9',
  'R10',
  'R11',
  'R12',
  'R13',
  'R14',
  'R15',
  'R16',
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
    this.appMembers = const [],
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
    this.forbiddenIoMembers = const [],
    this.pluginFreeMembers = const [],
    this.pluginExceptions = const {},
    this.pluginPackages = const [],
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

    final exceptionsRaw = yaml['plugin_exceptions'];
    if (exceptionsRaw != null && exceptionsRaw is! YamlMap) {
      throw const RulesFormatException('`plugin_exceptions` must be a map');
    }
    final pluginExceptions = <String, List<String>>{
      if (exceptionsRaw is YamlMap)
        for (final entry in exceptionsRaw.entries)
          '${entry.key}': strings(
            entry.value,
            'plugin_exceptions.${entry.key}',
          ),
    };

    return WorkspaceRules(
      allowedDependencies: Map.unmodifiable(allowed),
      appMembers: strings(yaml['app_members'], 'app_members'),
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
      forbiddenIoMembers: strings(
        yaml['forbidden_io_members'],
        'forbidden_io_members',
      ),
      pluginFreeMembers: strings(
        yaml['plugin_free_members'],
        'plugin_free_members',
      ),
      pluginExceptions: Map.unmodifiable(pluginExceptions),
      pluginPackages: strings(yaml['plugin_packages'], 'plugin_packages'),
    );
  }

  /// R8: allowed workspace sibling dependencies per member name.
  final Map<String, List<String>> allowedDependencies;

  /// R14: app members (`noteapp`, `ink_lab`) — their `lib/` files are not
  /// public entry points, so the export name check skips them.
  final List<String> appMembers;

  /// R2: members that must stay pure Dart.
  final List<String> pureDartMembers;

  /// R9: exact versions of the external packages of contract 7.5.
  final Map<String, String> pinnedExternal;

  /// R4: imports forbidden in `lib/`.
  final List<String> forbiddenImportsLib;

  /// R7: imports forbidden in `lib/` and `test/`.
  final List<String> forbiddenImportsLibAndTest;

  /// R4: packages importable only from native-suffixed files.
  final List<String> nativeOnlyImports;

  /// R4: test-only entry points.
  final List<String> testOnlyEntrypoints;

  /// R4: exempt files / directories (trailing `/`).
  final List<String> libExceptions;

  /// R5: web-only imports.
  final List<String> webOnlyImports;

  final List<String> nativeSuffixes;

  final List<String> webSuffixes;

  /// R11: generated file patterns skipped by the format check.
  final List<String> generatedFiles;

  /// R11: checker fixture directories skipped by the format check.
  final List<String> fixtureDirs;

  /// R15: tags that must have `skip:` in the member `dart_test.yaml`.
  final List<String> skipByDefaultTags;

  /// `affected`: paths that make every member affected.
  final List<String> globalTriggers;

  /// R4 (2차): `dart:io` identifiers that `lib/` must not use, even in
  /// `*_native.dart` / `*_io.dart` files (contract 7.4.1 — `Platform`).
  final List<String> forbiddenIoMembers;

  /// R16 (2차): members whose direct dependencies contain no plugin.
  final List<String> pluginFreeMembers;

  /// R16 (2차): members with 1차 plugin dependencies → the only plugins they
  /// may depend on. Never extended (see [r16BaselineExceptions]).
  final Map<String, List<String>> pluginExceptions;

  /// R16 / NR6 (2차): every plugin the app resolves (the names of
  /// `app/.flutter-plugins-dependencies` `dependencyGraph`).
  final List<String> pluginPackages;
}

/// Runs every static rule (all implemented rules except the format rule R11,
/// see [checkFormat]) on [workspace]. The result is sorted by path, line and
/// rule. Warnings (`isWarning`) are included.
List<RuleViolation> checkWorkspace(Workspace workspace, WorkspaceRules rules) {
  final violations = <RuleViolation>[
    ..._checkR1(workspace),
    ..._checkR2(workspace, rules),
    ..._checkR3(workspace),
    ..._checkR4(workspace, rules),
    ..._checkR5(workspace, rules),
    ..._checkR6(workspace, rules),
    ..._checkR7(workspace, rules),
    ..._checkR8(workspace, rules),
    ..._checkR9(workspace, rules),
    ..._checkR10(workspace),
    ..._checkR12(workspace),
    ..._checkR13(workspace),
    ..._checkR16(workspace, rules),
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
// R4 — lib/: forbidden imports, native-only packages, test-only entry points

/// Whether [path] (repo-relative) is covered by an entry of [exceptions]
/// (an entry ending with `/` covers the whole directory).
bool _isException(String path, List<String> exceptions) => exceptions.any(
  (entry) => entry.endsWith('/') ? path.startsWith(entry) : path == entry,
);

/// Whether the file or URI [path] names a platform file with one of
/// [suffixes]. The package entry point `<package>.dart` is never a platform
/// file (`pdf_io.dart` ends with `_io.dart` but is the pdf_io barrel);
/// [packageName] is the package of a file or relative URI — `package:` URIs
/// carry their own.
bool _hasSuffix(
  String path,
  List<String> suffixes, {
  required String packageName,
}) {
  var package = packageName;
  if (path.startsWith('package:')) package = _packageOf(path) ?? packageName;
  final name = p.posix.basename(path);
  if (name == '$package.dart') return false;
  return suffixes.any(name.endsWith);
}

Iterable<RuleViolation> _checkR4(Workspace ws, WorkspaceRules rules) sync* {
  final names = ws.memberNames;
  for (final member in ws.members) {
    final libDir = '${member.path}/lib';
    for (final file in listDartFiles(
      ws.root,
      p.join(member.directory, 'lib'),
    )) {
      if (_isException(file, rules.libExceptions)) continue;
      final native = _hasSuffix(
        file,
        rules.nativeSuffixes,
        packageName: member.name,
      );
      final isTestEntry = rules.testOnlyEntrypoints.any(
        (entry) => file == '$libDir/$entry',
      );
      final directives = _directivesOf(ws.root, file);
      if (rules.forbiddenIoMembers.isNotEmpty &&
          directives.any((d) => d.allUris.contains('dart:io'))) {
        yield* _forbiddenIoMembers(ws.root, file, rules.forbiddenIoMembers);
      }
      for (final directive in directives) {
        for (final uri in directive.allUris) {
          if (_matchesAny(uri, rules.forbiddenImportsLib) &&
              !(native && (uri == 'dart:io' || uri == 'dart:ffi'))) {
            yield RuleViolation(
              rule: 'R4',
              path: file,
              line: directive.line,
              message:
                  '`$uri` is not allowed in lib/ (move it to a '
                  '${rules.nativeSuffixes.join('/')} or '
                  '${rules.webSuffixes.join('/')} file behind a conditional '
                  'import — contract 7.4.3)',
            );
            continue;
          }
          if (_matchesAny(uri, rules.nativeOnlyImports) && !native) {
            yield RuleViolation(
              rule: 'R4',
              path: file,
              line: directive.line,
              message:
                  '`$uri` is native-only: import it only from files ending '
                  'with ${rules.nativeSuffixes.join(' or ')}',
            );
            continue;
          }
          final other = _packageOf(uri);
          if (other != null && names.contains(other)) {
            final entry = uri.substring('package:$other/'.length);
            if (rules.testOnlyEntrypoints.contains(entry)) {
              yield RuleViolation(
                rule: 'R4',
                path: file,
                line: directive.line,
                message:
                    '`$uri` is a test-only entry point: import it from '
                    'test/ only',
              );
            }
            continue;
          }
          if (_isRelative(uri) && !isTestEntry) {
            final target = p.posix.normalize(
              p.posix.join(p.posix.dirname(file), uri),
            );
            if (rules.testOnlyEntrypoints.any(
              (entry) => target == '$libDir/$entry',
            )) {
              yield RuleViolation(
                rule: 'R4',
                path: file,
                line: directive.line,
                message:
                    '`$uri` reaches the test-only entry point '
                    '${p.posix.basename(target)}: only the other lib/testing*'
                    '.dart files of the package may import it',
              );
            }
          }
        }
      }
    }
  }
}

bool _isRelative(String uri) => !uri.contains(':');

/// R4 (2차, contract 7.4.1): a `lib/` file that imports `dart:io` must not use
/// the identifiers of [members] (`Platform`) — not even in `*_native.dart`.
/// Identifier tokens only (comments and strings are skipped), so
/// `io.Platform` and `show Platform` are caught and `TargetPlatform` /
/// `defaultTargetPlatform` are not.
Iterable<RuleViolation> _forbiddenIoMembers(
  String root,
  String file,
  List<String> members,
) sync* {
  final source = File(p.join(root, file)).readAsStringSync();
  final lines = LineIndex(source);
  for (final token in tokenizeDart(source)) {
    for (final member in members) {
      if (token.isIdentifier(member)) {
        yield RuleViolation(
          rule: 'R4',
          path: file,
          line: lines.lineOf(token.offset),
          message:
              'dart:io $member is not allowed (계약 7.4.1): use kIsWeb + '
              'defaultTargetPlatform, or the service capability API',
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// R5 — web-only imports only in *_browser.dart (lib/, test/ outside test/web/)

Iterable<RuleViolation> _checkR5(Workspace ws, WorkspaceRules rules) sync* {
  for (final member in ws.members) {
    final webTests = '${member.path}/test/web/';
    for (final dir in const ['lib', 'test']) {
      for (final file in listDartFiles(
        ws.root,
        p.join(member.directory, dir),
      )) {
        if (file.startsWith(webTests)) continue;
        if (_hasSuffix(file, rules.webSuffixes, packageName: member.name)) {
          continue;
        }
        for (final directive in _directivesOf(ws.root, file)) {
          for (final uri in directive.allUris) {
            if (_matchesAny(uri, rules.webOnlyImports)) {
              yield RuleViolation(
                rule: 'R5',
                path: file,
                line: directive.line,
                message:
                    '`$uri` is web-only: use it only in files ending with '
                    '${rules.webSuffixes.join(' or ')} (or in test/web/)',
              );
            }
          }
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// R6 — lib/: platform files only through conditional clauses with a stub

Iterable<RuleViolation> _checkR6(Workspace ws, WorkspaceRules rules) sync* {
  final platformSuffixes = [...rules.nativeSuffixes, ...rules.webSuffixes];
  for (final member in ws.members) {
    bool has(String path, List<String> suffixes) =>
        !path.startsWith('dart:') &&
        _hasSuffix(path, suffixes, packageName: member.name);

    for (final file in listDartFiles(
      ws.root,
      p.join(member.directory, 'lib'),
    )) {
      // A platform file may use files of its own platform directly: it is
      // itself only reached through a conditional clause.
      final ownSuffixes = has(file, rules.nativeSuffixes)
          ? rules.nativeSuffixes
          : has(file, rules.webSuffixes)
          ? rules.webSuffixes
          : const <String>[];
      for (final directive in _directivesOf(ws.root, file)) {
        if (!has(directive.uri, platformSuffixes)) continue;
        if (has(directive.uri, ownSuffixes)) continue;
        yield RuleViolation(
          rule: 'R6',
          path: file,
          line: directive.line,
          message: directive.isConditional
              ? 'the default URI `${directive.uri}` of a conditional '
                    '${directive.kind.name} must be a stub, not a platform '
                    'file'
              : '`${directive.uri}` is a platform file: '
                    '${directive.kind.name} it only through `if '
                    '(dart.library.…)` clauses with a stub default '
                    '(contract 7.4.3)',
        );
      }
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
// R10 — dependency_overrides only in the root pubspec

Iterable<RuleViolation> _checkR10(Workspace ws) sync* {
  for (final member in ws.members) {
    if (member.pubspec.containsKey('dependency_overrides')) {
      yield RuleViolation(
        rule: 'R10',
        path: member.pubspecPath,
        line: lineOfKey(member.pubspec, 'dependency_overrides'),
        message:
            '${member.name}: `dependency_overrides` is allowed only in the '
            'root pubspec.yaml',
      );
    }
  }
}

// ---------------------------------------------------------------------------
// R11 — dart format (async, runs `dart format`)

/// The files R11 checks: `*.dart` under `app/`, `packages/` and `tool/`,
/// without hidden and `build/` directories, [WorkspaceRules.generatedFiles]
/// and [WorkspaceRules.fixtureDirs]. This set is also what "dart format
/// leaves nothing changed" means (G4, contract V2). Sorted repo-relative
/// paths.
List<String> formatTargets(Workspace ws, WorkspaceRules rules) {
  final generated = [for (final g in rules.generatedFiles) _globToRegExp(g)];
  return [
    for (final top in const ['app', 'packages', 'tool'])
      for (final file in listDartFiles(ws.root, p.join(ws.root, top)))
        if (!rules.fixtureDirs.any(file.startsWith) &&
            !generated.any((g) => g.hasMatch(p.posix.basename(file))))
          file,
  ];
}

RegExp _globToRegExp(String glob) {
  final pattern = StringBuffer('^');
  for (final rune in glob.runes) {
    final char = String.fromCharCode(rune);
    pattern.write(switch (char) {
      '*' => '.*',
      '?' => '.',
      _ => RegExp.escape(char),
    });
  }
  pattern.write(r'$');
  return RegExp(pattern.toString());
}

/// R11: runs `dart format --output=none --set-exit-if-changed` on
/// [formatTargets] with [dart] and reports every file it would change.
/// Returns an R11 violation on `pubspec.yaml` when the formatter itself
/// fails.
Future<List<RuleViolation>> checkFormat(
  Workspace ws,
  WorkspaceRules rules, {
  required ProcessRunner processes,
  required String dart,
}) async {
  final files = formatTargets(ws, rules);
  if (files.isEmpty) return const [];
  final violations = <RuleViolation>[];
  // Keep each command line well below OS argument limits.
  const chunk = 400;
  for (var start = 0; start < files.length; start += chunk) {
    final batch = files.sublist(
      start,
      start + chunk > files.length ? files.length : start + chunk,
    );
    final result = await processes.run(
      dart,
      ['format', '--output=none', '--set-exit-if-changed', ...batch],
      workingDirectory: ws.root,
      echo: false,
    );
    final changed = [
      for (final line in result.output.split('\n'))
        if (line.startsWith('Changed '))
          line.substring('Changed '.length).trim(),
    ];
    for (final file in changed) {
      violations.add(
        RuleViolation(
          rule: 'R11',
          path: p.split(p.normalize(file)).join('/'),
          line: 1,
          message: 'not formatted: run `dart format $file`',
        ),
      );
    }
    if (result.exitCode != 0 && result.exitCode != 1) {
      violations.add(
        RuleViolation(
          rule: 'R11',
          path: 'pubspec.yaml',
          line: 1,
          message:
              '`dart format` failed (exit code ${result.exitCode}): '
              '${result.output.trim()}',
        ),
      );
    } else if (result.exitCode == 1 && changed.isEmpty) {
      violations.add(
        RuleViolation(
          rule: 'R11',
          path: 'pubspec.yaml',
          line: 1,
          message: '`dart format` reported changes it did not name',
        ),
      );
    }
  }
  return violations..sort();
}

// ---------------------------------------------------------------------------
// R12 — tool/web_assets.yaml files in app/web/ with size and sha256

Iterable<RuleViolation> _checkR12(Workspace ws) sync* {
  final WebAssetsManifest? manifest;
  try {
    manifest = WebAssetsManifest.loadIfExists(
      p.join(ws.root, webAssetsManifestPath),
    );
  } on WebAssetsFormatException catch (e) {
    yield RuleViolation(
      rule: 'R12',
      path: webAssetsManifestPath,
      line: 1,
      message: e.message,
    );
    return;
  }
  if (manifest == null) return;
  for (final problem in verifyWebAssets(
    manifest,
    p.join(ws.root, appWebDirectory),
  )) {
    yield RuleViolation(
      rule: 'R12',
      path: webAssetsManifestPath,
      line: problem.asset.line,
      message:
          '$appWebDirectory/${problem.asset.path}: ${problem.message} '
          '(run `dart run tool/ws.dart web-assets fetch`)',
    );
  }
}

// ---------------------------------------------------------------------------
// R13 — app/web icon PNG sizes match their names

final RegExp _iconSizeName = RegExp(r'-(\d+)\.png$');

Iterable<RuleViolation> _checkR13(Workspace ws) sync* {
  final web = p.join(ws.root, appWebDirectory);
  final icons = Directory(p.join(web, 'icons'));
  final files = <String>[
    if (File(p.join(web, 'favicon.png')).existsSync()) 'favicon.png',
    if (icons.existsSync())
      for (final entry
          in icons.listSync()..sort((a, b) => a.path.compareTo(b.path)))
        if (entry is File && entry.path.endsWith('.png'))
          'icons/${p.basename(entry.path)}',
  ];
  for (final name in files) {
    final path = '$appWebDirectory/$name';
    final size = pngSize(File(p.join(web, name)).readAsBytesSync());
    if (size == null) {
      yield RuleViolation(
        rule: 'R13',
        path: path,
        line: 1,
        message: 'not a PNG file (no IHDR)',
      );
      continue;
    }
    final match = _iconSizeName.firstMatch(name);
    final expected = match == null ? null : int.parse(match.group(1)!);
    if (expected == null) {
      if (name.startsWith('icons/')) {
        yield RuleViolation(
          rule: 'R13',
          path: path,
          line: 1,
          message: 'icon name must end with -<size>.png',
        );
      } else if (size.width != size.height) {
        yield RuleViolation(
          rule: 'R13',
          path: path,
          line: 1,
          message: 'is ${size.width}x${size.height}, expected a square PNG',
        );
      }
    } else if (size.width != expected || size.height != expected) {
      yield RuleViolation(
        rule: 'R13',
        path: path,
        line: 1,
        message:
            'is ${size.width}x${size.height}, its name says '
            '${expected}x$expected',
      );
    }
  }
}

// ---------------------------------------------------------------------------
// R16 — no plugin in the direct dependencies of plugin-free members (2차)

/// The 1차 plugin dependencies that `plugin_exceptions` may keep (contract
/// 7.4.1 v2.1). The rules file must not extend them: a new plugin goes to a
/// service package (`media_io`, `ink_recognition`, `pencil_bridge`).
const Map<String, Set<String>> r16BaselineExceptions = {
  'pdf_io': {'file_picker'},
  'sync_engine': {
    'firebase_core',
    'firebase_auth',
    'cloud_firestore',
    'firebase_storage',
    'connectivity_plus',
  },
};

/// The members that `plugin_free_members` must keep (contract 7.4.1 v2.1).
const Set<String> r16BaselinePluginFreeMembers = {
  'feature_editor',
  'feature_library',
  'ink_engine',
  'note_core',
};

const String _rulesFile = 'tool/workspace_rules.yaml';

Iterable<RuleViolation> _checkR16(Workspace ws, WorkspaceRules rules) sync* {
  for (final member in r16BaselinePluginFreeMembers) {
    if (!rules.pluginFreeMembers.contains(member)) {
      yield RuleViolation(
        rule: 'R16',
        path: _rulesFile,
        line: 1,
        message:
            'plugin_free_members must keep $member (계약 7.4.1 — R16 '
            'baseline)',
      );
    }
  }
  for (final MapEntry(key: member, value: plugins)
      in rules.pluginExceptions.entries) {
    final baseline = r16BaselineExceptions[member];
    for (final plugin in plugins) {
      if (baseline == null || !baseline.contains(plugin)) {
        yield RuleViolation(
          rule: 'R16',
          path: _rulesFile,
          line: 1,
          message:
              'plugin_exceptions.$member must not add $plugin: the 1차 '
              'exceptions are never extended (계약 7.4.1)',
        );
      }
    }
  }

  final checked = {
    for (final m in rules.pluginFreeMembers) m: const <String>{},
    for (final e in rules.pluginExceptions.entries)
      if (!rules.pluginFreeMembers.contains(e.key)) e.key: e.value.toSet(),
  };
  if (checked.isEmpty) return;
  final locator = _PluginLocator(ws.root, rules.pluginPackages.toSet());
  for (final member in ws.members) {
    final allowed = checked[member.name];
    if (allowed == null) continue;
    for (final section in const ['dependencies', 'dev_dependencies']) {
      final deps = member.pubspec[section];
      if (deps is! YamlMap) continue;
      for (final entry in deps.entries) {
        final dep = entry.key;
        if (dep is! String || allowed.contains(dep)) continue;
        if (!locator.isPlugin(dep)) continue;
        yield RuleViolation(
          rule: 'R16',
          path: member.pubspecPath,
          line: lineOfKey(deps, dep),
          message: "${member.name}: depends on plugin '$dep' (계약 7.4.1)",
        );
      }
    }
  }
}

/// Decides whether a package is a Flutter plugin: listed in
/// `plugin_packages`, or its pubspec (found through the workspace's
/// `.dart_tool/package_config.json`) has `flutter: plugin:` — so a plugin
/// that is not listed yet is caught too.
final class _PluginLocator {
  _PluginLocator(this._root, this._listed);

  final String _root;
  final Set<String> _listed;
  Map<String, String>? _packageRoots;
  final Map<String, bool> _cache = {};

  bool isPlugin(String name) {
    if (_listed.contains(name)) return true;
    return _cache.putIfAbsent(name, () {
      final dir = _roots()[name];
      if (dir == null) return false;
      final pubspec = File(p.join(dir, 'pubspec.yaml'));
      if (!pubspec.existsSync()) return false;
      try {
        final yaml = loadYaml(pubspec.readAsStringSync());
        if (yaml is! YamlMap) return false;
        final flutter = yaml['flutter'];
        return flutter is YamlMap && flutter.containsKey('plugin');
      } on YamlException {
        return false;
      }
    });
  }

  Map<String, String> _roots() => _packageRoots ??= _readPackageConfig();

  Map<String, String> _readPackageConfig() {
    final config = File(p.join(_root, '.dart_tool', 'package_config.json'));
    if (!config.existsSync()) return const {};
    try {
      final json = jsonDecode(config.readAsStringSync());
      if (json is! Map<String, Object?>) return const {};
      final packages = json['packages'];
      if (packages is! List<Object?>) return const {};
      final base = config.parent.uri;
      return {
        for (final entry in packages)
          if (entry is Map<String, Object?> &&
              entry['name'] is String &&
              entry['rootUri'] is String)
            entry['name']! as String: p.fromUri(
              base.resolve(entry['rootUri']! as String),
            ),
      };
    } on FormatException {
      return const {};
    }
  }
}

// ---------------------------------------------------------------------------

List<DartDirective> _directivesOf(String root, String file) =>
    scanDirectives(File(p.join(root, file)).readAsStringSync());
