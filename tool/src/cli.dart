/// Command line of `dart run tool/ws.dart` (docs/plans/01-infra.md 4.2,
/// docs/plans/m5-7/01-infra.md 4.2).
///
/// Commands: `list`, `check` (R1–R16; R14 since the integration step G3,
/// R16 since the 2차 step R2-B1), `analyze`, `test` (vm / chrome,
/// `--affected-since`, `--all-if-no-base`, the heavy test lock and the fake
/// media Chrome for `media`), `with-heavy-lock`, `native-reqs` (NR1–NR7,
/// 2차 J1), `web-budget measure|check` (2차 J17), `lock-age` (2차 J20),
/// `affected`, `channel-id`, `build-info`, `finalize-web`,
/// `web-assets verify|fetch` and `hosting-config`.
///
/// Exit codes: 0 success, 1 check / test failure, 2 usage error, 3
/// environment error (no workspace, flutter, git or Chrome not found, no
/// base for `--affected-since` without `--all-if-no-base`), 4 the heavy test
/// lock did not come free in time, 130 / 143 stopped by SIGINT / SIGTERM.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'affected.dart';
import 'build_info_file.dart';
import 'channel_id.dart';
import 'export_names.dart';
import 'flutter_runner.dart';
import 'heavy_lock.dart';
import 'hosting_config.dart';
import 'lock_age.dart';
import 'native_config.dart';
import 'native_reqs.dart';
import 'rules.dart';
import 'test_command.dart';
import 'web_assets.dart';
import 'web_budget.dart';
import 'web_finalize.dart';
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
    Downloader? download,
    DateTime Function()? now,
    HeavyLocker? heavyLocker,
  }) : out = out ?? stdout,
       err = err ?? stderr,
       environment = environment ?? Platform.environment,
       resolvedExecutable = resolvedExecutable ?? Platform.resolvedExecutable,
       isFile = isFile ?? ((path) => File(path).existsSync()),
       workingDirectory = workingDirectory ?? Directory.current.path,
       download = download ?? httpDownload,
       now = now ?? DateTime.now,
       heavyLocker = heavyLocker ?? HeavyLocker(),
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

  /// Runs `flutter` / `dart` / `git` (real processes unless a test injects
  /// a fake).
  final ProcessRunner processes;

  /// Downloads for `web-assets fetch`.
  final Downloader download;

  /// Clock for `build-info`.
  final DateTime Function() now;

  /// Takes the heavy test lock (`ws test`, `ws with-heavy-lock`).
  final HeavyLocker heavyLocker;
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
        ..addCommand(_WithHeavyLockCommand(ctx))
        ..addCommand(_AnalyzeCommand(ctx))
        ..addCommand(_NativeReqsCommand(ctx))
        ..addCommand(_AffectedCommand(ctx))
        ..addCommand(_ChannelIdCommand(ctx))
        ..addCommand(_BuildInfoCommand(ctx))
        ..addCommand(_FinalizeWebCommand(ctx))
        ..addCommand(_WebAssetsCommand(ctx))
        ..addCommand(_WebBudgetCommand(ctx))
        ..addCommand(_LockAgeCommand(ctx))
        ..addCommand(_HostingConfigCommand(ctx));
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
  } on AffectedException catch (e) {
    ctx.err.writeln('ws: ${e.message}');
    return environmentExitCode;
  } on WebAssetsFormatException catch (e) {
    ctx.err.writeln('ws: ${e.message}');
    return environmentExitCode;
  } on HostingConfigException catch (e) {
    ctx.err.writeln('ws: ${e.message}');
    return environmentExitCode;
  } on ExportNamesException catch (e) {
    ctx.err.writeln('ws: ${e.message}');
    return environmentExitCode;
  } on NativeReqsException catch (e) {
    ctx.err.writeln('ws: ${e.message}');
    return environmentExitCode;
  } on NativeConfigException catch (e) {
    ctx.err.writeln('ws: ${e.message}');
    return environmentExitCode;
  } on WebBudgetException catch (e) {
    ctx.err.writeln('ws: ${e.message}');
    return environmentExitCode;
  } on LockAgeException catch (e) {
    ctx.err.writeln('ws: ${e.message}');
    return environmentExitCode;
  } on _HeavyLockTimeout catch (e) {
    ctx.err.writeln('ws: ${e.message}');
    return heavyLockTimeoutExitCode;
  }
}

final class _HeavyLockTimeout implements Exception {
  const _HeavyLockTimeout(this.message);

  final String message;
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

  String requireGit() {
    final git = findOnPath(
      'git',
      environment: ctx.environment,
      isFile: ctx.isFile,
      windows: Platform.isWindows,
    );
    if (git == null) throw const _EnvironmentError('git not found on PATH');
    return git;
  }

  /// [path] resolved against the working directory.
  String resolvePath(String path) =>
      p.normalize(p.join(ctx.workingDirectory, path));

  void rejectRest() {
    final rest = argResults!.rest;
    if (rest.isNotEmpty) usageException('Unexpected arguments: $rest');
  }

  /// Minutes of the option [name] (`null` when not given).
  Duration? minutesOption(String name) {
    final text = argResults![name] as String?;
    if (text == null) return null;
    final minutes = num.tryParse(text);
    if (minutes == null || minutes < 0) {
      usageException('--$name must be a number of minutes, got `$text`');
    }
    return Duration(milliseconds: (minutes * 60000).round());
  }

  /// Takes the heavy test lock for [command] (docs/plans/m5-7/01-infra.md
  /// 6.13). Throws [_HeavyLockTimeout] (exit code 4) after [timeout].
  Future<HeavyLockLease> takeHeavyLock(String command, Duration timeout) async {
    final path = heavyLockPath(ctx.environment);
    final lease = await ctx.heavyLocker.acquire(
      path: path,
      command: command,
      timeout: timeout,
      log: ctx.out,
    );
    if (lease == null) {
      throw _HeavyLockTimeout(
        'the heavy test lock $path did not come free within '
        '${timeout.inMinutes} min (another media / emulator / full Chrome '
        'run is going on — see the lock file and $heavyLockLogName)',
      );
    }
    return lease;
  }

  /// The members changed since [ref] (see `affectedMembers`).
  Future<List<WorkspaceMember>> affectedSince(
    Workspace workspace,
    String ref,
  ) async {
    final rules = WorkspaceRules.load(
      p.join(workspace.root, 'tool', 'workspace_rules.yaml'),
    );
    final changed = await changedPathsSince(
      ref,
      processes: ctx.processes,
      git: requireGit(),
      root: workspace.root,
    );
    return affectedMembers(workspace, changed, rules.globalTriggers);
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
      ..addFlag(
        'format',
        defaultsTo: true,
        help: 'Run the format rule R11 (`dart format`).',
      )
      ..addFlag(
        'exports',
        defaultsTo: true,
        help:
            'Run the export name rule R14 (resolves the package entry points '
            'with package:analyzer in `dart run tool/export_names.dart`, '
            'about a minute; exit code 3 when they cannot be resolved).',
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
    final format = argResults!['format'] as bool;
    final exports = argResults!['exports'] as bool;
    final results = [
      ...checkWorkspace(workspace, rules),
      if (format)
        ...await checkFormat(
          workspace,
          rules,
          processes: ctx.processes,
          dart: ctx.resolvedExecutable,
        ),
      if (exports)
        ...await checkExports(
          workspace,
          rules,
          processes: ctx.processes,
          dart: ctx.resolvedExecutable,
        ),
    ]..sort();
    final checked = [
      for (final rule in implementedRules)
        if ((format || rule != 'R11') && (exports || rule != 'R14')) rule,
    ];
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
      'ws check (${checked.join(', ')}${strict ? ', strict' : ''}): '
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
        'affected-since',
        help:
            'Only test members changed since this git ref, and their '
            'dependents (see `ws affected`).',
        valueHelp: 'git-ref',
      )
      ..addFlag(
        'all-if-no-base',
        negatable: false,
        help:
            'With --affected-since: when the ref names no commit or has no '
            'merge base with HEAD, test every member (or the --package '
            'ones) instead of failing with exit code 3.',
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
      )
      ..addOption(
        'member-timeout',
        help:
            "Time limit of one member's flutter test run; a run over it is "
            'killed (with its Chrome) and started once more. Default: '
            '${defaultChromeMemberTimeout.inMinutes} for chrome, none for vm; '
            '0 = none.',
        valueHelp: 'minutes',
      )
      ..addFlag(
        'heavy-lock',
        defaultsTo: true,
        help:
            'Take the container-wide heavy test lock ($defaultHeavyLockPath, '
            '\$$heavyLockPathVariable) for media / emulator runs and full '
            'Chrome runs (no --package), for the whole run including '
            'retries. Not taken when \$$heavyLockHeldVariable=1.',
      )
      ..addOption(
        'heavy-lock-timeout',
        help:
            'How long to wait for the heavy test lock (default '
            '${defaultHeavyLockTimeout.inMinutes}); exit code '
            '$heavyLockTimeoutExitCode when it does not come free.',
        valueHelp: 'minutes',
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
    final workspace = loadWorkspace();
    final since = args['affected-since'] as String?;
    final allIfNoBase = args['all-if-no-base'] as bool;
    if (allIfNoBase && since == null) {
      usageException('--all-if-no-base needs --affected-since');
    }
    var packages = args['package'] as List<String>;
    final packagesChosen = packages.isNotEmpty;
    List<String>? affected;
    if (since != null) {
      try {
        affected = [
          for (final m in await affectedSince(workspace, since)) m.name,
        ];
      } on MissingBaseException catch (e) {
        if (!allIfNoBase) rethrow;
        ctx.out.writeln(
          'ws test: ${e.message}; testing '
          '${packages.isEmpty ? 'every member' : packages.join(', ')} '
          '(--all-if-no-base)',
        );
      }
    }
    if (affected != null) {
      ctx.out.writeln(
        'ws test: affected since $since: '
        '${affected.isEmpty ? '(none)' : affected.join(', ')}',
      );
      final unknown = [
        for (final name in packages)
          if (workspace.memberNamed(name) == null) name,
      ];
      if (unknown.isNotEmpty) {
        usageException(
          UnknownPackageException(unknown, [
            for (final m in workspace.members) m.name,
          ]).toString(),
        );
      }
      packages = packages.isEmpty
          ? affected
          : [
              for (final name in packages)
                if (affected.contains(name)) name,
            ];
      if (packages.isEmpty) {
        ctx.out.writeln('ws test: nothing affected, nothing to run');
        return 0;
      }
    }
    final memberTimeout = minutesOption('member-timeout');
    final lockTimeout =
        minutesOption('heavy-lock-timeout') ?? defaultHeavyLockTimeout;
    final options = TestOptions(
      memberTimeout: memberTimeout,
      packages: packages,
      platform: args['platform'] == 'chrome'
          ? TestPlatform.chrome
          : TestPlatform.vm,
      tags: args['tags'] as List<String>,
      excludeTags: args.wasParsed('exclude-tags') ? excluded : null,
      runSkipped: args['run-skipped'] as bool,
      reporter: args['reporter'] as String?,
    );
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
    final environment = <String, String>{};
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
      if (options.usesFakeMediaChrome) {
        // contract 7.4.6 v2.1 (CP10): media tests always get the fake
        // microphone; areas never set CHROME_EXECUTABLE themselves.
        final wrapper = p.join(workspace.root, chromeFakeMediaPath);
        if (!ctx.isFile(wrapper)) {
          throw _EnvironmentError(
            '$chromeFakeMediaPath not found (needed for -t media)',
          );
        }
        // A CHROME_EXECUTABLE that already is the wrapper would make it
        // start itself; it then searches PATH on its own.
        if (!p.equals(chrome, wrapper)) {
          environment[realChromeVariable] = chrome;
        }
        chrome = wrapper;
      }
    }

    final heavy = options.isHeavy(packagesChosen: packagesChosen);
    final lockByParent = heavyLockHeldByParent(ctx.environment);
    HeavyLockLease? lease;
    if (heavy && !lockByParent && args['heavy-lock'] as bool) {
      lease = await takeHeavyLock(
        'ws test ${[...?argResults?.arguments].join(' ')}',
        lockTimeout,
      );
    }
    if (lease != null || (heavy && lockByParent)) {
      environment[heavyLockHeldVariable] = '1';
    }
    try {
      final runner = TestRunner(
        processes: ctx.processes,
        flutter: flutter,
        dart: ctx.resolvedExecutable,
        chrome: chrome,
        out: ctx.out,
        environment: environment,
      );
      final results = await runner.run(plan, options);
      ctx.out
        ..writeln()
        ..writeln(formatTestSummary(results, plan));
      if (lease != null) {
        ctx.out.writeln(
          'ws test: heavy test lock waited ${lease.waited.inSeconds}s '
          '(잠금 대기 ${lease.waited.inSeconds}초)',
        );
      } else if (heavy && lockByParent) {
        ctx.out.writeln(
          'ws test: heavy test lock held by the caller '
          '($heavyLockHeldVariable=1)',
        );
      }
      return results.any((r) => r.isFailure) ? 1 : 0;
    } finally {
      lease?.release();
    }
  }
}

final class _WithHeavyLockCommand extends _WsCommand {
  _WithHeavyLockCommand(super.ctx) {
    argParser.addOption(
      'timeout',
      help:
          'How long to wait for the lock (default '
          '${defaultHeavyLockTimeout.inMinutes}); exit code '
          '$heavyLockTimeoutExitCode when it does not come free.',
      valueHelp: 'minutes',
    );
  }

  @override
  String get name => 'with-heavy-lock';

  @override
  String get invocation =>
      'ws with-heavy-lock [--timeout <minutes>] -- <command> [arguments]';

  @override
  String get description =>
      'Run a command under the container-wide heavy test lock '
      '($defaultHeavyLockPath, \$$heavyLockPathVariable) with '
      '$heavyLockHeldVariable=1, and return its exit code (contract 7.4.6 — '
      'npm / shell scripts; a `ws test` inside does not take the lock again).';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) usageException('missing the command after `--`');
    final timeout = minutesOption('timeout') ?? defaultHeavyLockTimeout;
    final lease = heavyLockHeldByParent(ctx.environment)
        ? null
        : await takeHeavyLock(
            'ws with-heavy-lock -- ${rest.join(' ')}',
            timeout,
          );
    try {
      final result = await ctx.processes.run(
        rest.first,
        rest.sublist(1),
        workingDirectory: ctx.workingDirectory,
        environment: const {heavyLockHeldVariable: '1'},
      );
      // A child ended by a signal: report it the shell way (128 + n).
      return result.exitCode < 0 ? 128 - result.exitCode : result.exitCode;
    } finally {
      lease?.release();
    }
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

final class _AffectedCommand extends _WsCommand {
  _AffectedCommand(super.ctx) {
    argParser.addOption(
      'since',
      help: 'Git ref to compare with (its merge base with HEAD).',
      valueHelp: 'git-ref',
    );
  }

  @override
  String get name => 'affected';

  @override
  String get description =>
      'List the members changed since a git ref and their dependents, in '
      'topological order.';

  @override
  Future<int> run() async {
    rejectRest();
    final since = argResults!['since'] as String?;
    if (since == null || since.isEmpty) usageException('--since is required');
    final workspace = loadWorkspace();
    for (final member in await affectedSince(workspace, since)) {
      ctx.out.writeln('${member.name}  ${member.path}');
    }
    return 0;
  }
}

final class _ChannelIdCommand extends _WsCommand {
  _ChannelIdCommand(super.ctx) {
    argParser.addOption(
      'branch',
      help: 'Branch name (refs/heads/ prefix allowed).',
      valueHelp: 'name',
    );
  }

  @override
  String get name => 'channel-id';

  @override
  String get description =>
      'Print the Firebase Hosting preview channel id of a branch (6.12).';

  @override
  Future<int> run() async {
    rejectRest();
    final branch = (argResults!['branch'] as String?)?.trim() ?? '';
    if (branch.isEmpty || branch == 'refs/heads/') {
      usageException('--branch is required');
    }
    ctx.out.writeln(previewChannelId(branch));
    return 0;
  }
}

final class _BuildInfoCommand extends _WsCommand {
  _BuildInfoCommand(super.ctx) {
    argParser
      ..addOption(
        'out',
        help: 'File to write (e.g. build/build_info.json).',
        valueHelp: 'file',
      )
      ..addOption(
        'channel',
        allowed: buildChannels,
        defaultsTo: 'local',
        help: 'Build channel.',
      )
      ..addOption(
        'version',
        help: 'App version x.y.z (default: the version of app/pubspec.yaml).',
        valueHelp: 'x.y.z',
      );
  }

  @override
  String get name => 'build-info';

  @override
  String get description =>
      'Write the build info JSON (APP_* values from GITHUB_SHA, '
      'GITHUB_REF_NAME, GITHUB_RUN_NUMBER; `local` without them).';

  @override
  Future<int> run() async {
    rejectRest();
    final args = argResults!;
    final out = args['out'] as String?;
    if (out == null || out.isEmpty) usageException('--out is required');
    final Map<String, String> values;
    try {
      final version =
          args['version'] as String? ??
          appVersionFromPubspec(p.join(root, 'app', 'pubspec.yaml'));
      values = buildInfoValues(
        channel: args['channel'] as String,
        version: version,
        environment: ctx.environment,
        now: ctx.now(),
      );
    } on BuildInfoException catch (e) {
      usageException(e.message);
    }
    final file = File(resolvePath(out));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(encodeBuildInfo(values));
    ctx.out.writeln(
      'ws build-info: wrote ${file.path} (${values['APP_CHANNEL']}, '
      '${values['APP_VERSION']} #${values['APP_BUILD_NUMBER']}, '
      '${values['APP_GIT_SHA']})',
    );
    return 0;
  }
}

final class _FinalizeWebCommand extends _WsCommand {
  _FinalizeWebCommand(super.ctx) {
    argParser
      ..addOption(
        'build-dir',
        help: 'Web build directory (default: <root>/app/build/web).',
        valueHelp: 'dir',
      )
      ..addOption(
        'info',
        help:
            'Build info JSON written by `ws build-info` (default: '
            '<root>/build/build_info.json).',
        valueHelp: 'file',
      );
  }

  @override
  String get name => 'finalize-web';

  @override
  String get description =>
      'Copy build_info.json into the web build, rename the web app off the '
      'live channel, check the required files and report main.dart.js size.';

  @override
  Future<int> run() async {
    rejectRest();
    final args = argResults!;
    final workspaceRoot = root;
    final buildDir = args['build-dir'] != null
        ? resolvePath(args['build-dir'] as String)
        : p.join(workspaceRoot, 'app', 'build', 'web');
    final info = args['info'] != null
        ? resolvePath(args['info'] as String)
        : p.join(workspaceRoot, 'build', 'build_info.json');
    final manifest = WebAssetsManifest.loadIfExists(
      p.join(workspaceRoot, webAssetsManifestPath),
    );
    final summary = ctx.environment['GITHUB_STEP_SUMMARY'];
    final report = finalizeWeb(
      buildDir: buildDir,
      infoFile: info,
      extraRequiredFiles: [
        for (final asset in manifest?.assets ?? const <WebAsset>[]) asset.path,
      ],
      stepSummaryPath: summary == null || summary.isEmpty ? null : summary,
    );
    for (final line in report.lines) {
      ctx.out.writeln(line);
    }
    for (final problem in report.problems) {
      ctx.out.writeln('finalize-web: $problem');
    }
    ctx.out.writeln(
      report.ok
          ? 'ws finalize-web: ok'
          : 'ws finalize-web: ${report.problems.length} problem(s)',
    );
    return report.ok ? 0 : 1;
  }
}

final class _WebAssetsCommand extends _WsCommand {
  _WebAssetsCommand(super.ctx) {
    addSubcommand(_WebAssetsVerifyCommand(ctx));
    addSubcommand(_WebAssetsFetchCommand(ctx));
  }

  @override
  String get name => 'web-assets';

  @override
  String get description =>
      'Verify or fetch the app/web files listed in tool/web_assets.yaml.';
}

abstract base class _WebAssetsSubcommand extends _WsCommand {
  _WebAssetsSubcommand(super.ctx);

  WebAssetsManifest loadManifest(String workspaceRoot) {
    final path = p.join(workspaceRoot, webAssetsManifestPath);
    final manifest = WebAssetsManifest.loadIfExists(path);
    if (manifest == null) throw _EnvironmentError('$path not found');
    return manifest;
  }
}

final class _WebAssetsVerifyCommand extends _WebAssetsSubcommand {
  _WebAssetsVerifyCommand(super.ctx);

  @override
  String get name => 'verify';

  @override
  String get description =>
      'Check that every asset exists in app/web/ with its size and sha256.';

  @override
  Future<int> run() async {
    rejectRest();
    final workspaceRoot = root;
    final manifest = loadManifest(workspaceRoot);
    final problems = verifyWebAssets(
      manifest,
      p.join(workspaceRoot, appWebDirectory),
    );
    for (final problem in problems) {
      ctx.out.writeln('$appWebDirectory/$problem');
    }
    ctx.out.writeln(
      'ws web-assets verify: ${manifest.assets.length} asset(s), '
      '${problems.length} problem(s)',
    );
    return problems.isEmpty ? 0 : 1;
  }
}

final class _WebAssetsFetchCommand extends _WebAssetsSubcommand {
  _WebAssetsFetchCommand(super.ctx);

  @override
  String get name => 'fetch';

  @override
  String get description =>
      'Download missing or wrong assets; a file is written only when its '
      'size and sha256 match.';

  @override
  Future<int> run() async {
    rejectRest();
    final workspaceRoot = root;
    final manifest = loadManifest(workspaceRoot);
    final results = await fetchWebAssets(
      manifest,
      p.join(workspaceRoot, appWebDirectory),
      download: ctx.download,
    );
    for (final result in results) {
      ctx.out.writeln('$appWebDirectory/$result');
    }
    final failures = results.where((r) => r.isFailure).length;
    ctx.out.writeln(
      'ws web-assets fetch: ${results.length} asset(s), $failures failure(s)',
    );
    return failures == 0 ? 0 : 1;
  }
}

final class _WebBudgetCommand extends _WsCommand {
  _WebBudgetCommand(super.ctx) {
    addSubcommand(_WebBudgetSubcommand(ctx, check: false));
    addSubcommand(_WebBudgetSubcommand(ctx, check: true));
  }

  @override
  String get name => 'web-budget';

  @override
  String get description =>
      'Measure a web build (main.dart.js, startup fonts, report assets) and '
      'check it against $webBudgetPath (docs/plans/m5-7/01-infra.md 6.15).';
}

final class _WebBudgetSubcommand extends _WsCommand {
  _WebBudgetSubcommand(super.ctx, {required this.check}) {
    argParser
      ..addOption(
        'build-dir',
        help: 'Web build directory (default: <root>/app/build/web).',
        valueHelp: 'dir',
      )
      ..addOption(
        'budget',
        help:
            'Budget file (default: <root>/$webBudgetPath; measure uses its '
            'bundles and report assets when it exists).',
        valueHelp: 'file',
      );
  }

  final bool check;

  @override
  String get name => check ? 'check' : 'measure';

  @override
  String get description => check
      ? 'Measure and compare with the limits (null = report only); a '
            'forbidden font family is a violation. Exit 1 on a violation.'
      : 'Print the sizes (also to GITHUB_STEP_SUMMARY). Always exit 0.';

  @override
  Future<int> run() async {
    rejectRest();
    final args = argResults!;
    final workspaceRoot = root;
    final buildDir = args['build-dir'] != null
        ? resolvePath(args['build-dir'] as String)
        : p.join(workspaceRoot, 'app', 'build', 'web');
    final budgetPath = args['budget'] != null
        ? resolvePath(args['budget'] as String)
        : p.join(workspaceRoot, webBudgetPath);
    final budget = check || File(budgetPath).existsSync()
        ? WebBudget.load(budgetPath)
        : const WebBudget();
    final measurement = measureWebBuild(
      buildDir,
      reportAssets: budget.reportAssets,
    );
    final report = webBudgetReport(measurement, budget, check: check);
    final text = report.format(command: name);
    ctx.out.write(text);
    final summary = ctx.environment['GITHUB_STEP_SUMMARY'];
    if (summary != null && summary.isNotEmpty) {
      File(summary).writeAsStringSync(
        '### Web budget ($name)\n\n$text\n',
        mode: FileMode.append,
      );
    }
    return report.violations.isEmpty ? 0 : 1;
  }
}

/// `ws lock-age` (docs/plans/m5-7/01-infra.md 4.2, J20 — P-C, Q8 '경고
/// 단계'): see lock_age.dart. The base lock is `git show <ref>:pubspec.lock`;
/// a ref that is not a commit is a warning (nothing compared, exit 0), a ref
/// without pubspec.lock makes every hosted entry new.
final class _LockAgeCommand extends _WsCommand {
  _LockAgeCommand(super.ctx) {
    argParser
      ..addOption(
        'since',
        help: 'Git ref whose pubspec.lock is the base (required).',
        valueHelp: 'git-ref',
      )
      ..addOption(
        'min-days',
        help: 'Minimum whole days (UTC) between publication and now.',
        valueHelp: 'n',
        defaultsTo: '$defaultLockAgeMinDays',
      )
      ..addOption(
        'now',
        help: 'The day to check against (tests; default: today, UTC).',
        valueHelp: 'YYYY-MM-DD',
      );
  }

  @override
  String get name => 'lock-age';

  @override
  String get description =>
      'Check that every hosted package new or changed in pubspec.lock since '
      'a git ref was published at least --min-days ago (pub API). Exit 1 on '
      'a violation; network errors are warnings.';

  @override
  Future<int> run() async {
    rejectRest();
    final args = argResults!;
    final since = args['since'] as String?;
    if (since == null || since.isEmpty) usageException('--since is required');
    final minDaysText = args['min-days'] as String;
    final minDays = int.tryParse(minDaysText);
    if (minDays == null || minDays < 0) {
      usageException('--min-days must be a whole number, got `$minDaysText`');
    }
    final nowText = args['now'] as String?;
    final DateTime now;
    if (nowText == null) {
      now = ctx.now().toUtc();
    } else {
      final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(nowText);
      final parsed = match == null
          ? null
          : DateTime.utc(
              int.parse(match.group(1)!),
              int.parse(match.group(2)!),
              int.parse(match.group(3)!),
            );
      if (parsed == null || _date(parsed) != nowText) {
        usageException('--now must be YYYY-MM-DD, got `$nowText`');
      }
      now = parsed;
    }
    final workspaceRoot = root;
    final lockFile = File(p.join(workspaceRoot, 'pubspec.lock'));
    if (!lockFile.existsSync()) {
      throw _EnvironmentError('no pubspec.lock at $workspaceRoot');
    }
    final git = requireGit();
    Future<RunResult> runGit(List<String> arguments) => ctx.processes.run(
      git,
      arguments,
      workingDirectory: workspaceRoot,
      echo: false,
    );

    final LockAgeReport report;
    final commit = await runGit([
      'rev-parse',
      '--verify',
      '--quiet',
      '$since^{commit}',
    ]);
    if (commit.exitCode != 0) {
      report = LockAgeReport(
        entries: const [],
        minDays: minDays,
        now: now,
        baseWarning: '`$since` is not a commit',
      );
    } else {
      final exists = await runGit(['cat-file', '-e', '$since:pubspec.lock']);
      String? baseLock;
      if (exists.exitCode == 0) {
        final shown = await runGit(['show', '$since:pubspec.lock']);
        if (shown.exitCode != 0) {
          throw _EnvironmentError(
            '`git show $since:pubspec.lock` failed (exit code '
            '${shown.exitCode}): ${shown.output.trim()}',
          );
        }
        baseLock = shown.output;
      }
      report = await checkLockAge(
        baseLock: baseLock,
        lock: lockFile.readAsStringSync(),
        fetch: ctx.download,
        now: now,
        minDays: minDays,
      );
    }
    final text = report.format(since: since);
    ctx.out.write(text);
    final summary = ctx.environment['GITHUB_STEP_SUMMARY'];
    if (summary != null && summary.isNotEmpty) {
      File(summary).writeAsStringSync(
        '### Lock age (since $since)\n\n$text\n',
        mode: FileMode.append,
      );
    }
    return report.violations.isEmpty ? 0 : 1;
  }

  static String _date(DateTime t) => t.toIso8601String().substring(0, 10);
}

final class _NativeReqsCommand extends _WsCommand {
  _NativeReqsCommand(super.ctx);

  @override
  String get name => 'native-reqs';

  @override
  String get description =>
      'Check the native requirements of the app\'s plugins against the '
      'app\'s native files (NR1–NR7, ${NativeReqsPaths.requirements}). '
      'Needs ${NativeReqsPaths.pluginsDependencies} (flutter pub get). '
      'Exit 1 on a violation; NR4 is a warning.';

  @override
  Future<int> run() async {
    rejectRest();
    final workspaceRoot = root;
    final config = NativeConfig.load(workspaceRoot);
    final report = checkNativeRequirements(
      requirements: NativeRequirements.load(
        p.join(workspaceRoot, NativeReqsPaths.requirements),
      ),
      dependencies: FlutterPluginsDependencies.load(
        p.join(workspaceRoot, NativeReqsPaths.pluginsDependencies),
      ),
      pluginPackages: WorkspaceRules.load(
        p.join(workspaceRoot, 'tool', 'workspace_rules.yaml'),
      ).pluginPackages,
      config: config,
      flutterDefaults: _flutterDefaults(),
      appProblems: appNativeConfigProblems(config),
    );
    ctx.out.write(report.format());
    return report.violations.isEmpty ? 0 : 1;
  }

  /// Flutter's default SDK levels from the Flutter in use (null when it or
  /// its `FlutterExtension.kt` is not found — the requirements file's
  /// `flutter_defaults` then apply).
  ({int minSdk, int compileSdk})? _flutterDefaults() {
    final flutter = locateFlutter(
      environment: ctx.environment,
      resolvedExecutable: ctx.resolvedExecutable,
      isFile: ctx.isFile,
      windows: Platform.isWindows,
    );
    if (flutter == null) return null;
    try {
      final sdkRoot = p.dirname(
        p.dirname(File(flutter).resolveSymbolicLinksSync()),
      );
      final kotlin = File(p.join(sdkRoot, NativeReqsPaths.flutterExtension));
      if (!kotlin.existsSync()) return null;
      return flutterGradleDefaults(kotlin.readAsStringSync());
    } on FileSystemException {
      return null;
    }
  }
}

final class _HostingConfigCommand extends _WsCommand {
  _HostingConfigCommand(super.ctx) {
    argParser.addFlag(
      'isolate',
      negatable: false,
      help:
          'Add Cross-Origin-Opener-Policy / Cross-Origin-Embedder-Policy '
          '(experiment channel only).',
    );
  }

  @override
  String get name => 'hosting-config';

  @override
  String get description =>
      'Check app/firebase.json (6.12) and print it, with --isolate plus '
      'COOP/COEP headers. Exit 1 when the file breaks a 6.12 rule.';

  @override
  Future<int> run() async {
    rejectRest();
    final file = File(p.join(root, hostingConfigPath));
    if (!file.existsSync()) {
      throw _EnvironmentError('${file.path} not found');
    }
    var config = parseHostingConfig(file.readAsStringSync());
    final problems = hostingConfigProblems(
      config,
      appDir: p.dirname(file.path),
    );
    if (problems.isNotEmpty) {
      for (final problem in problems) {
        ctx.err.writeln('$hostingConfigPath: $problem');
      }
      return 1;
    }
    if (argResults!['isolate'] as bool) config = isolatedHostingConfig(config);
    ctx.out.write(encodeHostingConfig(config));
    return 0;
  }
}
