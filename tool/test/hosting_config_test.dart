// ws hosting-config (docs/plans/01-infra.md 6.12, contract 00-overview
// 7.4.9). I1 covers the --isolate transform; I12 adds the checks of the
// committed app/firebase.json and of the M4 rule file references.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../src/cli.dart';
import '../src/hosting_config.dart';
import 'support/fixture_workspace.dart';

const _config = {
  'hosting': {
    'public': 'build/web',
    'ignore': ['firebase.json', '**/.*'],
    'rewrites': [
      {'source': '**', 'destination': '/index.html'},
    ],
    'headers': [
      {
        'source': '**',
        'headers': [
          {'key': 'Cache-Control', 'value': 'no-cache'},
        ],
      },
      {
        'source': '**/*.wasm',
        'headers': [
          {'key': 'Content-Type', 'value': 'application/wasm'},
        ],
      },
    ],
  },
};

List<Object?> headersOf(Map<String, Object?> config, String source) {
  final hosting = config['hosting']! as Map<String, Object?>;
  final entry = (hosting['headers']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .firstWhere((e) => e['source'] == source);
  return entry['headers']! as List<Object?>;
}

void main() {
  test(
    '--isolate adds COOP/COEP to the ** entry without changing the input',
    () {
      final input = jsonDecode(jsonEncode(_config)) as Map<String, Object?>;
      final isolated = isolatedHostingConfig(input);
      expect(headersOf(isolated, '**'), [
        {'key': 'Cache-Control', 'value': 'no-cache'},
        {'key': 'Cross-Origin-Opener-Policy', 'value': 'same-origin'},
        {'key': 'Cross-Origin-Embedder-Policy', 'value': 'require-corp'},
      ]);
      expect(headersOf(isolated, '**/*.wasm').length, 1);
      expect(input, _config);
      // Idempotent.
      expect(isolatedHostingConfig(isolated), isolated);
    },
  );

  test('--isolate creates the ** entry when it is missing', () {
    final isolated = isolatedHostingConfig({
      'hosting': {'public': 'build/web'},
    });
    expect(headersOf(isolated, '**').length, 2);
  });

  test('parse errors', () {
    expect(
      () => parseHostingConfig('{'),
      throwsA(isA<HostingConfigException>()),
    );
    expect(
      () => parseHostingConfig('{"x": 1}'),
      throwsA(isA<HostingConfigException>()),
    );
  });

  test(
    'ws hosting-config prints the file, with --isolate the variant',
    () async {
      final fixture = FixtureWorkspace.clean({
        hostingConfigPath: jsonEncode(_config),
      });
      addTearDown(fixture.dispose);
      Future<(int, String)> ws(List<String> args) async {
        final out = StringBuffer();
        final code = await runWs(
          ['hosting-config', ...args],
          context: WsContext(root: fixture.root, out: out, err: StringBuffer()),
        );
        return (code, out.toString());
      }

      final (code, out) = await ws([]);
      expect(code, 0);
      expect(jsonDecode(out), _config);
      expect(out, isNot(contains('Cross-Origin')));
      final (isoCode, isoOut) = await ws(['--isolate']);
      expect(isoCode, 0);
      expect(isoOut, contains('Cross-Origin-Embedder-Policy'));

      fixture.delete(hostingConfigPath);
      expect((await ws([])).$1, environmentExitCode);
    },
  );

  group('the committed app/firebase.json', () {
    late Map<String, Object?> config;

    setUpAll(() {
      config = parseHostingConfig(
        File(p.join(repoRoot, hostingConfigPath)).readAsStringSync(),
      );
    });

    test('6.12 table: public, ignore, rewrites, no-cache, wasm type', () {
      final hosting = config['hosting']! as Map<String, Object?>;
      expect(hosting['public'], 'build/web');
      expect(hosting['ignore'], ['firebase.json', '**/.*']);
      expect(hosting['rewrites'], [
        {'source': '**', 'destination': '/index.html'},
      ]);
      expect(headersOf(config, '**'), [
        {'key': 'Cache-Control', 'value': 'no-cache'},
      ]);
      expect(headersOf(config, '**/*.wasm'), [
        {'key': 'Content-Type', 'value': 'application/wasm'},
      ]);
      expect(
        hostingConfigProblems(config, appDir: p.join(repoRoot, 'app')),
        isEmpty,
      );
    });

    test('no COOP / COEP by default; --isolate adds both', () {
      final text = encodeHostingConfig(config);
      expect(text, isNot(contains('Cross-Origin')));
      final isolated = encodeHostingConfig(isolatedHostingConfig(config));
      expect(isolated, contains('"Cross-Origin-Opener-Policy"'));
      expect(isolated, contains('"Cross-Origin-Embedder-Policy"'));
    });

    test('no M4 rule references in this scope; 2차 functions and '
        'emulators (01-infra 6.14, contract 7.4.7)', () {
      expect(config.keys, ['hosting', 'functions', 'emulators']);
      for (final (section, _) in hostingRuleFileKeys) {
        expect(config, isNot(contains(section)));
      }
      expect(config['functions'], expectedFunctionsConfig);
      expect(config['emulators'], expectedEmulatorsConfig);
      final functions =
          (config['functions']! as List<Object?>).single!
              as Map<String, Object?>;
      expect(functions['source'], '../functions');
      // functions/.env.demo-noteapp (demo values, committed) is not caught
      // by the `*.local` pattern; .env.local / .secret.local are.
      final ignore = (functions['ignore']! as List<Object?>).cast<String>();
      expect(ignore, contains('*.local'));
      expect(ignore, isNot(contains('.env*')));
      expect(ignore, containsAll(['test', 'lib/test', 'tool', 'eval-out']));
    });

    test('a changed functions or emulators entry is a problem', () {
      final appDir = p.join(repoRoot, 'app');
      final changed = jsonDecode(jsonEncode(config)) as Map<String, Object?>;
      ((changed['functions']! as List<Object?>).single!
              as Map<String, Object?>)['source'] =
          'functions';
      ((changed['emulators']! as Map<String, Object?>)['auth']!
              as Map<String, Object?>)['host'] =
          'localhost';
      expect(hostingConfigProblems(changed, appDir: appDir), [
        startsWith('functions must be exactly'),
        startsWith('emulators must be exactly'),
      ]);
    });
  });

  group('hostingConfigProblems', () {
    test('each broken rule is reported', () {
      final appDir = Directory.systemTemp.createTempSync('hosting_').path;
      addTearDown(() => Directory(appDir).deleteSync(recursive: true));
      expect(
        hostingConfigProblems({
          'hosting': {'public': 'web'},
        }, appDir: appDir),
        [
          'hosting.public must be "build/web"',
          'hosting.rewrites must send "**" to "/index.html"',
          '"**" needs Cache-Control: no-cache',
          '"**/*.wasm" needs Content-Type: application/wasm',
        ],
      );
      expect(
        hostingConfigProblems(isolatedHostingConfig(_config), appDir: appDir),
        hasLength(2),
      );
      expect(hostingConfigProblems(_config, appDir: appDir), isEmpty);
    });

    test('M4 shape: rule files must exist relative to app/', () {
      // tool/test/fixtures/firebase_m4 (6.12), written to a temp workspace.
      final m4 = {
        ..._config,
        'firestore': {
          'rules': '../packages/sync_engine/firebase/firestore.rules',
          'indexes': '../packages/sync_engine/firebase/firestore.indexes.json',
        },
        'storage': {'rules': '../packages/sync_engine/firebase/storage.rules'},
      };
      final fixture = FixtureWorkspace.clean({
        hostingConfigPath: jsonEncode(m4),
        'packages/sync_engine/firebase/firestore.rules': 'rules_version = 2;',
        'packages/sync_engine/firebase/firestore.indexes.json': '{}',
        'packages/sync_engine/firebase/storage.rules': 'rules_version = 2;',
      });
      addTearDown(fixture.dispose);
      final appDir = p.join(fixture.root, 'app');
      expect(hostingConfigProblems(m4, appDir: appDir), isEmpty);

      fixture.delete('packages/sync_engine/firebase/storage.rules');
      const missing =
          'storage.rules: ../packages/sync_engine/firebase/storage.rules '
          'does not exist (relative to app/)';
      expect(hostingConfigProblems(m4, appDir: appDir), [missing]);
    });

    test('ws hosting-config exits 1 on a broken file', () async {
      final fixture = FixtureWorkspace.clean({
        hostingConfigPath: jsonEncode({
          'hosting': {'public': 'build/web'},
        }),
      });
      addTearDown(fixture.dispose);
      final err = StringBuffer();
      final code = await runWs([
        'hosting-config',
      ], context: WsContext(root: fixture.root, out: StringBuffer(), err: err));
      expect(code, 1);
      expect(err.toString(), contains('app/firebase.json: hosting.rewrites'));
    });
  });
}
