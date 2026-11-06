// .github checks (docs/plans/01-infra.md 6.13 and the 9.1 workflows_test row,
// I13; docs/plans/m5-7/01-infra.md 6.14 and 6.16 for 2차 R2-B1): the six
// workflows (triggers, concurrency, time limits, the two caches and their
// keys, browser and integration tests, the test scope — main / manual full
// runs, the default branch since its previous push, other branches since the
// default branch, with the full-run fallbacks —, the live channel on main
// only, the deploy gate on secrets, pinned versions, the iOS gate, the manual
// APK build, the functions skeleton with its `hashFiles` guard) and the issue
// templates; 2차 J2 / J3 (m5-7/01-infra 6.10.3, 6.11.5, 6.11.6): the APK
// signing ways, ios-compile.yml and the two TestFlight signing ways, their
// shell steps run with fake tools. Every `ws` call in a workflow is parsed by
// the real `ws` argument parser, and every `run` script passes `bash -n`.

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
  // 2차 (m5-7/01-infra 7.3): functions.yml.
  'actions/setup-node': 'v6',
};

/// `paths-ignore` of every push trigger (6.13).
const _ignoredPaths = ['docs/**', '**/*.md', '.github/ISSUE_TEMPLATE/**'];

/// Job time limits (6.13).
const _timeouts = {
  'android.yml': 30,
  'ci.yml': 60,
  'functions.yml': 15,
  'ios-compile.yml': 45,
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

/// ci.yml (2차 R2-B1, m5-7/01-infra 6.16): the "Test scope" step sets
/// FULL_RUN, STRICT_CHECK and AFFECTED_BASE.
const _fullRun = "env.FULL_RUN == 'true'";
const _notFullRun = "env.FULL_RUN != 'true'";
const _strict = "env.STRICT_CHECK == 'true'";
const _notStrict = "env.STRICT_CHECK != 'true'";
const _defaultBranchValue = r'${{ github.event.repository.default_branch }}';
const _affected = r'--affected-since "$AFFECTED_BASE" --all-if-no-base';
const _zeroSha = '0000000000000000000000000000000000000000';
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

/// The fixed Android key secrets (m5-7/01-infra 6.10.3, guide 07).
const _androidSecrets = [
  'ANDROID_KEYSTORE_BASE64',
  'ANDROID_KEYSTORE_PASSWORD',
  'ANDROID_KEY_ALIAS',
  'ANDROID_KEY_PASSWORD',
];

/// The development branch: the repository's default branch while the remote
/// has no main.
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
  'AFFECTED_BASE': 'origin/$_devBranch',
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
    test('the four workflows of 6.13, functions.yml and ios-compile.yml (2차) '
        'exist and '
        'parse', () {
      expect(_workflowNames(), [
        'android.yml',
        'ci.yml',
        'functions.yml',
        'ios-compile.yml',
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
      expect(count, 5);
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
      expect(count, 5);
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
      for (final name in [
        'android.yml',
        'ci.yml',
        'ios-compile.yml',
        'web-experiment.yml',
      ]) {
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
      expect(count, 7);
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
      expect(calls, hasLength(20));
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
      expect(count, 5);
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
            // Contract v2.3 C23-01: the pinned firebase-tools is 15.34.1.
            expect(withMap['firebaseToolsVersion'], '15.34.1', reason: name);
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

    test('push on every branch (docs ignored) and manual dispatch with '
        'deploy, integration and full', () {
      final on = ci['on'] as YamlMap;
      expect(on.keys, unorderedEquals(['push', 'workflow_dispatch']));
      final push = on['push'] as YamlMap;
      expect(push.keys, ['paths-ignore'], reason: 'no branch filter');
      expect(push['paths-ignore'], _ignoredPaths);
      final inputs = (on['workflow_dispatch'] as YamlMap)['inputs'] as YamlMap;
      expect(inputs.keys, unorderedEquals(['deploy', 'integration', 'full']));
      expect((inputs['deploy'] as YamlMap)['type'], 'boolean');
      expect((inputs['deploy'] as YamlMap)['default'], isTrue);
      expect((inputs['integration'] as YamlMap)['type'], 'boolean');
      expect((inputs['integration'] as YamlMap)['default'], isFalse);
      // 2차 R2-B1: a manual run tests only the changed members unless full.
      expect((inputs['full'] as YamlMap)['type'], 'boolean');
      expect((inputs['full'] as YamlMap)['default'], isFalse);
    });

    test('concurrency per ref with cancel-in-progress; default-branch '
        'pushes (not main) get one group per run', () {
      final concurrency = ci['concurrency'] as YamlMap;
      // Each default-branch push tests only its change since
      // github.event.before: a cancelled or replaced run would leave that
      // change untested.
      expect(
        concurrency['group'],
        r'ci-${{ github.ref }}'
        r"${{ github.event_name == 'push' && "
        r"github.ref != 'refs/heads/main' && "
        r'github.ref_name == github.event.repository.default_branch && '
        r"format('-{0}', github.run_id) || '' }}",
      );
      expect(concurrency['cancel-in-progress'], isTrue);
    });

    test('single job on ubuntu with a 60 minute limit and the env', () {
      expect(_jobs(ci), hasLength(1));
      expect(job['runs-on'], 'ubuntu-latest');
      // A full run (every member, VM and Chrome) on the 2-core runner of a
      // private repository: 30 minutes measured after the 1차 integration
      // (VM 15, Chrome 10, web build 1), plus the integration input.
      expect(job['timeout-minutes'], 60);
      expect((job['env'] as YamlMap).value, {
        'FIREBASE_SA': r'${{ secrets.FIREBASE_SERVICE_ACCOUNT }}',
        'FIREBASE_PROJECT_ID': r'${{ vars.FIREBASE_PROJECT_ID }}',
        'DEFAULT_BRANCH': _defaultBranchValue,
        'BEFORE_SHA': r'${{ github.event.before }}',
        'FULL_INPUT': r'${{ inputs.full }}',
      });
    });

    test('the 6.13 steps in order', () {
      expect(
        [for (final s in steps) s['name']],
        [
          'Start clock',
          'Test scope', // 2차 R2-B1
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

    test('FULL_RUN picks every member or the affected ones, STRICT_CHECK the '
        'strict check', () {
      expect(step('Workspace rules (strict)')['if'], _strict);
      expect(step('Workspace rules')['if'], _notStrict);
      for (final name in [
        'VM tests (all members)',
        'Browser tests (all members)',
      ]) {
        expect(step(name)['if'], _fullRun, reason: name);
      }
      for (final name in ['VM tests (affected)', 'Browser tests (affected)']) {
        expect(step(name)['if'], _notFullRun, reason: name);
      }
      for (final name in [
        'Test scope',
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

    // m5-7/01-infra 6.16 (2차 R2-B1): main and manual full runs test every
    // member; the default branch only what changed since its previous push
    // (every member without one); other branches what changed since the
    // default branch. Live stays main's.
    test('per push: the test scope (Test scope script) and the channel', () {
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
      const before = '1234567890abcdef1234567890abcdef12345678';
      // (event, pushed branch, default branch, before, full input) →
      // (full run, strict, affected base, Hosting channel)
      final scenarios = [
        // now: the development branch is the default branch
        (
          'push',
          _devBranch,
          _devBranch,
          before,
          '',
          false,
          true,
          before,
          'b-fake-channel',
        ),
        (
          'push',
          _devBranch,
          _devBranch,
          _zeroSha,
          '',
          true,
          true,
          '',
          'b-fake-channel',
        ), // first push of the branch
        (
          'workflow_dispatch',
          _devBranch,
          _devBranch,
          '',
          'false',
          true,
          true,
          '',
          'b-fake-channel',
        ), // no previous push to compare with
        (
          'workflow_dispatch',
          _devBranch,
          _devBranch,
          '',
          'true',
          true,
          true,
          '',
          'b-fake-channel',
        ),
        (
          'push',
          'area2/infra',
          _devBranch,
          before,
          '',
          false,
          false,
          'origin/$_devBranch',
          'b-fake-channel',
        ),
        (
          'workflow_dispatch',
          'area2/infra',
          _devBranch,
          '',
          'false',
          false,
          false,
          'origin/$_devBranch',
          'b-fake-channel',
        ),
        (
          'workflow_dispatch',
          'area2/infra',
          _devBranch,
          '',
          'true',
          true,
          true,
          '',
          'b-fake-channel',
        ),
        // main: always every member, live channel
        ('push', 'main', _devBranch, before, '', true, true, '', 'live'),
        ('push', 'main', 'main', before, '', true, true, '', 'live'),
        (
          'push',
          'feature/x',
          'main',
          before,
          '',
          false,
          false,
          'origin/main',
          'b-fake-channel',
        ),
      ];
      for (final (
            event,
            branch,
            defaultBranch,
            beforeSha,
            fullInput,
            full,
            strict,
            base,
            channel,
          )
          in scenarios) {
        final reason =
            '$event $branch (default $defaultBranch, before '
            '${beforeSha.isEmpty ? '-' : beforeSha.substring(0, 4)}, '
            'full=$fullInput)';
        // The Test scope script itself.
        final githubEnv = File(p.join(scratch.path, 'github-env'))
          ..writeAsStringSync('');
        final scope = Process.runSync(
          'bash',
          ['-e', '-c', '${step('Test scope')['run']}'],
          environment: {
            'PATH': '/usr/bin:/bin',
            'GITHUB_REF': 'refs/heads/$branch',
            'GITHUB_REF_NAME': branch,
            'GITHUB_ENV': githubEnv.path,
            'DEFAULT_BRANCH': defaultBranch,
            'BEFORE_SHA': beforeSha,
            'FULL_INPUT': fullInput,
          },
        );
        expect(scope.exitCode, 0, reason: '$reason: ${scope.stderr}');
        final values = {
          for (final line in githubEnv.readAsLinesSync())
            line.substring(0, line.indexOf('=')): line.substring(
              line.indexOf('=') + 1,
            ),
        };
        expect(values['FULL_RUN'], '$full', reason: reason);
        expect(values['STRICT_CHECK'], '$strict', reason: reason);
        expect(values['AFFECTED_BASE'], base, reason: reason);
        expect(values['TEST_SCOPE'], isNotEmpty, reason: reason);
        final env = {
          for (final MapEntry(:key, :value) in values.entries)
            'env.$key': value,
        };
        for (final (all, affected) in [
          ('VM tests (all members)', 'VM tests (affected)'),
          ('Browser tests (all members)', 'Browser tests (affected)'),
        ]) {
          expect(_evaluate('${step(all)['if']}', env), full, reason: reason);
          expect(
            _evaluate('${step(affected)['if']}', env),
            !full,
            reason: reason,
          );
        }
        expect(
          _evaluate('${step('Workspace rules (strict)')['if']}', env),
          strict,
          reason: reason,
        );
        expect(
          _evaluate('${step('Workspace rules')['if']}', env),
          !strict,
          reason: reason,
        );
        if (!full) {
          for (final name in [
            'VM tests (affected)',
            'Browser tests (affected)',
          ]) {
            final args = _shellWords(_commands(step(name)).single, {
              'AFFECTED_BASE': values['AFFECTED_BASE']!,
            });
            expect(args.sublist(args.indexOf('--affected-since')), [
              '--affected-since',
              base,
              '--all-if-no-base',
            ], reason: '$reason: $name');
          }
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

    test('the summary reports the test scope', () {
      expect('${step('Summary')['run']}', contains(r'${TEST_SCOPE:-'));
      expect(
        steps.indexOf(step('Test scope')),
        lessThan(steps.indexOf(step('Workspace rules (strict)'))),
      );
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
        ['Test scope', 'Channel'],
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

    test('manual runs only (2차 R2-B1 — the free Actions minutes; Run '
        'workflow on the default branch, guide 05)', () {
      final on = android['on'] as YamlMap;
      expect(on.keys, ['workflow_dispatch']);
      expect(on['workflow_dispatch'], isNull, reason: 'no inputs');
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

    test('the 6.10.3 steps in order: signing first, signature check after '
        'the build, clean-up last', () {
      expect(
        [for (final s in steps) s['name']],
        [
          'Checkout',
          'Signing',
          'Set up Java',
          'Cache Android NDK',
          'Set up Flutter',
          'Build hooks (downloads sqlite3 when not cached)',
          'Dependencies',
          'Build info',
          'Build APK',
          'Check signature',
          'Upload APK',
          'Remove signing material',
        ],
      );
      expect(
        [
          for (final s in steps)
            if (s['run'] != null && _commands(s).isNotEmpty)
              _commands(s).single,
        ],
        ['flutter pub get --enforce-lockfile', _buildInfoFromEnv, _apkBuild],
      );
    });

    test('Java 17 (temurin) with the gradle cache', () {
      final java = _with(_usesSteps(android, 'actions/setup-java').single);
      expect(java['distribution'], 'temurin');
      expect('${java['java-version']}', '17');
      expect(java['cache'], 'gradle');
    });

    test("the NDK cache holds Flutter's default NDK version", () {
      final ndk = _with(_named(steps, 'Cache Android NDK'));
      const version = '28.2.13676358';
      expect(ndk['path'], '/usr/local/lib/android/sdk/ndk/$version');
      expect(ndk['key'], 'ndk-$version');
      final flutterRoot = _flutterRoot();
      if (flutterRoot == null) {
        markTestSkipped('flutter not on PATH');
        return;
      }
      final kotlin = File(
        p.join(
          flutterRoot,
          'packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt',
        ),
      ).readAsStringSync();
      expect(kotlin, contains('val ndkVersion: String = "$version"'));
    });

    test('the secrets come in through the job env only; the variable too', () {
      expect((job['env'] as YamlMap).value, {
        for (final name in _androidSecrets) name: '\${{ secrets.$name }}',
        'ANDROID_CERT_SHA256': r'${{ vars.ANDROID_CERT_SHA256 }}',
      });
      for (final step in steps) {
        expect('${step.value}', isNot(contains('secrets.')));
        expect('${step['if'] ?? ''}', isNot(contains('vars.')));
      }
    });

    test('key.properties: the file build.gradle.kts reads, written by the '
        'signing step and removed by the clean-up step', () {
      final gradle = File(p.join(repoRoot, 'app/android/app/build.gradle.kts'))
          .readAsStringSync();
      // rootProject = app/android (its settings.gradle.kts).
      expect(gradle, contains('rootProject.file("key.properties")'));
      expect(
        File(p.join(repoRoot, 'app/android/settings.gradle.kts')).existsSync(),
        isTrue,
      );
      expect(
        '${_named(steps, 'Signing')['run']}',
        contains('} > app/android/key.properties'),
      );
      final clean = _named(steps, 'Remove signing material');
      expect(clean['if'], 'always()');
      expect(_runLines(clean), [
        'rm -f app/android/key.properties "\$RUNNER_TEMP/release.jks"',
      ]);
      // A failed signing step skips every later step except the clean-up.
      for (final step in steps.skip(2)) {
        if (identical(step, clean)) continue;
        expect(step['if'], isNull, reason: '${step['name']}');
      }
    });

    group('the signing step, run with fake environments', () {
      late Directory dir;
      setUp(() {
        dir = Directory.systemTemp.createTempSync('android_signing_');
        addTearDown(() => dir.deleteSync(recursive: true));
        Directory(p.join(dir.path, 'work', 'app', 'android'))
            .createSync(recursive: true);
        Directory(p.join(dir.path, 'runner')).createSync();
      });

      final keystore = List<int>.generate(300, (i) => (i * 7) % 256);
      final secrets = {
        'ANDROID_KEYSTORE_BASE64': base64Encode(keystore),
        'ANDROID_KEYSTORE_PASSWORD': 'Pass1234word5678',
        'ANDROID_KEY_ALIAS': 'noteapp-sideload',
        'ANDROID_KEY_PASSWORD': 'Key9876pass5432',
      };
      const cert = 'AB:CD:EF:01';

      ({int code, String stdout, String output, File properties, File jks})
      runSigning(Map<String, String> env) {
        final output = File(p.join(dir.path, 'output'))..writeAsStringSync('');
        final result = Process.runSync(
          'bash',
          ['-e', '-c', '${_named(steps, 'Signing')['run']}'],
          workingDirectory: p.join(dir.path, 'work'),
          environment: {
            'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
            'RUNNER_TEMP': p.join(dir.path, 'runner'),
            'GITHUB_OUTPUT': output.path,
            for (final name in [..._androidSecrets, 'ANDROID_CERT_SHA256'])
              name: env[name] ?? '',
          },
          includeParentEnvironment: false,
        );
        return (
          code: result.exitCode,
          stdout: '${result.stdout}',
          output: output.readAsStringSync(),
          properties: File(
            p.join(dir.path, 'work', 'app', 'android', 'key.properties'),
          ),
          jks: File(p.join(dir.path, 'runner', 'release.jks')),
        );
      }

      test('four secrets → release: the key file and key.properties', () {
        for (final env in [
          {...secrets, 'ANDROID_CERT_SHA256': cert},
          // Before the variable is set (first run after the secrets).
          secrets,
        ]) {
          final run = runSigning(env);
          expect(run.code, 0, reason: run.stdout);
          expect(run.output, 'mode=release\n');
          expect(run.jks.readAsBytesSync(), keystore);
          expect(run.properties.readAsLinesSync(), [
            'storeFile=${run.jks.path}',
            'storePassword=Pass1234word5678',
            'keyAlias=noteapp-sideload',
            'keyPassword=Key9876pass5432',
          ]);
          expect(
            run.properties.readAsLinesSync().map((l) => l.split('=').first),
            unorderedEquals([
              'storeFile',
              'storePassword',
              'keyAlias',
              'keyPassword',
            ]),
          );
          run.properties.deleteSync();
        }
      });

      test('a secret missing while ANDROID_CERT_SHA256 is set → the job '
          'fails before the build', () {
        for (final missing in _androidSecrets) {
          final run = runSigning({
            ...secrets,
            missing: '',
            'ANDROID_CERT_SHA256': cert,
          });
          expect(run.code, 1, reason: missing);
          expect(
            run.stdout,
            contains(
              '::error::고정 키 서명 재료가 없어요 — 이 APK는 덮어 설치할 수 없어 '
              '만들지 않아요(docs/guides/07-android-signing.md)',
            ),
          );
          expect(run.output, isEmpty);
          expect(run.properties.existsSync(), isFalse);
        }
      });

      test('no fixed key yet (no variable, not all secrets) → debug', () {
        for (final env in [
          <String, String>{},
          {...secrets, 'ANDROID_KEY_PASSWORD': ''},
        ]) {
          final run = runSigning(env);
          expect(run.code, 0, reason: run.stdout);
          expect(run.output, 'mode=debug\n');
          expect(run.properties.existsSync(), isFalse);
          expect(run.jks.existsSync(), isFalse);
        }
      });
    });

    test('the artifact name tells the signing: noteapp-apk-<run> or '
        'noteapp-debug-signed-<run>', () {
      final upload = _with(_named(steps, 'Upload APK'));
      String nameFor(String mode) => '${upload['name']}'.replaceAllMapped(
        RegExp(r'\$\{\{ (.+?) \}\}'),
        (m) {
          final expression = m.group(1)!;
          if (expression == 'github.run_number') return '42';
          final choice = RegExp(r"^(.+) && '([^']*)' \|\| '([^']*)'$")
              .firstMatch(expression);
          expect(choice, isNotNull, reason: expression);
          return _evaluate(choice!.group(1)!, {
                'steps.signing.outputs.mode': mode,
              })
              ? choice.group(2)!
              : choice.group(3)!;
        },
      );
      expect(nameFor('release'), 'noteapp-apk-42');
      expect(nameFor('debug'), 'noteapp-debug-signed-42');
      expect(
        upload['path'],
        'app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk',
      );
      expect(upload['retention-days'], 7);
      expect(upload['compression-level'], 0);
      expect(upload['if-no-files-found'], 'error');
    });

    group('the signature check, run with a fake apksigner', () {
      late Directory dir;
      const digest =
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      setUp(() {
        dir = Directory.systemTemp.createTempSync('android_apksigner_');
        addTearDown(() => dir.deleteSync(recursive: true));
        // `sort -V` must pick 36.1.0 (a plain sort would take 9.0.0).
        for (final (version, printed) in [
          ('9.0.0', 'f' * 64),
          ('34.0.0', 'e' * 64),
          ('36.1.0', digest),
        ]) {
          final tool = File(
            p.join(dir.path, 'sdk', 'build-tools', version, 'apksigner'),
          )..createSync(recursive: true);
          tool.writeAsStringSync('''
#!/usr/bin/env bash
[ "\$1 \$2 \$3" = "verify --print-certs app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk" ] || exit 9
[ -n "\$FAKE_SILENT" ] && exit 0
echo "Signer #1 certificate DN: CN=noteapp sideload"
echo "Signer #1 certificate SHA-256 digest: $printed"
echo "Signer #1 certificate SHA-1 digest: 0123456789abcdef0123456789abcdef01234567"
echo "Signer #1 certificate MD5 digest: 0123456789abcdef0123456789abcdef"
''');
          Process.runSync('chmod', ['+x', tool.path]);
        }
      });

      ({int code, String stdout, String summary}) check(
        String mode, {
        String cert = '',
        bool silent = false,
      }) {
        final summary = File(p.join(dir.path, 'summary'))
          ..writeAsStringSync('');
        final result = Process.runSync(
          'bash',
          [
            '-e',
            '-o',
            'pipefail',
            '-c',
            '${_named(steps, 'Check signature')['run']}',
          ],
          workingDirectory: dir.path,
          environment: {
            'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
            'ANDROID_HOME': p.join(dir.path, 'sdk'),
            'GITHUB_STEP_SUMMARY': summary.path,
            'SIGNING_MODE': mode,
            'ANDROID_CERT_SHA256': cert,
            if (silent) 'FAKE_SILENT': '1',
          },
          includeParentEnvironment: false,
        );
        return (
          code: result.exitCode,
          stdout: '${result.stdout}',
          summary: summary.readAsStringSync(),
        );
      }

      test('release with the registered fingerprint (keytool form: '
          'upper case, colons) → the fixed key in the summary', () {
        final keytool = [
          for (var i = 0; i < digest.length; i += 2)
            digest.substring(i, i + 2).toUpperCase(),
        ].join(':');
        for (final cert in [keytool, digest, '']) {
          final run = check('release', cert: cert);
          expect(run.code, 0, reason: run.stdout);
          expect(run.summary, '서명: 고정 키 (0123456789abcdef)\n');
        }
      });

      test('release with another fingerprint → failure', () {
        final run = check('release', cert: 'AA:BB');
        expect(run.code, 1);
        expect(
          run.stdout,
          contains('::error::서명 지문 $digest 이(가) ANDROID_CERT_SHA256와 달라요'),
        );
        expect(run.summary, isEmpty);
      });

      test('debug → the summary says it cannot be installed over', () {
        // The variable is never compared on a debug build.
        final run = check('debug', cert: 'AA:BB');
        expect(run.code, 0, reason: run.stdout);
        expect(
          run.summary,
          '서명: debug 키 — 이전 APK 위에 덮어 설치할 수 없어요. 설치가 안 되면 앱을 '
          '지우지 말고 알려 주세요\n',
        );
      });

      test('no digest printed → failure', () {
        final run = check('release', silent: true);
        expect(run.code, 1);
        expect(run.stdout, contains('::error::apksigner printed no SHA-256'));
      });
    });
  });

  group('functions.yml (2차 R2-B1 skeleton, m5-7/01-infra 6.14)', () {
    late YamlMap functions;
    late YamlMap job;
    late List<YamlMap> steps;

    setUp(() {
      functions = _workflow('functions.yml');
      job = _jobs(functions).values.single;
      steps = _steps(job);
    });

    test('runs on its paths only, or by hand', () {
      final on = functions['on'] as YamlMap;
      expect(on.keys, unorderedEquals(['push', 'workflow_dispatch']));
      final push = on['push'] as YamlMap;
      expect(push.keys, ['paths']);
      expect(push['paths'], [
        'functions/**',
        'app/firebase.json',
        '.github/workflows/functions.yml',
        'packages/ink_recognition/**',
      ]);
      expect(
        (functions['concurrency'] as YamlMap)['group'],
        r'functions-${{ github.ref }}',
      );
    });

    test('ubuntu, 15 minutes, no job-level if, no secrets', () {
      expect(job['runs-on'], 'ubuntu-latest');
      expect(job['timeout-minutes'], 15);
      // hashFiles cannot be used in a job-level `if:` — every step has it.
      expect(job.containsKey('if'), isFalse);
      expect(
        File(p.join(_workflowsDir, 'functions.yml')).readAsStringSync(),
        isNot(contains('secrets.')),
      );
    });

    test('every step after the checkout is guarded by hashFiles', () {
      expect(steps.first['uses'], 'actions/checkout@v7');
      expect(steps.first.containsKey('if'), isFalse);
      const present = "hashFiles('functions/package.json') != ''";
      const absent = "hashFiles('functions/package.json') == ''";
      for (final s in steps.skip(1)) {
        expect(s['if'], isIn([present, absent]), reason: '${s['name']}');
      }
      final skipped = _named(steps, 'Skipped (no functions/)');
      expect(skipped['if'], absent);
      expect('${skipped['run']}', contains('functions/ 없음 — 건너뜀'));
      expect(
        [
          for (final s in steps.skip(1))
            if (s['if'] == present) s['name'],
        ],
        ['Set up Node', 'Install', 'Unit tests'],
      );
    });

    test('Node 22 with the npm cache of functions/package-lock.json; npm ci '
        'only', () {
      final node = _with(_usesSteps(functions, 'actions/setup-node').single);
      expect('${node['node-version']}', '22');
      expect(node['cache'], 'npm');
      expect(node['cache-dependency-path'], 'functions/package-lock.json');
      final install = _named(steps, 'Install');
      expect(install['working-directory'], 'functions');
      expect(_runLines(install), ['npm ci']);
      for (final s in steps) {
        expect('${s['run'] ?? ''}', isNot(contains('npm install')));
      }
    });

    test('npm test must run at least one test (contract 7.4.7)', () {
      final unit = _named(steps, 'Unit tests');
      expect(unit['working-directory'], 'functions');
      final run = '${unit['run']}';
      expect(run, contains('set -o pipefail'));
      expect(run, contains('npm test'));
      final scratch = Directory.systemTemp.createTempSync('ws_fn_');
      addTearDown(() => scratch.deleteSync(recursive: true));
      // A fake npm that prints [output] and exits with [exitCode].
      final printed = File(p.join(scratch.path, 'printed'));
      final npm = File(p.join(scratch.path, 'bin', 'npm'))
        ..createSync(recursive: true);
      Process.runSync('chmod', ['+x', npm.path]);
      int runWith(List<String> output, {int exitCode = 0}) {
        printed.writeAsStringSync('${output.join('\n')}\n');
        npm.writeAsStringSync(
          '#!/bin/sh\ncat "${printed.path}"\nexit $exitCode\n',
        );
        final summary = File(p.join(scratch.path, 'summary'))
          ..writeAsStringSync('');
        return Process.runSync(
          'bash',
          ['-e', '-c', run],
          environment: {
            'PATH': '${p.dirname(npm.path)}:/usr/bin:/bin',
            'RUNNER_TEMP': scratch.path,
            'GITHUB_STEP_SUMMARY': summary.path,
          },
        ).exitCode;
      }

      expect(runWith(['TAP version 13', '# tests 3', '# pass 3']), 0);
      expect(runWith(['ℹ tests 2', 'ℹ pass 2']), 0);
      expect(runWith(['# tests 0', '# pass 0']), isNot(0));
      expect(runWith(['no counter']), isNot(0));
      expect(runWith(['# tests 3'], exitCode: 1), isNot(0));
    });

    test('the emulator steps are J16 (not in the skeleton)', () {
      final text = File(p.join(_workflowsDir, 'functions.yml'))
          .readAsStringSync();
      expect(text, isNot(contains('emulators:exec')));
      expect(text, contains('J16'));
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

  group('ios-compile.yml (2차 J3, m5-7/01-infra 6.11.5)', () {
    late YamlMap compile;
    late YamlMap job;
    late List<YamlMap> steps;

    setUp(() {
      compile = _workflow('ios-compile.yml');
      job = _jobs(compile).values.single;
      steps = _steps(job);
    });

    test(
      'manual only: the macOS cost confirmation and the xcarchive switch',
      () {
        final on = compile['on'] as YamlMap;
        expect(on.keys, ['workflow_dispatch']);
        final inputs =
            (on['workflow_dispatch'] as YamlMap)['inputs'] as YamlMap;
        expect(inputs.keys, ['confirm', 'ipa']);
        final confirm = inputs['confirm'] as YamlMap;
        expect(confirm['type'], 'string');
        expect(confirm['required'], isTrue);
        expect(confirm['description'], 'macOS 10배 과금 확인: yes 입력');
        final ipa = inputs['ipa'] as YamlMap;
        expect(ipa['type'], 'boolean');
        expect(ipa['default'], isFalse);
      },
    );

    test('gate on the input only, macos-26, 45 minutes, one run at a time '
        '(not cancelled)', () {
      expect(job['if'], "inputs.confirm == 'yes'");
      expect(job['runs-on'], 'macos-26');
      expect(job['timeout-minutes'], 45);
      expect((compile['concurrency'] as YamlMap).value, {
        'group': 'ios-compile',
        'cancel-in-progress': false,
      });
    });

    test('no secret, no variable, no signing', () {
      final text = File(p.join(_workflowsDir, 'ios-compile.yml'))
          .readAsStringSync();
      expect(text, isNot(contains('secrets.')));
      expect(text, isNot(contains('vars.')));
      expect(job.containsKey('env'), isFalse);
      for (final step in steps) {
        for (final line in _commands(step)) {
          if (line.startsWith('flutter build ')) {
            expect(line, contains(' --no-codesign '));
          }
        }
      }
    });

    test('the 6.11.5 steps in order', () {
      expect(
        [for (final s in steps) s['name']],
        [
          'Checkout',
          'Set up Flutter',
          'Cache CocoaPods',
          'Cache build hooks',
          'Dependencies',
          'Build info',
          'Build iOS (no signing)',
          'Build xcarchive (no signing)',
          'Summary',
          'Upload Podfile.lock and build log',
          'Upload xcarchive',
        ],
      );
      expect(
        _commands(_named(steps, 'Build info')).single,
        '$_ws build-info --channel experiment --out build/build_info.json',
      );
      final pods = _with(_named(steps, 'Cache CocoaPods'));
      expect('${pods['path']}'.trim().split('\n'), [
        '~/Library/Caches/CocoaPods',
        'app/ios/Pods',
      ]);
      expect(
        pods['key'],
        r"pods-${{ hashFiles('pubspec.lock', 'app/ios/Podfile') }}",
      );
    });

    test('the build pipes through tee with pipefail, the xcarchive only on '
        'request', () {
      final build = _named(steps, 'Build iOS (no signing)');
      expect(build['id'], 'build');
      expect(build['working-directory'], 'app');
      final lines = _runLines(build);
      expect(lines.first, 'set -o pipefail');
      expect(
        _commands(build).single,
        'flutter build ios --release --no-codesign $_buildNumber '
        '$_defineFile 2>&1 | tee "\$RUNNER_TEMP/ios-build.log"',
      );
      expect(lines.last, contains(r'seconds='));
      expect(lines.last, endsWith(r'>> "$GITHUB_OUTPUT"'));
      final ipa = _named(steps, 'Build xcarchive (no signing)');
      expect(ipa['if'], 'inputs.ipa');
      expect(_runLines(ipa).first, 'set -o pipefail');
      expect(
        _commands(ipa).single,
        startsWith('flutter build ipa --release --no-codesign '),
      );
      expect(
        _commands(ipa).single,
        endsWith('| tee -a "\$RUNNER_TEMP/ios-build.log"'),
      );
      expect(_named(steps, 'Upload xcarchive')['if'], 'inputs.ipa');
    });

    test('artifacts: Podfile.lock and the build log always, 7 days', () {
      final upload = _named(steps, 'Upload Podfile.lock and build log');
      expect(upload['if'], 'always()');
      final withMap = _with(upload);
      expect(withMap['name'], r'ios-compile-${{ github.run_number }}');
      expect('${withMap['path']}'.trim().split('\n'), [
        'app/ios/Podfile.lock',
        r'${{ runner.temp }}/ios-build.log',
      ]);
      expect(withMap['retention-days'], 7);
      final archive = _with(_named(steps, 'Upload xcarchive'));
      expect(archive['path'], r'${{ runner.temp }}/Runner.xcarchive.zip');
      expect(archive['retention-days'], 7);
      expect(archive['if-no-files-found'], 'error');
    });

    test('the summary script on a sample log and Podfile.lock', () {
      final dir = Directory.systemTemp.createTempSync('ios_compile_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File(p.join(dir.path, 'runner', 'ios-build.log'))
        ..createSync(recursive: true)
        ..writeAsStringSync('''
Running pod install...
Warning: The following plugins do not support Swift Package Manager for ios:
  - google_mlkit_commons
  - google_mlkit_digital_ink_recognition
This will become an error in a future version of Flutter. Please contact the plugin maintainers to request Swift Package Manager adoption.
Building com.example for device (ios-release)...
''');
      File(p.join(dir.path, 'app', 'ios', 'Podfile.lock'))
        ..createSync(recursive: true)
        ..writeAsStringSync('''
PODS:
  - Flutter (1.0.0)
  - google_mlkit_commons (0.13.0):
    - Flutter
    - MLKitVision
  - MLKitCommon (14.0.0):
    - GoogleUtilities/Logger (~> 8.0)

DEPENDENCIES:
  - Flutter (from `Flutter`)

SPEC CHECKSUMS:
  Flutter: abc
''');
      final summary = File(p.join(dir.path, 'summary'))..writeAsStringSync('');
      final result = Process.runSync(
        'bash',
        ['-eo', 'pipefail', '-c', '${_named(steps, 'Summary')['run']}'],
        workingDirectory: dir.path,
        environment: {
          'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
          'RUNNER_TEMP': p.join(dir.path, 'runner'),
          'GITHUB_STEP_SUMMARY': summary.path,
          'BUILD_SECONDS': '612',
        },
        includeParentEnvironment: false,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(summary.readAsLinesSync(), [
        '## iOS compile',
        '- build: 612 s',
        '- CocoaPods-only warnings: 1 (google_mlkit_commons google_mlkit_digital_ink_recognition)',
        '- pods in Podfile.lock: 3',
      ]);
      // A failed build leaves no log, no Podfile.lock and no time.
      File(p.join(dir.path, 'runner', 'ios-build.log')).deleteSync();
      File(p.join(dir.path, 'app', 'ios', 'Podfile.lock')).deleteSync();
      summary.writeAsStringSync('');
      final empty = Process.runSync(
        'bash',
        ['-eo', 'pipefail', '-c', '${_named(steps, 'Summary')['run']}'],
        workingDirectory: dir.path,
        environment: {
          'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
          'RUNNER_TEMP': p.join(dir.path, 'runner'),
          'GITHUB_STEP_SUMMARY': summary.path,
        },
        includeParentEnvironment: false,
      );
      expect(empty.exitCode, 0, reason: '${empty.stderr}');
      expect(summary.readAsLinesSync(), [
        '## iOS compile',
        '- build: ? s',
        '- CocoaPods-only warnings: 0 (none)',
        '- pods in Podfile.lock: 0',
      ]);
    });
  });

  group('ios-testflight.yml (draft)', () {
    late YamlMap ios;
    late YamlMap job;
    late List<YamlMap> steps;

    setUp(() {
      ios = _workflow('ios-testflight.yml');
      job = _jobs(ios).values.single;
      steps = _steps(job);
    });

    test('manual only, with the macOS cost confirmation input', () {
      final on = ios['on'] as YamlMap;
      expect(on.keys, ['workflow_dispatch']);
      final inputs = (on['workflow_dispatch'] as YamlMap)['inputs'] as YamlMap;
      final confirm = inputs['confirm'] as YamlMap;
      expect(confirm['required'], isTrue);
      expect(confirm['description'], contains('yes'));
    });

    test('the job is gated on the repository variable and the input; '
        'macos-26 (6.11.6)', () {
      expect(
        job['if'],
        "vars.IOS_TESTFLIGHT_ENABLED == 'true' && inputs.confirm == 'yes'",
      );
      expect(job['runs-on'], 'macos-26');
      expect(job['timeout-minutes'], 45);
      expect((job['env'] as YamlMap).value, {
        for (final name in [
          'APPLE_TEAM_ID',
          'ASC_KEY_ID',
          'ASC_ISSUER_ID',
          'ASC_PRIVATE_KEY',
        ])
          name: '\${{ secrets.$name }}',
        'IOS_SIGNING_MODE': r"${{ vars.IOS_SIGNING_MODE || 'cloud' }}",
      });
    });

    test('build without signing, archive, export with ExportOptions', () {
      final runs = [for (final s in steps) ..._runLines(s)].join('\n');
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

    test('manual signing: its secrets only in its own step, which runs only '
        'when IOS_SIGNING_MODE is manual', () {
      final manual = _named(steps, 'Certificate and profile (manual signing)');
      expect(manual['if'], "env.IOS_SIGNING_MODE == 'manual'");
      expect((manual['env'] as YamlMap).value, {
        for (final name in [
          'IOS_DIST_P12_BASE64',
          'IOS_DIST_P12_PASSWORD',
          'IOS_PROFILE_BASE64',
        ])
          name: '\${{ secrets.$name }}',
      });
      for (final step in steps) {
        if (identical(step, manual)) continue;
        expect('${step['env'] ?? ''}', isNot(contains('IOS_DIST')));
      }
      final run = _runLines(manual).join('\n');
      expect(run, contains('security create-keychain'));
      expect(run, contains('security import "\$RUNNER_TEMP/dist.p12"'));
      expect(
        run,
        contains(
          r'cp "$RUNNER_TEMP/profile.mobileprovision" "$profiles/$uuid.mobileprovision"',
        ),
      );
      for (final name in [
        'IOS_KEYCHAIN',
        'IOS_PROFILE_NAME',
        'IOS_BUNDLE_ID',
      ]) {
        expect(run, contains('echo "$name='));
      }
      final clean = _named(steps, 'Remove signing material');
      expect(clean['if'], 'always()');
      expect(identical(steps.last, clean), isTrue);
      final cleanRun = _runLines(clean).join('\n');
      expect(cleanRun, contains(r'"$RUNNER_TEMP"/AuthKey_*.p8'));
      expect(cleanRun, contains(r'"$RUNNER_TEMP/dist.p12"'));
      expect(cleanRun, contains(r'security delete-keychain "$IOS_KEYCHAIN"'));
    });

    test('the two signing ways: the archive script run with a fake '
        'xcodebuild', () {
      final dir = Directory.systemTemp.createTempSync('ios_archive_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final bin = Directory(p.join(dir.path, 'bin'))..createSync();
      final args = File(p.join(dir.path, 'args'));
      final xcodebuild = File(p.join(bin.path, 'xcodebuild'))
        ..writeAsStringSync(
          '#!/usr/bin/env bash\nprintf \'%s\\n\' "\$@" > "${args.path}"\n',
        );
      Process.runSync('chmod', ['+x', xcodebuild.path]);
      List<String> archive(String mode) {
        final result = Process.runSync(
          'bash',
          ['-eo', 'pipefail', '-c', '${_named(steps, 'Archive')['run']}'],
          workingDirectory: dir.path,
          environment: {
            'PATH':
                '${bin.path}:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}',
            'RUNNER_TEMP': '/tmp/runner',
            'IOS_SIGNING_MODE': mode,
            'APPLE_TEAM_ID': 'TEAM123',
            'ASC_KEY_PATH': '/tmp/runner/AuthKey_K.p8',
            'ASC_KEY_ID': 'K',
            'ASC_ISSUER_ID': 'I',
            'IOS_PROFILE_NAME': 'noteapp App Store',
          },
          includeParentEnvironment: false,
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        return args.readAsLinesSync();
      }

      const common = [
        'archive',
        '-workspace',
        'Runner.xcworkspace',
        '-scheme',
        'Runner',
        '-configuration',
        'Release',
        '-archivePath',
        '/tmp/runner/Runner.xcarchive',
        'DEVELOPMENT_TEAM=TEAM123',
      ];
      expect(archive('cloud'), [
        ...common,
        '-allowProvisioningUpdates',
        '-authenticationKeyPath',
        '/tmp/runner/AuthKey_K.p8',
        '-authenticationKeyID',
        'K',
        '-authenticationKeyIssuerID',
        'I',
        'CODE_SIGN_STYLE=Automatic',
      ]);
      expect(archive('manual'), [
        ...common,
        'CODE_SIGN_STYLE=Manual',
        'CODE_SIGN_IDENTITY=Apple Distribution',
        'PROVISIONING_PROFILE_SPECIFIER=noteapp App Store',
      ]);
      // The export names the certificate and the profile only when manual.
      final export = '${_named(steps, 'Export and upload')['run']}';
      expect(export, contains('if [ "\$IOS_SIGNING_MODE" = manual ]; then'));
      expect(export, contains('plutil -replace signingStyle -string manual'));
      expect(
        export,
        contains(
          r'Add :provisioningProfiles:$IOS_BUNDLE_ID string $IOS_PROFILE_NAME',
        ),
      );
    });

    test('the cloud signing comment warns about the Admin key', () {
      final text = File(p.join(_workflowsDir, 'ios-testflight.yml'))
          .readAsStringSync();
      expect(text, contains('cloud signing may need an Admin'));
      expect(text, contains('Run ios-compile.yml first'));
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
      expect(
        export,
        matches(RegExp(r'<key>signingStyle</key>\s*<string>automatic<')),
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

/// FLUTTER_ROOT, or the SDK of `flutter` on PATH (null when not found).
String? _flutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return env;
  for (final dir in (Platform.environment['PATH'] ?? '').split(':')) {
    final flutter = File(p.join(dir, 'flutter'));
    if (flutter.existsSync()) {
      return p.dirname(p.dirname(flutter.resolveSymbolicLinksSync()));
    }
  }
  return null;
}
