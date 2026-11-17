// ws affected / affectedMembers (docs/plans/01-infra.md 4.2 and 9.1).

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../src/affected.dart';
import '../src/cli.dart';
import '../src/flutter_runner.dart';
import '../src/rules.dart';
import '../src/workspace.dart';
import 'support/fake_processes.dart';
import 'support/fixture_workspace.dart';

void main() {
  late Workspace workspace;
  late List<String> triggers;

  setUpAll(() {
    workspace = Workspace.load(repoRoot);
    triggers = WorkspaceRules.load(realRulesPath).globalTriggers;
  });

  List<String> affected(List<String> paths) => [
    for (final m in affectedMembers(workspace, paths, triggers)) m.name,
  ];

  test('note_core change: note_core, its seven dependents (2차 service '
      'packages media_io and ink_recognition included) and the two apps', () {
    expect(affected(['packages/note_core/lib/x.dart']), [
      'note_core',
      'ink_engine',
      'feature_editor',
      'feature_library',
      'pdf_io',
      'sync_engine',
      'ink_lab',
      'media_io',
      'ink_recognition',
      'feature_markdown', // v2.17-md
      'noteapp',
    ]);
  });

  test('feature_library change: feature_library and noteapp', () {
    expect(affected(['packages/feature_library/lib/src/a.dart']), [
      'feature_library',
      'noteapp',
    ]);
  });

  test('ink_engine change reaches editor, pdf, ink lab, ink_recognition and '
      'the app, not library or media_io', () {
    expect(affected(['packages/ink_engine/test/a_test.dart']), [
      'ink_engine',
      'feature_editor',
      'pdf_io',
      'ink_lab',
      'ink_recognition',
      'feature_markdown', // v2.17-md
      'noteapp',
    ]);
  });

  test('pencil_bridge change (2차): pencil_bridge and the app only', () {
    expect(
      affected(['packages/pencil_bridge/ios/pencil_bridge/Package.swift']),
      ['pencil_bridge', 'noteapp'],
    );
  });

  test('a file of the nested ink lab affects only the ink lab, not '
      'ink_engine (innermost member)', () {
    expect(affected(['packages/ink_engine/example/lib/main.dart']), [
      'ink_lab',
    ]);
    expect(affected(['packages/ink_engine/example/pubspec.yaml']), ['ink_lab']);
    expect(
      memberOfPath(workspace, 'packages/ink_engine/lib/a.dart')!.name,
      'ink_engine',
    );
    expect(
      memberOfPath(workspace, 'packages/ink_engine/example')!.name,
      'ink_lab',
    );
    expect(memberOfPath(workspace, 'packages/ink_engine_x/a.dart'), isNull);
  });

  test('sync_engine change: only sync_engine (the app does not use it)', () {
    expect(affected(['packages/sync_engine/pubspec.yaml']), ['sync_engine']);
  });

  test('global triggers affect every member in topological order', () {
    final all = [for (final m in workspace.topologicalOrder()) m.name];
    for (final path in [
      'pubspec.lock',
      'pubspec.yaml',
      'analysis_options.yaml',
      'tool/src/rules.dart',
      '.github/workflows/ci.yml',
    ]) {
      expect(affected([path]), all, reason: path);
    }
    expect(all.first, 'note_core');
    expect(all.indexOf('noteapp'), greaterThan(all.indexOf('pdf_io')));
  });

  test('docs and other paths affect nothing', () {
    expect(
      affected(['docs/a.md', 'README.md', '.github/ISSUE_TEMPLATE/x']),
      isEmpty,
    );
    expect(affected([]), isEmpty);
  });

  test('a member path prefix does not match a sibling directory', () {
    expect(affected(['packages/note_core_extra/x.dart']), isEmpty);
    expect(affected(['application/x.dart']), isEmpty);
  });

  group('ws affected', () {
    late FixtureWorkspace fixture;
    late FakeProcesses processes;

    setUp(() {
      fixture = FixtureWorkspace.clean({
        'tool/workspace_rules.yaml': File(realRulesPath).readAsStringSync(),
      });
      processes = FakeProcesses((call) {
        final args = call.arguments;
        if (args.first == 'merge-base') {
          return const RunResult(exitCode: 0, output: 'abc123\n');
        }
        if (args.first == 'diff') {
          return const RunResult(
            exitCode: 0,
            output: 'packages/ink_engine/lib/a.dart\ndocs/x.md\n',
          );
        }
        return const RunResult(exitCode: 0, output: '');
      });
    });
    tearDown(() => fixture.dispose());

    Future<(int, String, String)> ws(
      List<String> args, {
      bool hasGit = true,
    }) async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runWs(
        args,
        context: WsContext(
          root: fixture.root,
          out: out,
          err: err,
          environment: const {'PATH': '/usr/bin'},
          isFile: (path) => hasGit && path == '/usr/bin/git',
          processes: processes,
        ),
      );
      return (code, out.toString(), err.toString());
    }

    test('prints the affected members; git runs quietly in the root', () async {
      final (code, out, _) = await ws(['affected', '--since', 'origin/main']);
      expect(code, 0);
      expect(out.trim().split('\n'), [
        'ink_engine  packages/ink_engine',
        'noteapp  app',
      ]);
      expect(
        [for (final c in processes.calls) c.arguments.join(' ')],
        [
          'rev-parse --verify --quiet origin/main^{commit}',
          'merge-base origin/main HEAD',
          'diff --name-only --relative abc123',
          'ls-files --others --exclude-standard',
        ],
      );
      expect(processes.calls.every((c) => !c.echo), isTrue);
      expect(processes.calls.first.workingDirectory, fixture.root);
      expect(processes.calls.first.executable, '/usr/bin/git');
    });

    test('untracked files count too', () async {
      processes.handler = (call) => switch (call.arguments.first) {
        'merge-base' => const RunResult(exitCode: 0, output: 'abc\n'),
        'ls-files' => const RunResult(
          exitCode: 0,
          output: 'packages/feature_library/lib/new.dart\n',
        ),
        _ => const RunResult(exitCode: 0),
      };
      final (_, out, _) = await ws(['affected', '--since', 'main']);
      expect(out.trim().split('\n'), [
        'feature_library  packages/feature_library',
        'noteapp  app',
      ]);
    });

    test('missing --since is a usage error, no git an environment error, '
        'an unknown ref an environment error', () async {
      expect((await ws(['affected'])).$1, usageExitCode);
      expect(
        (await ws(['affected', '--since', 'x'], hasGit: false)).$1,
        environmentExitCode,
      );
      // `rev-parse --verify --quiet` exits 1 without output for a name that
      // is not a commit.
      processes.handler = (call) => call.arguments.first == 'rev-parse'
          ? const RunResult(exitCode: 1)
          : const RunResult(exitCode: 0);
      final (code, _, err) = await ws(['affected', '--since', 'origin/main']);
      expect(code, environmentExitCode);
      expect(err, contains('`origin/main` names no commit'));
      expect(processes.calls.last.arguments.first, 'rev-parse');
    });

    test(
      'no merge base and other git failures are environment errors',
      () async {
        processes.handler = (call) => call.arguments.first == 'merge-base'
            ? const RunResult(exitCode: 1)
            : const RunResult(exitCode: 0);
        var (code, _, err) = await ws(['affected', '--since', 'other']);
        expect(code, environmentExitCode);
        expect(err, contains('no merge base between `other` and HEAD'));

        processes.handler = (_) => const RunResult(
          exitCode: 128,
          output: 'fatal: not a git repository',
        );
        (code, _, err) = await ws(['affected', '--since', 'main']);
        expect(code, environmentExitCode);
        expect(err, contains('fatal: not a git repository'));
      },
    );
  });

  test('changedPathsSince on a real git repository', () async {
    final dir = Directory.systemTemp.createTempSync('ws_git_');
    addTearDown(() => dir.deleteSync(recursive: true));
    Future<void> git(List<String> args) async {
      final r = await Process.run('git', [
        '-c',
        'user.name=t',
        '-c',
        'user.email=t@example.invalid',
        ...args,
      ], workingDirectory: dir.path);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    }

    void write(String path, String text) => File(p.join(dir.path, path))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);

    await git(['init', '-q', '-b', 'main']);
    write('a.txt', 'a');
    write('.gitignore', 'ignored/\n');
    await git(['add', '.']);
    await git(['commit', '-q', '-m', 'base']);
    await git(['checkout', '-q', '-b', 'work']);
    write('packages/x/lib/committed.dart', '');
    await git(['add', '.']);
    await git(['commit', '-q', '-m', 'work']);
    write('a.txt', 'changed');
    write('new/untracked.dart', '');
    write('ignored/skip.dart', '');

    final paths = await changedPathsSince(
      'main',
      processes: IoProcessRunner(out: StringBuffer()),
      git: 'git',
      root: dir.path,
    );
    expect(paths, [
      'a.txt',
      'new/untracked.dart',
      'packages/x/lib/committed.dart',
    ]);

    Future<List<String>> since(String ref, {String? root}) => changedPathsSince(
      ref,
      processes: IoProcessRunner(out: StringBuffer()),
      git: 'git',
      root: root ?? dir.path,
    );

    // The base is missing: an unknown ref (the remote has no `main`) or a
    // history with no common ancestor.
    await expectLater(
      since('origin/main'),
      throwsA(
        isA<MissingBaseException>().having(
          (e) => e.message,
          'message',
          contains('`origin/main` names no commit'),
        ),
      ),
    );
    await git(['checkout', '-q', '--orphan', 'unrelated']);
    await git(['commit', '-q', '-m', 'unrelated']);
    await expectLater(
      since('main'),
      throwsA(
        isA<MissingBaseException>().having(
          (e) => e.message,
          'message',
          contains('no merge base'),
        ),
      ),
    );
    // Not a repository: a git failure, not a missing base.
    final outside = Directory.systemTemp.createTempSync('ws_no_git_');
    addTearDown(() => outside.deleteSync(recursive: true));
    await expectLater(
      since('main', root: outside.path),
      throwsA(
        isA<AffectedException>().having(
          (e) => e is MissingBaseException,
          'is MissingBaseException',
          isFalse,
        ),
      ),
    );
  }, tags: ['process']);
}
