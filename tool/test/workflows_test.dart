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
// shell steps run with fake tools; 2차 J21 (6.10.5): android-emulator.yml
// (the emulator, the debug APK with granted permissions, the KVM step with a
// fake sudo, the native smoke it runs); 2차 J15 (6.16): ci.yml in five jobs
// (check → vm, chrome, heavy → web), the test scope handed on as the check
// job's outputs, heavy only on a full-run push or the manual `integration`
// input, each job's timing table. Every `ws` call in a workflow is parsed by
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
  // 2차 J21 (m5-7/01-infra 7.3, P-C): android-emulator.yml.
  'reactivecircus/android-emulator-runner': 'v2',
};

/// `paths-ignore` of every push trigger (6.13).
const _ignoredPaths = ['docs/**', '**/*.md', '.github/ISSUE_TEMPLATE/**'];

/// Job time limits (6.13).
const _timeouts = {
  'android-emulator.yml': 45,
  'android.yml': 30,
  'functions.yml': 15,
  'ios-compile.yml': 45,
  'ios-testflight.yml': 45,
  'web-experiment.yml': 25,
};

/// ci.yml job time limits (2차 J15, m5-7/01-infra 6.16 — the plan's
/// provisional values; J0 ④ sets the measured time × 1.5).
const _ciTimeouts = {
  'check': 15,
  'vm': 30,
  'chrome': 30,
  'heavy': 30,
  'web': 15,
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

/// android-emulator.yml (2차 J21, m5-7/01-infra 6.10.5).
const _emulatorApkBuild = 'flutter build apk --debug';
const _emulatorApk = 'build/app/outputs/flutter-apk/app-debug.apk';
const _nativeSmoke = 'integration_test/native_smoke_test.dart';
const _emulatorReleaseBuild =
    'flutter build apk --release --target-platform android-x64 '
    '$_buildNumber $_defineFile';
const _emulatorReleaseApk = 'build/app/outputs/flutter-apk/app-release.apk';
const _launchCheck = '../tool/android/release_launch_check.sh';
const _kvmRule =
    'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"';

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
  'LOCK_BASE': 'origin/$_devBranch',
};

/// Evaluates the `||` / `&&` / `==` / `!=` expressions of [expression]
/// (`${{ … }}` or a bare `if:`) against [context] (`github.ref`, …, `env.X`,
/// `needs.check.outputs.x`, `inputs.x` — an input missing on a push is ''):
/// enough for the conditions of ci.yml, not the whole GitHub grammar. A
/// parenthesized `&&` group between `||` is read as one alternative (the
/// grammar's precedence); `true` / `false` are the literals.
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
    if (o == 'true' || o == 'false') return o;
    expect(context, contains(o), reason: 'no sample for `$o`');
    return context[o]!;
  }

  String group(String alternative) {
    final a = alternative.trim();
    if (a.startsWith('(') && a.endsWith(')')) {
      final inner = a.substring(1, a.length - 1);
      expect(inner, isNot(contains('(')), reason: 'nested in `$expression`');
      return inner;
    }
    expect(a, isNot(contains('(')), reason: 'unsupported `$a`');
    return a;
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

  return text
      .split('||')
      .any((any) => group(any).split('&&').every(comparison));
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
    // ci.yml heavy (2차 J15): a parenthesized group and the literal `true`.
    const heavy =
        "(github.event_name == 'push' && needs.c.outputs.f == 'true') || "
        'inputs.i == true';
    for (final (event, full, input, expected) in [
      ('push', 'true', '', true),
      ('push', 'false', '', false),
      ('workflow_dispatch', 'true', 'false', false),
      ('workflow_dispatch', 'false', 'true', true),
    ]) {
      expect(
        _evaluate(heavy, {
          'github.event_name': event,
          'needs.c.outputs.f': full,
          'inputs.i': input,
        }),
        expected,
        reason: '$event $full $input',
      );
    }
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
    test('the four workflows of 6.13, functions.yml, ios-compile.yml and '
        'android-emulator.yml (2차) exist and parse', () {
      expect(_workflowNames(), [
        'android-emulator.yml',
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
            name == 'ci.yml' ? _ciTimeouts[key] : _timeouts[name],
            reason: '$name: job $key',
          );
          // The one exception: android.yml publishes the APK as a release
          // (artifacts hit the storage quota — Android APK run 6).
          if (name == 'android.yml' && key == 'apk') {
            expect((value['permissions'] as YamlMap).value, {
              'contents': 'write',
            }, reason: '$name: job $key');
            continue;
          }
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
      // ci.yml: one per job (2차 J15 — five jobs).
      expect(count, 11);
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
      // ci.yml: one per job (2차 J15 — five jobs).
      expect(count, 11);
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

    test('job outputs name a step of their job; `needs.<job>.outputs.<name>` '
        'an output of a job in `needs`', () {
      final stepOutput = RegExp(r'steps\.([A-Za-z0-9_-]+)\.outputs\.');
      final needsOutput = RegExp(
        r'needs\.([A-Za-z0-9_-]+)\.outputs\.([A-Za-z0-9_]+)',
      );
      var outputs = 0;
      var reads = 0;
      for (final name in _workflowNames()) {
        final jobs = _jobs(_workflow(name));
        for (final MapEntry(key: id, value: job) in jobs.entries) {
          final stepIds = {
            for (final s in _steps(job))
              if (s['id'] case final String stepId) stepId,
          };
          for (final value in (job['outputs'] as YamlMap?)?.values ?? []) {
            outputs++;
            final match = stepOutput.firstMatch('$value');
            expect(match, isNotNull, reason: '$name: $id outputs $value');
            expect(stepIds, contains(match!.group(1)), reason: '$name: $id');
          }
          final needs = switch (job['needs']) {
            null => <String>[],
            final String one => [one],
            final YamlList many => [for (final n in many) '$n'],
            final other => fail('$name: $id needs $other'),
          };
          for (final need in needs) {
            expect(jobs, contains(need), reason: '$name: $id');
          }
          for (final match in needsOutput.allMatches('${job.value}')) {
            reads++;
            expect(needs, contains(match.group(1)), reason: '$name: $id');
            final defined = jobs[match.group(1)]!['outputs'] as YamlMap?;
            expect(
              defined?.keys,
              contains(match.group(2)),
              reason: '$name: $id reads ${match.group(0)}',
            );
          }
        }
      }
      // ci.yml (2차 J15): check's three outputs, read by vm, chrome, heavy
      // and web.
      expect(outputs, 3);
      expect(reads, 6);
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
      // ci.yml (2차 J15): one in each job that builds members — not in check.
      const counts = {
        'android-emulator.yml': 1,
        'android.yml': 1,
        'ci.yml': 4,
        'functions.yml': 1,
        'ios-compile.yml': 1,
        'web-experiment.yml': 1,
      };
      for (final MapEntry(key: name, value: count) in counts.entries) {
        final hooks = _usesSteps(
          _workflow(name),
          'actions/cache',
        ).where((s) => _with(s)['path'] == _hooksPath).toList();
        expect(hooks, hasLength(count), reason: name);
        for (final cache in hooks) {
          expect(_with(cache)['key'], _hooksKey, reason: name);
          expect(_with(cache)['restore-keys'], _hooksRestoreKey, reason: name);
        }
      }
      for (final job in _jobs(_workflow('ci.yml')).values) {
        expect([
          for (final s in _steps(job))
            if (_with(s)['path'] == _hooksPath) s,
        ], hasLength(lessThanOrEqualTo(1)));
      }
    });

    test('every flutter build passes the build info and run number (the '
        'emulator debug APK aside)', () {
      var count = 0;
      var debug = 0;
      for (final name in _workflowNames()) {
        for (final step in _allSteps(_workflow(name))) {
          for (final line in _commands(step)) {
            if (!line.startsWith('flutter build ')) continue;
            if (line.contains(' --debug')) {
              // android-emulator.yml (J21): the debug APK installed with
              // `adb install -g` before flutter test (no build info).
              debug++;
              expect(name, 'android-emulator.yml');
              expect(line, _emulatorApkBuild);
              expect(step['working-directory'], 'app');
              continue;
            }
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
      expect(count, 8);
      expect(debug, 1);
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
      // + web-budget check (J17), + lock-age (J20), + the Dart emulator tests
      // of functions.yml (J16), + native-reqs and the media tests of ci.yml
      // (J15)
      expect(calls, hasLength(26));
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
      expect(count, 6);
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

  // 2차 J15 (m5-7/01-infra 6.16): five jobs — check, then vm, chrome and
  // heavy beside each other, then web after vm and chrome.
  group('ci.yml', () {
    late YamlMap ci;
    late Map<String, YamlMap> jobs;

    setUp(() {
      ci = _workflow('ci.yml');
      jobs = _jobs(ci);
    });

    List<YamlMap> stepsOf(String job) => _steps(jobs[job]!);
    YamlMap step(String job, String name) => _named(stepsOf(job), name);
    List<String> namesOf(String job) => [
      for (final s in stepsOf(job)) '${s['name']}',
    ];
    Map<String, String> envOf(String job) => {
      for (final MapEntry(:key, :value)
          in ((jobs[job]!['env'] as YamlMap?) ?? YamlMap()).entries)
        '$key': '$value',
    };

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
      // change untested. One group for the whole workflow (all five jobs).
      expect(
        concurrency['group'],
        r'ci-${{ github.ref }}'
        r"${{ github.event_name == 'push' && "
        r"github.ref != 'refs/heads/main' && "
        r'github.ref_name == github.event.repository.default_branch && '
        r"format('-{0}', github.run_id) || '' }}",
      );
      expect(concurrency['cancel-in-progress'], isTrue);
      for (final job in jobs.values) {
        expect(job.containsKey('concurrency'), isFalse);
      }
    });

    test('five jobs on ubuntu with their limits: check first, vm / chrome / '
        'heavy after it, web after vm and chrome (not heavy)', () {
      expect(jobs.keys, ['check', 'vm', 'chrome', 'heavy', 'web']);
      expect(
        {for (final e in jobs.entries) e.key: '${e.value['name']}'},
        {
          'check': 'Check and analyze',
          'vm': 'VM tests',
          'chrome': 'Browser tests',
          'heavy': 'Integration and media tests',
          'web': 'Build and deploy web',
        },
      );
      for (final MapEntry(:key, :value) in jobs.entries) {
        expect(value['runs-on'], 'ubuntu-latest', reason: key);
        // The plan's provisional values (6.16 — the single job's 60 minutes
        // is not used for the split jobs); J0 ④ sets measured × 1.5.
        expect(value['timeout-minutes'], _ciTimeouts[key], reason: key);
      }
      expect(jobs['check']!.containsKey('needs'), isFalse);
      for (final name in ['vm', 'chrome', 'heavy']) {
        expect(jobs[name]!['needs'], 'check', reason: name);
      }
      // check for its outputs; a failed vm or chrome job never deploys; the
      // heavy job does not hold the deploy up.
      expect((jobs['web']!['needs'] as YamlList).toList(), [
        'check',
        'vm',
        'chrome',
      ]);
      expect(ci.containsKey('env'), isFalse, reason: 'no workflow env');
      for (final name in ['check', 'vm', 'chrome', 'web']) {
        expect(jobs[name]!.containsKey('if'), isFalse, reason: name);
      }
    });

    test('job env: the scope inputs in check, its outputs in vm / chrome / '
        'web, the deploy secret and variable in web only', () {
      expect(envOf('check'), {
        'DEFAULT_BRANCH': _defaultBranchValue,
        'BEFORE_SHA': r'${{ github.event.before }}',
        'FULL_INPUT': r'${{ inputs.full }}',
      });
      for (final name in ['vm', 'chrome']) {
        expect(envOf(name), {
          'FULL_RUN': r'${{ needs.check.outputs.full_run }}',
          'AFFECTED_BASE': r'${{ needs.check.outputs.affected_base }}',
        }, reason: name);
      }
      // A job-level `if:` cannot read `env`: heavy reads the output there.
      expect(jobs['heavy']!.containsKey('env'), isFalse);
      expect(envOf('web'), {
        'FIREBASE_SA': r'${{ secrets.FIREBASE_SERVICE_ACCOUNT }}',
        'FIREBASE_PROJECT_ID': r'${{ vars.FIREBASE_PROJECT_ID }}',
        'TEST_SCOPE': r'${{ needs.check.outputs.test_scope }}',
      });
      for (final name in ['check', 'vm', 'chrome', 'heavy']) {
        expect(
          '${jobs[name]!.value}',
          isNot(contains('secrets.')),
          reason: name,
        );
      }
    });

    test('the check outputs come from the Test scope step', () {
      expect(step('check', 'Test scope')['id'], 'scope');
      expect((jobs['check']!['outputs'] as YamlMap).value, {
        'full_run': r'${{ steps.scope.outputs.full_run }}',
        'affected_base': r'${{ steps.scope.outputs.affected_base }}',
        'test_scope': r'${{ steps.scope.outputs.test_scope }}',
      });
      for (final name in ['vm', 'chrome', 'heavy', 'web']) {
        expect(jobs[name]!.containsKey('outputs'), isFalse, reason: name);
      }
    });

    test('the steps of each job in order', () {
      const setup = ['Start clock', 'Checkout', 'Set up Flutter'];
      expect(namesOf('check'), [
        'Start clock',
        'Test scope', // 2차 R2-B1
        'Checkout',
        'Set up Flutter',
        'Dependencies',
        'Lock age', // 2차 J20
        'Workspace rules (strict)',
        'Workspace rules',
        'Analyze',
        'Tool tests', // contract 7.6 B1 v1.3, V3
        'Native requirements', // 2차 J1 / J15
        'Timing',
      ]);
      expect(namesOf('vm'), [
        ...setup,
        'Cache build hooks',
        'Dependencies',
        'VM tests (all members)',
        'VM tests (affected)',
        'Timing',
      ]);
      expect(namesOf('chrome'), [
        ...setup,
        'Cache build hooks',
        'Cache browser test assets',
        'Dependencies',
        'Browser tests (all members)',
        'Browser tests (affected)',
        'Timing',
      ]);
      expect(namesOf('heavy'), [
        ...setup,
        'Cache build hooks',
        'Cache browser test assets',
        'Dependencies',
        'Integration tests (VM)',
        'Integration tests (Chrome)',
        'Media tests (Chrome fake mic)', // 2차 6.13
        'Timing',
      ]);
      expect(namesOf('web'), [
        ...setup,
        'Cache build hooks',
        'Dependencies',
        'Channel',
        'Build info',
        'Verify web assets',
        'Web build',
        'Finalize web build',
        'Web budget', // 2차 J17 — right after Finalize, before the deploy
        'Deploy to Firebase Hosting',
        'Summary',
      ]);
    });

    test('commands of each step', () {
      final expected = {
        ('check', 'Lock age'): ['$_ws lock-age --since "\$LOCK_BASE"'],
        ('check', 'Workspace rules (strict)'): ['$_ws check --strict'],
        ('check', 'Workspace rules'): ['$_ws check'],
        ('check', 'Analyze'): ['$_ws analyze'],
        ('check', 'Tool tests'): ['dart test tool/test'],
        ('check', 'Native requirements'): ['$_ws native-reqs'],
        ('vm', 'VM tests (all members)'): ['$_ws test'],
        ('vm', 'VM tests (affected)'): ['$_ws test $_affected'],
        ('chrome', 'Browser tests (all members)'): [
          '$_ws test --platform chrome',
        ],
        ('chrome', 'Browser tests (affected)'): [
          '$_ws test --platform chrome $_affected',
        ],
        ('heavy', 'Integration tests (VM)'): [
          '$_ws test --run-skipped -t integration',
        ],
        ('heavy', 'Integration tests (Chrome)'): [
          '$_ws test --platform chrome --run-skipped -t integration',
        ],
        ('heavy', 'Media tests (Chrome fake mic)'): [
          '$_ws test --platform chrome --run-skipped -t media',
        ],
        ('web', 'Build info'): [_buildInfoFromEnv],
        ('web', 'Verify web assets'): ['$_ws web-assets verify'],
        ('web', 'Web build'): [_webBuild],
        ('web', 'Finalize web build'): [_finalize],
        ('web', 'Web budget'): [
          '$_ws web-budget check --build-dir app/build/web',
        ],
      };
      for (final MapEntry(key: (job, name), :value) in expected.entries) {
        expect(_commands(step(job, name)), value, reason: '$job / $name');
      }
      for (final job in jobs.keys) {
        expect(_commands(step(job, 'Dependencies')), [
          'flutter pub get --enforce-lockfile',
        ], reason: job);
      }
      expect(step('web', 'Web build')['working-directory'], 'app');
    });

    test('the setup steps are the same in every job; full history where '
        '--affected-since or the lock diff needs it', () {
      String text(YamlMap s) => '${s.value}';
      for (final name in ['Start clock', 'Set up Flutter', 'Dependencies']) {
        final forms = {for (final job in jobs.keys) text(step(job, name))};
        expect(forms, hasLength(1), reason: name);
      }
      for (final job in jobs.keys) {
        expect(stepsOf(job).first['name'], 'Start clock', reason: job);
        final checkout = step(job, 'Checkout');
        expect(checkout['uses'], 'actions/checkout@v7', reason: job);
        final depth = _with(checkout)['fetch-depth'];
        // heavy runs every member, web reads GITHUB_SHA for build-info.
        expect(
          depth,
          ['check', 'vm', 'chrome'].contains(job) ? 0 : isNull,
          reason: job,
        );
      }
    });

    test('caches: build hooks in every job that builds members, browser '
        'assets for the Chrome jobs, both before Dependencies', () {
      bool hasCache(String job, String name) =>
          namesOf(job).contains(name) &&
          step(job, name)['uses'] == 'actions/cache@v6';
      expect(
        [
          for (final job in jobs.keys)
            if (hasCache(job, 'Cache build hooks')) job,
        ],
        ['vm', 'chrome', 'heavy', 'web'],
      );
      expect(
        [
          for (final job in jobs.keys)
            if (hasCache(job, 'Cache browser test assets')) job,
        ],
        ['chrome', 'heavy'],
      );
      expect(_usesSteps(ci, 'actions/cache'), hasLength(6));
      for (final cache in _usesSteps(ci, 'actions/cache')) {
        expect('${_with(cache)['key']}', contains("hashFiles('pubspec.lock'"));
      }
      for (final job in ['vm', 'chrome', 'heavy', 'web']) {
        final hooks = _with(step(job, 'Cache build hooks'));
        expect(hooks['path'], _hooksPath, reason: job);
        expect(hooks['key'], _hooksKey, reason: job);
        expect(
          namesOf(job).indexOf('Cache build hooks'),
          lessThan(namesOf(job).indexOf('Dependencies')),
          reason: job,
        );
      }
      for (final job in ['chrome', 'heavy']) {
        final prep = _with(step(job, 'Cache browser test assets'));
        expect(prep['key'], _prepKey, reason: job);
        expect(
          '${prep['path']}'.trim().split('\n').map((l) => l.trim()),
          _prepPaths,
          reason: job,
        );
        // Restored before the first build hook runs.
        expect(
          namesOf(job).indexOf('Cache browser test assets'),
          lessThan(namesOf(job).indexOf('Dependencies')),
          reason: job,
        );
      }
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
        'strict check; no other step condition but the deploy and the last '
        'steps', () {
      expect(step('check', 'Workspace rules (strict)')['if'], _strict);
      expect(step('check', 'Workspace rules')['if'], _notStrict);
      for (final (job, name) in [
        ('vm', 'VM tests (all members)'),
        ('chrome', 'Browser tests (all members)'),
      ]) {
        expect(step(job, name)['if'], _fullRun, reason: name);
      }
      for (final (job, name) in [
        ('vm', 'VM tests (affected)'),
        ('chrome', 'Browser tests (affected)'),
      ]) {
        expect(step(job, name)['if'], _notFullRun, reason: name);
      }
      const conditioned = {
        'Workspace rules (strict)',
        'Workspace rules',
        'VM tests (all members)',
        'VM tests (affected)',
        'Browser tests (all members)',
        'Browser tests (affected)',
        'Deploy to Firebase Hosting',
        'Timing',
        'Summary',
      };
      for (final job in jobs.keys) {
        for (final s in stepsOf(job)) {
          expect(
            s.containsKey('if'),
            conditioned.contains(s['name']),
            reason: '$job / ${s['name']}',
          );
        }
      }
    });

    // m5-7/01-infra 4.2 (2차 J20, Q8): a warning step — runs ws lock-age
    // only when pubspec.lock changed since the scope's base; a violation
    // never fails the job. In the check job (J15), right after Dependencies.
    test('lock age: warning step, base = AFFECTED_BASE or the previous push, '
        'only when pubspec.lock changed', () {
      final lockAge = step('check', 'Lock age');
      expect(lockAge['continue-on-error'], isTrue);
      expect(lockAge.containsKey('if'), isFalse);
      expect(
        namesOf('check').indexOf('Lock age'),
        namesOf('check').indexOf('Dependencies') + 1,
      );
      final script = '${lockAge['run']}';
      expect(
        Process.runSync('bash', ['-n', '-c', script]).exitCode,
        0,
        reason: 'bash -n',
      );
      final scratch = Directory.systemTemp.createTempSync('ws_ci_lock_age_');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final bin = Directory(p.join(scratch.path, 'bin'))..createSync();
      final dartLog = p.join(scratch.path, 'dart-args');
      final gitLog = p.join(scratch.path, 'git-args');
      void fake(String name, String body) {
        final file = File(p.join(bin.path, name))
          ..writeAsStringSync('#!/bin/sh\n$body');
        Process.runSync('chmod', ['+x', file.path]);
      }

      fake('dart', 'echo "\$*" > "$dartLog"\n');
      // git diff --quiet: 0 = unchanged, 1 = changed (FAKE_DIFF).
      fake('git', 'echo "\$*" > "$gitLog"\nexit "\${FAKE_DIFF:-0}"\n');
      const before = '1234567890abcdef1234567890abcdef12345678';
      // (AFFECTED_BASE, BEFORE_SHA, diff exit) → (git args, dart args, echo)
      final scenarios = [
        ('', '', '0', null, null, 'no base to compare with'),
        ('', _zeroSha, '0', null, null, 'no base to compare with'),
        (
          '',
          before,
          '0',
          'diff --quiet $before -- pubspec.lock',
          null,
          'unchanged since $before',
        ),
        (
          '',
          before,
          '1',
          'diff --quiet $before -- pubspec.lock',
          'run tool/ws.dart lock-age --since $before',
          null,
        ),
        (
          'origin/$_devBranch',
          before,
          '1',
          'diff --quiet origin/$_devBranch -- pubspec.lock',
          'run tool/ws.dart lock-age --since origin/$_devBranch',
          null,
        ),
        (
          'origin/$_devBranch',
          '',
          '0',
          'diff --quiet origin/$_devBranch -- pubspec.lock',
          null,
          'unchanged since origin/$_devBranch',
        ),
      ];
      for (final (affected, beforeSha, diff, gitArgs, dartArgs, echo)
          in scenarios) {
        for (final log in [dartLog, gitLog]) {
          if (File(log).existsSync()) File(log).deleteSync();
        }
        final result = Process.runSync(
          'bash',
          ['-e', '-c', script],
          environment: {
            'PATH': '${bin.path}:${Platform.environment['PATH']}',
            'AFFECTED_BASE': affected,
            'BEFORE_SHA': beforeSha,
            'FAKE_DIFF': diff,
          },
          includeParentEnvironment: false,
        );
        final what = '($affected, $beforeSha, $diff)';
        expect(result.exitCode, 0, reason: '$what ${result.stderr}');
        String? read(String log) =>
            File(log).existsSync() ? File(log).readAsStringSync().trim() : null;
        expect(read(gitLog), gitArgs, reason: what);
        expect(read(dartLog), dartArgs, reason: what);
        if (echo != null) {
          expect('${result.stdout}', contains(echo), reason: what);
        }
      }
    });

    test('native requirements: the last check step, a violation fails the '
        'job', () {
      final nativeReqs = step('check', 'Native requirements');
      expect(nativeReqs.containsKey('continue-on-error'), isFalse);
      // After the pub get that writes app/.flutter-plugins-dependencies.
      expect(
        namesOf('check').indexOf('Native requirements'),
        namesOf('check').length - 2,
      );
      expect(
        namesOf('check').indexOf('Dependencies'),
        lessThan(namesOf('check').indexOf('Native requirements')),
      );
    });

    // m5-7/01-infra 6.16 (2차 R2-B1, J15): main and manual full runs test
    // every member; the default branch only what changed since its previous
    // push (every member without one); other branches what changed since the
    // default branch. The check job computes the scope once; vm and chrome
    // read it from its outputs, heavy runs on a full-run push or the manual
    // input `integration`, live stays main's.
    test('per push: the test scope through the check outputs into vm, chrome, '
        'heavy and web, and the channel', () {
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
      const fake = 'b-fake-channel';
      // The inputs are '' on a push (no `inputs` there).
      final scenarios = [
        // now: the development branch is the default branch
        (
          event: 'push',
          branch: _devBranch,
          defaultBranch: _devBranch,
          before: before,
          fullInput: '',
          integration: '',
          full: false,
          strict: true,
          base: before,
          channel: fake,
          heavy: false,
        ),
        (
          event: 'push',
          branch: _devBranch,
          defaultBranch: _devBranch,
          before: _zeroSha,
          fullInput: '',
          integration: '',
          full: true,
          strict: true,
          base: '',
          channel: fake,
          heavy: true,
        ), // first push of the branch
        (
          event: 'workflow_dispatch',
          branch: _devBranch,
          defaultBranch: _devBranch,
          before: '',
          fullInput: 'false',
          integration: 'false',
          full: true,
          strict: true,
          base: '',
          channel: fake,
          heavy: false,
        ), // no previous push to compare with; heavy is the input's
        (
          event: 'workflow_dispatch',
          branch: _devBranch,
          defaultBranch: _devBranch,
          before: '',
          fullInput: 'true',
          integration: 'false',
          full: true,
          strict: true,
          base: '',
          channel: fake,
          heavy: false,
        ),
        (
          event: 'workflow_dispatch',
          branch: _devBranch,
          defaultBranch: _devBranch,
          before: '',
          fullInput: 'false',
          integration: 'true',
          full: true,
          strict: true,
          base: '',
          channel: fake,
          heavy: true,
        ),
        // an area branch (even one that changed media_io: heavy reads no
        // paths)
        (
          event: 'push',
          branch: 'area2/infra',
          defaultBranch: _devBranch,
          before: before,
          fullInput: '',
          integration: '',
          full: false,
          strict: false,
          base: 'origin/$_devBranch',
          channel: fake,
          heavy: false,
        ),
        (
          event: 'workflow_dispatch',
          branch: 'area2/infra',
          defaultBranch: _devBranch,
          before: '',
          fullInput: 'false',
          integration: 'false',
          full: false,
          strict: false,
          base: 'origin/$_devBranch',
          channel: fake,
          heavy: false,
        ),
        (
          event: 'workflow_dispatch',
          branch: 'area2/infra',
          defaultBranch: _devBranch,
          before: '',
          fullInput: 'true',
          integration: 'false',
          full: true,
          strict: true,
          base: '',
          channel: fake,
          heavy: false,
        ),
        (
          event: 'workflow_dispatch',
          branch: 'area2/infra',
          defaultBranch: _devBranch,
          before: '',
          fullInput: 'false',
          integration: 'true',
          full: false,
          strict: false,
          base: 'origin/$_devBranch',
          channel: fake,
          heavy: true,
        ),
        // main: always every member, live channel, heavy
        (
          event: 'push',
          branch: 'main',
          defaultBranch: _devBranch,
          before: before,
          fullInput: '',
          integration: '',
          full: true,
          strict: true,
          base: '',
          channel: 'live',
          heavy: true,
        ),
        (
          event: 'push',
          branch: 'main',
          defaultBranch: 'main',
          before: before,
          fullInput: '',
          integration: '',
          full: true,
          strict: true,
          base: '',
          channel: 'live',
          heavy: true,
        ),
        (
          event: 'push',
          branch: 'feature/x',
          defaultBranch: 'main',
          before: before,
          fullInput: '',
          integration: '',
          full: false,
          strict: false,
          base: 'origin/main',
          channel: fake,
          heavy: false,
        ),
      ];
      String resolve(String expression, Map<String, String> context) {
        final match = RegExp(r'^\$\{\{ ([A-Za-z0-9_.]+) \}\}$')
            .firstMatch(expression);
        if (match == null) return expression;
        expect(context, contains(match.group(1)), reason: expression);
        return context[match.group(1)]!;
      }

      Map<String, String> jobEnv(String job, Map<String, String> context) => {
        for (final MapEntry(:key, :value) in envOf(job).entries)
          'env.$key': resolve(value, context),
      };

      for (final s in scenarios) {
        final reason =
            '${s.event} ${s.branch} (default ${s.defaultBranch}, before '
            '${s.before.isEmpty ? '-' : s.before.substring(0, 4)}, '
            'full=${s.fullInput}, integration=${s.integration})';
        // The Test scope script itself.
        final githubEnv = File(p.join(scratch.path, 'github-env'))
          ..writeAsStringSync('');
        final githubOutput = File(p.join(scratch.path, 'github-output'))
          ..writeAsStringSync('');
        final scope = Process.runSync(
          'bash',
          ['-e', '-c', '${step('check', 'Test scope')['run']}'],
          environment: {
            'PATH': '/usr/bin:/bin',
            'GITHUB_REF': 'refs/heads/${s.branch}',
            'GITHUB_REF_NAME': s.branch,
            'GITHUB_ENV': githubEnv.path,
            'GITHUB_OUTPUT': githubOutput.path,
            'DEFAULT_BRANCH': s.defaultBranch,
            'BEFORE_SHA': s.before,
            'FULL_INPUT': s.fullInput,
          },
          includeParentEnvironment: false,
        );
        expect(scope.exitCode, 0, reason: '$reason: ${scope.stderr}');
        Map<String, String> pairs(File file) => {
          for (final line in file.readAsLinesSync())
            line.substring(0, line.indexOf('=')): line.substring(
              line.indexOf('=') + 1,
            ),
        };
        final values = pairs(githubEnv);
        expect(values['FULL_RUN'], '${s.full}', reason: reason);
        expect(values['STRICT_CHECK'], '${s.strict}', reason: reason);
        expect(values['AFFECTED_BASE'], s.base, reason: reason);
        expect(values['TEST_SCOPE'], isNotEmpty, reason: reason);
        // check job: the strict check reads the step's env values.
        final checkEnv = {
          for (final MapEntry(:key, :value) in values.entries)
            'env.$key': value,
        };
        expect(
          _evaluate('${step('check', 'Workspace rules (strict)')['if']}', {
            ...checkEnv,
          }),
          s.strict,
          reason: reason,
        );
        expect(
          _evaluate('${step('check', 'Workspace rules')['if']}', checkEnv),
          !s.strict,
          reason: reason,
        );
        // The step outputs → the check job outputs.
        final stepOutputs = {
          for (final MapEntry(:key, :value) in pairs(githubOutput).entries)
            'steps.scope.outputs.$key': value,
        };
        final checkOutputs = {
          for (final MapEntry(:key, :value)
              in (jobs['check']!['outputs'] as YamlMap).entries)
            'needs.check.outputs.$key': resolve('$value', stepOutputs),
        };
        expect(checkOutputs, {
          'needs.check.outputs.full_run': '${s.full}',
          'needs.check.outputs.affected_base': s.base,
          'needs.check.outputs.test_scope': values['TEST_SCOPE'],
        }, reason: reason);
        // vm and chrome: every member or --affected-since <base>.
        for (final (job, all, affected) in [
          ('vm', 'VM tests (all members)', 'VM tests (affected)'),
          ('chrome', 'Browser tests (all members)', 'Browser tests (affected)'),
        ]) {
          final env = jobEnv(job, checkOutputs);
          expect(
            _evaluate('${step(job, all)['if']}', env),
            s.full,
            reason: '$reason: $job',
          );
          expect(
            _evaluate('${step(job, affected)['if']}', env),
            !s.full,
            reason: '$reason: $job',
          );
          if (!s.full) {
            final args = _shellWords(_commands(step(job, affected)).single, {
              'AFFECTED_BASE': env['env.AFFECTED_BASE']!,
            });
            expect(args.sublist(args.indexOf('--affected-since')), [
              '--affected-since',
              s.base,
              '--all-if-no-base',
            ], reason: '$reason: $job');
          }
        }
        // heavy: a full-run push, or the manual input `integration`.
        expect(
          _evaluate('${jobs['heavy']!['if']}', {
            'github.event_name': s.event,
            ...checkOutputs,
            'inputs.integration': s.integration,
          }),
          s.heavy,
          reason: '$reason: heavy',
        );
        // web: the summary's test scope is the check job's.
        expect(
          jobEnv('web', {
            ...checkOutputs,
            'secrets.FIREBASE_SERVICE_ACCOUNT': '',
            'vars.FIREBASE_PROJECT_ID': '',
          })['env.TEST_SCOPE'],
          values['TEST_SCOPE'],
          reason: reason,
        );
        // The Channel script itself, with a fake `dart` for ws channel-id.
        final output = File(p.join(scratch.path, 'output'))
          ..writeAsStringSync('');
        final result = Process.runSync(
          'bash',
          ['-e', '-c', '${step('web', 'Channel')['run']}'],
          environment: {
            'PATH': '${p.dirname(fakeDart.path)}:/usr/bin:/bin',
            'GITHUB_REF': 'refs/heads/${s.branch}',
            'GITHUB_REF_NAME': s.branch,
            'GITHUB_OUTPUT': output.path,
          },
          includeParentEnvironment: false,
        );
        expect(result.exitCode, 0, reason: '$reason: ${result.stderr}');
        expect(output.readAsLinesSync(), [
          'id=${s.channel}',
          'build=${s.channel == 'live' ? 'live' : 'preview'}',
        ], reason: reason);
        if (s.channel != 'live') {
          expect(
            File(p.join(scratch.path, 'dart-args')).readAsStringSync().trim(),
            'run tool/ws.dart channel-id --branch ${s.branch}',
            reason: reason,
          );
        }
      }
    });

    test('heavy: the 6.16 condition, word for word (no paths, no env)', () {
      expect(
        jobs['heavy']!['if'],
        "(github.event_name == 'push' && "
        "needs.check.outputs.full_run == 'true') || "
        'inputs.integration == true',
      );
    });

    test('--run-skipped only in the heavy job: the integration tag (VM, '
        'Chrome) and media with Chrome', () {
      final runSkipped = [
        for (final MapEntry(key: job, value: value) in jobs.entries)
          for (final s in _steps(value))
            if ('${s['run'] ?? ''}'.contains('--run-skipped'))
              '$job / ${s['name']}',
      ];
      expect(runSkipped, [
        'heavy / Integration tests (VM)',
        'heavy / Integration tests (Chrome)',
        'heavy / Media tests (Chrome fake mic)',
      ]);
    });

    test('no fixed main base; main is named only where live is decided', () {
      for (final name in _workflowNames()) {
        final text = File(p.join(_workflowsDir, name)).readAsStringSync();
        expect(text, isNot(contains('origin/main')), reason: name);
      }
      expect(
        [
          for (final MapEntry(key: job, value: value) in jobs.entries)
            for (final s in _steps(value))
              if ('${s.value}'.contains('refs/heads/main'))
                '$job / ${s['name']}',
        ],
        ['check / Test scope', 'web / Channel'],
      );
      for (final MapEntry(key: job, value: value) in jobs.entries) {
        expect(
          '${value['if'] ?? ''}${value['env'] ?? ''}',
          isNot(contains('refs/heads/main')),
          reason: job,
        );
      }
      // Deploying does not look at the branch: Channel picks live or the
      // preview channel, the secrets and the event gate the step.
      expect(
        '${step('web', 'Deploy to Firebase Hosting')['if']}',
        isNot(contains('github.ref')),
      );
    });

    test('channel: live on main, ws channel-id elsewhere', () {
      final channel = step('web', 'Channel');
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
        (step('web', 'Build info')['env'] as YamlMap)['BUILD_CHANNEL'],
        r'${{ steps.channel.outputs.build }}',
      );
    });

    test('deploy: push or the deploy input, the branch channel, 7 days', () {
      final deploy = step('web', 'Deploy to Firebase Hosting');
      expect(
        deploy['if'],
        "env.FIREBASE_SA != '' && env.FIREBASE_PROJECT_ID != '' && "
        "(github.event_name == 'push' || inputs.deploy)",
      );
      expect(deploy['uses'], 'FirebaseExtended/action-hosting-deploy@v0');
      expect(_with(deploy)['channelId'], r'${{ steps.channel.outputs.id }}');
    });

    test('summary always runs: label, channel, test scope, address or the '
        'guide', () {
      final summary = step('web', 'Summary');
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
      // TEST_SCOPE comes from the web job env (the check output).
      expect(run, contains(r'${TEST_SCOPE:-'));
    });

    test('every job ends with its timing table (always): the same script in '
        'check, vm, chrome and heavy, its table in the web summary', () {
      final timing = {
        for (final job in ['check', 'vm', 'chrome', 'heavy'])
          '${step(job, 'Timing')['run']}',
      };
      expect(timing, hasLength(1));
      for (final job in jobs.keys) {
        final last = stepsOf(job).last;
        expect(last['name'], job == 'web' ? 'Summary' : 'Timing', reason: job);
        expect(last['if'], 'always()', reason: job);
      }
      final script = timing.single;
      final table = script.substring(script.indexOf("echo '| 단계 | 시간 |'"));
      final summary = '${step('web', 'Summary')['run']}';
      expect(summary, contains(table.substring(0, table.indexOf('} >>'))));

      // Run it: the per-step lines, the job total, the scope only when set.
      final scratch = Directory.systemTemp.createTempSync('ws_ci_timing_');
      addTearDown(() => scratch.deleteSync(recursive: true));
      File(p.join(scratch.path, 'step-seconds'))
          .writeAsStringSync('75 준비 (체크아웃 · Flutter · 캐시)\n12 의존성\n34 분석\n');
      final start = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 100;
      File(p.join(scratch.path, 'ci-start')).writeAsStringSync('$start\n');
      for (final scope in ['기본 브랜치 — 1234567 이후 바뀐 멤버', null]) {
        final out = File(p.join(scratch.path, 'summary'))
          ..writeAsStringSync('');
        final result = Process.runSync(
          'bash',
          ['-e', '-c', script],
          environment: {
            'PATH': '/usr/bin:/bin',
            'RUNNER_TEMP': scratch.path,
            'GITHUB_STEP_SUMMARY': out.path,
            'GITHUB_JOB': 'check',
            'TEST_SCOPE': ?scope,
          },
          includeParentEnvironment: false,
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        final lines = out.readAsLinesSync();
        expect(lines.first, '### 단계 시간 — check');
        expect(
          lines.where((l) => l.startsWith('- 시험 범위:')).toList(),
          scope == null ? isEmpty : ['- 시험 범위: $scope'],
        );
        expect(
          lines,
          containsAllInOrder([
            '| 단계 | 시간 |',
            '|---|---|',
            '| 준비 (체크아웃 · Flutter · 캐시) | 75초 |',
            '| 의존성 | 12초 |',
            '| 분석 | 34초 |',
          ]),
        );
        expect(lines.last, matches(RegExp(r'^\| 잡 전체 \| \d+초 \|$')));
      }
    });

    test('timed steps record their seconds for the summary', () {
      final timed = [
        for (final job in jobs.keys)
          for (final s in stepsOf(job))
            if ('${s['run'] ?? ''}'.contains(r'"$SECONDS"')) '${s['name']}',
      ];
      expect(
        timed,
        containsAll([
          'Dependencies',
          'Analyze',
          'Tool tests',
          'Native requirements',
          'VM tests (all members)',
          'VM tests (affected)',
          'Browser tests (all members)',
          'Browser tests (affected)',
          'Integration tests (VM)',
          'Integration tests (Chrome)',
          'Media tests (Chrome fake mic)',
          'Web build',
        ]),
      );
      expect(timed.where((n) => n == 'Dependencies'), hasLength(5));
      for (final job in jobs.keys) {
        for (final s in stepsOf(job)) {
          for (final line in _runLines(s)) {
            if (line.contains(r'"$SECONDS"')) {
              expect(line, endsWith(r'>> "$RUNNER_TEMP/step-seconds"'));
            }
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
          'Publish APK',
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

    test('the release file name tells the signing: noteapp-apk-<run> or '
        'noteapp-debug-signed-<run>', () {
      final publish = _named(steps, 'Publish APK');
      expect(publish['uses'], isNull);
      final env = publish['env'] as YamlMap;
      expect(env['GH_TOKEN'], r'${{ github.token }}');
      expect(env['SIGNING_MODE'], r'${{ steps.signing.outputs.mode }}');
      String nameFor(String mode) => '${env['APK_NAME']}'.replaceAllMapped(
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
    });

    group('the publish step, run with a fake gh', () {
      late Directory dir;
      late File calls;
      setUp(() {
        dir = Directory.systemTemp.createTempSync('android_publish_');
        addTearDown(() => dir.deleteSync(recursive: true));
        calls = File(p.join(dir.path, 'calls'))..writeAsStringSync('');
        File(
            p.join(
              dir.path,
              'app/build/app/outputs/flutter-apk/'
              'app-arm64-v8a-release.apk',
            ),
          )
          ..createSync(recursive: true)
          ..writeAsStringSync('APK');
        Directory(p.join(dir.path, 'tmp')).createSync();
        // `release list` answers with five APK releases, newest first after
        // the --jq filter (the fake applies none: it prints the filtered list).
        final gh = File(p.join(dir.path, 'bin', 'gh'))
          ..createSync(recursive: true)
          ..writeAsStringSync('''
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "\$CALLS"
if [ "\$1 \$2" = "release create" ]; then
  [ -f "\$4" ] || exit 7
  cp "\$4" "\$CALLS.uploaded"
fi
if [ "\$1 \$2" = "release list" ]; then
  printf 'android-4\\nandroid-3\\n'
fi
''');
        Process.runSync('chmod', ['+x', gh.path]);
      });

      ({int code, String stdout, String summary, List<String> calls}) publish(
        String mode,
      ) {
        final summary = File(p.join(dir.path, 'summary'))
          ..writeAsStringSync('');
        final name = mode == 'release'
            ? 'noteapp-apk-7'
            : 'noteapp-debug-signed-7';
        final result = Process.runSync(
          'bash',
          [
            '-e',
            '-o',
            'pipefail',
            '-c',
            '${_named(steps, 'Publish APK')['run']}',
          ],
          workingDirectory: dir.path,
          environment: {
            'PATH':
                '${p.join(dir.path, 'bin')}:'
                '${Platform.environment['PATH'] ?? '/usr/bin:/bin'}',
            'CALLS': calls.path,
            'GITHUB_STEP_SUMMARY': summary.path,
            'GITHUB_RUN_NUMBER': '7',
            'GITHUB_REPOSITORY': 'owner/noteapp',
            'GITHUB_SERVER_URL': 'https://github.com',
            'GITHUB_SHA': 'abc123',
            'RUNNER_TEMP': p.join(dir.path, 'tmp'),
            'SIGNING_MODE': mode,
            'APK_NAME': name,
          },
          includeParentEnvironment: false,
        );
        return (
          code: result.exitCode,
          stdout: '${result.stdout}${result.stderr}',
          summary: summary.readAsStringSync(),
          calls: calls.readAsLinesSync(),
        );
      }

      test('a pre-release android-<run> with the named .apk, then the '
          'releases past the newest three are deleted with their tags', () {
        for (final mode in ['release', 'debug']) {
          calls.writeAsStringSync('');
          final run = publish(mode);
          expect(run.code, 0, reason: run.stdout);
          final name = mode == 'release'
              ? 'noteapp-apk-7'
              : 'noteapp-debug-signed-7';
          final create = run.calls.first;
          expect(
            create,
            startsWith(
              'release create android-7 ${p.join(dir.path, 'tmp', '$name.apk')} '
              '--repo owner/noteapp --target abc123 --prerelease --title $name '
              '--notes ',
            ),
          );
          expect(
            create,
            contains(mode == 'release' ? '고정 키 판이에요' : '덮어 설치할 수 없는 시험판'),
          );
          expect(File('${calls.path}.uploaded').readAsStringSync(), 'APK');
          expect(run.calls[1], startsWith('release list --repo owner/noteapp'));
          expect(run.calls.sublist(2), [
            'release delete android-4 --repo owner/noteapp --yes --cleanup-tag',
            'release delete android-3 --repo owner/noteapp --yes --cleanup-tag',
          ]);
          expect(
            run.summary,
            '다운로드: https://github.com/owner/noteapp/releases/tag/android-7 — '
            '$name.apk\n',
          );
        }
      });

      test(
        'the list keeps only android-* releases, newest first, past three',
        () {
          final run = _runLines(_named(steps, 'Publish APK')).join('\n');
          expect(
            run,
            contains(
              "--jq '[.[] | select(.tagName | startswith(\"android-\"))] | "
              "sort_by(.createdAt) | reverse | .[3:] | .[].tagName'",
            ),
          );
        },
      );
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
[ -n "\$FAKE_FAIL" ] && { echo "DOES NOT VERIFY" >&2; exit 1; }
if [ -n "\$FAKE_V2_SIGNER" ]; then
  echo "Verifies"
  echo "Verified using v2 scheme (APK Signature Scheme v2): true"
  echo "V2 Signer: certificate DN: C=US, O=Android, CN=Android Debug"
  echo "V2 Signer: certificate SHA-256 digest: $printed"
  echo "V2 Signer: certificate SHA-1 digest: 36d01b7cfb7a9133669d3fb3a3cffd27fcd89d17"
  exit 0
fi
if [ -n "\$FAKE_SDK_RANGE" ]; then
  echo "Signer (minSdkVersion=24, maxSdkVersion=2147483647) certificate DN: CN=Android Debug"
  echo "Signer (minSdkVersion=24, maxSdkVersion=2147483647) certificate SHA-256 digest: $printed"
  exit 0
fi
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
        bool sdkRange = false,
        bool v2Signer = false,
        bool fail = false,
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
            if (sdkRange) 'FAKE_SDK_RANGE': '1',
            if (v2Signer) 'FAKE_V2_SIGNER': '1',
            if (fail) 'FAKE_FAIL': '1',
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

      test('no digest printed → failure on release, a warning on debug', () {
        final run = check('release', silent: true);
        expect(run.code, 1);
        expect(run.stdout, contains('::error::apksigner printed no SHA-256'));
        final debug = check('debug', silent: true);
        expect(debug.code, 0, reason: debug.stdout);
        expect(
          debug.stdout,
          contains('::warning::apksigner printed no SHA-256'),
        );
        expect(debug.summary, startsWith('서명: debug 키'));
      });

      test('newer build-tools: "Signer (minSdkVersion=…)" lines are read too '
          '(Android APK run 5 failed on them)', () {
        final run = check('release', cert: digest, sdkRange: true);
        expect(run.code, 0, reason: run.stdout);
        expect(run.summary, '서명: 고정 키 (0123456789abcdef)\n');
        expect(run.stdout, contains('certificate SHA-256 digest: $digest'));
        final debug = check('debug', sdkRange: true);
        expect(debug.code, 0, reason: debug.stdout);
      });

      test('"V2 Signer: certificate SHA-256 digest:" lines are read too '
          '(Android APK run 6 printed only those)', () {
        final run = check('release', cert: digest, v2Signer: true);
        expect(run.code, 0, reason: run.stdout);
        expect(run.summary, '서명: 고정 키 (0123456789abcdef)\n');
        final debug = check('debug', v2Signer: true);
        expect(debug.code, 0, reason: debug.stdout);
        expect(debug.stdout, isNot(contains('::warning::')));
      });

      test(
        'apksigner fails to verify → failure with its output in the log',
        () {
          final run = check('debug', fail: true);
          expect(run.code, 1);
          expect(run.stdout, contains('DOES NOT VERIFY'));
          expect(run.stdout, contains('::error::apksigner could not verify'));
        },
      );
    });
  });

  group('functions.yml (2차 R2-B1 skeleton → J16, m5-7/01-infra 6.14)', () {
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
        [
          'Set up Node',
          'Install',
          'Unit tests',
          'Emulator tests',
          'Set up Flutter',
          'Cache build hooks',
          'Dependencies',
          'Dart emulator tests',
        ],
      );
    });

    test('the 6.14 order: npm ci → npm test → npm run test:emulator (before '
        'Flutter — 07-sync RQ-8) → Flutter → pub get → the Dart emulator '
        'tests', () {
      expect(
        [for (final s in steps) s['name']],
        [
          'Checkout',
          'Set up Node',
          'Install',
          'Unit tests',
          'Emulator tests',
          'Set up Flutter',
          'Cache build hooks',
          'Dependencies',
          'Dart emulator tests',
          'Skipped (no functions/)',
        ],
      );
      expect(_named(steps, 'Emulator tests')['working-directory'], 'functions');
      expect(
        '${_named(steps, 'Emulator tests')['run']}',
        contains('npm run test:emulator'),
      );
      expect(
        _named(steps, 'Set up Flutter')['uses'],
        'subosito/flutter-action@v2',
      );
      expect(_runLines(_named(steps, 'Dependencies')), [
        'flutter pub get --enforce-lockfile',
      ]);
      // The Dart step runs at the repository root (--config app/firebase.json).
      expect(
        _named(steps, 'Dart emulator tests').containsKey('working-directory'),
        isFalse,
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
          includeParentEnvironment: false,
        ).exitCode;
      }

      expect(runWith(['TAP version 13', '# tests 3', '# pass 3']), 0);
      expect(runWith(['ℹ tests 2', 'ℹ pass 2']), 0);
      expect(runWith(['# tests 0', '# pass 0']), isNot(0));
      expect(runWith(['no counter']), isNot(0));
      expect(runWith(['# tests 3'], exitCode: 1), isNot(0));
    });

    test(
      'npm run test:emulator: `# tests 0` passes (no emulator test file '
      'before SYNC S2-11), a failure fails, the count goes to the summary',
      () {
        final run = '${_named(steps, 'Emulator tests')['run']}';
        expect(run, contains('set -o pipefail'));
        final scratch = Directory.systemTemp.createTempSync('ws_fn_emu_');
        addTearDown(() => scratch.deleteSync(recursive: true));
        final npm = File(p.join(scratch.path, 'bin', 'npm'))
          ..createSync(recursive: true);
        final calls = File(p.join(scratch.path, 'calls'));
        Process.runSync('chmod', ['+x', npm.path]);
        ({int code, String summary}) runWith(
          List<String> output, {
          int exitCode = 0,
        }) {
          npm.writeAsStringSync(
            '#!/bin/sh\necho "\$*" >> "${calls.path}"\n'
            "printf '%s\\n' ${[for (final l in output) "'$l'"].join(' ')}\n"
            'exit $exitCode\n',
          );
          final summary = File(p.join(scratch.path, 'summary'))
            ..writeAsStringSync('');
          final code = Process.runSync(
            'bash',
            ['-e', '-c', run],
            environment: {
              'PATH': '${p.dirname(npm.path)}:/usr/bin:/bin',
              'RUNNER_TEMP': scratch.path,
              'GITHUB_STEP_SUMMARY': summary.path,
            },
            includeParentEnvironment: false,
          ).exitCode;
          return (code: code, summary: summary.readAsStringSync());
        }

        final zero = runWith(['# tests 0', '# pass 0']);
        expect(zero.code, 0);
        expect(zero.summary, '- npm run test:emulator: 시험 0개 통과\n');
        final ten = runWith(['TAP version 13', '# tests 10', '# pass 10']);
        expect(ten.code, 0);
        expect(ten.summary, '- npm run test:emulator: 시험 10개 통과\n');
        expect(runWith(['# tests 10', '# fail 1'], exitCode: 1).code, isNot(0));
        expect(runWith(['no counter']).summary, contains('시험 ?개'));
        expect(calls.readAsLinesSync().toSet(), {'run test:emulator'});
      },
    );

    test('the Dart emulator tests: emulators:exec of functions/ firebase with '
        'the committed config and demo project, the ink_recognition '
        'emulator tag inside (6.13 path without with-heavy-lock)', () {
      final step = _named(steps, 'Dart emulator tests');
      final lines = _runLines(step);
      expect(lines, hasLength(1));
      const inner =
          '$_ws test --package ink_recognition --run-skipped -t emulator';
      expect(_shellWords(lines.single, {}), [
        'npx',
        '--prefix',
        'functions',
        'firebase',
        'emulators:exec',
        '--config',
        'app/firebase.json',
        '--only',
        'functions,auth',
        '--project',
        'demo-noteapp',
        inner,
      ]);
      // The CI runner is one job: the heavy-test lock is never taken here.
      for (final s in steps) {
        expect('${s['run'] ?? ''}', isNot(contains('with-heavy-lock')));
      }
      // What the command names exists: the emulator config (functions 5001,
      // auth 9099), the demo project's committed values, firebase-tools in
      // functions/package.json (npx --prefix functions), the tag in
      // ink_recognition's dart_test.yaml.
      final firebase = jsonDecode(
        File(p.join(repoRoot, 'app', 'firebase.json')).readAsStringSync(),
      ) as Map<String, Object?>;
      final emulators = firebase['emulators']! as Map<String, Object?>;
      expect((emulators['functions']! as Map)['port'], 5001);
      expect((emulators['auth']! as Map)['port'], 9099);
      expect(
        File(p.join(repoRoot, 'functions', '.env.demo-noteapp')).existsSync(),
        isTrue,
      );
      final package = jsonDecode(
        File(p.join(repoRoot, 'functions', 'package.json')).readAsStringSync(),
      ) as Map<String, Object?>;
      expect(
        package['devDependencies']! as Map<String, Object?>,
        containsPair('firebase-tools', '15.34.1'),
      );
      expect(
        (package['scripts']! as Map<String, Object?>).keys,
        containsAll(['build', 'test', 'test:emulator']),
      );
      final tags =
          _load(
                p.join(
                  repoRoot,
                  'packages',
                  'ink_recognition',
                  'dart_test.yaml',
                ),
              )['tags']
              as YamlMap;
      expect(tags.keys, contains('emulator'));
      expect('${(tags['emulator'] as YamlMap)['skip']}', isNotEmpty);
      // The same tag and lock-free inner command as the container path of
      // tool/README.md (which adds with-heavy-lock and runs every member).
      final readme = File(p.join(repoRoot, 'tool', 'README.md'))
          .readAsStringSync();
      expect(readme, contains('"$_ws test --run-skipped -t emulator"'));
      expect(
        readme,
        contains(
          'npx --prefix functions firebase emulators:exec --config app/firebase.json',
        ),
      );
    });
  });

  group('android-emulator.yml (2차 J21, m5-7/01-infra 6.10.5)', () {
    late YamlMap emulator;
    late YamlMap job;
    late List<YamlMap> steps;

    setUp(() {
      emulator = _workflow('android-emulator.yml');
      job = _jobs(emulator).values.single;
      steps = _steps(job);
    });

    test('manual runs only, one run per ref (a new one cancels)', () {
      final on = emulator['on'] as YamlMap;
      expect(on.keys, ['workflow_dispatch']);
      expect(on['workflow_dispatch'], isNull, reason: 'no inputs');
      final concurrency = emulator['concurrency'] as YamlMap;
      expect(concurrency['group'], r'android-emulator-${{ github.ref }}');
      expect(concurrency['cancel-in-progress'], isTrue);
    });

    test(
      'ubuntu with a 45 minute limit, no job if, no secret, no variable',
      () {
        expect(job['runs-on'], 'ubuntu-latest');
        expect(job['timeout-minutes'], 45);
        expect(job.containsKey('if'), isFalse);
        expect(job.containsKey('env'), isFalse);
        final text = File(p.join(_workflowsDir, 'android-emulator.yml'))
            .readAsStringSync();
        expect(text, isNot(contains('secrets.')));
        expect(text, isNot(contains('vars.')));
      },
    );

    test('the 6.10.5 steps in order: KVM, the android.yml toolchain, the '
        'debug APK before the emulator boots, the smoke last', () {
      expect(
        [for (final s in steps) s['name']],
        [
          'Checkout',
          'Enable KVM',
          'Set up Java',
          'Cache Android NDK',
          'Set up Flutter',
          'Build hooks (downloads sqlite3 when not cached)',
          'Dependencies',
          'Build debug APK',
          'Build info',
          'Build release APK (x86_64)',
          'Native smoke',
        ],
      );
      expect(
        [
          for (final s in steps)
            if (s['run'] != null && _commands(s).isNotEmpty)
              _commands(s).single,
        ],
        [
          'flutter pub get --enforce-lockfile',
          _emulatorApkBuild,
          _buildInfoFromEnv,
          _emulatorReleaseBuild,
        ],
      );
      expect(_named(steps, 'Build debug APK')['working-directory'], 'app');
      expect(
        _named(steps, 'Build release APK (x86_64)')['working-directory'],
        'app',
      );
      // The same channel rule as android.yml.
      expect(
        (_named(steps, 'Build info')['env'] as YamlMap).value,
        (_named(
                  _steps(_jobs(_workflow('android.yml')).values.single),
                  'Build info',
                )['env']
                as YamlMap)
            .value,
      );
      for (final step in steps) {
        expect(step['if'], isNull, reason: '${step['name']}');
      }
    });

    test('Java and the NDK cache are the ones of android.yml', () {
      final android = _steps(_jobs(_workflow('android.yml')).values.single);
      for (final name in ['Set up Java', 'Cache Android NDK']) {
        expect(
          _named(steps, name).value,
          _named(android, name).value,
          reason: name,
        );
      }
    });

    test('the emulator: API 34 google_apis x86_64, the microphone on '
        '(no -noaudio), the app directory', () {
      final step = _named(steps, 'Native smoke');
      expect(step['uses'], 'reactivecircus/android-emulator-runner@v2');
      final withMap = _with(step);
      expect(
        {for (final key in withMap.keys) key},
        {
          'api-level',
          'target',
          'arch',
          'emulator-options',
          'disable-animations',
          'working-directory',
          'script',
        },
      );
      expect(withMap['api-level'], 34);
      expect(withMap['target'], 'google_apis');
      expect(withMap['arch'], 'x86_64');
      expect(withMap['disable-animations'], isTrue);
      expect(withMap['working-directory'], 'app');
      // The action's default options (-no-window -gpu swiftshader_indirect
      // -no-snapshot -noaudio -no-boot-anim) without -noaudio.
      final options = '${withMap['emulator-options']}'.split(' ');
      expect(options, [
        '-no-window',
        '-gpu',
        'swiftshader_indirect',
        '-no-snapshot',
        '-no-boot-anim',
      ]);
      expect(options, isNot(contains('-noaudio')));
    });

    test('the script: the debug APK with granted permissions, then flutter '
        'test of the native smoke (each line on its own)', () {
      final script = '${_with(_named(steps, 'Native smoke'))['script']}';
      final lines = [
        for (final line in script.split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      ];
      expect(lines, [
        '$_launchCheck $_emulatorReleaseApk dev.noteapp.noteapp 20',
        'adb install -r -g $_emulatorApk',
        'flutter test $_nativeSmoke',
      ]);
      // Each line runs alone: no `cd`, no continuation, no `&&`.
      for (final line in lines) {
        expect(line, isNot(startsWith('cd ')));
        expect(line, isNot(endsWith(r'\')));
        expect(line, isNot(contains('&&')));
        expect(
          Process.runSync('bash', ['-n', '-c', line]).exitCode,
          0,
          reason: line,
        );
      }
      // The APK the build step makes in the same directory (app/).
      expect(_emulatorApkBuild, 'flutter build apk --debug');
      expect(_emulatorApk, endsWith('/app-debug.apk'));
    });

    group('the release launch check, run with a fake adb', () {
      late Directory dir;
      late File calls;
      setUp(() {
        dir = Directory.systemTemp.createTempSync('android_launch_');
        addTearDown(() => dir.deleteSync(recursive: true));
        calls = File(p.join(dir.path, 'calls'))..writeAsStringSync('');
        final adb = File(p.join(dir.path, 'bin', 'adb'))
          ..createSync(recursive: true)
          ..writeAsStringSync('''
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "\$CALLS"
case "\$*" in
  install*) [ -z "\$FAKE_INSTALL_FAILS" ] || exit 1 ;;
  "shell pidof"*) [ -n "\$FAKE_CRASH" ] || printf '4242\\r\\n' ;;
  "logcat -d -b crash") [ -z "\$FAKE_CRASH" ] || echo "E AndroidRuntime: FATAL EXCEPTION: main" ;;
  "logcat -d -v brief") echo "I flutter : started"; echo "W other   : noise" ;;
esac
exit 0
''');
        Process.runSync('chmod', ['+x', adb.path]);
      });

      ({int code, String stdout, String summary, List<String> calls}) launch({
        bool crash = false,
        bool installFails = false,
      }) {
        final summary = File(p.join(dir.path, 'summary'))
          ..writeAsStringSync('');
        final result = Process.runSync(
          'bash',
          [
            p.join(repoRoot, 'tool', 'android', 'release_launch_check.sh'),
            'app-release.apk',
            'dev.noteapp.noteapp',
            '0',
          ],
          environment: {
            'PATH':
                '${p.join(dir.path, 'bin')}:'
                '${Platform.environment['PATH'] ?? '/usr/bin:/bin'}',
            'CALLS': calls.path,
            'GITHUB_STEP_SUMMARY': summary.path,
            if (crash) 'FAKE_CRASH': '1',
            if (installFails) 'FAKE_INSTALL_FAILS': '1',
          },
          includeParentEnvironment: false,
        );
        return (
          code: result.exitCode,
          stdout: '${result.stdout}${result.stderr}',
          summary: summary.readAsStringSync(),
          calls: calls.readAsLinesSync(),
        );
      }

      test('still running → 0, the logs printed, the app uninstalled', () {
        final run = launch();
        expect(run.code, 0, reason: run.stdout);
        expect(run.calls, [
          'install -r -g app-release.apk',
          'logcat -c',
          'shell am start -W -n dev.noteapp.noteapp/.MainActivity',
          'shell pidof dev.noteapp.noteapp',
          'logcat -d -b crash',
          'logcat -d -v brief',
          'uninstall dev.noteapp.noteapp',
        ]);
        expect(run.stdout, contains('I flutter : started'));
        expect(run.stdout, isNot(contains('noise')));
        expect(run.stdout, contains('still running after 0 s (pid 4242)'));
        expect(run.summary, '릴리스 실행: 0초 뒤에도 실행 중\n');
      });

      test('gone → 1 with the crash buffer in the log', () {
        final run = launch(crash: true);
        expect(run.code, 1);
        expect(run.stdout, contains('FATAL EXCEPTION: main'));
        expect(run.stdout, contains('::error::릴리스 APK가 시작한 뒤 0초 안에 꺼졌어요'));
        expect(run.summary, '릴리스 실행: 0초 안에 꺼짐\n');
        expect(run.calls.last, 'uninstall dev.noteapp.noteapp');
      });

      test('the install fails → 1, nothing started', () {
        final run = launch(installFails: true);
        expect(run.code, 1);
        expect(run.calls, ['install -r -g app-release.apk']);
      });
    });

    test('Enable KVM, run with a fake sudo: the udev rule for /dev/kvm, '
        'reload, trigger', () {
      final dir = Directory.systemTemp.createTempSync('android_kvm_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final bin = Directory(p.join(dir.path, 'bin'))..createSync();
      final log = File(p.join(dir.path, 'sudo.log'));
      final sudo = File(p.join(bin.path, 'sudo'))
        ..writeAsStringSync(
          '#!/usr/bin/env bash\n'
          'printf "%s\\n" "\$*" >> "${log.path}"\n'
          'if [ "\$1" = tee ]; then sed "s/^/stdin: /" >> "${log.path}"; fi\n',
        );
      Process.runSync('chmod', ['+x', sudo.path]);
      final result = Process.runSync(
        'bash',
        ['-e', '-c', '${_named(steps, 'Enable KVM')['run']}'],
        workingDirectory: dir.path,
        environment: {
          'PATH': '${bin.path}:${Platform.environment['PATH'] ?? '/usr/bin'}',
        },
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(log.readAsLinesSync(), [
        'tee /etc/udev/rules.d/99-kvm4all.rules',
        'stdin: $_kvmRule',
        'udevadm control --reload-rules',
        'udevadm trigger --name-match=kvm',
      ]);
    });

    test('the test it runs: the app integration_test file, on the '
        'production start, four cases (6.10.5)', () {
      final file = File(p.join(repoRoot, 'app', _nativeSmoke));
      expect(file.existsSync(), isTrue);
      final source = file.readAsStringSync();
      expect(
        source,
        contains('IntegrationTestWidgetsFlutterBinding.ensureInitialized()'),
      );
      expect(source, contains('modules: productionModules()'));
      expect(source, contains('features: AppFeatures.compileTime'));
      expect(source, contains('resolveNativeStoragePaths()'));
      expect(source, contains('supportedImageSources()'));
      expect(source, contains(".ensureModel('en', wifiOnly: false)"));
      expect(source, contains('markTestSkipped('));
      expect(source, contains('const Duration(seconds: 2)'));
      expect(source, contains('recordings.recordingsOf('));
      expect(
        RegExp(r'^  testWidgets\(', multiLine: true).allMatches(source),
        hasLength(4),
      );
      // integration_test is the app's dev dependency (an SDK package —
      // contract 7.5 v2.1, R2-B1), and what `adb install -g` grants is
      // declared in the main manifest.
      final pubspec = _load(p.join(repoRoot, 'app', 'pubspec.yaml'));
      expect(
        ((pubspec['dev_dependencies'] as YamlMap)['integration_test']
                as YamlMap)
            .value,
        {'sdk': 'flutter'},
      );
      final manifest = File(
        p.join(repoRoot, 'app/android/app/src/main/AndroidManifest.xml'),
      ).readAsStringSync();
      for (final permission in ['RECORD_AUDIO', 'POST_NOTIFICATIONS']) {
        expect(
          manifest,
          contains('android:name="android.permission.$permission"'),
        );
      }
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
