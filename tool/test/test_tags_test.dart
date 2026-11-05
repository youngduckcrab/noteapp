// R15 — test tag declarations (contract 00-overview 7.4.2 / 7.4.8 v1.2,
// docs/plans/01-infra.md 6.2 and 9.1).

import 'package:test/test.dart';

import '../src/cli.dart';
import '../src/rules.dart';
import '../src/test_tags.dart';
import 'support/fixture_workspace.dart';

const _integrationSkipped = '''
tags:
  integration:
    skip: "integration stage only — ws test --run-skipped -t integration"
''';

void main() {
  group('scanTestTags', () {
    test('reads @Tags list literals with either quote style', () {
      final uses = scanTestTags('''
@Tags(['integration', "golden"])
library;
''');
      expect(uses, [const TagUse('integration', 1), const TagUse('golden', 1)]);
    });

    test('reads typed and const lists', () {
      expect(scanTestTags("@Tags(<String>['a'])\nlibrary;").map((u) => u.tag), [
        'a',
      ]);
      expect(scanTestTags("@Tags(const ['b'])\nlibrary;").map((u) => u.tag), [
        'b',
      ]);
    });

    test('reads tags: on test, testWidgets and group', () {
      final uses = scanTestTags('''
void main() {
  group('g', tags: 'scenario', () {});
  test('a', () {}, tags: ['golden', 'pdfium']);
  testWidgets('x', tags: ['golden'], (tester) async {});
  test('b', () {}, tags: 'perf');
}
''');
      expect(uses, [
        const TagUse('scenario', 2),
        const TagUse('golden', 3),
        const TagUse('pdfium', 3),
        const TagUse('golden', 4),
        const TagUse('perf', 5),
      ]);
    });

    test('reads multi-line lists and reports the line of each literal', () {
      final uses = scanTestTags('''
void main() {
  test(
    'a',
    () {},
    tags: [
      'golden',
      'perf',
    ],
  );
}
''');
      expect(uses, [const TagUse('golden', 6), const TagUse('perf', 7)]);
    });

    test('ignores commented-out tags', () {
      final uses = scanTestTags('''
// @Tags(['integration'])
/* @Tags(['perf']) /* nested */ test('a', () {}, tags: ['golden']); */
/// test('a', () {}, tags: 'scenario');
library;
''');
      expect(uses, isEmpty);
    });

    test('ignores tag-like text inside strings', () {
      final uses = scanTestTags(r'''
void main() {
  test("tags: 'golden' in a name", () {});
  test(r"@Tags(['perf'])", () {});
  final s = """
  @Tags(['integration'])
  """;
  test('a $s', () {}, tags: ['ok']);
}
''');
      expect(uses.map((u) => u.tag), ['ok']);
    });

    test('does not recognise tags passed through variables or constants', () {
      // Contract 7.4.8 v1.2: the scanner only sees string literals.
      final uses = scanTestTags('''
const kTags = ['integration'];
const kTag = 'perf';
void main() {
  test('a', () {}, tags: kTags);
  test('b', () {}, tags: kTag);
  test('c', () {}, tags: [kTag, 'golden']);
  test('d', () {}, tags: ['in\$kTag']);
}
''');
      expect(uses.map((u) => u.tag), ['golden']);
    });

    test('ignores tags: of calls other than test, testWidgets and group', () {
      // B2 report: data constructors such as Note(tags: [...]) in test code
      // are not test tags (contract 7.4.2 names test / testWidgets / group).
      final uses = scanTestTags('''
void main() {
  final note = Note(tags: ['math'], title: 'x');
  final copy = note.copyWith(tags: const <String>['art']);
  final single = Label(tags: 'perf');
  final list = [Note(tags: ['in-list'])];
  testWidgets('w', (tester) async {
    final inner = Note(tags: ['inside']);
    await tester.pumpWidget(Card(tags: ['widget']));
  }, tags: ['golden']);
  ft.group('g', () {
    test('t', () => Note(tags: ['nested']), tags: 'perf');
  }, tags: ['scenario']);
}
''');
      expect(uses, [
        const TagUse('golden', 9),
        const TagUse('perf', 11),
        const TagUse('scenario', 12),
      ]);
    });

    test('ignores other named arguments and member accesses', () {
      final uses = scanTestTags('''
void main() {
  test('a', () {}, onPlatform: {'browser': Skip('x')});
  final t = config.tags;
  print(other.tags);
}
''');
      expect(uses, isEmpty);
    });
  });

  group('DartTestConfig', () {
    test('skip string or true means skipped, skip false only declared', () {
      final config = DartTestConfig.parse('''
tags:
  integration:
    skip: "integration stage only"
  perf:
    skip: true
  golden:
  bench:
    skip: false
  pdfium: {}
''');
      expect(config.declarationOf('integration'), TagDeclaration.skipped);
      expect(config.declarationOf('perf'), TagDeclaration.skipped);
      expect(config.declarationOf('golden'), TagDeclaration.declared);
      expect(config.declarationOf('bench'), TagDeclaration.declared);
      expect(config.declarationOf('pdfium'), TagDeclaration.declared);
      expect(config.declarationOf('scenario'), TagDeclaration.missing);
    });

    test('a file without tags: declares nothing', () {
      final config = DartTestConfig.parse('timeout: 2x\n');
      expect(config.declarationOf('golden'), TagDeclaration.missing);
    });
  });

  group('R15 on a workspace', () {
    late FixtureWorkspace fixture;
    late WorkspaceRules rules;

    setUp(() => rules = WorkspaceRules.load(realRulesPath));
    tearDown(() => fixture.dispose());

    List<RuleViolation> r15() => [
      for (final v in checkWorkspace(fixture.load(), rules))
        if (v.rule == 'R15') v,
    ];

    test('the clean fixture has no R15 violation', () {
      fixture = FixtureWorkspace.clean();
      expect(r15(), isEmpty);
    });

    test('integration tag without dart_test.yaml is a violation', () {
      fixture = FixtureWorkspace.clean({
        'packages/note_core/test/integration/x_test.dart': '''
@Tags(['integration'])
library;
''',
      });
      final violations = r15();
      expect(violations, hasLength(1));
      expect(
        violations.single.path,
        'packages/note_core/test/integration/x_test.dart',
      );
      expect(violations.single.line, 1);
      expect(
        violations.single.message,
        allOf(
          startsWith(
            "note_core: tag 'integration' used in "
            'test/integration/x_test.dart but',
          ),
          contains('dart_test.yaml'),
        ),
      );
    });

    test('integration declared without skip is a violation', () {
      fixture = FixtureWorkspace.clean({
        'packages/note_core/dart_test.yaml': 'tags:\n  integration:\n',
        'packages/note_core/test/x_test.dart': "@Tags(['integration'])\n",
      });
      final violations = r15();
      expect(violations, hasLength(1));
      expect(
        violations.single.format(),
        'packages/note_core/test/x_test.dart:1: [R15] note_core: tag '
        "'integration' used in test/x_test.dart but dart_test.yaml does not "
        'skip it',
      );
    });

    test('integration declared with skip is fine', () {
      fixture = FixtureWorkspace.clean({
        'packages/note_core/dart_test.yaml': _integrationSkipped,
        'packages/note_core/test/x_test.dart': "@Tags(['integration'])\n",
      });
      expect(r15(), isEmpty);
    });

    test('perf is checked like integration', () {
      fixture = FixtureWorkspace.clean({
        'packages/ink_engine/dart_test.yaml': 'tags:\n  perf: {}\n',
        'packages/ink_engine/test/perf_test.dart':
            "void main() { test('p', () {}, tags: 'perf'); }\n",
      });
      expect(r15().single.message, contains('does not skip it'));

      fixture.write(
        'packages/ink_engine/dart_test.yaml',
        'tags:\n  perf:\n    skip: "manual benchmark"\n',
      );
      expect(r15(), isEmpty);
    });

    test('golden only needs a declaration', () {
      fixture = FixtureWorkspace.clean({
        'packages/ink_engine/dart_test.yaml': _integrationSkipped,
        'packages/ink_engine/test/goldens/a_test.dart': '''
void main() {
  testWidgets('x', tags: ['golden'], (tester) async {});
}
''',
      });
      final violations = r15();
      expect(violations, hasLength(1));
      expect(violations.single.line, 2);
      expect(
        violations.single.message,
        "ink_engine: tag 'golden' used in test/goldens/a_test.dart but "
        'dart_test.yaml does not declare it under `tags:`',
      );

      fixture.write(
        'packages/ink_engine/dart_test.yaml',
        '$_integrationSkipped  golden:\n',
      );
      expect(r15(), isEmpty);
    });

    test("tags: 'golden' (single string) is recognised", () {
      fixture = FixtureWorkspace.clean({
        'packages/ink_engine/test/a_test.dart':
            "void main() { test('x', () {}, tags: 'golden'); }\n",
      });
      expect(r15().single.message, contains("tag 'golden'"));
    });

    test('commented-out @Tags is ignored', () {
      fixture = FixtureWorkspace.clean({
        'packages/note_core/test/x_test.dart': '''
// @Tags(['integration'])
/* @Tags(['perf']) */
library;
''',
      });
      expect(r15(), isEmpty);
    });

    test('a member without tags needs no dart_test.yaml', () {
      fixture = FixtureWorkspace.clean({
        'packages/note_core/test/plain_test.dart':
            "void main() { test('x', () {}); }\n",
      });
      expect(r15(), isEmpty);
    });

    test('the same tag in several files of a member is reported once', () {
      fixture = FixtureWorkspace.clean({
        'packages/note_core/test/b_test.dart': "@Tags(['integration'])\n",
        'packages/note_core/test/a_test.dart': "@Tags(['integration'])\n",
        'packages/note_core/test/c/d_test.dart':
            "void main() { test('x', () {}, tags: ['integration']); }\n",
      });
      final violations = r15();
      expect(violations, hasLength(1));
      // First file in path order.
      expect(violations.single.path, 'packages/note_core/test/a_test.dart');
    });

    test('different members are reported separately', () {
      fixture = FixtureWorkspace.clean({
        'packages/note_core/test/a_test.dart': "@Tags(['integration'])\n",
        'app/test/a_test.dart': "@Tags(['integration'])\n",
      });
      expect(r15().map((v) => v.path), [
        'app/test/a_test.dart',
        'packages/note_core/test/a_test.dart',
      ]);
    });

    test(
      'tags passed through a variable are not recognised (0 violations)',
      () {
        // Fixes the contract 7.4.8 v1.2 "literals only" limitation.
        fixture = FixtureWorkspace.clean({
          'packages/note_core/test/x_test.dart': '''
const kTags = ['integration'];
void main() {
  test('x', () {}, tags: kTags);
}
''',
        });
        expect(r15(), isEmpty);
      },
    );

    test('a broken dart_test.yaml is reported', () {
      fixture = FixtureWorkspace.clean({
        'packages/note_core/dart_test.yaml': 'tags: [unclosed\n',
        'packages/note_core/test/x_test.dart': "@Tags(['golden'])\n",
      });
      expect(r15().single.message, contains('cannot parse dart_test.yaml'));
    });

    test('ws check exits with 1 when R15 finds a violation', () async {
      fixture = FixtureWorkspace.clean({
        'packages/note_core/test/x_test.dart': "@Tags(['integration'])\n",
      });
      final out = StringBuffer();
      final code = await runWs([
        'check',
        '--rules',
        realRulesPath,
      ], context: WsContext(root: fixture.root, out: out, err: StringBuffer()));
      expect(code, 1);
      expect(out.toString(), contains('[R15] note_core:'));
      expect(out.toString(), contains('1 violation(s)'));
    });

    test(
      'ws check exits with 0 once the tag is declared and skipped',
      () async {
        fixture = FixtureWorkspace.clean({
          'packages/note_core/dart_test.yaml': _integrationSkipped,
          'packages/note_core/test/x_test.dart': "@Tags(['integration'])\n",
        });
        final code = await runWs(
          ['check', '--rules', realRulesPath],
          context: WsContext(
            root: fixture.root,
            out: StringBuffer(),
            err: StringBuffer(),
          ),
        );
        expect(code, 0);
      },
    );
  });

  test('the real rules file skips integration and perf by default', () {
    expect(
      WorkspaceRules.load(realRulesPath).skipByDefaultTags,
      unorderedEquals(['integration', 'perf']),
    );
  });
}
