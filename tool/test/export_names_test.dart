// R14 — export name overlap (integration step G3, docs/plans/01-infra.md 6.2
// and the 9.1 export_names_test row): three fixture packages (plus an app
// that is not compared), overlapping public name reported once, `show` /
// `hide` / private names respected, entry points of one package not
// compared with each other, exit code 3 when an entry point cannot be
// resolved. The fixture packages are pure Dart and resolve with a written
// package_config.json (no `pub get`, no network).

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../src/cli.dart';
import '../src/export_names.dart';
import '../src/export_namespace.dart';
import '../src/flutter_runner.dart';
import '../src/rules.dart';
import '../src/workspace.dart';
import 'support/fake_processes.dart';
import 'support/fixture_workspace.dart';

String _pubspec(String name, [String deps = '']) =>
    '''
name: $name
publish_to: none
resolution: workspace
environment:
  sdk: ^3.13.0
  flutter: 3.47.9
$deps''';

const _packages = ['alpha', 'beta', 'gamma'];

/// A workspace of three pure Dart packages and the app `noteapp`:
///
/// - `Shared` is exported by alpha (both of its entry points) and beta — the
///   one overlap;
/// - `Hidden` is declared in alpha and beta but alpha does not `show` it and
///   beta `hide`s it;
/// - `_private` / `_Private` names exist in every package (never exported);
/// - `alphaOnly`, `betaOnly`, `Gamma` are unique;
/// - the app declares `Shared` and `Gamma` too, but apps are not compared.
Map<String, String> _files() => {
  'pubspec.yaml': '''
name: r14_fixture
publish_to: none
environment:
  sdk: ^3.13.0
  flutter: 3.47.9
workspace:
  - app
  - packages/alpha
  - packages/beta
  - packages/gamma
''',
  '.dart_tool/package_config.json': jsonEncode({
    'configVersion': 2,
    'packages': [
      for (final name in _packages)
        {
          'name': name,
          'rootUri': '../packages/$name',
          'packageUri': 'lib/',
          'languageVersion': '3.13',
        },
      {
        'name': 'noteapp',
        'rootUri': '../app',
        'packageUri': 'lib/',
        'languageVersion': '3.13',
      },
    ],
  }),
  'packages/alpha/pubspec.yaml': _pubspec('alpha'),
  'packages/alpha/lib/alpha.dart': '''
export 'src/a.dart' show Shared, alphaOnly;

class _Private {}

final _private = _Private();
Object get alphaPrivate => _private;
''',
  // Same package as alpha.dart: sharing `Shared` with it is fine.
  'packages/alpha/lib/testing.dart': '''
export 'package:alpha/src/a.dart' show Shared;
''',
  'packages/alpha/lib/src/a.dart': '''
class Shared {}

class Hidden {}

const alphaOnly = 1;
''',
  'packages/beta/pubspec.yaml': _pubspec('beta'),
  'packages/beta/lib/beta.dart': '''
export 'src/b.dart' hide Hidden;
''',
  'packages/beta/lib/src/b.dart': '''
class Shared {}

class Hidden {}

class _Private {}

const betaOnly = 2;
Object get betaPrivate => _Private();
''',
  'packages/gamma/pubspec.yaml': _pubspec('gamma'),
  'packages/gamma/lib/gamma.dart': '''
class Gamma {}

class _Shared {}

Object get gammaPrivate => _Shared();
''',
  'app/pubspec.yaml': _pubspec('noteapp'),
  'app/lib/main.dart': '''
class Shared {}

class Gamma {}

void main() {}
''',
  // `ws check` looks for the resolver script in the workspace; the tests
  // run it in-process (_InProcessResolver).
  exportNamesScript: '// placeholder: the tests resolve in-process\n',
  // The real rules with the three fixture packages allowed (R8).
  'tool/workspace_rules.yaml': File(realRulesPath)
      .readAsStringSync()
      .replaceFirst(
        'allowed_dependencies:',
        'allowed_dependencies:\n  alpha: []\n  beta: []\n  gamma: []',
      ),
};

/// Runs `dart run tool/export_names.dart …` in-process with
/// [exportNamesMain]; any other call is an error.
final class _InProcessResolver implements ProcessRunner {
  final calls = <List<String>>[];

  @override
  Future<RunResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    Map<String, String> environment = const {},
    Duration? timeout,
    bool echo = true,
  }) async {
    calls.add(arguments);
    expect(arguments.take(2), ['run', exportNamesScript]);
    final output = StringBuffer();
    final code = await exportNamesMain(
      arguments.sublist(2),
      out: output,
      err: output,
    );
    return RunResult(exitCode: code, output: output.toString());
  }
}

void main() {
  late WorkspaceRules rules;
  late FixtureWorkspace fixture;

  setUp(() {
    fixture = FixtureWorkspace.create(_files());
    rules = WorkspaceRules.load(
      p.join(fixture.root, 'tool', 'workspace_rules.yaml'),
    );
  });
  tearDown(() => fixture.dispose());

  Future<List<RuleViolation>> check([ProcessRunner? processes]) => checkExports(
    fixture.load(),
    rules,
    processes: processes ?? _InProcessResolver(),
    dart: '/fake/dart',
  );

  group('entry points', () {
    test('every lib/*.dart of the non-app members, apps skipped', () {
      expect(
        [for (final e in exportEntryPoints(fixture.load(), rules)) e.label],
        [
          'alpha/alpha.dart',
          'alpha/testing.dart',
          'beta/beta.dart',
          'gamma/gamma.dart',
        ],
      );
    });

    test('the real workspace: the six packages of contract 7.1 (15 entry '
        'points), not the app nor the ink lab', () {
      final entries = exportEntryPoints(Workspace.load(repoRoot), rules);
      expect(
        {for (final e in entries) e.package},
        {
          'note_core',
          'ink_engine',
          'feature_editor',
          'feature_library',
          'pdf_io',
          'sync_engine',
        },
      );
      expect(
        [for (final e in entries) e.path],
        everyElement(matches(RegExp(r'^packages/[a-z_]+/lib/[a-z_]+\.dart$'))),
      );
      expect(
        [for (final e in entries) e.label],
        containsAll([
          'note_core/note_core.dart',
          'note_core/testing_vm.dart',
          'ink_engine/dev_tools.dart',
          'sync_engine/platform.dart',
        ]),
      );
    });
  });

  group('names', () {
    test(
      'show / hide / private are respected; setters count by name',
      () async {
        final ws = fixture.load();
        final report = await resolveExportNames([
          for (final e in exportEntryPoints(ws, rules)) p.join(ws.root, e.path),
        ]);
        expect(report.unresolved, isEmpty);
        String path(String rel) => p.join(ws.root, rel);
        expect(report.names[path('packages/alpha/lib/alpha.dart')], {
          'Shared',
          'alphaOnly',
          'alphaPrivate',
        });
        expect(report.names[path('packages/alpha/lib/testing.dart')], {
          'Shared',
        });
        expect(report.names[path('packages/beta/lib/beta.dart')], {
          'Shared',
          'betaOnly',
          'betaPrivate',
        });
        expect(report.names[path('packages/gamma/lib/gamma.dart')], {
          'Gamma',
          'gammaPrivate',
        });
        expect(publicExportNames(['a', 'a=', 'b=', '_c', '_d=']), {'a', 'b'});
      },
    );

    test('the overlapping public name is reported once, with every entry '
        'point that exports it', () async {
      final v = await check();
      expect(v, hasLength(1));
      expect(
        v.single.format(),
        'packages/alpha/lib/alpha.dart:1: [R14] Shared: alpha/alpha.dart & '
        'alpha/testing.dart & beta/beta.dart',
      );
    });

    test('entry points of the same package are not compared', () async {
      fixture.write(
        'packages/beta/lib/beta.dart',
        "export 'src/b.dart' hide Hidden, Shared;\n",
      );
      // alpha.dart and alpha/testing.dart still share Shared.
      expect(await check(), isEmpty);
    });

    test('exportOverlaps: three packages, sorted by name', () {
      const a = ExportEntryPoint(package: 'a', path: 'packages/a/lib/a.dart');
      const b = ExportEntryPoint(package: 'b', path: 'packages/b/lib/b.dart');
      const c = ExportEntryPoint(package: 'c', path: 'packages/c/lib/c.dart');
      final v = exportOverlaps({
        c: {'Z', 'Y'},
        b: {'Z', 'X'},
        a: {'Y', 'Z', 'W'},
      });
      expect(
        [for (final r in v) r.message],
        ['Y: a/a.dart & c/c.dart', 'Z: a/a.dart & b/b.dart & c/c.dart'],
      );
      expect({for (final r in v) r.path}, {'packages/a/lib/a.dart'});
    });
  });

  group('resolution failures', () {
    test('an unresolvable export: the resolver exits 3 and ws check exits '
        '3', () async {
      fixture.write(
        'packages/gamma/lib/gamma.dart',
        "export 'package:missing/missing.dart';\n",
      );
      final out = StringBuffer();
      final err = StringBuffer();
      final reportFile = p.join(fixture.root, 'out', 'r14.json');
      final code = await exportNamesMain(
        [
          '--out',
          reportFile,
          p.join(fixture.root, 'packages/gamma/lib/gamma.dart'),
          p.join(fixture.root, 'packages/beta/lib/beta.dart'),
        ],
        out: out,
        err: err,
      );
      expect(code, exportNamesUnresolvedExitCode);
      expect(code, environmentExitCode);
      final report = ExportNamesReport.decode(
        File(reportFile).readAsStringSync(),
      );
      expect(report.unresolved.keys.single, endsWith('gamma.dart'));
      expect(report.unresolved.values.single, contains('uri_does_not_exist'));
      expect(report.names.keys.single, endsWith('beta.dart'));
      expect(err.toString(), contains('cannot resolve'));

      final wsErr = StringBuffer();
      final wsCode = await runWs(
        ['check', '--no-format'],
        context: WsContext(
          root: fixture.root,
          out: StringBuffer(),
          err: wsErr,
          processes: _InProcessResolver(),
        ),
      );
      expect(wsCode, environmentExitCode);
      expect(wsErr.toString(), contains('R14 cannot resolve 1 entry point'));
      expect(wsErr.toString(), contains('packages/gamma/lib/gamma.dart'));
    });

    test('a missing entry file or a part file is unresolved', () async {
      fixture
        ..write('packages/gamma/lib/part.dart', "part of 'gamma.dart';\n")
        ..write(
          'packages/gamma/lib/gamma.dart',
          "part 'part.dart';\n\nclass Gamma {}\n",
        );
      final part = p.join(fixture.root, 'packages/gamma/lib/part.dart');
      final none = p.join(fixture.root, 'packages/gamma/lib/none.dart');
      final report = await resolveExportNames([part, none]);
      expect(report.unresolved, {
        part: 'a part file, not a library',
        none: 'file not found',
      });
      expect(report.names, isEmpty);
    });

    test('resolver process problems are environment errors', () async {
      Future<Object?> failure(RunResult Function(FakeCall) handler) async {
        try {
          await check(FakeProcesses(handler));
          return null;
        } on ExportNamesException catch (e) {
          return e.message;
        }
      }

      // Crashed before writing its report.
      expect(
        await failure((_) => const RunResult(exitCode: 255, output: 'boom')),
        allOf(contains('exit code 255'), contains('boom')),
      );
      // Killed at its time limit.
      expect(
        await failure((_) => const RunResult(exitCode: -9, timedOut: true)),
        contains('timed out after ${exportNamesTimeout.inMinutes} min'),
      );
      // Garbage instead of the JSON report.
      expect(
        await failure((call) {
          File(call.arguments[3]).writeAsStringSync('not json');
          return const RunResult(exitCode: 0);
        }),
        contains('not JSON'),
      );
      // A report without one of the entry points.
      expect(
        await failure((call) {
          File(call.arguments[3]).writeAsStringSync(
            const ExportNamesReport(names: {}, unresolved: {}).encode(),
          );
          return const RunResult(exitCode: 0);
        }),
        contains('no names for packages/alpha/lib/alpha.dart'),
      );
      // No resolver script in the workspace.
      fixture.delete(exportNamesScript);
      expect(
        await failure((_) => const RunResult(exitCode: 0)),
        allOf(contains('not found'), contains('--no-exports')),
      );
    });
  });

  group('ws check', () {
    test(
      'runs R14 through the resolver script and fails on the overlap',
      () async {
        final processes = _InProcessResolver();
        final out = StringBuffer();
        final code = await runWs(
          ['check', '--no-format'],
          context: WsContext(
            root: fixture.root,
            out: out,
            err: StringBuffer(),
            processes: processes,
          ),
        );
        expect(code, 1);
        expect(processes.calls, hasLength(1));
        final args = processes.calls.single;
        expect(args.sublist(0, 3), ['run', exportNamesScript, '--out']);
        expect(args.sublist(4), [
          for (final e in exportEntryPoints(fixture.load(), rules))
            p.join(fixture.root, e.path),
        ]);
        expect(
          out.toString(),
          contains('packages/alpha/lib/alpha.dart:1: [R14] Shared: '),
        );
        expect(out.toString(), contains('R13, R14, R15): 1 violation(s)'));
      },
    );

    test('--no-exports skips R14 (no resolver process)', () async {
      final processes = _InProcessResolver();
      final out = StringBuffer();
      final code = await runWs(
        ['check', '--no-format', '--no-exports'],
        context: WsContext(
          root: fixture.root,
          out: out,
          err: StringBuffer(),
          processes: processes,
        ),
      );
      expect(code, 0);
      expect(processes.calls, isEmpty);
      expect(out.toString(), contains('R13, R15): 0 violation(s)'));
    });

    test('implementedRules lists R1-R15', () {
      expect(implementedRules, [for (var i = 1; i <= 15; i++) 'R$i']);
    });
  });

  test('the real script: `dart run tool/export_names.dart` exits 3 on an '
      'unresolvable entry point and 0 otherwise', () async {
    fixture.write(
      'packages/gamma/lib/broken.dart',
      "export 'package:missing/missing.dart';\n",
    );
    Future<(int, ExportNamesReport)> run(List<String> entries) async {
      final out = p.join(fixture.root, 'out.json');
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        p.join(repoRoot, exportNamesScript),
        '--out',
        out,
        for (final e in entries) p.join(fixture.root, e),
      ], workingDirectory: repoRoot);
      return (
        result.exitCode,
        ExportNamesReport.decode(File(out).readAsStringSync()),
      );
    }

    final (bad, badReport) = await run(['packages/gamma/lib/broken.dart']);
    expect(bad, exportNamesUnresolvedExitCode);
    expect(badReport.unresolved, hasLength(1));
    final (good, goodReport) = await run(['packages/beta/lib/beta.dart']);
    expect(good, 0);
    expect(goodReport.names.values.single, contains('Shared'));
  }, tags: ['process']);
}
