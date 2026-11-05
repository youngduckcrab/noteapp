// ws test (docs/plans/01-infra.md 4.2 and 9.1, contract 00-overview 7.4.8),
// with a fake process runner: no real flutter / Chrome is started.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../src/cli.dart';
import '../src/flutter_runner.dart';
import '../src/test_command.dart';
import 'support/fixture_workspace.dart';

final class _Call {
  _Call(
    this.executable,
    this.arguments,
    this.workingDirectory,
    this.env,
    this.timeout,
  );

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final Map<String, String> env;
  final Duration? timeout;

  @override
  String toString() => '$executable ${arguments.join(' ')} @ $workingDirectory';
}

final class _FakeProcesses implements ProcessRunner {
  final calls = <_Call>[];

  /// Result per working directory basename + executable kind
  /// (`flutter` / `dart`), default: success with one passing test.
  final results = <String, RunResult>{};

  /// Results used one after the other (before [results]) for the same key:
  /// e.g. a time-out, then a pass.
  final queued = <String, List<RunResult>>{};

  /// Output of `/usr/bin/git <first argument> ...`.
  final git = <String, String>{'merge-base': 'base\n'};

  @override
  Future<RunResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    Map<String, String> environment = const {},
    Duration? timeout,
    bool echo = true,
  }) async {
    calls.add(
      _Call(executable, arguments, workingDirectory, environment, timeout),
    );
    if (executable == '/usr/bin/git') {
      return RunResult(exitCode: 0, output: git[arguments.first] ?? '');
    }
    final kind = executable == '/fake/flutter' ? 'flutter' : 'dart';
    final key = '${p.basename(workingDirectory)}:$kind';
    final queue = queued[key];
    if (queue != null && queue.isNotEmpty) return queue.removeAt(0);
    return results[key] ??
        RunResult(
          exitCode: 0,
          output: kind == 'flutter' ? '00:01 +1: All tests passed!\n' : '',
        );
  }
}

void main() {
  late FixtureWorkspace fixture;
  late _FakeProcesses processes;

  setUp(() {
    processes = _FakeProcesses();
    fixture = FixtureWorkspace.clean({
      // note_core: VM tests + browser tests + a prepare script.
      'packages/note_core/test/web/db_browser_test.dart': '',
      'packages/note_core/test/web/support.dart': '',
      'packages/note_core/test/unit/b_test.dart': '',
      'packages/note_core/test/helpers.dart': '',
      'packages/note_core/tool/prepare_web_test.dart': '',
      // ink_engine: browser tests without a prepare script.
      'packages/ink_engine/test/web/paint_test.dart': '',
      // feature_library: no tests at all.
      'app/test/app_test.dart': '',
    });
  });
  tearDown(() => fixture.dispose());

  Future<(int, String, String)> ws(
    List<String> args, {
    Map<String, String> env = const {
      'PATH': '/usr/bin',
      'CHROME_EXECUTABLE': '/opt/chrome-nosandbox',
    },
  }) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runWs(
      ['test', ...args],
      context: WsContext(
        root: fixture.root,
        out: out,
        err: err,
        environment: {'FLUTTER_BIN': '/fake/flutter', ...env},
        isFile: (path) =>
            path == '/fake/flutter' ||
            path == '/usr/bin/google-chrome' ||
            path == '/usr/bin/git',
        resolvedExecutable: '/fake/dart',
        processes: processes,
      ),
    );
    return (code, out.toString(), err.toString());
  }

  List<_Call> flutterCalls() => [
    for (final c in processes.calls)
      if (c.executable == '/fake/flutter') c,
  ];

  test('vm: runs each member with its test files outside test/web/', () async {
    final (code, out, _) = await ws([]);
    expect(code, 0);
    final calls = flutterCalls();
    // Topological order; feature_library has no tests.
    expect(calls.map((c) => p.basename(c.workingDirectory)), [
      'note_core',
      'ink_engine',
      'app',
    ]);
    expect(calls.first.arguments, [
      'test',
      '--exclude-tags',
      'bench',
      'test/a_test.dart',
      'test/unit/b_test.dart',
    ]);
    expect(
      calls.first.workingDirectory,
      p.join(fixture.root, 'packages/note_core'),
    );
    expect(calls[1].arguments.last, 'test/ink_test.dart');
    expect(out, contains('no VM tests'));
    expect(out, contains('ws test: 3 member run(s), all passed'));
    // No prepare script in vm mode.
    expect(processes.calls.where((c) => c.executable == '/fake/dart'), isEmpty);
  });

  test('chrome: only members with test/web/, prepare script first', () async {
    final (code, out, _) = await ws(['--platform', 'chrome']);
    expect(code, 0);
    expect(
      processes.calls.map(
        (c) =>
            '${c.executable} ${c.arguments.first}'
            ' @${p.basename(c.workingDirectory)}',
      ),
      [
        '/fake/dart run @note_core',
        '/fake/flutter test @note_core',
        '/fake/flutter test @ink_engine',
      ],
    );
    final prepare = processes.calls.first;
    expect(prepare.arguments, ['run', 'tool/prepare_web_test.dart']);
    expect(prepare.timeout, const Duration(minutes: 5));
    final noteCore = processes.calls[1];
    expect(noteCore.arguments, [
      'test',
      '--platform',
      'chrome',
      '--exclude-tags',
      'bench',
      'test/web',
    ]);
    expect(noteCore.env['CHROME_EXECUTABLE'], '/opt/chrome-nosandbox');
    expect(out, contains('no test/web/'));
  });

  test(
    'chrome: a failing prepare script skips that member and fails',
    () async {
      processes.results['note_core:dart'] = const RunResult(exitCode: 1);
      final (code, out, _) = await ws(['--platform', 'chrome']);
      expect(code, 1);
      expect(flutterCalls().map((c) => p.basename(c.workingDirectory)), [
        'ink_engine',
      ]);
      expect(out, contains('PREPARE FAILED'));
      expect(out, contains('ws test: 1 of 2 member run(s) failed'));
    },
  );

  test('chrome: a timed-out prepare script counts as failed', () async {
    processes.results['note_core:dart'] = const RunResult(
      exitCode: -9,
      timedOut: true,
    );
    final (code, out, _) = await ws(['--platform', 'chrome']);
    expect(code, 1);
    expect(out, contains('timed out after 5 min'));
  });

  test(
    'chrome: without CHROME_EXECUTABLE the PATH Chrome is exported',
    () async {
      final (code, _, _) = await ws(
        ['--platform', 'chrome'],
        env: {'PATH': '/usr/bin'},
      );
      expect(code, 0);
      expect(
        flutterCalls().first.env['CHROME_EXECUTABLE'],
        '/usr/bin/google-chrome',
      );
    },
  );

  group('member time limit (CI: a hung CanvasKit start)', () {
    const timedOut = RunResult(
      exitCode: -15,
      output: '00:00 +0: loading test/web/db_browser_test.dart\n',
      timedOut: true,
    );

    test('chrome: 15 minutes per member run by default, vm: none', () async {
      await ws(['--platform', 'chrome']);
      expect(
        flutterCalls().map((c) => c.timeout),
        everyElement(const Duration(minutes: 15)),
      );
      expect(defaultChromeMemberTimeout, const Duration(minutes: 15));
      processes.calls.clear();
      await ws([]);
      expect(flutterCalls(), isNotEmpty);
      expect(flutterCalls().map((c) => c.timeout), everyElement(isNull));
    });

    test('--member-timeout sets the limit; 0 removes it; a bad value is a '
        'usage error', () async {
      await ws(['--platform', 'chrome', '--member-timeout', '2.5']);
      expect(
        flutterCalls().map((c) => c.timeout),
        everyElement(const Duration(seconds: 150)),
      );
      processes.calls.clear();
      await ws(['--member-timeout', '3']);
      expect(
        flutterCalls().map((c) => c.timeout),
        everyElement(const Duration(minutes: 3)),
      );
      processes.calls.clear();
      await ws(['--platform', 'chrome', '--member-timeout', '0']);
      expect(flutterCalls().map((c) => c.timeout), everyElement(isNull));
      final (code, _, err) = await ws(['--member-timeout', 'soon']);
      expect(code, 2);
      expect(err, contains('--member-timeout must be a number of minutes'));
    });

    test('a timed-out run is tried once more; passing then is ok', () async {
      processes.queued['note_core:flutter'] = [timedOut];
      final (code, out, _) = await ws(['--platform', 'chrome']);
      expect(code, 0);
      final calls = flutterCalls();
      expect(calls.map((c) => p.basename(c.workingDirectory)), [
        'note_core',
        'note_core',
        'ink_engine',
      ]);
      expect(calls[1].arguments, calls[0].arguments);
      // The prepare script is not run again.
      expect(
        processes.calls.where((c) => c.executable == '/fake/dart'),
        hasLength(1),
      );
      expect(
        out,
        contains(
          '== note_core: timed out after 15 min — killed, '
          'trying again',
        ),
      );
      expect(out, contains('== note_core (chrome, try 2): flutter test'));
      expect(out, contains('ok (try 2, after a time-out)'));
      expect(out, contains('ws test: 2 member run(s), all passed'));
    });

    test('two time-outs fail the member; the next member still runs', () async {
      processes.queued['note_core:flutter'] = [timedOut, timedOut];
      final (code, out, _) = await ws(['--platform', 'chrome']);
      expect(code, 1);
      expect(flutterCalls().map((c) => p.basename(c.workingDirectory)), [
        'note_core',
        'note_core',
        'ink_engine',
      ]);
      expect(out, contains('TIMED OUT (2 tries)'));
      expect(out, contains('ws test: 1 of 2 member run(s) failed'));
    });

    test('a run killed by a signal from outside stops ws test: the next '
        'members are not run', () async {
      processes.results['note_core:flutter'] = const RunResult(
        exitCode: -15,
        output: '00:20 +3: loading test/web/db_browser_test.dart\n',
      );
      final (code, out, _) = await ws(['--platform', 'chrome']);
      expect(code, 1);
      expect(flutterCalls().map((c) => p.basename(c.workingDirectory)), [
        'note_core',
      ]);
      expect(out, contains('stopped by a signal'));
      expect(out, contains('INTERRUPTED'));
      expect(
        out,
        matches(RegExp(r'ink_engine +chrome .*not run \(interrupted\)')),
      );
    });

    test('ws stopping (SIGINT / SIGTERM) during a run or a prepare script '
        'runs nothing more', () async {
      processes.results['note_core:dart'] = const RunResult(
        exitCode: -1,
        interrupted: true,
      );
      final (code, out, _) = await ws(['--platform', 'chrome']);
      expect(code, 1);
      expect(flutterCalls(), isEmpty);
      expect(out, contains('INTERRUPTED'));

      processes.calls.clear();
      processes.results
        ..remove('note_core:dart')
        ..['note_core:flutter'] = const RunResult(
          exitCode: -1,
          interrupted: true,
        );
      final (code2, out2, _) = await ws([]);
      expect(code2, 1);
      expect(flutterCalls().map((c) => p.basename(c.workingDirectory)), [
        'note_core',
      ]);
      expect(out2, contains('not run (interrupted)'));
    });

    test('RunResult.killedBySignal: negative exit code from outside only', () {
      expect(const RunResult(exitCode: -15).killedBySignal, isTrue);
      expect(const RunResult(exitCode: 1).killedBySignal, isFalse);
      expect(
        const RunResult(exitCode: -15, timedOut: true).killedBySignal,
        isFalse,
      );
      expect(
        const RunResult(exitCode: -15, interrupted: true).killedBySignal,
        isFalse,
      );
    });
  });

  test('chrome: no Chrome anywhere is an environment error (3)', () async {
    final (code, _, err) = await ws(
      ['--platform', 'chrome'],
      env: {'PATH': '/nowhere'},
    );
    expect(code, environmentExitCode);
    expect(err, contains('Chrome not found'));
    expect(processes.calls, isEmpty);
  });

  test('no flutter is an environment error (3)', () async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runWs(
      ['test'],
      context: WsContext(
        root: fixture.root,
        out: out,
        err: err,
        environment: {'PATH': '/nowhere'},
        isFile: (_) => false,
        resolvedExecutable: '/usr/lib/dart/bin/dart',
        processes: processes,
      ),
    );
    expect(code, environmentExitCode);
    expect(err.toString(), contains('flutter not found'));
  });

  test(
    '--run-skipped -t integration is passed through, -x bench kept',
    () async {
      final (code, _, _) = await ws([
        '--run-skipped',
        '-t',
        'integration',
        '--package',
        'note_core',
      ]);
      expect(code, 0);
      expect(flutterCalls().single.arguments.take(6), [
        'test',
        '--tags',
        'integration',
        '--exclude-tags',
        'bench',
        '--run-skipped',
      ]);
    },
  );

  test('explicit -x replaces the default; -t bench drops it', () async {
    await ws(['-x', 'golden', '-x', 'perf', '--package', 'ink_engine']);
    expect(flutterCalls().last.arguments.take(5), [
      'test',
      '--exclude-tags',
      'golden',
      '--exclude-tags',
      'perf',
    ]);
    await ws(['-t', 'bench', '--package', 'ink_engine']);
    expect(flutterCalls().last.arguments, isNot(contains('--exclude-tags')));
  });

  test('--reporter is passed through', () async {
    await ws(['--reporter', 'expanded', '--package', 'noteapp']);
    expect(
      flutterCalls().single.arguments,
      containsAllInOrder(['--reporter', 'expanded']),
    );
  });

  test(
    '--package selects members; unknown names are a usage error (2)',
    () async {
      final (code, _, _) = await ws(['--package', 'ink_engine']);
      expect(code, 0);
      expect(flutterCalls().map((c) => p.basename(c.workingDirectory)), [
        'ink_engine',
      ]);
      final (badCode, _, err) = await ws(['--package', 'nope']);
      expect(badCode, usageExitCode);
      expect(err, contains('unknown package(s): nope'));
    },
  );

  test(
    'a failing member fails the run; counts appear in the summary',
    () async {
      processes.results['ink_engine:flutter'] = const RunResult(
        exitCode: 1,
        output: '00:02 +3 ~1 -2: Some tests failed.\n',
      );
      final (code, out, _) = await ws([]);
      expect(code, 1);
      final row = out.split('\n').firstWhere((l) => l.startsWith('ink_engine'));
      expect(row.split(RegExp(r'\s+')), [
        'ink_engine',
        'vm',
        '-',
        '3',
        '2',
        '1',
        matches(r'^\d+\.\ds$'),
        'FAILED',
      ]);
    },
  );

  test('exit code 79 (no test matched the tags) is not a failure', () async {
    processes.results['note_core:flutter'] = const RunResult(
      exitCode: noTestsRanExitCode,
      output: 'No tests match the requested tag selectors:\n',
    );
    final (code, out, _) = await ws(['-t', 'integration']);
    expect(code, 0);
    expect(out, contains('no matching tests'));
  });

  test('nothing to run is a success', () async {
    final (code, out, _) = await ws([
      '--platform',
      'chrome',
      '--package',
      'noteapp',
    ]);
    expect(code, 0);
    expect(out, contains('nothing to run for chrome'));
    expect(processes.calls, isEmpty);
  });

  group('--affected-since', () {
    setUp(
      () => fixture.write(
        'tool/workspace_rules.yaml',
        File(realRulesPath).readAsStringSync(),
      ),
    );

    test('tests only the changed members and their dependents', () async {
      processes.git['diff'] = 'packages/ink_engine/lib/a.dart\n';
      final (code, out, _) = await ws(['--affected-since', 'origin/main']);
      expect(code, 0);
      expect(out, contains('affected since origin/main: ink_engine, noteapp'));
      expect(flutterCalls().map((c) => p.basename(c.workingDirectory)), [
        'ink_engine',
        'app',
      ]);
      final git = [
        for (final c in processes.calls)
          if (c.executable == '/usr/bin/git') c.arguments.first,
      ];
      expect(git, ['merge-base', 'diff', 'ls-files']);
    });

    test('a global trigger tests every member', () async {
      processes.git['diff'] = 'pubspec.lock\n';
      final (code, _, _) = await ws(['--affected-since', 'main']);
      expect(code, 0);
      expect(flutterCalls().length, 3); // members with VM tests
    });

    test('intersects with --package; nothing affected runs nothing', () async {
      processes.git['diff'] = 'packages/ink_engine/lib/a.dart\n';
      var (code, _, _) = await ws([
        '--affected-since',
        'main',
        '--package',
        'note_core',
      ]);
      expect(code, 0);
      expect(flutterCalls(), isEmpty);

      processes.git['diff'] = 'docs/a.md\n';
      final String out;
      (code, out, _) = await ws(['--affected-since', 'main']);
      expect(code, 0);
      expect(out, contains('nothing affected'));
      expect(flutterCalls(), isEmpty);
    });
  });

  group('parseTestCounts', () {
    test('reads the last counter line', () {
      expect(
        parseTestCounts(
          '00:00 +0: loading x\n00:01 +1: a\n00:02 +4 ~2 -1: Some tests failed.',
        ),
        (passed: 4, skipped: 2, failed: 1),
      );
      expect(parseTestCounts('00:03 +7: All tests passed!'), (
        passed: 7,
        skipped: 0,
        failed: 0,
      ));
      expect(parseTestCounts('00:03 +2 -1: x'), (
        passed: 2,
        skipped: 0,
        failed: 1,
      ));
      expect(parseTestCounts('no counters'), isNull);
    });
  });
}
