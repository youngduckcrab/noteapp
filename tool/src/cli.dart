/// Command line of `dart run tool/ws.dart` (docs/plans/01-infra.md 4.2).
///
/// Foundation step B1 commands: `list`, `check` (R1–R3, R7–R9, R15),
/// `test` (vm / chrome) and `analyze`. The remaining commands of 4.2
/// (`affected`, `channel-id`, `build-info`, `finalize-web`, `web-assets`,
/// `hosting-config`) and the other rules come with I1.
///
/// Exit codes: 0 success, 1 check / test failure, 2 usage error, 3
/// environment error (no workspace, flutter or Chrome not found).
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'flutter_runner.dart';
import 'rules.dart';
import 'test_command.dart';
import 'workspace.dart';

/// Exit code for usage errors.
const int usageExitCode = 2;

/// Exit code for environment errors.
const int environmentExitCode = 3;

/// Everything `ws` reads from its surroundings, injectable for tests.
final class WsContext {
  WsContext({
    this.root,
    StringSink? out,
    StringSink? err,
    Map<String, String>? environment,
    ProcessRunner? processes,
    String? resolvedExecutable,
    bool Function(String path)? isFile,
    String? workingDirectory,
  }) : out = out ?? stdout,
       err = err ?? stderr,
       environment = environment ?? Platform.environment,
       resolvedExecutable = resolvedExecutable ?? Platform.resolvedExecutable,
       isFile = isFile ?? ((path) => File(path).existsSync()),
       workingDirectory = workingDirectory ?? Directory.current.path,
       processes = processes ?? IoProcessRunner(out: out ?? stdout);

  /// Workspace root; `null` = search upwards from [workingDirectory].
  final String? root;

  final StringSink out;
  final StringSink err;
  final Map<String, String> environment;

  /// The running Dart VM (also used to run preparation scripts).
  final String resolvedExecutable;

  final bool Function(String path) isFile;
  final String workingDirectory;

  /// Runs `flutter` / `dart` (real processes unless a test injects a fake).
  final ProcessRunner processes;
}

final class _EnvironmentError implements Exception {
  const _EnvironmentError(this.message);

  final String message;
}

/// Runs `ws` with [arguments] and returns the exit code.
Future<int> runWs(List<String> arguments, {WsContext? context}) async {
  final ctx = context ?? WsContext();
  final runner =
      CommandRunner<int>(
          'ws',
          'Workspace tool of the note app (docs/plans/01-infra.md 4.2).',
        )
        ..argParser.addOption(
          'root',
          help:
              'Workspace root (default: nearest parent with a workspace '
              'pubspec.yaml).',
          valueHelp: 'dir',
        )
        ..addCommand(_ListCommand(ctx))
        ..addCommand(_CheckCommand(ctx))
        ..addCommand(_TestCommand(ctx))
        ..addCommand(_AnalyzeCommand(ctx));
  try {
    final code = await runner.run(arguments);
    return code ?? 0;
  } on UsageException catch (e) {
    ctx.err
      ..writeln(e.message)
      ..writeln()
      ..writeln(e.usage);
    return usageExitCode;
  } on _EnvironmentError catch (e) {
    ctx.err.writeln('ws: ${e.message}');
    return environmentExitCode;
  } on WorkspaceException catch (e) {
    ctx.err.writeln('ws: ${e.message}');
    return environmentExitCode;
  } on RulesFormatException catch (e) {
    ctx.err.writeln('ws: ${e.message}');
    return environmentExitCode;
  }
}

abstract base class _WsCommand extends Command<int> {
  _WsCommand(this.ctx);

  final WsContext ctx;

  String get root {
    final explicit = globalResults?['root'] as String? ?? ctx.root;
    if (explicit != null) return p.normalize(p.absolute(explicit));
    final found = Workspace.findRoot(ctx.workingDirectory);
    if (found == null) {
      throw _EnvironmentError(
        'no workspace pubspec.yaml found at or above ${ctx.workingDirectory}',
      );
    }
    return found;
  }

  Workspace loadWorkspace() => Workspace.load(root);

  String requireFlutter() {
    final flutter = locateFlutter(
      environment: ctx.environment,
      resolvedExecutable: ctx.resolvedExecutable,
      isFile: ctx.isFile,
      windows: Platform.isWindows,
    );
    if (flutter == null) {
      throw const _EnvironmentError(
        'flutter not found (set FLUTTER_BIN or FLUTTER_ROOT, or add it to '
        'PATH)',
      );
    }
    return flutter;
  }

  void rejectRest() {
    final rest = argResults!.rest;
    if (rest.isNotEmpty) usageException('Unexpected arguments: $rest');
  }
}

final class _ListCommand extends _WsCommand {
  _ListCommand(super.ctx);

  @override
  String get name => 'list';

  @override
  String get description =>
      'List the workspace members in topological order (dependencies first).';

  @override
  Future<int> run() async {
    rejectRest();
    final members = loadWorkspace().topologicalOrder();
    final width = members.fold(
      0,
      (w, m) => m.name.length > w ? m.name.length : w,
    );
    for (final member in members) {
      ctx.out.writeln('${member.name.padRight(width)}  ${member.path}');
    }
    return 0;
  }
}

final class _CheckCommand extends _WsCommand {
  _CheckCommand(super.ctx) {
    argParser
      ..addFlag(
        'strict',
        negatable: false,
        help:
            'Treat warnings (R9w: external dependency not in '
            'pinned_external) as violations.',
      )
      ..addOption(
        'rules',
        help: 'Rules file (default: <root>/tool/workspace_rules.yaml).',
        valueHelp: 'file',
      );
  }

  @override
  String get name => 'check';

  @override
  String get description =>
      'Check the workspace rules (${implementedRules.join(', ')}).';

  @override
  Future<int> run() async {
    rejectRest();
    final strict = argResults!['strict'] as bool;
    final workspace = loadWorkspace();
    final rulesPath =
        argResults!['rules'] as String? ??
        p.join(workspace.root, 'tool', 'workspace_rules.yaml');
    final rules = WorkspaceRules.load(rulesPath);
    final results = checkWorkspace(workspace, rules);
    final violations = [
      for (final r in results)
        if (!r.isWarning || strict) r,
    ];
    final warnings = [
      for (final r in results)
        if (r.isWarning && !strict) r,
    ];
    for (final r in violations) {
      ctx.out.writeln(r.format());
    }
    for (final r in warnings) {
      ctx.out.writeln('${r.format()} (warning)');
    }
    ctx.out.writeln(
      'ws check (${implementedRules.join(', ')}${strict ? ', strict' : ''}): '
      '${violations.length} violation(s), ${warnings.length} warning(s)',
    );
    return violations.isEmpty ? 0 : 1;
  }
}

final class _TestCommand extends _WsCommand {
  _TestCommand(super.ctx) {
    argParser
      ..addMultiOption(
        'package',
        help: 'Only test this member (repeatable).',
        valueHelp: 'name',
      )
      ..addOption(
        'platform',
        allowed: ['vm', 'chrome'],
        defaultsTo: 'vm',
        help:
            'vm: test/ outside test/web/. chrome: test/web/ of members '
            'that have it (runs tool/prepare_web_test.dart first).',
      )
      ..addMultiOption(
        'tags',
        abbr: 't',
        help: 'Run only tests with this tag (repeatable).',
        valueHelp: 'tag',
      )
      ..addMultiOption(
        'exclude-tags',
        abbr: 'x',
        help: 'Skip tests with this tag (repeatable, default: bench).',
        valueHelp: 'tag',
      )
      ..addFlag(
        'run-skipped',
        negatable: false,
        help: 'Also run tests skipped by default (integration stage).',
      )
      ..addOption(
        'reporter',
        help: 'Reporter passed to flutter test.',
        valueHelp: 'name',
      );
  }

  @override
  String get name => 'test';

  @override
  String get description =>
      'Run `flutter test` in every member directory (contract 7.4.8).';

  @override
  Future<int> run() async {
    rejectRest();
    final args = argResults!;
    final excluded = args['exclude-tags'] as List<String>;
    final options = TestOptions(
      packages: args['package'] as List<String>,
      platform: args['platform'] == 'chrome'
          ? TestPlatform.chrome
          : TestPlatform.vm,
      tags: args['tags'] as List<String>,
      excludeTags: args.wasParsed('exclude-tags') ? excluded : null,
      runSkipped: args['run-skipped'] as bool,
      reporter: args['reporter'] as String?,
    );
    final workspace = loadWorkspace();
    final TestPlan plan;
    try {
      plan = buildTestPlan(workspace, options);
    } on UnknownPackageException catch (e) {
      usageException(e.toString());
    }
    if (plan.targets.isEmpty) {
      ctx.out
        ..writeln(formatTestSummary(const [], plan))
        ..writeln('ws test: nothing to run for ${plan.platform.name}');
      return 0;
    }
    final flutter = requireFlutter();
    String? chrome;
    if (plan.platform == TestPlatform.chrome) {
      chrome = locateChrome(
        environment: ctx.environment,
        isFile: ctx.isFile,
        windows: Platform.isWindows,
      );
      if (chrome == null) {
        throw _EnvironmentError(
          'Chrome not found: set CHROME_EXECUTABLE or put one of '
          '${chromeExecutableNames.join(', ')} on PATH',
        );
      }
    }
    final runner = TestRunner(
      processes: ctx.processes,
      flutter: flutter,
      dart: ctx.resolvedExecutable,
      chrome: chrome,
      out: ctx.out,
    );
    final results = await runner.run(plan, options);
    ctx.out
      ..writeln()
      ..writeln(formatTestSummary(results, plan));
    return results.any((r) => r.isFailure) ? 1 : 0;
  }
}

final class _AnalyzeCommand extends _WsCommand {
  _AnalyzeCommand(super.ctx);

  @override
  String get name => 'analyze';

  @override
  String get description =>
      'Run `flutter analyze --fatal-infos` at the workspace root.';

  @override
  Future<int> run() async {
    rejectRest();
    final workspaceRoot = loadWorkspace().root;
    final result = await ctx.processes.run(requireFlutter(), const [
      'analyze',
      '--fatal-infos',
    ], workingDirectory: workspaceRoot);
    return result.exitCode;
  }
}
