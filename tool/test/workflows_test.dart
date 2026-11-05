// .github checks (docs/plans/01-infra.md 6.13 and the 9.1 workflows_test row,
// I13): the four workflows (triggers, concurrency, time limits, the two
// caches and their keys, browser and integration tests, the default-branch
// base of `--affected-since` with its full-run fallback, the live channel on
// main only, the deploy gate on secrets, pinned versions, the iOS gate, the
// APK artifact) and the issue templates. Every `ws` call in a workflow
// is parsed by the real `ws` argument parser, and every `run` script passes
// `bash -n`.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../src/build_info_file.dart';
import '../src/cli.dart';
import '../src/workspace.dart';
import 'support/fixture_workspace.dart';

/// Action versions pinned in 01-infra 7.3.
const _pinnedActions = {
  'actions/checkout': 'v7',
  'subosito/flutter-action': 'v2',
  'actions/cache': 'v6',
  'actions/setup-java': 'v6',
  'actions/upload-artifact': 'v7',
  'FirebaseExtended/action-hosting-deploy': 'v0',
};

/// `paths-ignore` of every push trigger (6.13).
const _ignoredPaths = ['docs/**', '**/*.md', '.github/ISSUE_TEMPLATE/**'];

/// Job time limits (6.13).
const _timeouts = {
  'android.yml': 30,
  'ci.yml': 60,
  'ios-testflight.yml': 45,
  'web-experiment.yml': 25,
};

const _hooksPath = '.dart_tool/hooks_runner';
const _hooksKey = r"hooks-${{ runner.os }}-${{ hashFiles('pubspec.lock') }}";
const _hooksRestoreKey = r'hooks-${{ runner.os }}-';

/// Outputs of the members' tool/prepare_web_test.dart (contract 7.4.8).
const _prepPaths = [
  'packages/note_core/test/web/sqlite3.wasm',
  'packages/note_core/test/web/drift_worker.js',
  'packages/pdf_io/test/web/pdfium/',
  'app/test/web/sqlite3.wasm',
  'app/test/web/drift_worker.js',
];
const _prepKey =
    r'prep-${{ runner.os }}-'
    r"${{ hashFiles('pubspec.lock', 'tool/web_assets.yaml', "
    r"'**/tool/prepare_web_test.dart') }}";

const _onMain = "github.ref == 'refs/heads/main'";

/// ci.yml: main and the default branch itself run the strict check and every
/// member; the others the affected members since the default branch.
const _fullRun = "env.FULL_RUN == 'true'";
const _notFullRun = "env.FULL_RUN != 'true'";
const _fullRunValue =
    r"${{ github.ref == 'refs/heads/main' || "
    r'github.ref_name == github.event.repository.default_branch }}';
const _defaultBranchValue = r'${{ github.event.repository.default_branch }}';
const _affected = r'--affected-since "origin/$DEFAULT_BRANCH" --all-if-no-base';
const _ws = 'dart run tool/ws.dart';
const _defineFile = '--dart-define-from-file=../build/build_info.json';
const _buildNumber = r'--build-number=$GITHUB_RUN_NUMBER';
const _buildInfoFromEnv =
    '$_ws build-info --channel "\$BUILD_CHANNEL" --out build/build_info.json';
const _finalize =
    '$_ws finalize-web --build-dir app/build/web --info build/build_info.json';
const _webBuild =
    'flutter build web --release --no-wasm-dry-run $_defineFile $_buildNumber';
const _apkBuild =
    'flutter build apk --release --split-per-abi $_buildNumber $_defineFile';
const _inkLabDir = 'packages/ink_engine/example';

/// The development branch whose pushes also build the APK (android.yml).
const _devBranch = 'claude/note-app-planning-bk29xb';

final _workflowsDir = p.join(repoRoot, '.github', 'workflows');

YamlMap _load(String path) {
  final yaml = loadYaml(File(path).readAsStringSync());
  expect(yaml, isA<YamlMap>(), reason: '$path is not a YAML map');
  return yaml as YamlMap;
}

YamlMap _workflow(String name) => _load(p.join(_workflowsDir, name));

List<String> _workflowNames() =>
    Directory(_workflowsDir)
        .listSync()
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .where((n) => n.endsWith('.yml') || n.endsWith('.yaml'))
        .toList()
      ..sort();

Map<String, YamlMap> _jobs(YamlMap workflow) => {
  for (final MapEntry(:key, :value) in (workflow['jobs'] as YamlMap).entries)
    key as String: value as YamlMap,
};

List<YamlMap> _steps(YamlMap job) => [
  for (final step in job['steps'] as YamlList) step as YamlMap,
];

List<YamlMap> _allSteps(YamlMap workflow) => [
  for (final job in _jobs(workflow).values) ..._steps(job),
];

YamlMap _with(YamlMap step) => step['with'] as YamlMap? ?? YamlMap();

YamlMap _named(List<YamlMap> steps, String name) {
  final found = steps.where((s) => s['name'] == name).toList();
  expect(found, hasLength(1), reason: 'one step named `$name`');
  return found.single;
}

/// Lines of a `run` script, trimmed, without blanks.
List<String> _runLines(YamlMap step) => [
  for (final line in '${step['run'] ?? ''}'.split('\n'))
    if (line.trim().isNotEmpty) line.trim(),
];

/// The `dart …` / `flutter …` command lines of a `run` script (the timing
/// lines `printf … step-seconds` and `date …` are left out).
List<String> _commands(YamlMap step) => [
  for (final line in _runLines(step))
    if (line.startsWith('dart ') || line.startsWith('flutter ')) line,
];

List<YamlMap> _usesSteps(YamlMap workflow, String action) => [
  for (final step in _allSteps(workflow))
    if ('${step['uses'] ?? ''}'.startsWith('$action@')) step,
];

final _variableName = RegExp(r'^[A-Z_][A-Z0-9_]*');

/// Splits a shell command line into words: quotes removed, `$NAME` (also
/// inside double quotes) replaced from [variables], stopping at an unquoted
/// `>` or `)`.
List<String> _shellWords(String line, Map<String, String> variables) {
  final words = <String>[];
  final word = StringBuffer();
  var inWord = false;
  String? quote;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == r'$' && quote != "'") {
      final name = _variableName.stringMatch(line.substring(i + 1));
      expect(name, isNotNull, reason: 'unsupported `\$` in `$line`');
      expect(variables, contains(name), reason: 'no sample for \$$name');
      word.write(variables[name]);
      i += name!.length;
      inWord = true;
    } else if (quote != null) {
      if (c == quote) {
        quote = null;
      } else {
        word.write(c);
      }
    } else if (c == '"' || c == "'") {
      quote = c;
      inWord = true;
    } else if (c == ' ') {
      if (inWord) words.add(word.toString());
      word.clear();
      inWord = false;
    } else if (c == '>' || c == ')') {
      break;
    } else {
      word.write(c);
      inWord = true;
    }
  }
  if (inWord) words.add(word.toString());
  return words;
}

/// Sample values of the shell variables the workflows pass to `ws`.
const _sampleVariables = {
  'BUILD_CHANNEL': 'preview',
  'DEFAULT_BRANCH': _devBranch,
  'GITHUB_REF_NAME': 'area/infra',
};

/// Evaluates the `||` / `&&` / `==` / `!=` expressions of [expression]
/// (`${{ … }}` or a bare `if:`) against [context] (`github.ref`, …, `env.X`):
/// enough for the conditions of ci.yml, not the whole GitHub grammar.
bool _evaluate(String expression, Map<String, String> context) {
  var text = expression.trim();
  if (text.startsWith(r'${{') && text.endsWith('}}')) {
    text = text.substring(3, text.length - 2).trim();
  }
  String value(String operand) {
    final o = operand.trim();
    if (o.startsWith("'") && o.endsWith("'")) {
      return o.substring(1, o.length - 1);
    }
    expect(context, contains(o), reason: 'no sample for `$o`');
    return context[o]!;
  }

  bool comparison(String term) {
    for (final op in ['==', '!=']) {
      final parts = term.split(op);
      if (parts.length == 2) {
        final equal = value(parts[0]) == value(parts[1]);
        return op == '==' ? equal : !equal;
      }
    }
    fail('unsupported term `$term` in `$expression`');
  }

  return text.split('||').any((any) => any.split('&&').every(comparison));
}

void main() {
  test('_evaluate reads the condition forms used here', () {
    const context = {'github.ref': 'refs/heads/a', 'env.X': 'true'};
    expect(_evaluate("github.ref == 'refs/heads/a'", context), isTrue);
    expect(_evaluate("github.ref != 'refs/heads/a'", context), isFalse);
    expect(
      _evaluate(r"${{ github.ref == 'x' || env.X == 'true' }}", context),
      isTrue,
    );
    expect(_evaluate("env.X == 'true' && github.ref == 'x'", context), isFalse);
  });

  test('_shellWords splits like the shell for the forms used here', () {
    expect(
      _shellWords(r'channel-id --branch "$GITHUB_REF_NAME")"', {
        'GITHUB_REF_NAME': 'a/b',
      }),
      ['channel-id', '--branch', 'a/b'],
    );
    expect(_shellWords('hosting-config --isolate > "x"', {}), [
      'hosting-config',
      '--isolate',
    ]);
    expect(_shellWords("check  'a b' c", {}), ['check', 'a b', 'c']);
  });

  group('all workflows', () {
    test('the four workflows of 6.13 exist and parse', () {
      expect(_workflowNames(), [
        'android.yml',
        'ci.yml',
        'ios-testflight.yml',
        'web-experiment.yml',
      ]);
      for (final name in _workflowNames()) {
        final workflow = _workflow(name);
        expect(workflow['name'], isA<String>(), reason: name);
        expect(workflow['on'], isA<YamlMap>(), reason: name);
        expect(_jobs(workflow), isNotEmpty, reason: name);
      }
    });

    test('every job has its timeout-minutes; the token is read-only', () {
      for (final name in _workflowNames()) {
        final workflow = _workflow(name);
        expect((workflow['permissions'] as YamlMap).value, {
          'contents': 'read',
        }, reason: name);
        for (final MapEntry(:key, :value) in _jobs(workflow).entries) {
          expect(
            value['timeout-minutes'],
            _timeouts[name],
            reason: '$name: job $key',
          );
          expect(
            value.containsKey('permissions'),
            isFalse,
            reason: '$name: job $key widens permissions',
          );
        }
      }
    });

    test('every action is pinned to the 7.3 version', () {
      for (final name in _workflowNames()) {
        for (final step in _allSteps(_workflow(name))) {
          final uses = step['uses'];
          if (uses == null) continue;
          final [action, version] = '$uses'.split('@');
          expect(
            _pinnedActions,
            contains(action),
            reason: '$name: unknown action $uses',
          );
          expect(version, _pinnedActions[action], reason: '$name: $uses');
        }
      }
    });

    test('every flutter-action reads the version from the root pubspec', () {
      var count = 0;
      for (final name in _workflowNames()) {
        for (final step in _usesSteps(
          _workflow(name),
          'subosito/flutter-action',
        )) {
          count++;
          final withMap = _with(step);
          expect(withMap['flutter-version-file'], 'pubspec.yaml');
          expect(withMap['cache'], isTrue);
          expect(withMap.containsKey('flutter-version'), isFalse);
        }
      }
      expect(count, 4);
      final rootPubspec = _load(p.join(repoRoot, 'pubspec.yaml'));
      expect((rootPubspec['environment'] as YamlMap)['flutter'], '3.47.9');
    });

    test('pub get always enforces the lock file', () {
      var count = 0;
      for (final name in _workflowNames()) {
        for (final step in _allSteps(_workflow(name))) {
          for (final line in _runLines(step)) {
            if (line.contains('pub get')) {
              count++;
              expect(line, 'flutter pub get --enforce-lockfile', reason: name);
            }
          }
        }
      }
      expect(count, 4);
    });

    test('no `if:` reads `secrets` (not allowed there — job env instead)', () {
      for (final name in _workflowNames()) {
        final workflow = _workflow(name);
        for (final MapEntry(:key, :value) in _jobs(workflow).entries) {
          expect('${value['if'] ?? ''}', isNot(contains('secrets.')));
          for (final step in _steps(value)) {
            expect(
              '${step['if'] ?? ''}',
              isNot(contains('secrets.')),
              reason: '$name: $key / ${step['name']}',
            );
          }
        }
      }
    });

    test('`steps.<id>` refers to an earlier step of the same job', () {
      final reference = RegExp(r'steps\.([A-Za-z0-9_-]+)\.');
      for (final name in _workflowNames()) {
        for (final job in _jobs(_workflow(name)).values) {
          final seen = <String>{};
          for (final step in _steps(job)) {
            for (final match in reference.allMatches('${step.value}')) {
              expect(
                seen,
                contains(match.group(1)),
                reason: '$name: ${step['name']} uses ${match.group(0)}',
              );
            }
            if (step['id'] case final String id) seen.add(id);
          }
        }
      }
    });

    test('every build-hooks cache has the same path and key (step 3)', () {
      for (final name in ['android.yml', 'ci.yml', 'web-experiment.yml']) {
        final hooks = _usesSteps(
          _workflow(name),
          'actions/cache',
        ).where((s) => _with(s)['path'] == _hooksPath).toList();
        expect(hooks, hasLength(1), reason: name);
        expect(_with(hooks.single)['key'], _hooksKey, reason: name);
        expect(
          _with(hooks.single)['restore-keys'],
          _hooksRestoreKey,
          reason: name,
        );
      }
    });

    test('every flutter build passes the build info and run number', () {
      var count = 0;
      for (final name in _workflowNames()) {
        for (final step in _allSteps(_workflow(name))) {
          for (final line in _commands(step)) {
            if (!line.startsWith('flutter build ')) continue;
            count++;
            final dir = '${step['working-directory']}';
            // The app, and the ink lab of web-experiment (INFRA-O1).
            expect(dir, isIn(['app', _inkLabDir]), reason: name);
            final defineFile =
                '--dart-define-from-file='
                '${p.posix.relative('build/build_info.json', from: dir)}';
            expect(line, contains(' --release'), reason: name);
            expect(line, contains(' $defineFile'), reason: name);
            expect(line, contains(' $_buildNumber'), reason: name);
          }
        }
      }
      expect(count, 5);
    });

    test('every `ws` call parses with the real ws arguments', () async {
      final calls = <String>[];
      final ws = RegExp(r'dart run tool/ws\.dart ([^\n]*)');
      for (final name in _workflowNames()) {
        for (final step in _allSteps(_workflow(name))) {
          for (final match in ws.allMatches('${step['run'] ?? ''}')) {
            calls.add(match.group(1)!);
          }
        }
      }
      expect(calls, hasLength(19));
      for (final call in calls) {
        final args = _shellWords(call, _sampleVariables);
        final err = StringBuffer();
        final code = await runZoned(
          () => runWs([
            ...args,
            '--help',
          ], context: WsContext(out: StringBuffer(), err: err)),
          zoneSpecification: ZoneSpecification(print: (_, _, _, _) {}),
        );
        expect(code, 0, reason: '`ws $call` → $args: $err');
      }
    });

    test('every build-info channel is a build channel', () {
      final channel = RegExp(r'build-info --channel ("\$BUILD_CHANNEL"|\w+) ');
      final quoted = RegExp(r"'([a-z]+)'");
      var count = 0;
      for (final name in _workflowNames()) {
        for (final step in _allSteps(_workflow(name))) {
          for (final line in _commands(step)) {
            if (!line.contains(' build-info ')) continue;
            count++;
            expect(line, endsWith(' --out build/build_info.json'));
            final value = channel.firstMatch(line)!.group(1)!;
            if (value == r'"$BUILD_CHANNEL"') {
              // Set from an expression in the step env.
              final env = '${(step['env'] as YamlMap)['BUILD_CHANNEL']}';
              final values = [
                for (final m in quoted.allMatches(env)) m.group(1)!,
              ];
              if (values.isEmpty) {
                expect(env, r'${{ steps.channel.outputs.build }}');
              }
              expect(buildChannels, containsAll(values), reason: name);
            } else {
              expect(buildChannels, contains(value), reason: name);
            }
          }
        }
      }
      expect(count, 4);
    });

    test('every deploy is gated on the secret and the project variable', () {
      var count = 0;
      for (final name in _workflowNames()) {
        final workflow = _workflow(name);
        for (final job in _jobs(workflow).values) {
          for (final step in _steps(job)) {
            if (!'${step['uses'] ?? ''}'.startsWith(
              'FirebaseExtended/action-hosting-deploy@',
            )) {
              continue;
            }
            count++;
            final env = job['env'] as YamlMap;
            expect(
              env['FIREBASE_SA'],
              r'${{ secrets.FIREBASE_SERVICE_ACCOUNT }}',
            );
            expect(
              env['FIREBASE_PROJECT_ID'],
              r'${{ vars.FIREBASE_PROJECT_ID }}',
            );
            expect(step['id'], 'deploy');
            expect(
              '${step['if']}',
              startsWith(
                "env.FIREBASE_SA != '' && env.FIREBASE_PROJECT_ID != ''",
              ),
              reason: name,
            );
            final withMap = _with(step);
            expect(
              withMap['firebaseServiceAccount'],
              r'${{ secrets.FIREBASE_SERVICE_ACCOUNT }}',
            );
            expect(withMap['projectId'], r'${{ vars.FIREBASE_PROJECT_ID }}');
            expect(withMap['firebaseToolsVersion'], '15.34.2', reason: name);
            expect(withMap['entryPoint'], 'app');
            expect(withMap['expires'], '7d');
            expect(withMap['disableComment'], isTrue);
            expect(withMap.containsKey('repoToken'), isFalse);
          }
        }
      }
      expect(count, 2);
    });

    test('every run script passes `bash -n`', () {
      final expression = RegExp(r'\$\{\{[^}]*\}\}');
      var count = 0;
      for (final name in _workflowNames()) {
        for (final step in _allSteps(_workflow(name))) {
          final run = step['run'];
          if (run == null) continue;
          count++;
          final script = '$run'.replaceAll(expression, 'x');
          final result = Process.runSync('bash', ['-n', '-c', script]);
          expect(
            result.exitCode,
            0,
            reason: '$name: ${step['name']}: ${result.stderr}',
          );
        }
      }
      expect(count, greaterThan(30));
      // The check itself catches a broken script.
      expect(
        Process.runSync('bash', ['-n', '-c', 'if [ x ]; then echo']).exitCode,
        isNot(0),
      );
    });
  });

  group('ci.yml', () {
    late YamlMap ci;
    late YamlMap job;
    late List<YamlMap> steps;

    setUp(() {
      ci = _workflow('ci.yml');
      job = _jobs(ci).values.single;
      steps = _steps(job);
    });

    YamlMap step(String name) => _named(steps, name);

    test('push on every branch (docs ignored) and manual dispatch', () {
      final on = ci['on'] as YamlMap;
      expect(on.keys, unorderedEquals(['push', 'workflow_dispatch']));
      final push = on['push'] as YamlMap;
      expect(push.keys, ['paths-ignore'], reason: 'no branch filter');
      expect(push['paths-ignore'], _ignoredPaths);
      final inputs = (on['workflow_dispatch'] as YamlMap)['inputs'] as YamlMap;
      expect(inputs.keys, unorderedEquals(['deploy', 'integration']));
      expect((inputs['deploy'] as YamlMap)['type'], 'boolean');
      expect((inputs['deploy'] as YamlMap)['default'], isTrue);
      expect((inputs['integration'] as YamlMap)['type'], 'boolean');
      expect((inputs['integration'] as YamlMap)['default'], isFalse);
    });

    test('concurrency per ref with cancel-in-progress', () {
      final concurrency = ci['concurrency'] as YamlMap;
      expect(concurrency['group'], r'ci-${{ github.ref }}');
      expect(concurrency['cancel-in-progress'], isTrue);
    });

    test('single job on ubuntu with a 60 minute limit and the env', () {
      expect(_jobs(ci), hasLength(1));
      expect(job['runs-on'], 'ubuntu-latest');
      // A full run on main or the default branch (every member, VM and
      // Chrome — locally about 9 + 8 minutes on 4 cores) on the 2-core
      // runner of a private repository, plus the integration input.
      expect(job['timeout-minutes'], 60);
      expect((job['env'] as YamlMap).value, {
        'FIREBASE_SA': r'${{ secrets.FIREBASE_SERVICE_ACCOUNT }}',
        'FIREBASE_PROJECT_ID': r'${{ vars.FIREBASE_PROJECT_ID }}',
        'DEFAULT_BRANCH': _defaultBranchValue,
        'FULL_RUN': _fullRunValue,
      });
    });

    test('the 6.13 steps in order', () {
      expect(
        [for (final s in steps) s['name']],
        [
          'Start clock',
          'Checkout', // 1
          'Set up Flutter', // 2
          'Cache build hooks', // 3
          'Cache browser test assets', // 4
          'Dependencies', // 5
          'Workspace rules (strict)', // 6
          'Workspace rules',
          'Analyze', // 7
          'VM tests (all members)', // 8
          'VM tests (affected)',
          'Tool tests', // contract 7.6 B1 v1.3, V3
          'Browser tests (all members)', // 9
          'Browser tests (affected)',
          'Integration tests (VM)', // 10
          'Integration tests (Chrome)',
          'Channel', // 11
          'Build info', // 12
          'Verify web assets', // 13
          'Web build', // 14
          'Finalize web build', // 15
          'Deploy to Firebase Hosting', // 16
          'Summary', // 17
        ],
      );
    });

    test('commands of each step', () {
      final expected = {
        'Dependencies': ['flutter pub get --enforce-lockfile'],
        'Workspace rules (strict)': ['$_ws check --strict'],
        'Workspace rules': ['$_ws check'],
        'Analyze': ['$_ws analyze'],
        'VM tests (all members)': ['$_ws test'],
        'VM tests (affected)': ['$_ws test $_affected'],
        'Tool tests': ['dart test tool/test'],
        'Browser tests (all members)': ['$_ws test --platform chrome'],
        'Browser tests (affected)': ['$_ws test --platform chrome $_affected'],
        'Integration tests (VM)': ['$_ws test --run-skipped -t integration'],
        'Integration tests (Chrome)': [
          '$_ws test --platform chrome --run-skipped -t integration',
        ],
        'Build info': [_buildInfoFromEnv],
        'Verify web assets': ['$_ws web-assets verify'],
        'Web build': [_webBuild],
        'Finalize web build': [_finalize],
      };
      for (final MapEntry(:key, :value) in expected.entries) {
        expect(_commands(step(key)), value, reason: key);
      }
      expect(step('Web build')['working-directory'], 'app');
    });

    test('checkout with full history (merge base for --affected-since)', () {
      expect(step('Checkout')['uses'], 'actions/checkout@v7');
      expect(_with(step('Checkout'))['fetch-depth'], 0);
    });

    test('two caches, both keyed on pubspec.lock', () {
      final caches = _usesSteps(ci, 'actions/cache');
      expect(caches, hasLength(2));
      for (final cache in caches) {
        expect(cache['uses'], 'actions/cache@v6');
        expect('${_with(cache)['key']}', contains("hashFiles('pubspec.lock'"));
      }
      final hooks = _with(step('Cache build hooks'));
      expect(hooks['path'], _hooksPath);
      expect(hooks['key'], _hooksKey);
      final prep = _with(step('Cache browser test assets'));
      expect(prep['key'], _prepKey);
      expect(
        '${prep['path']}'.trim().split('\n').map((l) => l.trim()),
        _prepPaths,
      );
      // Both caches are restored before the first build hook runs.
      expect(
        steps.indexOf(step('Cache browser test assets')),
        lessThan(steps.indexOf(step('Dependencies'))),
      );
    });

    test('the prep cache covers the app preparation outputs', () {
      final ignored = File(p.join(repoRoot, 'app', '.gitignore'))
          .readAsLinesSync()
          .where((l) => l.startsWith('/test/web/'));
      expect(ignored, isNotEmpty);
      for (final line in ignored) {
        expect(_prepPaths, contains('app$line'));
      }
      expect(
        File(p.join(repoRoot, 'app', 'tool', 'prepare_web_test.dart'))
            .existsSync(),
        isTrue,
      );
    });

    test('main and the default branch run the strict check and every '
        'member, other branches the affected ones', () {
      for (final name in [
        'Workspace rules (strict)',
        'VM tests (all members)',
        'Browser tests (all members)',
      ]) {
        expect(step(name)['if'], _fullRun, reason: name);
      }
      for (final name in [
        'Workspace rules',
        'VM tests (affected)',
        'Browser tests (affected)',
      ]) {
        expect(step(name)['if'], _notFullRun, reason: name);
      }
      for (final name in [
        'Dependencies',
        'Analyze',
        'Tool tests',
        'Channel',
        'Build info',
        'Verify web assets',
        'Web build',
        'Finalize web build',
      ]) {
        expect(step(name).containsKey('if'), isFalse, reason: name);
      }
    });

    // 01-infra 6.13: the base is the repository's default branch, which is
    // the development branch while the remote has no main. On the default
    // branch itself nothing is compared (every member); live stays main's.
    test('per push: full run or the default-branch base, and the channel', () {
      final scratch = Directory.systemTemp.createTempSync('ws_ci_channel_');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final fakeDart = File(p.join(scratch.path, 'bin', 'dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '#!/bin/sh\n'
          'echo "\$*" > "${p.join(scratch.path, 'dart-args')}"\n'
          'echo b-fake-channel\n',
        );
      Process.runSync('chmod', ['+x', fakeDart.path]);
      final pairs = [
        ('Workspace rules (strict)', 'Workspace rules'),
        ('VM tests (all members)', 'VM tests (affected)'),
        ('Browser tests (all members)', 'Browser tests (affected)'),
      ];
      // (pushed branch, default branch, full run, Hosting channel)
      final scenarios = [
        (_devBranch, _devBranch, true, 'b-fake-channel'), // now
        ('area/infra', _devBranch, false, 'b-fake-channel'),
        ('main', _devBranch, true, 'live'), // main before it is the default
        ('main', 'main', true, 'live'),
        ('feature/x', 'main', false, 'b-fake-channel'),
      ];
      for (final (branch, defaultBranch, full, channel) in scenarios) {
        final reason = '$branch (default $defaultBranch)';
        final github = {
          'github.ref': 'refs/heads/$branch',
          'github.ref_name': branch,
          'github.event.repository.default_branch': defaultBranch,
        };
        expect(_evaluate(_fullRunValue, github), full, reason: reason);
        final env = {'env.FULL_RUN': '$full'};
        for (final (all, affected) in pairs) {
          expect(_evaluate('${step(all)['if']}', env), full, reason: reason);
          expect(
            _evaluate('${step(affected)['if']}', env),
            !full,
            reason: reason,
          );
        }
        if (!full) {
          // The affected run compares with origin/<default branch>.
          final args = _shellWords(
            _commands(step('VM tests (affected)')).single,
            {'DEFAULT_BRANCH': defaultBranch},
          );
          expect(args.sublist(3), [
            'test',
            '--affected-since',
            'origin/$defaultBranch',
            '--all-if-no-base',
          ], reason: reason);
        }
        // The Channel script itself, with a fake `dart` for ws channel-id.
        final output = File(p.join(scratch.path, 'output'))
          ..writeAsStringSync('');
        final result = Process.runSync(
          'bash',
          ['-e', '-c', '${step('Channel')['run']}'],
          environment: {
            'PATH': '${p.dirname(fakeDart.path)}:/usr/bin:/bin',
            'GITHUB_REF': 'refs/heads/$branch',
            'GITHUB_REF_NAME': branch,
            'GITHUB_OUTPUT': output.path,
          },
        );
        expect(result.exitCode, 0, reason: '$reason: ${result.stderr}');
        expect(output.readAsLinesSync(), [
          'id=$channel',
          'build=${channel == 'live' ? 'live' : 'preview'}',
        ], reason: reason);
        if (channel != 'live') {
          expect(
            File(p.join(scratch.path, 'dart-args')).readAsStringSync().trim(),
            'run tool/ws.dart channel-id --branch $branch',
            reason: reason,
          );
        }
      }
    });

    test('no fixed main base; main is named only where live is decided', () {
      for (final name in _workflowNames()) {
        final text = File(p.join(_workflowsDir, name)).readAsStringSync();
        expect(text, isNot(contains('origin/main')), reason: name);
      }
      expect(
        [
          for (final s in steps)
            if ('${s.value}'.contains('refs/heads/main')) s['name'],
        ],
        ['Channel'],
      );
      // Deploying does not look at the branch: Channel picks live or the
      // preview channel, the secrets and the event gate the step.
      expect(
        '${step('Deploy to Firebase Hosting')['if']}',
        isNot(contains('github.ref')),
      );
    });

    test('integration tag tests only on manual dispatch with the input', () {
      for (final name in [
        'Integration tests (VM)',
        'Integration tests (Chrome)',
      ]) {
        expect(step(name)['if'], 'inputs.integration == true', reason: name);
      }
      final runSkipped = [
        for (final s in steps)
          if ('${s['run'] ?? ''}'.contains('--run-skipped')) s['name'],
      ];
      expect(runSkipped, [
        'Integration tests (VM)',
        'Integration tests (Chrome)',
      ]);
    });

    test('channel: live on main, ws channel-id elsewhere', () {
      final channel = step('Channel');
      expect(channel['id'], 'channel');
      final run = '${channel['run']}';
      expect(run, contains(r'''if [ "$GITHUB_REF" = 'refs/heads/main' ]'''));
      expect(run, contains(r'''echo 'id=live' >> "$GITHUB_OUTPUT"'''));
      expect(run, contains(r'''echo 'build=live' >> "$GITHUB_OUTPUT"'''));
      expect(
        run,
        contains(
          r'$(dart run tool/ws.dart channel-id --branch "$GITHUB_REF_NAME")',
        ),
      );
      expect(run, contains(r'''echo "id=$channel_id" >> "$GITHUB_OUTPUT"'''));
      expect(run, contains(r'''echo 'build=preview' >> "$GITHUB_OUTPUT"'''));
      expect(
        (step('Build info')['env'] as YamlMap)['BUILD_CHANNEL'],
        r'${{ steps.channel.outputs.build }}',
      );
    });

    test('deploy: push or the deploy input, the branch channel, 7 days', () {
      final deploy = step('Deploy to Firebase Hosting');
      expect(
        deploy['if'],
        "env.FIREBASE_SA != '' && env.FIREBASE_PROJECT_ID != '' && "
        "(github.event_name == 'push' || inputs.deploy)",
      );
      expect(deploy['uses'], 'FirebaseExtended/action-hosting-deploy@v0');
      expect(_with(deploy)['channelId'], r'${{ steps.channel.outputs.id }}');
    });

    test('summary always runs: label, channel, address or the guide', () {
      final summary = step('Summary');
      expect(summary['if'], 'always()');
      final env = summary['env'] as YamlMap;
      expect(env['DEPLOY_URL'], r'${{ steps.deploy.outputs.details_url }}');
      expect(env['DEPLOY_OUTCOME'], r'${{ steps.deploy.outcome }}');
      expect(env['CHANNEL_ID'], r'${{ steps.channel.outputs.id }}');
      final run = '${summary['run']}';
      expect(run, contains(r'>> "$GITHUB_STEP_SUMMARY"'));
      expect(run, contains('build/build_info.json'));
      expect(run, contains('Firebase 미설정 — docs/guides/02-github-secrets.md'));
      expect(run, contains(r'$RUNNER_TEMP/step-seconds'));
    });

    test('timed steps record their seconds for the summary', () {
      final timed = [
        for (final s in steps)
          if ('${s['run'] ?? ''}'.contains(r'"$SECONDS"')) s['name'],
      ];
      expect(
        timed,
        containsAll([
          'Dependencies',
          'Analyze',
          'VM tests (all members)',
          'VM tests (affected)',
          'Browser tests (all members)',
          'Browser tests (affected)',
          'Web build',
        ]),
      );
      for (final s in steps) {
        for (final line in _runLines(s)) {
          if (line.contains(r'"$SECONDS"')) {
            expect(line, endsWith(r'>> "$RUNNER_TEMP/step-seconds"'));
          }
        }
      }
    });
  });

  group('android.yml', () {
    late YamlMap android;
    late YamlMap job;
    late List<YamlMap> steps;

    setUp(() {
      android = _workflow('android.yml');
      job = _jobs(android).values.single;
      steps = _steps(job);
    });

    test('pushes to main and to the development branch (docs ignored), and '
        'manual runs', () {
      final on = android['on'] as YamlMap;
      expect(on.keys, unorderedEquals(['push', 'workflow_dispatch']));
      final push = on['push'] as YamlMap;
      // The development branch (the default branch while the remote has no
      // main) builds an APK on every push too, until main is the default
      // branch — guide 05.
      expect(push['branches'], ['main', _devBranch]);
      expect(push['paths-ignore'], _ignoredPaths);
      // Off main the build is labelled `preview` (main: `live`).
      expect(
        (_named(steps, 'Build info')['env'] as YamlMap)['BUILD_CHANNEL'],
        "\${{ $_onMain && 'live' || 'preview' }}",
      );
    });

    test('ubuntu with a 30 minute limit', () {
      expect(job['runs-on'], 'ubuntu-latest');
      expect(job['timeout-minutes'], 30);
    });

    test('the 6.13 steps in order', () {
      expect(
        [for (final s in steps) s['uses'] ?? _commands(s).single],
        [
          'actions/checkout@v7',
          'actions/setup-java@v6',
          'subosito/flutter-action@v2',
          'actions/cache@v6',
          'flutter pub get --enforce-lockfile',
          _buildInfoFromEnv,
          _apkBuild,
          'actions/upload-artifact@v7',
        ],
      );
    });

    test('Java 17 (temurin) with the gradle cache', () {
      final java = _with(_usesSteps(android, 'actions/setup-java').single);
      expect(java['distribution'], 'temurin');
      expect('${java['java-version']}', '17');
      expect(java['cache'], 'gradle');
    });

    test('the arm64 APK is kept for 7 days, uncompressed', () {
      final upload = _with(
        _usesSteps(android, 'actions/upload-artifact').single,
      );
      expect(upload['name'], r'noteapp-apk-${{ github.run_number }}');
      expect(
        upload['path'],
        'app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk',
      );
      expect(upload['retention-days'], 7);
      expect(upload['compression-level'], 0);
    });
  });

  group('web-experiment.yml', () {
    late YamlMap experiment;
    late List<YamlMap> steps;

    setUp(() {
      experiment = _workflow('web-experiment.yml');
      steps = _steps(_jobs(experiment).values.single);
    });

    test('manual only, inputs wasm (on), isolate (off) and target', () {
      final on = experiment['on'] as YamlMap;
      expect(on.keys, ['workflow_dispatch']);
      final inputs = (on['workflow_dispatch'] as YamlMap)['inputs'] as YamlMap;
      expect(inputs.keys, unorderedEquals(['wasm', 'isolate', 'target']));
      expect((inputs['wasm'] as YamlMap)['type'], 'boolean');
      expect((inputs['wasm'] as YamlMap)['default'], isTrue);
      expect((inputs['isolate'] as YamlMap)['type'], 'boolean');
      expect((inputs['isolate'] as YamlMap)['default'], isFalse);
      // INFRA-O1: the app or the ink lab, the app by default.
      final target = inputs['target'] as YamlMap;
      expect(target['type'], 'choice');
      expect(target['options'], ['app', 'ink_lab']);
      expect(target['default'], 'app');
      expect(
        (experiment['concurrency'] as YamlMap)['group'],
        r'web-experiment-${{ inputs.target }}',
      );
    });

    test('target ink_lab builds the ink lab member and serves it from the '
        'Hosting public directory; the app steps are skipped', () {
      // The ink lab is a workspace member (root pubspec, INFRA-O1).
      expect(Workspace.load(repoRoot).memberNamed('ink_lab')?.path, _inkLabDir);
      const app = "inputs.target == 'app'";
      const inkLab = "inputs.target == 'ink_lab'";
      final appBuild = _named(steps, 'Web build');
      final finalize = _named(steps, 'Finalize web build');
      final labBuild = _named(steps, 'Web build (ink lab)');
      final copy = _named(steps, 'Ink lab to the hosting directory');
      final deploy = _named(steps, 'Deploy to Firebase Hosting');
      expect(appBuild['if'], app);
      expect(finalize['if'], app);
      expect(labBuild['if'], inkLab);
      expect(copy['if'], inkLab);
      expect(labBuild['working-directory'], _inkLabDir);
      expect(labBuild['env'], appBuild['env']);
      // The same flag lines as the app build.
      expect(
        _runLines(labBuild).where((l) => l.startsWith('if ')),
        _runLines(appBuild).where((l) => l.startsWith('if ')),
      );
      expect(_runLines(copy), [
        'rm -rf app/build/web',
        'mkdir -p app/build',
        'cp -R $_inkLabDir/build/web app/build/web',
      ]);
      // app/firebase.json serves build/web (entryPoint app).
      expect(
        ((jsonDecode(
              File(p.join(repoRoot, 'app', 'firebase.json')).readAsStringSync(),
            ) as Map)['hosting']
            as Map)['public'],
        'build/web',
      );
      expect(_with(deploy)['entryPoint'], 'app');
      for (final step in [labBuild, copy]) {
        expect(steps.indexOf(step), greaterThan(steps.indexOf(appBuild)));
        expect(steps.indexOf(step), lessThan(steps.indexOf(deploy)));
      }
      expect(steps.indexOf(labBuild), lessThan(steps.indexOf(copy)));
    });

    test('experiment build: --wasm, isolation with self-hosted CanvasKit', () {
      final build = _named(steps, 'Web build');
      expect((build['env'] as YamlMap).value, {
        'WASM': r'${{ inputs.wasm }}',
        'ISOLATE': r'${{ inputs.isolate }}',
      });
      final run = '${build['run']}';
      expect(
        run,
        contains(r'''if [ "$WASM" = 'true' ]; then flags+=(--wasm)'''),
      );
      expect(
        run,
        contains(
          r'''if [ "$ISOLATE" = 'true' ]; then flags+=(--no-web-resources-cdn)''',
        ),
      );
      final headers = _named(steps, 'Cross-origin isolation headers');
      expect(headers['if'], 'inputs.isolate == true');
      expect(_runLines(headers), [
        '$_ws hosting-config --isolate > "\$RUNNER_TEMP/firebase.json"',
        r'mv "$RUNNER_TEMP/firebase.json" app/firebase.json',
      ]);
      expect(
        steps.indexOf(headers),
        lessThan(steps.indexOf(_named(steps, 'Deploy to Firebase Hosting'))),
      );
    });

    test('experiment channel exp-wasm, checked assets, finalized build', () {
      expect(_commands(_named(steps, 'Build info')), [
        '$_ws build-info --channel experiment --out build/build_info.json',
      ]);
      expect(_commands(_named(steps, 'Verify web assets')), [
        '$_ws web-assets verify',
      ]);
      expect(_commands(_named(steps, 'Finalize web build')), [_finalize]);
      final deploy = _named(steps, 'Deploy to Firebase Hosting');
      // exp-wasm for the app, exp-ink-lab for the ink lab (job env).
      expect(_with(deploy)['channelId'], r'${{ env.CHANNEL_ID }}');
      expect(
        (_jobs(experiment).values.single['env'] as YamlMap)['CHANNEL_ID'],
        r"${{ inputs.target == 'ink_lab' && 'exp-ink-lab' || 'exp-wasm' }}",
      );
      expect(
        deploy['if'],
        "env.FIREBASE_SA != '' && env.FIREBASE_PROJECT_ID != ''",
      );
      final summary = _named(steps, 'Summary');
      expect((summary['env'] as YamlMap)['TARGET'], r'${{ inputs.target }}');
      expect('${summary['run']}', contains(r'target=$TARGET'));
      expect('${summary['run']}', contains(r'$CHANNEL_ID'));
    });
  });

  group('ios-testflight.yml (draft)', () {
    late YamlMap ios;
    late YamlMap job;

    setUp(() {
      ios = _workflow('ios-testflight.yml');
      job = _jobs(ios).values.single;
    });

    test('manual only, with the macOS cost confirmation input', () {
      final on = ios['on'] as YamlMap;
      expect(on.keys, ['workflow_dispatch']);
      final inputs = (on['workflow_dispatch'] as YamlMap)['inputs'] as YamlMap;
      final confirm = inputs['confirm'] as YamlMap;
      expect(confirm['required'], isTrue);
      expect(confirm['description'], contains('yes'));
    });

    test('the job is gated on the repository variable and the input', () {
      expect(
        job['if'],
        "vars.IOS_TESTFLIGHT_ENABLED == 'true' && inputs.confirm == 'yes'",
      );
      expect(job['runs-on'], 'macos-latest');
      expect(job['timeout-minutes'], 45);
      expect((job['env'] as YamlMap).value, {
        for (final name in [
          'APPLE_TEAM_ID',
          'ASC_KEY_ID',
          'ASC_ISSUER_ID',
          'ASC_PRIVATE_KEY',
        ])
          name: '\${{ secrets.$name }}',
      });
    });

    test('build without signing, archive, export with ExportOptions', () {
      final runs = [for (final s in _steps(job)) ..._runLines(s)].join('\n');
      expect(
        runs,
        contains(
          'flutter build ios --release --no-codesign $_buildNumber '
          '$_defineFile',
        ),
      );
      expect(runs, contains('xcodebuild archive'));
      expect(runs, contains('xcodebuild -exportArchive'));
      expect(runs, contains('-allowProvisioningUpdates'));
      expect(runs, contains(r'DEVELOPMENT_TEAM="$APPLE_TEAM_ID"'));
      expect(runs, contains('CODE_SIGN_STYLE=Automatic'));
      expect(runs, contains('cp ExportOptions.plist'));
    });

    test('app/ios: ExportOptions.plist and the display name (6.15)', () {
      final export = File(p.join(repoRoot, 'app', 'ios', 'ExportOptions.plist'))
          .readAsStringSync();
      expect(
        export,
        matches(RegExp(r'<key>method</key>\s*<string>app-store-connect<')),
      );
      expect(
        export,
        matches(RegExp(r'<key>destination</key>\s*<string>upload<')),
      );
      final info = File(p.join(repoRoot, 'app', 'ios', 'Runner', 'Info.plist'))
          .readAsStringSync();
      expect(
        info,
        matches(RegExp(r'<key>CFBundleDisplayName</key>\s*<string>필기노트<')),
      );
    });
  });

  group('issue templates', () {
    final dir = p.join(repoRoot, '.github', 'ISSUE_TEMPLATE');

    test('feedback form with the 6.13 inputs', () {
      final form = _load(p.join(dir, 'feedback.yml'));
      expect(form['name'], isA<String>());
      expect(form['description'], isA<String>());
      final fields = <String, YamlMap>{
        for (final item in form['body'] as YamlList)
          if ((item as YamlMap)['id'] case final String id) id: item,
      };
      expect(fields.keys, [
        'device',
        'pencil',
        'app-version',
        'steps',
        'expected',
        'actual',
        'diagnostics',
        'media',
      ]);
      YamlMap attributes(String id) => fields[id]!['attributes'] as YamlMap;
      expect(fields['device']!['type'], 'dropdown');
      expect(attributes('device')['options'], [
        'iPad Pro 13',
        '안드로이드 태블릿',
        '기타',
      ]);
      bool required(String id) =>
          (fields[id]!['validations'] as YamlMap?)?['required'] == true;
      expect(
        [
          for (final id in fields.keys)
            if (required(id)) id,
        ],
        ['device', 'app-version', 'steps', 'expected', 'actual'],
      );
      expect('${attributes('diagnostics')['label']}', contains('선택'));
      expect('${attributes('app-version')['description']}', contains('앱 정보'));
      expect(
        '${attributes('diagnostics')['description']}',
        contains('진단 정보 복사'),
      );
    });

    test('config keeps blank issues', () {
      expect(_load(p.join(dir, 'config.yml'))['blank_issues_enabled'], isTrue);
    });
  });
}
