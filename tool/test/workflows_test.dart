// .github/workflows checks (docs/plans/01-infra.md 6.13, B1-5). The B1
// workflow has the 6.13 steps 1, 2, 5–9 and 14 and no deploy.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'support/fixture_workspace.dart';

void main() {
  final workflowsDir = p.join(repoRoot, '.github', 'workflows');

  List<File> workflowFiles() =>
      Directory(workflowsDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.yml') || f.path.endsWith('.yaml'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  YamlMap load(String name) {
    final yaml = loadYaml(File(p.join(workflowsDir, name)).readAsStringSync());
    expect(yaml, isA<YamlMap>(), reason: '$name is not a YAML map');
    return yaml as YamlMap;
  }

  List<YamlMap> stepsOf(YamlMap workflow) => [
    for (final job in (workflow['jobs'] as YamlMap).values)
      for (final step in (job as YamlMap)['steps'] as YamlList) step as YamlMap,
  ];

  test('every workflow parses and every job has timeout-minutes', () {
    final files = workflowFiles();
    expect(files, isNotEmpty);
    for (final file in files) {
      final workflow = load(p.basename(file.path));
      final jobs = workflow['jobs'];
      expect(jobs, isA<YamlMap>(), reason: '${file.path}: no jobs');
      for (final MapEntry(:key, :value) in (jobs as YamlMap).entries) {
        expect(
          (value as YamlMap)['timeout-minutes'],
          isA<int>(),
          reason: '${file.path}: job $key has no timeout-minutes',
        );
      }
    }
  });

  test('every flutter-action reads the version from the root pubspec', () {
    for (final file in workflowFiles()) {
      for (final step in stepsOf(load(p.basename(file.path)))) {
        final uses = step['uses'];
        if (uses is String && uses.startsWith('subosito/flutter-action')) {
          expect(uses, 'subosito/flutter-action@v2');
          final withMap = step['with'] as YamlMap;
          expect(withMap['flutter-version-file'], 'pubspec.yaml');
          expect(withMap['cache'], isTrue);
          expect(withMap.containsKey('flutter-version'), isFalse);
        }
      }
    }
    final rootPubspec = loadYaml(
      File(p.join(repoRoot, 'pubspec.yaml')).readAsStringSync(),
    ) as YamlMap;
    expect((rootPubspec['environment'] as YamlMap)['flutter'], '3.47.9');
  });

  group('ci.yml', () {
    late YamlMap ci;
    late List<YamlMap> steps;

    setUp(() {
      ci = load('ci.yml');
      steps = stepsOf(ci);
    });

    String runOf(bool Function(YamlMap step) where) =>
        steps.where(where).map((s) => '${s['run']}').join('\n');

    test('triggers on push (docs ignored) and manual dispatch', () {
      final on = ci['on'] as YamlMap;
      expect(on.containsKey('workflow_dispatch'), isTrue);
      final ignored = (on['push'] as YamlMap)['paths-ignore'] as YamlList;
      expect(ignored, containsAll(['docs/**', '**/*.md']));
    });

    test('concurrency per ref with cancel-in-progress, read-only token', () {
      final concurrency = ci['concurrency'] as YamlMap;
      expect(concurrency['group'], r'ci-${{ github.ref }}');
      expect(concurrency['cancel-in-progress'], isTrue);
      expect((ci['permissions'] as YamlMap)['contents'], 'read');
    });

    test('single job on ubuntu with a 25 minute limit', () {
      final jobs = ci['jobs'] as YamlMap;
      expect(jobs, hasLength(1));
      final job = jobs.values.single as YamlMap;
      expect(job['runs-on'], 'ubuntu-latest');
      expect(job['timeout-minutes'], 25);
    });

    test('checkout with full history', () {
      final checkout = steps.firstWhere(
        (s) => '${s['uses']}'.startsWith('actions/checkout'),
      );
      expect(checkout['uses'], 'actions/checkout@v7');
      expect((checkout['with'] as YamlMap)['fetch-depth'], 0);
    });

    test('runs the B1 steps in order', () {
      final commands = [for (final s in steps) '${s['run'] ?? s['uses']}'];
      final expected = [
        'actions/checkout@v7',
        'subosito/flutter-action@v2',
        'flutter pub get --enforce-lockfile',
        'dart run tool/ws.dart check --strict',
        'dart run tool/ws.dart check',
        'dart run tool/ws.dart analyze',
        'dart run tool/ws.dart test',
        'dart test tool/test',
        'dart run tool/ws.dart test --platform chrome',
        'flutter build web --release --no-wasm-dry-run',
      ];
      expect(commands, expected);
    });

    test('main runs check --strict, other branches plain check', () {
      expect(
        runOf((s) => s['if'] == "github.ref == 'refs/heads/main'"),
        'dart run tool/ws.dart check --strict',
      );
      expect(
        runOf((s) => s['if'] == "github.ref != 'refs/heads/main'"),
        'dart run tool/ws.dart check',
      );
    });

    test('the web build runs in app/', () {
      final build = steps.firstWhere(
        (s) => '${s['run']}'.startsWith('flutter build web'),
      );
      expect(build['working-directory'], 'app');
    });

    test('B1 has no deploy, no secrets', () {
      final text = File(p.join(workflowsDir, 'ci.yml')).readAsStringSync();
      expect(text, isNot(contains('action-hosting-deploy')));
      expect(text, isNot(contains('secrets.')));
    });
  });
}
