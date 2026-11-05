// ws hosting-config (docs/plans/01-infra.md 6.12, contract 00-overview
// 7.4.9). I1 covers the --isolate transform; I12 adds the checks of the
// committed app/firebase.json.

import 'dart:convert';

import 'package:test/test.dart';

import '../src/cli.dart';
import '../src/hosting_config.dart';
import 'support/fixture_workspace.dart';

const _config = {
  'hosting': {
    'public': 'build/web',
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
}
