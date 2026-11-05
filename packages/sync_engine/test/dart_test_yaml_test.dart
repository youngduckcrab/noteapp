// dart_test.yaml of sync_engine (07-sync 3.2, 8 T1; contract 00-overview
// 7.4.8 v1.1 / v1.2): every tag a test uses is declared, `integration` is
// skipped by default, and no tag outside the plan is declared. Source-text
// check like `ws check` R15 (which stays the authority): only string-literal
// tags count, so tests must write them as literals.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tag names declared directly under the top-level `tags:` key, with the
/// lines of each tag's block.
Map<String, List<String>> _declaredTags(String yaml) {
  final tags = <String, List<String>>{};
  var inTags = false;
  String? current;
  for (final raw in yaml.split('\n')) {
    final line = raw.replaceFirst(RegExp(r'\s+#.*$'), '');
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    if (!line.startsWith(' ')) {
      inTags = line.trim() == 'tags:';
      current = null;
      continue;
    }
    if (!inTags) continue;
    final key = RegExp(r'^  ([A-Za-z0-9_-]+):').firstMatch(line);
    if (key != null) {
      current = key.group(1);
      tags[current!] = [line.substring(key.end).trim()];
    } else if (current != null) {
      tags[current]!.add(line.trim());
    }
  }
  return tags;
}

final RegExp _annotation = RegExp(
  r'''^\s*@Tags\(\s*(?:const\s*)?(?:<String>\s*)?\[([^\]]*)\]''',
  multiLine: true,
);
final RegExp _namedList = RegExp(
  r'''\btags:\s*(?:const\s*)?(?:<String>\s*)?\[([^\]]*)\]''',
);
final RegExp _namedSingle = RegExp(r'''\btags:\s*['"]([^'"]+)['"]''');
final RegExp _literal = RegExp(r'''['"]([^'"]+)['"]''');

/// Literal tags used in [source].
Set<String> _usedTags(String source) => {
  for (final m in [
    ..._annotation.allMatches(source),
    ..._namedList.allMatches(source),
  ])
    for (final l in _literal.allMatches(m.group(1)!)) l.group(1)!,
  for (final m in _namedSingle.allMatches(source)) m.group(1)!,
};

void main() {
  late Map<String, List<String>> declared;
  late Map<String, Set<String>> usedByFile;

  setUpAll(() {
    final yaml = File('dart_test.yaml');
    expect(yaml.existsSync(), isTrue, reason: 'run from packages/sync_engine');
    declared = _declaredTags(yaml.readAsStringSync());
    usedByFile = {
      for (final f in Directory('test').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            !f.path.endsWith('dart_test_yaml_test.dart'))
          f.path: _usedTags(f.readAsStringSync()),
    };
  });

  test('declares exactly the planned tags (3.2)', () {
    expect(declared.keys.toSet(), {'scenario', 'golden', 'integration'});
  });

  test('skips integration by default', () {
    expect(
      declared['integration']!.any((l) => l.startsWith('skip:')),
      isTrue,
      reason: 'integration runs only at the integration stage (7.7)',
    );
    expect(declared['scenario']!.any((l) => l.startsWith('skip:')), isFalse);
    expect(declared['golden']!.any((l) => l.startsWith('skip:')), isFalse);
  });

  test('every tag used by a test is declared', () {
    final undeclared = {
      for (final e in usedByFile.entries)
        for (final tag in e.value)
          if (!declared.containsKey(tag)) '${e.key}: $tag',
    };
    expect(undeclared, isEmpty);
  });

  group('the scanner', () {
    test('reads annotations and named tags', () {
      expect(_usedTags("@Tags(['golden'])\nlibrary;"), {'golden'});
      expect(_usedTags('@Tags(<String>["a", \'b\'])'), {'a', 'b'});
      expect(_usedTags("test('x', () {}, tags: ['scenario']);"), {'scenario'});
      expect(_usedTags("group('x', () {}, tags: 'integration');"), {
        'integration',
      });
    });

    test('reads the tags block of dart_test.yaml', () {
      final tags = _declaredTags('''
# comment
tags:
  a: {}   # note
  b:
    skip: "why"
other:
  c: {}
''');
      expect(tags.keys, ['a', 'b']);
      expect(tags['b'], ['', 'skip: "why"']);
    });
  });
}
