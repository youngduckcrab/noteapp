// ws check rules of the foundation step B1: R1–R3, R7–R9 (R15 lives in
// test_tags_test.dart). docs/plans/01-infra.md 6.2 and 9.1.

import 'package:test/test.dart';

import '../src/cli.dart';
import '../src/rules.dart';
import 'support/fixture_workspace.dart';

/// Contract 00-overview 7.5 (v1.3) external packages — the snapshot that
/// `pinned_external` must equal (analyzer is added only at G3 with R14).
const _contract75 = <String, String>{
  'flutter_riverpod': '3.4.3',
  'riverpod': '3.4.3',
  'material_ui': '1.10.0',
  'go_router': '18.1.2',
  'cupertino_icons': '2.0.0',
  'web': '1.1.2',
  'meta': '1.19.0',
  'collection': '1.19.1',
  'clock': '1.1.3',
  'crypto': '3.0.8',
  'drift': '2.35.3',
  'sqlite3': '3.8.0',
  'idb_shim': '2.11.2',
  'uuid': '4.6.0',
  'pdfrx': '2.11.0',
  'pdfium_dart': '0.4.1',
  'ffi': '2.2.0',
  'file_picker': '13.3.2',
  'firebase_core': '5.1.0',
  'firebase_auth': '7.0.1',
  'cloud_firestore': '7.1.0',
  'firebase_storage': '14.0.1',
  'connectivity_plus': '7.3.2',
  'test': '1.31.1',
  'build_runner': '2.16.1',
  'drift_dev': '2.35.2',
  'fake_async': '1.3.3',
  'perfect_freehand': '2.5.2+1',
  'fake_cloud_firestore': '4.5.0',
  'firebase_auth_mocks': '0.16.0',
  'flutter_lints': '6.0.0',
  'yaml': '3.1.4',
  'args': '2.7.0',
  'path': '1.9.1',
  'image': '4.12.0',
};

void main() {
  late WorkspaceRules rules;
  FixtureWorkspace? fixture;

  setUpAll(() => rules = WorkspaceRules.load(realRulesPath));
  tearDown(() {
    fixture?.dispose();
    fixture = null;
  });

  List<RuleViolation> check(Map<String, String?> overrides, {String? rule}) {
    fixture = FixtureWorkspace.clean(overrides);
    return [
      for (final v in checkWorkspace(fixture!.load(), rules))
        if (rule == null || v.rule == rule) v,
    ];
  }

  test('the clean fixture has no violation and no warning', () {
    expect(check({}), isEmpty);
  });

  group('rules file', () {
    test('pinned_external equals the contract 7.5 table', () {
      expect(rules.pinnedExternal, _contract75);
      expect(rules.pinnedExternal.length, 35);
    });

    test(
      'allowed_dependencies equals contract 7.1 (app without sync_engine)',
      () {
        expect(rules.allowedDependencies, {
          'note_core': <String>[],
          'ink_engine': ['note_core'],
          'feature_editor': ['note_core', 'ink_engine'],
          'feature_library': ['note_core'],
          'pdf_io': ['note_core', 'ink_engine'],
          'sync_engine': ['note_core'],
          'noteapp': [
            'note_core',
            'ink_engine',
            'feature_editor',
            'feature_library',
            'pdf_io',
          ],
        });
      },
    );

    test('keeps the data of the later rules (4.3 full format)', () {
      expect(rules.pureDartMembers, ['note_core']);
      expect(rules.libExceptions, ['packages/note_core/lib/testing_vm.dart']);
      expect(rules.testOnlyEntrypoints, ['testing.dart', 'testing_vm.dart']);
      expect(rules.forbiddenImportsLibAndTest, [
        'package:flutter/material.dart',
        'package:flutter/cupertino.dart',
      ]);
      expect(rules.fixtureDirs, ['tool/test/fixtures/']);
      expect(rules.nativeOnlyImports, isNotEmpty);
      expect(rules.webOnlyImports, isNotEmpty);
      expect(rules.globalTriggers, contains('pubspec.lock'));
    });
  });

  group('R1', () {
    test('a listed member without pubspec.yaml', () {
      final v = check({'packages/ink_engine/pubspec.yaml': null}, rule: 'R1');
      expect(v.single.path, 'pubspec.yaml');
      expect(v.single.line, 9); // the `- packages/ink_engine` entry
      expect(v.single.message, contains('packages/ink_engine'));
    });

    test('a member without resolution: workspace', () {
      final v = check({
        'packages/note_core/pubspec.yaml': '''
name: note_core
environment:
  sdk: ^3.13.0
  flutter: 3.47.9
''',
      }, rule: 'R1');
      expect(v.single.path, 'packages/note_core/pubspec.yaml');
      expect(v.single.message, contains('resolution: workspace'));
    });

    test('a package directory missing from the workspace list', () {
      final v = check({
        'packages/pdf_io/pubspec.yaml': 'name: pdf_io\n',
      }, rule: 'R1');
      expect(v.single.path, 'packages/pdf_io/pubspec.yaml');
      expect(v.single.message, contains('not listed under `workspace:`'));
    });

    test('a nested resolution: workspace package must be listed too', () {
      final v = check({
        'packages/ink_engine/example/pubspec.yaml':
            'name: ink_lab\nresolution: workspace\n',
        // A nested package that is its own root is fine.
        'packages/ink_engine/tool/fixture/pubspec.yaml': 'name: other\n',
      }, rule: 'R1');
      expect(v.single.path, 'packages/ink_engine/example/pubspec.yaml');
    });
  });

  group('R2', () {
    test('a different sdk constraint', () {
      final v = check({
        'packages/ink_engine/pubspec.yaml': '''
name: ink_engine
resolution: workspace
environment:
  sdk: ^3.12.0
  flutter: 3.47.9
dependencies:
  flutter:
    sdk: flutter
''',
      }, rule: 'R2');
      expect(v.single.format(), contains('[R2] ink_engine: `environment.sdk`'));
      expect(v.single.line, 4);
    });

    test('a pure Dart member without environment.flutter', () {
      final v = check({
        'packages/note_core/pubspec.yaml': '''
name: note_core
resolution: workspace
environment:
  sdk: ^3.13.0
''',
      }, rule: 'R2');
      expect(
        v.single.message,
        contains('missing `environment.flutter: 3.47.9`'),
      );
    });

    test('a pure Dart member with an sdk: flutter dependency', () {
      final v = check({
        'packages/note_core/pubspec.yaml': '''
name: note_core
resolution: workspace
environment:
  sdk: ^3.13.0
  flutter: 3.47.9
dev_dependencies:
  flutter_test:
    sdk: flutter
''',
      }, rule: 'R2');
      expect(v.single.line, 7);
      expect(v.single.message, contains('flutter_test in dev_dependencies'));
    });

    test('a pure Dart member importing package:flutter_test', () {
      final v = check({
        'packages/note_core/test/w_test.dart':
            "import 'package:flutter_test/flutter_test.dart';\n",
        'packages/note_core/lib/src/w.dart':
            "import 'package:flutter/foundation.dart';\n",
      }, rule: 'R2');
      expect(v.map((x) => x.path), [
        'packages/note_core/lib/src/w.dart',
        'packages/note_core/test/w_test.dart',
      ]);
    });

    test('Flutter members may import package:flutter/', () {
      expect(
        check({
          'packages/ink_engine/lib/src/x.dart':
              "import 'package:flutter/foundation.dart';\n",
        }, rule: 'R2'),
        isEmpty,
      );
    });
  });

  group('R3', () {
    test('analysis_options.yaml inside a member', () {
      final v = check({
        'packages/feature_library/analysis_options.yaml': 'include: x\n',
      }, rule: 'R3');
      expect(v.single.path, 'packages/feature_library/analysis_options.yaml');
    });
  });

  group('R7', () {
    test('SDK material.dart in test/ and cupertino.dart in lib/', () {
      final v = check({
        'packages/feature_library/test/a_test.dart':
            "import 'package:flutter/material.dart';\n",
        'packages/feature_library/lib/src/b.dart':
            "export 'package:flutter/cupertino.dart' show CupertinoIcons;\n",
      }, rule: 'R7');
      expect(v.map((x) => x.format()), [
        startsWith(
          'packages/feature_library/lib/src/b.dart:1: [R7] '
          '`package:flutter/cupertino.dart`',
        ),
        startsWith(
          'packages/feature_library/test/a_test.dart:1: [R7] '
          '`package:flutter/material.dart`',
        ),
      ]);
    });

    test("another member's src/ (lib and test), also in conditional URIs", () {
      final v = check({
        'packages/ink_engine/lib/src/x.dart': '''
import 'package:note_core/src/a.dart';
import 'y_stub.dart'
    if (dart.library.js_interop) 'package:note_core/src/b_browser.dart';
''',
        'app/test/x_test.dart': "import 'package:ink_engine/src/z.dart';\n",
      }, rule: 'R7');
      expect(v.map((x) => '${x.path}:${x.line}'), [
        'app/test/x_test.dart:1',
        'packages/ink_engine/lib/src/x.dart:1',
        'packages/ink_engine/lib/src/x.dart:2',
      ]);
    });

    test('own src/, non-member packages, comments and tool/ are fine', () {
      expect(
        check({
          // The clean fixture already imports package:note_core/src/ from
          // note_core's own test.
          'packages/ink_engine/lib/src/y.dart': '''
import 'package:material_ui/src/anything.dart';
// import 'package:flutter/material.dart';
/* import 'package:note_core/src/a.dart'; */
''',
          'packages/ink_engine/tool/prepare_web_test.dart':
              "import 'package:flutter/material.dart';\n",
        }, rule: 'R7'),
        isEmpty,
      );
    });
  });

  group('R8', () {
    String libraryPubspec(String extra) => '''
name: feature_library
resolution: workspace
environment:
  sdk: ^3.13.0
  flutter: 3.47.9
dependencies:
  flutter:
    sdk: flutter
$extra''';

    Map<String, String> withEditor() => {
      'pubspec.yaml': cleanWorkspaceFiles()['pubspec.yaml']!.replaceFirst(
        '  - packages/feature_library\n',
        '  - packages/feature_library\n  - packages/feature_editor\n',
      ),
      'packages/feature_editor/pubspec.yaml': '''
name: feature_editor
resolution: workspace
environment:
  sdk: ^3.13.0
  flutter: 3.47.9
dependencies:
  note_core: any
  ink_engine: any
''',
    };

    test('feature_library -> feature_editor is not allowed', () {
      final v = check({
        ...withEditor(),
        'packages/feature_library/pubspec.yaml': libraryPubspec(
          '  note_core: any\n  feature_editor: any\n',
        ),
      }, rule: 'R8');
      expect(v.single.message, contains('must not depend on feature_editor'));
      expect(v.single.line, 10);
    });

    test('noteapp -> sync_engine is not allowed in this scope', () {
      final v = check({
        'pubspec.yaml': cleanWorkspaceFiles()['pubspec.yaml']!.replaceFirst(
          '  - packages/feature_library\n',
          '  - packages/feature_library\n  - packages/sync_engine\n',
        ),
        'packages/sync_engine/pubspec.yaml': '''
name: sync_engine
resolution: workspace
environment:
  sdk: ^3.13.0
  flutter: 3.47.9
dependencies:
  note_core: any
''',
        'app/pubspec.yaml': '''
name: noteapp
resolution: workspace
environment:
  sdk: ^3.13.0
  flutter: 3.47.9
dependencies:
  note_core: any
  sync_engine: any
''',
      }, rule: 'R8');
      expect(v.single.path, 'app/pubspec.yaml');
      expect(
        v.single.message,
        contains('noteapp must not depend on sync_engine'),
      );
    });

    test('path: and version constraints on siblings', () {
      final v = check({
        'packages/feature_library/pubspec.yaml': libraryPubspec(
          '  note_core:\n    path: ../note_core\n',
        ),
        'packages/ink_engine/pubspec.yaml': '''
name: ink_engine
resolution: workspace
environment:
  sdk: ^3.13.0
  flutter: 3.47.9
dev_dependencies:
  note_core: ^0.0.1
''',
      }, rule: 'R8');
      expect(v.map((x) => x.path), [
        'packages/feature_library/pubspec.yaml',
        'packages/ink_engine/pubspec.yaml',
      ]);
      expect(v.every((x) => x.message.contains('must be declared as')), isTrue);
    });

    test('a member missing from allowed_dependencies', () {
      final v = check({
        'pubspec.yaml': cleanWorkspaceFiles()['pubspec.yaml']!.replaceFirst(
          '  - packages/feature_library\n',
          '  - packages/feature_library\n  - packages/extra\n',
        ),
        'packages/extra/pubspec.yaml': '''
name: extra
resolution: workspace
environment:
  sdk: ^3.13.0
  flutter: 3.47.9
''',
      }, rule: 'R8');
      expect(v.single.message, contains('extra is not listed'));
    });
  });

  group('R9', () {
    String inkPubspec(String deps) => '''
name: ink_engine
resolution: workspace
environment:
  sdk: ^3.13.0
  flutter: 3.47.9
dependencies:
  flutter:
    sdk: flutter
  note_core: any
$deps''';

    test('caret, range, any and path versions', () {
      final v = check({
        'packages/ink_engine/pubspec.yaml': inkPubspec('''
  meta: ^1.19.0
  collection: '>=1.19.0 <2.0.0'
  clock: any
  uuid:
  web:
    path: ../web
'''),
      }, rule: 'R9');
      expect(v.map((x) => x.line), [10, 11, 12, 13, 14]);
      expect(v.every((x) => x.message.contains('exact version')), isTrue);
    });

    test('an exact version different from pinned_external', () {
      final v = check({
        'packages/ink_engine/pubspec.yaml': inkPubspec('  riverpod: 3.4.2\n'),
      }, rule: 'R9');
      expect(
        v.single.message,
        'ink_engine: riverpod is 3.4.2 but contract 7.5 pins 3.4.3 '
        '(tool/workspace_rules.yaml pinned_external)',
      );
    });

    test('hosted map with the pinned version is fine', () {
      expect(
        check({
          'packages/ink_engine/pubspec.yaml': inkPubspec(
            '  riverpod:\n    hosted: https://pub.dev\n    version: 3.4.3\n',
          ),
        }),
        isEmpty,
      );
    });

    test('the root pubspec is checked too', () {
      final v = check({
        'pubspec.yaml': cleanWorkspaceFiles()['pubspec.yaml']!.replaceFirst(
          'test: 1.31.1',
          'test: 1.33.0',
        ),
      }, rule: 'R9');
      expect(v.single.path, 'pubspec.yaml');
      expect(v.single.message, startsWith('workspace root: test is 1.33.0'));
    });

    test('an unpinned external package is a warning (R9w)', () {
      final v = check({
        'packages/ink_engine/pubspec.yaml': inkPubspec('  foo: 1.0.0\n'),
      });
      expect(v.single.rule, 'R9w');
      expect(v.single.isWarning, isTrue);
      expect(v.single.message, contains('foo 1.0.0 is not in pinned_external'));
    });

    test('R9w: ws check exits 0, --strict exits 1', () async {
      fixture = FixtureWorkspace.clean({
        'packages/ink_engine/pubspec.yaml': inkPubspec('  foo: 1.0.0\n'),
      });
      Future<(int, String)> run(List<String> extra) async {
        final out = StringBuffer();
        final code = await runWs(
          ['check', '--rules', realRulesPath, ...extra],
          context: WsContext(
            root: fixture!.root,
            out: out,
            err: StringBuffer(),
          ),
        );
        return (code, out.toString());
      }

      final (code, out) = await run([]);
      expect(code, 0);
      expect(out, contains('[R9w]'));
      expect(out, contains('0 violation(s), 1 warning(s)'));

      final (strictCode, strictOut) = await run(['--strict']);
      expect(strictCode, 1);
      expect(strictOut, contains('1 violation(s), 0 warning(s)'));
    });
  });

  test('violations are printed as path:line: [rule] message', () async {
    fixture = FixtureWorkspace.clean({
      'packages/feature_library/analysis_options.yaml': '',
    });
    final out = StringBuffer();
    final code = await runWs([
      'check',
      '--rules',
      realRulesPath,
    ], context: WsContext(root: fixture!.root, out: out, err: StringBuffer()));
    expect(code, 1);
    expect(
      out.toString().split('\n').first,
      'packages/feature_library/analysis_options.yaml:1: [R3] '
      'feature_library: members must not have analysis_options.yaml '
      '(the root file applies)',
    );
  });

  test('a missing rules file is an environment error (exit 3)', () async {
    fixture = FixtureWorkspace.clean();
    final err = StringBuffer();
    final code = await runWs([
      'check',
    ], context: WsContext(root: fixture!.root, out: StringBuffer(), err: err));
    expect(code, environmentExitCode);
    expect(err.toString(), contains('rules file not found'));
  });
}
