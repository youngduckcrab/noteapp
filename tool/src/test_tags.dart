/// R15 — test tag declarations (contract 00-overview 7.4.2 / 7.4.8 v1.2,
/// docs/plans/01-infra.md 6.2).
///
/// Tags used by a member's tests (`@Tags([...])` and the `tags:` argument of
/// `test` / `testWidgets` / `group`) must be declared under `tags:` in that
/// member's `dart_test.yaml`, and every tag listed in `skip_by_default_tags`
/// (`integration`, `perf`) must have a `skip:` there.
///
/// Only **string literals** are recognised (the contract makes this a rule:
/// tags are written as `@Tags(['integration'])` / `tags: ['golden']`, never
/// passed through variables or constants).
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'dart_tokens.dart';
import 'rule_violation.dart';
import 'workspace.dart';

/// One literal tag found in a test file.
final class TagUse {
  const TagUse(this.tag, this.line);

  final String tag;

  /// 1-based line of the tag literal.
  final int line;

  @override
  bool operator ==(Object other) =>
      other is TagUse && other.tag == tag && other.line == line;

  @override
  int get hashCode => Object.hash(tag, line);

  @override
  String toString() => '$tag@$line';
}

/// Returns the literal tags used in [source], in source order.
///
/// Recognised forms (comments are ignored):
/// - `@Tags(['a', "b"])`, `@Tags(<String>['a'])`, `@Tags(const ['a'])`
/// - `tags: 'a'`, `tags: ['a', 'b']`, `tags: <String>['a']`,
///   `tags: const ['a']` as a named argument of a `test`, `testWidgets` or
///   `group` call (contract 7.4.2). A `tags:` argument of any other call,
///   such as the data constructor `Note(tags: ['math'])`, is not a test tag.
///
/// Non-literal elements (identifiers, interpolated strings) are skipped.
List<TagUse> scanTestTags(String source) {
  final tokens = tokenizeDart(source);
  final lines = LineIndex(source);
  final uses = <TagUse>[];

  void addString(DartToken token) {
    final value = token.value;
    if (token.kind == DartTokenKind.string && value != null) {
      uses.add(TagUse(value, lines.lineOf(token.offset)));
    }
  }

  // Reads a list literal starting at [start]; returns the index after it.
  int readList(int start) {
    var i = start;
    if (i < tokens.length && tokens[i].isIdentifier('const')) i++;
    if (i + 2 < tokens.length &&
        tokens[i].isPunctuation('<') &&
        tokens[i + 2].isPunctuation('>')) {
      i += 3;
    }
    if (i >= tokens.length || !tokens[i].isPunctuation('[')) return start;
    i++;
    var depth = 1;
    while (i < tokens.length && depth > 0) {
      final token = tokens[i];
      if (token.isPunctuation('[') ||
          token.isPunctuation('(') ||
          token.isPunctuation('{')) {
        depth++;
      } else if (token.isPunctuation(']') ||
          token.isPunctuation(')') ||
          token.isPunctuation('}')) {
        depth--;
      } else if (depth == 1 &&
          token.kind == DartTokenKind.string &&
          _isListElement(tokens, i)) {
        addString(token);
      }
      i++;
    }
    return i;
  }

  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (token.isPunctuation('@') &&
        i + 2 < tokens.length &&
        tokens[i + 1].isIdentifier('Tags') &&
        tokens[i + 2].isPunctuation('(')) {
      i = readList(i + 3) - 1;
    } else if (token.isIdentifier('tags') &&
        i + 2 < tokens.length &&
        tokens[i + 1].isPunctuation(':') &&
        (i == 0 || !tokens[i - 1].isPunctuation('.')) &&
        _isTestCallArgument(tokens, i)) {
      final value = tokens[i + 2];
      if (value.kind == DartTokenKind.string) {
        if (_isWholeArgument(tokens, i + 2)) addString(value);
        i += 2;
      } else {
        i = readList(i + 2) - 1;
      }
    }
  }
  return uses;
}

/// Callees whose `tags:` named argument holds test tags (contract 7.4.2).
const Set<String> _testCallNames = {'test', 'testWidgets', 'group'};

/// Whether the named argument at [index] belongs directly to a `test`,
/// `testWidgets` or `group` call: the nearest unclosed bracket before it is a
/// `(` preceded by one of those names (`ft.testWidgets(` counts too).
bool _isTestCallArgument(List<DartToken> tokens, int index) {
  var depth = 0;
  for (var j = index - 1; j >= 0; j--) {
    final token = tokens[j];
    if (token.isPunctuation(')') ||
        token.isPunctuation(']') ||
        token.isPunctuation('}')) {
      depth++;
    } else if (token.isPunctuation('(') ||
        token.isPunctuation('[') ||
        token.isPunctuation('{')) {
      if (depth > 0) {
        depth--;
        continue;
      }
      if (!token.isPunctuation('(') || j == 0) return false;
      final callee = tokens[j - 1];
      return callee.kind == DartTokenKind.identifier &&
          _testCallNames.any(callee.isIdentifier);
    }
  }
  return false;
}

/// A string inside a list counts only when it is a whole element:
/// preceded by `[` or `,` and followed by `,` or `]` (so `'a' + x` or
/// adjacent strings are not taken as literal tags).
bool _isListElement(List<DartToken> tokens, int index) {
  final before = tokens[index - 1];
  final after = index + 1 < tokens.length ? tokens[index + 1] : null;
  return (before.isPunctuation('[') || before.isPunctuation(',')) &&
      after != null &&
      (after.isPunctuation(',') || after.isPunctuation(']'));
}

/// `tags: 'a'` counts only when the string is the whole argument value.
bool _isWholeArgument(List<DartToken> tokens, int index) {
  final after = index + 1 < tokens.length ? tokens[index + 1] : null;
  return after != null &&
      (after.isPunctuation(',') || after.isPunctuation(')'));
}

/// How a tag is declared in a member's `dart_test.yaml`.
enum TagDeclaration {
  /// Not listed under `tags:` (or there is no `dart_test.yaml`).
  missing,

  /// Listed, without a `skip:` (a `skip: false` counts as no skip).
  declared,

  /// Listed with `skip: true` or `skip: "<reason>"`.
  skipped,
}

/// The `tags:` section of a `dart_test.yaml`.
final class DartTestConfig {
  const DartTestConfig._(this.exists, this._tags, {this.error});

  /// Reads `<memberDir>/dart_test.yaml`. A missing file declares nothing.
  factory DartTestConfig.read(String memberDir) {
    final file = File(p.join(memberDir, 'dart_test.yaml'));
    if (!file.existsSync()) return const DartTestConfig._(false, {});
    return DartTestConfig.parse(file.readAsStringSync());
  }

  /// Parses the content of a `dart_test.yaml`.
  factory DartTestConfig.parse(String text) {
    final Object? yaml;
    try {
      yaml = loadYaml(text);
    } on YamlException catch (e) {
      return DartTestConfig._(true, const {}, error: e.message);
    }
    final tags = <String, TagDeclaration>{};
    if (yaml is Map) {
      final section = yaml['tags'];
      if (section is Map) {
        for (final entry in section.entries) {
          final key = entry.key;
          if (key is! String) continue;
          final value = entry.value;
          var skipped = false;
          if (value is Map && value.containsKey('skip')) {
            final skip = value['skip'];
            skipped = skip == true || (skip is String && skip.isNotEmpty);
          }
          tags[key] = skipped
              ? TagDeclaration.skipped
              : TagDeclaration.declared;
        }
      }
    }
    return DartTestConfig._(true, tags);
  }

  /// Whether the `dart_test.yaml` file exists.
  final bool exists;

  final Map<String, TagDeclaration> _tags;

  /// YAML parse error, if any.
  final String? error;

  TagDeclaration declarationOf(String tag) =>
      _tags[tag] ?? TagDeclaration.missing;
}

/// Lists the `.dart` files under `<member>/test/` (sorted, repo-relative).
List<String> memberTestFiles(String root, WorkspaceMember member) =>
    listDartFiles(root, p.join(member.directory, 'test'));

/// Lists `.dart` files under [directory] recursively, skipping hidden and
/// `build` directories. Returns sorted repo-relative `/` paths.
List<String> listDartFiles(String root, String directory) {
  final dir = Directory(directory);
  if (!dir.existsSync()) return const [];
  final files = <String>[];
  void walk(Directory d) {
    final entries = d.listSync(followLinks: false)
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final entry in entries) {
      final name = p.basename(entry.path);
      if (entry is Directory) {
        if (name.startsWith('.') || name == 'build') continue;
        walk(entry);
      } else if (entry is File && name.endsWith('.dart')) {
        files.add(toPosixRelative(entry.path, root));
      }
    }
  }

  walk(dir);
  files.sort();
  return files;
}

/// R15 for one member. Each (member, tag) problem is reported once, at the
/// first file / line (in path order) that uses the tag.
List<RuleViolation> checkMemberTestTags({
  required String root,
  required WorkspaceMember member,
  required Set<String> skipByDefaultTags,
}) {
  final firstUse = <String, ({String file, int line})>{};
  for (final file in memberTestFiles(root, member)) {
    final source = File(p.join(root, file)).readAsStringSync();
    for (final use in scanTestTags(source)) {
      firstUse.putIfAbsent(use.tag, () => (file: file, line: use.line));
    }
  }
  if (firstUse.isEmpty) return const [];

  final config = DartTestConfig.read(member.directory);
  final violations = <RuleViolation>[];
  if (config.error != null) {
    violations.add(
      RuleViolation(
        rule: 'R15',
        path: '${member.path}/dart_test.yaml',
        line: 1,
        message: '${member.name}: cannot parse dart_test.yaml: ${config.error}',
      ),
    );
    return violations;
  }
  final tags = firstUse.keys.toList()..sort();
  for (final tag in tags) {
    final use = firstUse[tag]!;
    final usedIn = p.posix.relative(use.file, from: member.path);
    final declaration = config.declarationOf(tag);
    final mustSkip = skipByDefaultTags.contains(tag);
    String? problem;
    if (declaration == TagDeclaration.missing) {
      problem = config.exists
          ? 'dart_test.yaml does not declare it under `tags:`'
          : 'there is no ${member.path}/dart_test.yaml declaring it';
      if (mustSkip) problem = '$problem (it also needs `skip: "<reason>"`)';
    } else if (mustSkip && declaration != TagDeclaration.skipped) {
      problem = 'dart_test.yaml does not skip it';
    }
    if (problem != null) {
      violations.add(
        RuleViolation(
          rule: 'R15',
          path: use.file,
          line: use.line,
          message: "${member.name}: tag '$tag' used in $usedIn but $problem",
        ),
      );
    }
  }
  return violations;
}
