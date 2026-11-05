// buildInfoValues / ws build-info (docs/plans/01-infra.md 6.11 and 9.1).

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../src/build_info_file.dart';
import '../src/cli.dart';
import 'support/fixture_workspace.dart';

void main() {
  final now = DateTime.utc(2026, 11, 4, 9, 10, 0, 123);
  const sha = '0123456789abcdef0123456789abcdef01234567';

  test('values from the GitHub environment, all strings', () {
    final values = buildInfoValues(
      channel: 'live',
      version: '0.1.0',
      environment: const {
        'GITHUB_SHA': sha,
        'GITHUB_REF_NAME': 'main',
        'GITHUB_RUN_NUMBER': '42',
      },
      now: now,
    );
    expect(values, {
      'APP_VERSION': '0.1.0',
      'APP_BUILD_NUMBER': '42',
      'APP_GIT_SHA': sha,
      'APP_GIT_REF': 'main',
      'APP_CHANNEL': 'live',
      'APP_BUILD_TIME': '2026-11-04T09:10:00Z',
    });
    expect(values['APP_GIT_SHA']!.length, 40);
  });

  test('without the environment: local values', () {
    final values = buildInfoValues(
      channel: 'local',
      version: '0.1.0',
      environment: const {'GITHUB_SHA': '  ', 'PATH': '/usr/bin'},
      now: DateTime.utc(2026, 1, 2, 3, 4, 5),
    );
    expect(values['APP_GIT_SHA'], 'local');
    expect(values['APP_GIT_REF'], 'local');
    expect(values['APP_BUILD_NUMBER'], '0');
    expect(values['APP_BUILD_TIME'], '2026-01-02T03:04:05Z');
  });

  test('local time is written in UTC', () {
    final local = DateTime(2026, 11, 4, 9, 10);
    expect(formatBuildTime(local), formatBuildTime(local.toUtc()));
    expect(formatBuildTime(local), endsWith('Z'));
  });

  test('invalid channel, version, sha and run number are rejected', () {
    Map<String, String> build({
      String channel = 'preview',
      String version = '1.2.3',
      Map<String, String> env = const {},
    }) => buildInfoValues(
      channel: channel,
      version: version,
      environment: env,
      now: now,
    );
    expect(() => build(channel: 'prod'), throwsA(isA<BuildInfoException>()));
    expect(() => build(version: '1.2'), throwsA(isA<BuildInfoException>()));
    expect(
      () => build(env: {'GITHUB_SHA': 'abc'}),
      throwsA(isA<BuildInfoException>()),
    );
    expect(
      () => build(env: {'GITHUB_SHA': sha.toUpperCase()}),
      throwsA(isA<BuildInfoException>()),
    );
    expect(
      () => build(env: {'GITHUB_RUN_NUMBER': '4x'}),
      throwsA(isA<BuildInfoException>()),
    );
    for (final channel in buildChannels) {
      expect(build(channel: channel)['APP_CHANNEL'], channel);
    }
  });

  group('ws build-info', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('ws_build_info_'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<int> run(List<String> args, Map<String, String> env) => runWs(
      ['build-info', ...args],
      context: WsContext(
        root: repoRoot,
        out: StringBuffer(),
        err: StringBuffer(),
        environment: env,
        workingDirectory: dir.path,
        now: () => now,
      ),
    );

    test(
      'writes the JSON file; version defaults to app/pubspec.yaml',
      () async {
        final code = await run(
          ['--out', 'build/build_info.json', '--channel', 'preview'],
          {
            'GITHUB_SHA': sha,
            'GITHUB_REF_NAME': 'area/infra',
            'GITHUB_RUN_NUMBER': '7',
          },
        );
        expect(code, 0);
        final file = File(p.join(dir.path, 'build', 'build_info.json'));
        final json =
            jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
        expect(json['APP_CHANNEL'], 'preview');
        expect(json['APP_GIT_REF'], 'area/infra');
        expect(json['APP_BUILD_NUMBER'], '7');
        expect(json.values.every((v) => v is String), isTrue);
        expect(
          json['APP_VERSION'],
          appVersionFromPubspec(p.join(repoRoot, 'app', 'pubspec.yaml')),
        );
        expect(json['APP_VERSION'], matches(RegExp(r'^\d+\.\d+\.\d+$')));
      },
    );

    test('--version overrides; default channel is local', () async {
      final code = await run(['--out', 'i.json', '--version', '2.0.1'], {});
      expect(code, 0);
      final json = jsonDecode(
        File(p.join(dir.path, 'i.json')).readAsStringSync(),
      ) as Map<String, Object?>;
      expect(json['APP_VERSION'], '2.0.1');
      expect(json['APP_CHANNEL'], 'local');
      expect(json['APP_GIT_SHA'], 'local');
    });

    test('usage errors exit 2', () async {
      expect(await run([], {}), usageExitCode);
      expect(await run(['--out', 'x', '--channel', 'prod'], {}), usageExitCode);
      expect(await run(['--out', 'x', '--version', 'v1'], {}), usageExitCode);
      expect(await run(['--out', 'x'], {'GITHUB_SHA': 'short'}), usageExitCode);
    });
  });
}
