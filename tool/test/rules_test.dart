// ws check rules R1–R13 and R16 (R15 lives in test_tags_test.dart, R14 in
// export_names_test.dart). docs/plans/01-infra.md 6.2 and 9.1,
// docs/plans/m5-7/01-infra.md 4.3.1 and 6.2 (2차: R4 `dart:io` Platform, R16).

import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../src/cli.dart';
import '../src/flutter_runner.dart';
import '../src/rules.dart';
import '../src/web_assets.dart';
import '../src/workspace.dart';
import 'support/fake_processes.dart';
import 'support/fixture_workspace.dart';

/// Contract 00-overview 7.5 external packages — the snapshot that
/// `pinned_external` must equal (every row: 1차 v1.5 with the root dev
/// `analyzer` since the integration step G3, and the 2차 rows of
/// docs/plans/m5-7/00-overview.md 7.5 v2.1 including the transitive pins).
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
  'analyzer': '13.3.0',
  // 2차 (contract 7.5 v2.1)
  'record': '7.1.2',
  'just_audio': '0.10.6',
  'audio_session': '0.2.4',
  'flutter_foreground_task': '11.0.3',
  'image_picker': '1.2.4',
  'image_picker_ios': '0.8.13+13',
  'shared_preferences_android': '2.5.3',
  'shared_preferences_foundation': '2.6.0',
  'record_web': '2.1.3',
  'just_audio_web': '0.4.16',
  'record_platform_interface': '2.1.0',
  'just_audio_platform_interface': '4.6.0',
  'image_picker_platform_interface': '2.11.2',
  'path_provider': '2.1.6',
  'share_plus': '13.3.1', // app direct: native PDF share
  'google_mlkit_digital_ink_recognition': '0.16.1',
  'http': '1.6.0',
  'flutter_math_fork': '0.7.4',
  'flutter_onnxruntime': '1.9.0', // ink_recognition: on-device math engine
  'flutter_svg': '2.3.0',
  'vector_graphics': '1.2.3',
  'vector_graphics_compiler': '1.3.0',
  'xml': '7.0.1',
};

/// The plugins the app resolves after R2-B1 (`app/.flutter-plugins-
/// dependencies` `dependencyGraph`, docs/plans/m5-7/01-infra.md 4.3.1).
const _appPlugins = [
  'android_file_picker',
  'audio_session',
  'file_picker',
  'file_picker_darwin',
  'file_picker_linux',
  'file_picker_web',
  'file_selector_linux',
  'file_selector_macos',
  'file_selector_windows',
  'flutter_foreground_task',
  'flutter_onnxruntime',
  'flutter_plugin_android_lifecycle',
  'google_mlkit_commons',
  'google_mlkit_digital_ink_recognition',
  'image_picker',
  'image_picker_android',
  'image_picker_for_web',
  'image_picker_ios',
  'image_picker_linux',
  'image_picker_macos',
  'image_picker_windows',
  'integration_test',
  'jni',
  'jni_flutter',
  'just_audio',
  'just_audio_web',
  'path_provider',
  'path_provider_android',
  'path_provider_foundation',
  'path_provider_linux',
  'path_provider_windows',
  'pdfium_flutter',
  'pencil_bridge',
  'record',
  'record_android',
  'record_ios',
  'record_linux',
  'record_macos',
  'record_web',
  'record_windows',
  'share_plus',
  'shared_preferences',
  'shared_preferences_android',
  'shared_preferences_foundation',
  'shared_preferences_linux',
  'shared_preferences_web',
  'shared_preferences_windows',
  'url_launcher',
  'url_launcher_android',
  'url_launcher_ios',
  'url_launcher_linux',
  'url_launcher_macos',
  'url_launcher_web',
  'url_launcher_windows',
  'windows_file_picker',
];

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
    test('pinned_external equals the contract 7.5 table (1차 + 2차)', () {
      expect(rules.pinnedExternal, _contract75);
      // + share_plus (app), flutter_onnxruntime (ink_recognition)
      expect(rules.pinnedExternal.length, 36 + 21 + 2);
    });

    test('allowed_dependencies equals contract 7.1 v2.1 (app without '
        'sync_engine, service packages)', () {
      expect(rules.allowedDependencies, {
        'note_core': <String>[],
        'ink_engine': ['note_core'],
        'feature_editor': ['note_core', 'ink_engine', 'ui_kit'],
        'feature_library': ['note_core', 'ui_kit'],
        'pdf_io': ['note_core', 'ink_engine', 'ui_kit'],
        'sync_engine': ['note_core'],
        'media_io': ['note_core', 'ui_kit'],
        'ink_recognition': ['note_core', 'ink_engine', 'ui_kit'],
        'pencil_bridge': <String>[],
        // v2.14-ui: the shared design layer.
        'ui_kit': <String>[],
        'noteapp': [
          'note_core',
          'ink_engine',
          'feature_editor',
          'feature_library',
          'pdf_io',
          'media_io',
          'ink_recognition',
          'pencil_bridge',
          'ui_kit',
        ],
        'ink_lab': ['note_core', 'ink_engine'],
      });
    });

    test('keeps the data of the later rules (4.3 full format)', () {
      expect(rules.pureDartMembers, ['note_core']);
      expect(rules.libExceptions, [
        'packages/note_core/lib/testing_vm.dart',
        'packages/note_core/lib/testing_web.dart',
        'packages/ink_engine/example/lib/',
      ]);
      expect(rules.appMembers, ['noteapp', 'ink_lab']);
      expect(rules.testOnlyEntrypoints, [
        'testing.dart',
        'testing_vm.dart',
        'testing_web.dart',
      ]);
      expect(rules.forbiddenImportsLibAndTest, [
        'package:flutter/material.dart',
        'package:flutter/cupertino.dart',
      ]);
      expect(rules.fixtureDirs, ['tool/test/fixtures/']);
      expect(rules.nativeOnlyImports, isNotEmpty);
      expect(rules.webOnlyImports, isNotEmpty);
      expect(rules.globalTriggers, contains('pubspec.lock'));
    });

    test('2차 data (contract 7.4.1 / 7.4.6 v2.1)', () {
      expect(rules.nativeOnlyImports, [
        'package:ffi/',
        'package:pdfium_dart/',
        'package:drift/native.dart',
        'package:google_mlkit_digital_ink_recognition/',
        'package:google_mlkit_commons/',
        'package:flutter_foreground_task/',
        'package:path_provider/',
        'package:share_plus/',
        'package:flutter_onnxruntime/',
      ]);
      expect(rules.forbiddenIoMembers, ['Platform']);
      expect(rules.generatedFiles, contains('*.steps.dart'));
      expect(rules.skipByDefaultTags, [
        'integration',
        'perf',
        'media',
        'emulator',
      ]);
      expect(rules.pluginFreeMembers, [
        'feature_editor',
        'feature_library',
        'ink_engine',
        'note_core',
        'ui_kit',
      ]);
      expect(rules.pluginExceptions, {
        'pdf_io': ['file_picker'],
        'sync_engine': [
          'firebase_core',
          'firebase_auth',
          'cloud_firestore',
          'firebase_storage',
          'connectivity_plus',
        ],
      });
      expect(rules.pluginPackages, _appPlugins);
      expect(rules.pluginPackages, hasLength(55));
    });

    test('plugin_packages equals the app dependencyGraph (NR6) when the '
        'workspace is resolved', () {
      final file = File(
        p.join(repoRoot, 'app', '.flutter-plugins-dependencies'),
      );
      if (!file.existsSync()) {
        markTestSkipped('run `flutter pub get` first');
        return;
      }
      final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final graph = [
        for (final e in json['dependencyGraph']! as List<Object?>)
          (e! as Map<String, Object?>)['name']! as String,
      ]..sort();
      expect(rules.pluginPackages.toList()..sort(), graph);
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
          ['check', '--rules', realRulesPath, '--no-exports', ...extra],
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

  group('R4', () {
    test('dart:io in lib/a.dart; allowed in a_native.dart and b_io.dart', () {
      final v = check({
        'packages/ink_engine/lib/src/a.dart': "import 'dart:io';\n",
        'packages/ink_engine/lib/src/a_native.dart':
            "import 'dart:io';\nimport 'dart:ffi';\n",
        'packages/ink_engine/lib/src/b_io.dart': "import 'dart:io';\n",
      }, rule: 'R4');
      expect(v.single.path, 'packages/ink_engine/lib/src/a.dart');
      expect(v.single.message, contains('`dart:io` is not allowed in lib/'));
    });

    test('dart:html, dart:js_util and package:js are forbidden even in '
        'native files', () {
      final v = check({
        'packages/ink_engine/lib/src/a_native.dart':
            "import 'dart:html';\nimport 'dart:js_util';\n"
            "import 'package:js/js.dart';\n",
      }, rule: 'R4');
      expect(v.map((e) => e.line), [1, 2, 3]);
    });

    test('lib_exceptions: note_core/lib/testing_vm.dart may use dart:io and '
        'drift native', () {
      final v = check({
        'packages/note_core/lib/testing_vm.dart':
            "import 'dart:io';\nimport 'package:drift/native.dart';\n"
            "import 'testing.dart';\n",
        'packages/note_core/lib/testing.dart': '',
      }, rule: 'R4');
      expect(v, isEmpty);
    });

    test('native_only: pdfium_dart in compose_backend.dart is a violation, '
        'in compose_backend_native.dart it is allowed', () {
      final v = check({
        'packages/ink_engine/lib/src/compose/compose_backend.dart':
            "import 'package:pdfium_dart/pdfium_dart.dart';\n",
        'packages/ink_engine/lib/src/compose/compose_backend_native.dart':
            "import 'package:pdfium_dart/pdfium_dart.dart';\n"
            "import 'package:ffi/ffi.dart';\n",
      }, rule: 'R4');
      expect(
        v.single.path,
        'packages/ink_engine/lib/src/compose/compose_backend.dart',
      );
      expect(v.single.message, contains('native-only'));
    });

    test('drift/native.dart is native-only, other drift URIs are not', () {
      final v = check({
        'packages/note_core/lib/src/db.dart':
            "import 'package:drift/drift.dart';\n"
            "import 'package:drift/native.dart';\n",
      }, rule: 'R4');
      expect(v.single.line, 2);
    });

    test('test-only entry points through package: URIs', () {
      final v = check({
        'packages/note_core/lib/src/b.dart':
            "import 'package:note_core/testing.dart';\n",
        'packages/ink_engine/lib/src/c.dart':
            "export 'package:note_core/testing_vm.dart';\n",
        'packages/note_core/lib/testing.dart': '',
      }, rule: 'R4');
      expect(v.map((e) => e.path), [
        'packages/ink_engine/lib/src/c.dart',
        'packages/note_core/lib/src/b.dart',
      ]);
      expect(v.first.message, contains('test-only entry point'));
    });

    test('relative URIs: testing*.dart may import each other, other lib/ '
        'files may not reach them', () {
      final v = check({
        'packages/note_core/lib/testing.dart': "import 'src/a.dart';\n",
        'packages/feature_library/lib/testing.dart': '',
        'packages/feature_library/lib/testing_vm.dart':
            "import 'testing.dart';\n",
        'packages/note_core/lib/src/b.dart': "import '../testing.dart';\n",
      }, rule: 'R4');
      expect(v.single.path, 'packages/note_core/lib/src/b.dart');
      expect(v.single.message, contains('testing.dart'));
    });

    test('a directory entry of lib_exceptions exempts every file below it', () {
      final text = File(realRulesPath).readAsStringSync().replaceFirst(
        '  - packages/note_core/lib/testing_vm.dart',
        '  - packages/note_core/lib/testing_vm.dart\n'
            '  - packages/ink_engine/lib/lab/',
      );
      final custom = WorkspaceRules.parse(text);
      expect(custom.libExceptions, contains('packages/ink_engine/lib/lab/'));
      fixture = FixtureWorkspace.clean({
        'packages/ink_engine/lib/lab/deep/x.dart':
            "import 'package:note_core/testing.dart';\nimport 'dart:io';\n",
        'packages/ink_engine/lib/labx.dart':
            "import 'package:note_core/testing.dart';\n",
      });
      final v = [
        for (final r in checkWorkspace(fixture!.load(), custom))
          if (r.rule == 'R4') r,
      ];
      expect(v.single.path, 'packages/ink_engine/lib/labx.dart');
    });

    test('test/ files may use dart:io and testing.dart', () {
      final v = check({
        'packages/note_core/test/b_test.dart':
            "import 'dart:io';\nimport 'package:note_core/testing.dart';\n",
      }, rule: 'R4');
      expect(v, isEmpty);
    });

    test('a package barrel named <pkg>_io.dart is not a platform file', () {
      final v = check({
        'packages/feature_library/pubspec.yaml': null,
        'packages/feature_library/lib/feature_library.dart': null,
        'packages/pdf_io/pubspec.yaml': '''
name: pdf_io
publish_to: none
resolution: workspace
environment:
  sdk: ^3.13.0
  flutter: 3.47.9
dependencies:
  note_core: any
''',
        'pubspec.yaml': cleanWorkspaceFiles()['pubspec.yaml']!.replaceFirst(
          'packages/feature_library',
          'packages/pdf_io',
        ),
        'packages/pdf_io/lib/pdf_io.dart': "import 'dart:io';\n",
        'app/lib/main.dart': "import 'package:pdf_io/pdf_io.dart';\n",
      });
      expect(
        v.where((e) => e.rule == 'R4').single.path,
        'packages/pdf_io/lib/pdf_io.dart',
      );
      expect(v.where((e) => e.rule == 'R6'), isEmpty);
    });
  });

  group('R4 dart:io Platform (2차, contract 7.4.1)', () {
    test('Platform in a native file: direct, show and an `as io` prefix', () {
      final v = check({
        'packages/ink_engine/lib/src/a_native.dart':
            "import 'dart:io';\n\nbool get ios => Platform.isIOS;\n",
        'packages/ink_engine/lib/src/b_native.dart':
            "import 'dart:io' show Platform;\n",
        'packages/ink_engine/lib/src/c_io.dart':
            "import 'dart:io' as io;\n\n"
            'String get os => io.Platform.operatingSystem;\n',
      }, rule: 'R4');
      expect(
        [for (final e in v) '${e.path}:${e.line}'],
        [
          'packages/ink_engine/lib/src/a_native.dart:3',
          'packages/ink_engine/lib/src/b_native.dart:1',
          'packages/ink_engine/lib/src/c_io.dart:3',
        ],
      );
      expect(
        v.first.format(),
        startsWith(
          'packages/ink_engine/lib/src/a_native.dart:3: [R4] dart:io '
          'Platform is not allowed (계약 7.4.1)',
        ),
      );
    });

    test('TargetPlatform, defaultTargetPlatform, comments, strings and a '
        'file without dart:io are fine', () {
      final v = check({
        'packages/ink_engine/lib/src/a_native.dart': '''
import 'dart:io';
import 'package:flutter/foundation.dart';

// Platform.isIOS is not used here.
final ios = defaultTargetPlatform == TargetPlatform.iOS;
const label = 'Platform';
File? file;
''',
        'packages/ink_engine/lib/src/plain.dart': '''
class Platform {}
final p = Platform();
''',
      }, rule: 'R4');
      expect(v, isEmpty);
    });

    test('lib_exceptions are exempt; test/ is not checked', () {
      final v = check({
        'packages/note_core/lib/testing_vm.dart':
            "import 'dart:io';\nfinal s = Platform.pathSeparator;\n",
        'packages/note_core/test/p_test.dart':
            "import 'dart:io';\nfinal s = Platform.pathSeparator;\n",
      }, rule: 'R4');
      expect(v, isEmpty);
    });
  });

  group('R16 (2차, contract 7.4.1 v2.1)', () {
    // A pub cache stand-in outside app/ and packages/ (so R1 does not see
    // it), found through .dart_tool/package_config.json like the real
    // workspace.
    Map<String, String> packageConfig(Map<String, bool> packages) => {
      '.dart_tool/package_config.json': jsonEncode({
        'configVersion': 2,
        'packages': [
          for (final name in packages.keys)
            {
              'name': name,
              'rootUri': '../fake_pub/$name',
              'packageUri': 'lib/',
            },
        ],
      }),
      for (final MapEntry(key: name, value: plugin) in packages.entries)
        'fake_pub/$name/pubspec.yaml':
            'name: $name\n'
            '${plugin ? 'flutter:\n  plugin:\n    platforms:\n      ios:\n'
                      '        pluginClass: X\n' : ''}',
    };

    String libraryPubspec(String extra) => '''
name: feature_library
publish_to: none
resolution: workspace
environment:
  sdk: ^3.13.0
  flutter: 3.47.9
dependencies:
  flutter:
    sdk: flutter
  note_core: any
$extra''';

    Map<String, String> withPdfIo(String deps) => {
      'pubspec.yaml': cleanWorkspaceFiles()['pubspec.yaml']!.replaceFirst(
        '  - packages/feature_library\n',
        '  - packages/feature_library\n  - packages/pdf_io\n',
      ),
      'packages/pdf_io/pubspec.yaml': '''
name: pdf_io
publish_to: none
resolution: workspace
environment:
  sdk: ^3.13.0
  flutter: 3.47.9
dependencies:
  note_core: any
  ink_engine: any
$deps''',
    };

    test('a listed plugin in a plugin-free member (dependencies and '
        'dev_dependencies)', () {
      final v = check({
        'packages/feature_library/pubspec.yaml': libraryPubspec(
          '  image_picker: 1.2.4\n'
          'dev_dependencies:\n  integration_test:\n    sdk: flutter\n',
        ),
      }, rule: 'R16');
      expect(v, hasLength(2));
      expect(
        v.first.format(),
        'packages/feature_library/pubspec.yaml:11: [R16] feature_library: '
        "depends on plugin 'image_picker' (계약 7.4.1)",
      );
      expect(
        v.last.format(),
        'packages/feature_library/pubspec.yaml:13: [R16] feature_library: '
        "depends on plugin 'integration_test' (계약 7.4.1)",
      );
    });

    test('an unlisted package with `flutter: plugin:` is a plugin too; a '
        'plain package is not', () {
      final v = check({
        ...packageConfig({'new_plugin': true, 'plain_pkg': false}),
        'packages/ink_engine/pubspec.yaml': '''
name: ink_engine
publish_to: none
resolution: workspace
environment:
  sdk: ^3.13.0
  flutter: 3.47.9
dependencies:
  flutter:
    sdk: flutter
  note_core: any
  new_plugin: 1.0.0
  plain_pkg: 1.0.0
''',
      }, rule: 'R16');
      expect(
        v.single.message,
        "ink_engine: depends on plugin 'new_plugin' "
        '(계약 7.4.1)',
      );
    });

    test('pdf_io: file_picker is the 1차 exception, image_picker is not, '
        'pdfrx is not a plugin', () {
      final v = check({
        ...packageConfig({'pdfrx': false}),
        ...withPdfIo(
          '  pdfrx: 2.11.0\n  file_picker: 13.3.2\n  image_picker: 1.2.4\n',
        ),
      }, rule: 'R16');
      expect(v.single.path, 'packages/pdf_io/pubspec.yaml');
      expect(
        v.single.message,
        "pdf_io: depends on plugin 'image_picker' "
        '(계약 7.4.1)',
      );
    });

    test('service packages and the app may depend on plugins', () {
      final v = check({
        'app/pubspec.yaml': cleanWorkspaceFiles()['app/pubspec.yaml']!
            .replaceFirst(
              '  go_router: 18.1.2\n',
              '  go_router: 18.1.2\n  path_provider: 2.1.6\n',
            ),
      }, rule: 'R16');
      expect(v, isEmpty);
    });

    test('extending plugin_exceptions or shrinking plugin_free_members is a '
        'violation of the rules file', () {
      final text = File(realRulesPath)
          .readAsStringSync()
          .replaceFirst(
            '  pdf_io: [file_picker]',
            '  pdf_io: [file_picker, image_picker]\n  feature_editor: [record]',
          )
          .replaceFirst(
            'plugin_free_members: [feature_editor, feature_library, '
                'ink_engine, note_core, ui_kit]',
            'plugin_free_members: [feature_editor, feature_library, '
                'note_core, ui_kit]',
          );
      final custom = WorkspaceRules.parse(text);
      expect(custom.pluginExceptions['pdf_io'], [
        'file_picker',
        'image_picker',
      ]);
      fixture = FixtureWorkspace.clean();
      final v = [
        for (final r in checkWorkspace(fixture!.load(), custom))
          if (r.rule == 'R16') r.message,
      ];
      expect(v, [
        contains('plugin_exceptions.feature_editor must not add record'),
        contains('plugin_exceptions.pdf_io must not add image_picker'),
        contains('plugin_free_members must keep ink_engine'),
      ]);
    });

    test('the real workspace has no R16 violation', () {
      final v = [
        for (final r in checkWorkspace(Workspace.load(repoRoot), rules))
          if (r.rule == 'R16') r,
      ];
      expect(v, isEmpty);
    });
  });

  group('R5', () {
    test('package:web in test/web/ and *_browser.dart is fine, elsewhere a '
        'violation', () {
      final v = check({
        'packages/ink_engine/test/web/x_test.dart':
            "import 'package:web/web.dart';\n",
        'packages/ink_engine/test/unit/x_test.dart':
            "import 'package:web/web.dart';\n",
        'packages/ink_engine/lib/src/dom_browser.dart':
            "import 'dart:js_interop';\nimport 'package:web/web.dart';\n",
        'packages/ink_engine/lib/src/dom.dart':
            "import 'dart:js_interop_unsafe';\n",
      }, rule: 'R5');
      expect(v.map((e) => e.path), [
        'packages/ink_engine/lib/src/dom.dart',
        'packages/ink_engine/test/unit/x_test.dart',
      ]);
      expect(v.first.message, contains('web-only'));
    });
  });

  group('R6', () {
    test('an unconditional import of a _native.dart file in lib/', () {
      final v = check({
        'packages/ink_engine/lib/src/a.dart': "import 'b_native.dart';\n",
        'packages/ink_engine/lib/src/b_native.dart': '',
      }, rule: 'R6');
      expect(v.single.path, 'packages/ink_engine/lib/src/a.dart');
      expect(v.single.message, contains('platform file'));
    });

    test('a conditional import with a stub default is fine', () {
      final v = check({
        'packages/ink_engine/lib/src/a.dart': '''
import 'b_stub.dart'
    if (dart.library.js_interop) 'b_browser.dart'
    if (dart.library.ffi) 'b_native.dart';
export 'c_stub.dart' if (dart.library.io) 'c_io.dart';
''',
      }, rule: 'R6');
      expect(v, isEmpty);
    });

    test('a conditional export whose default is a platform file', () {
      final v = check({
        'packages/ink_engine/lib/src/a.dart':
            "export 'b_browser.dart' if (dart.library.ffi) 'b_native.dart';\n",
      }, rule: 'R6');
      expect(v.single.message, contains('must be a stub'));
    });

    test('platform files may use files of their own platform directly', () {
      final v = check({
        'packages/ink_engine/lib/src/a_native.dart':
            "import 'b_native.dart';\nimport 'c_io.dart';\n"
            "import 'd_browser.dart';\n",
        'packages/ink_engine/lib/src/a_browser.dart':
            "import 'b_browser.dart';\nimport 'b_native.dart';\n",
      }, rule: 'R6');
      expect(v.map((e) => (e.path, e.line)), [
        ('packages/ink_engine/lib/src/a_browser.dart', 2),
        ('packages/ink_engine/lib/src/a_native.dart', 3),
      ]);
    });

    test('test/ may import platform files directly', () {
      final v = check({
        'packages/ink_engine/test/a_test.dart':
            "import 'package:ink_engine/src/b_native.dart';\n",
      }, rule: 'R6');
      expect(v, isEmpty);
    });
  });

  group('R10', () {
    test('dependency_overrides in a member pubspec', () {
      final pubspec = cleanWorkspaceFiles()['packages/note_core/pubspec.yaml']!;
      final v = check({
        'packages/note_core/pubspec.yaml':
            '${pubspec}dependency_overrides:\n  riverpod: 3.4.3\n',
      }, rule: 'R10');
      expect(v.single.path, 'packages/note_core/pubspec.yaml');
      expect(v.single.line, 11);
    });

    test('dependency_overrides in the root pubspec is fine', () {
      final pubspec = cleanWorkspaceFiles()['pubspec.yaml']!;
      final v = check({
        'pubspec.yaml': '${pubspec}dependency_overrides:\n  path: 1.9.1\n',
      }, rule: 'R10');
      expect(v, isEmpty);
    });
  });

  group('R11', () {
    test('formatTargets skips generated files, fixture dirs and build/', () {
      fixture = FixtureWorkspace.clean({
        'packages/note_core/lib/src/a.g.dart': '',
        'packages/note_core/lib/src/schema_versions.dart': '',
        'tool/test/fixtures/bad.dart': '',
        'tool/ws.dart': '',
        'app/build/x.dart': '',
      });
      final targets = formatTargets(fixture!.load(), rules);
      expect(targets, contains('tool/ws.dart'));
      expect(targets, contains('packages/note_core/lib/src/a.dart'));
      expect(targets.where((t) => t.contains('.g.dart')), isEmpty);
      expect(targets.where((t) => t.contains('schema_versions')), isEmpty);
      expect(targets.where((t) => t.contains('fixtures')), isEmpty);
      expect(targets.where((t) => t.contains('build/')), isEmpty);
    });

    test(
      'an unformatted file is reported; generated and fixture files are not',
      () async {
        const unformatted = 'int  f( ){return 1;}\n';
        fixture = FixtureWorkspace.clean({
          'packages/note_core/lib/src/bad.dart': unformatted,
          'packages/note_core/lib/src/bad.g.dart': unformatted,
          'tool/test/fixtures/bad.dart': unformatted,
        });
        final v = await checkFormat(
          fixture!.load(),
          rules,
          processes: IoProcessRunner(out: StringBuffer()),
          dart: Platform.resolvedExecutable,
        );
        expect(v.single.rule, 'R11');
        expect(v.single.path, 'packages/note_core/lib/src/bad.dart');
      },
      tags: ['process'],
    );

    test(
      'the formatter is called quietly with --set-exit-if-changed',
      () async {
        fixture = FixtureWorkspace.clean();
        final processes = FakeProcesses(
          (_) => const RunResult(
            exitCode: 1,
            output:
                'Changed packages/note_core/lib/src/a.dart\n'
                'Formatted 6 files (1 changed) in 0.01 seconds.\n',
          ),
        );
        final v = await checkFormat(
          fixture!.load(),
          rules,
          processes: processes,
          dart: '/fake/dart',
        );
        final call = processes.calls.single;
        expect(call.arguments.take(3), [
          'format',
          '--output=none',
          '--set-exit-if-changed',
        ]);
        expect(call.echo, isFalse);
        expect(call.workingDirectory, fixture!.root);
        expect(v.single.path, 'packages/note_core/lib/src/a.dart');
      },
    );

    test('a formatter failure is a violation', () async {
      fixture = FixtureWorkspace.clean();
      final v = await checkFormat(
        fixture!.load(),
        rules,
        processes: FakeProcesses(
          (_) => const RunResult(exitCode: 65, output: 'Could not format'),
        ),
        dart: '/fake/dart',
      );
      expect(v.single.message, contains('exit code 65'));
    });

    test('ws check --no-format does not run the formatter', () async {
      fixture = FixtureWorkspace.clean();
      final processes = FakeProcesses();
      final out = StringBuffer();
      final code = await runWs(
        ['check', '--rules', realRulesPath, '--no-format', '--no-exports'],
        context: WsContext(
          root: fixture!.root,
          out: out,
          err: StringBuffer(),
          processes: processes,
        ),
      );
      expect(code, 0);
      expect(processes.calls, isEmpty);
      expect(out.toString(), isNot(contains('R11')));
    });
  });

  group('R12', () {
    const content = 'drift worker bytes';
    String manifest({int? bytes, String? sha}) =>
        '''
assets:
  - path: drift_worker.js
    url: https://example.invalid/drift_worker.js
    bytes: ${bytes ?? content.length}
    sha256: ${sha ?? sha256Hex(content.codeUnits)}
    owner: CORE
    reason: test
''';

    test('no tool/web_assets.yaml: nothing to check', () {
      expect(check({}, rule: 'R12'), isEmpty);
    });

    test('matching file: no violation', () {
      final v = check({
        'tool/web_assets.yaml': manifest(),
        'app/web/drift_worker.js': content,
      }, rule: 'R12');
      expect(v, isEmpty);
    });

    test('missing file, size and sha256 mismatches', () {
      expect(
        check({'tool/web_assets.yaml': manifest()}, rule: 'R12').single.message,
        contains('app/web/drift_worker.js: file is missing'),
      );
      expect(
        check({
          'tool/web_assets.yaml': manifest(bytes: 3),
          'app/web/drift_worker.js': content,
        }, rule: 'R12').single.message,
        contains('expected 3'),
      );
      final v = check({
        'tool/web_assets.yaml': manifest(sha: 'a' * 64),
        'app/web/drift_worker.js': content,
      }, rule: 'R12');
      expect(v.single.message, contains('sha256 is'));
      expect(v.single.path, 'tool/web_assets.yaml');
      expect(v.single.line, 2);
    });

    test('a malformed manifest is a violation', () {
      final v = check({
        'tool/web_assets.yaml': 'assets:\n  - path: x.js\n',
      }, rule: 'R12');
      expect(v.single.message, contains('missing `url`'));
    });
  });

  group('R13', () {
    List<int> png(int w, int h) =>
        img.encodePng(img.Image(width: w, height: h));

    void writePng(String path, int w, int h) =>
        File(p.join(fixture!.root, path))
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(png(w, h));

    List<RuleViolation> r13() => [
      for (final r in checkWorkspace(fixture!.load(), rules))
        if (r.rule == 'R13') r,
    ];

    test('icon sizes match their names, favicon is square', () {
      fixture = FixtureWorkspace.clean();
      writePng('app/web/icons/Icon-192.png', 192, 192);
      writePng('app/web/icons/Icon-maskable-512.png', 512, 512);
      writePng('app/web/favicon.png', 32, 32);
      expect(r13(), isEmpty);
    });

    test('wrong sizes, unnamed icon, non-square favicon and non-PNG', () {
      fixture = FixtureWorkspace.clean({'app/web/icons/Icon-180.png': 'x'});
      writePng('app/web/icons/Icon-192.png', 180, 180);
      writePng('app/web/icons/logo.png', 10, 10);
      writePng('app/web/favicon.png', 32, 16);
      final v = r13();
      expect(v.map((e) => e.path), [
        'app/web/favicon.png',
        'app/web/icons/Icon-180.png',
        'app/web/icons/Icon-192.png',
        'app/web/icons/logo.png',
      ]);
      expect(v[0].message, contains('square'));
      expect(v[1].message, contains('not a PNG'));
      expect(v[2].message, contains('180x180, its name says 192x192'));
      expect(v[3].message, contains('-<size>.png'));
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
      '--no-exports',
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
