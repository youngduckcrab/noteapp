/// `ws test`: runs `flutter test` in every member directory
/// (docs/plans/01-infra.md 4.2, contract 00-overview 7.4.8).
///
/// - vm: the member's `test/**/*_test.dart` files outside `test/web/`.
/// - chrome: members with a `test/web/` directory only. When the member has
///   `tool/prepare_web_test.dart` it runs first (`dart run`, 5 minutes); if
///   it fails the member is reported as "prepare failed" and its browser
///   tests are skipped.
///
/// Each member run has a time limit (chrome: [defaultChromeMemberTimeout],
/// vm: none — `--member-timeout`). A run that exceeds it is killed with its
/// process tree and retried once ([timeoutRetries]); a second time-out
/// fails the member and the next member runs. A run ended by a signal from
/// outside (or `ws` itself stopping on SIGINT / SIGTERM) stops `ws test`:
/// the remaining members are listed as not run.
///
/// 2차 (docs/plans/m5-7/01-infra.md 6.13): the command around [TestRunner]
/// may take the heavy test lock (`heavy_lock.dart`) for the whole run —
/// retries included — and swap Chrome for `tool/chrome-fakemedia`
/// ([chromeFakeMediaPath]) for `media`-tagged runs; [TestRunner.environment]
/// carries `NOTEAPP_HEAVY_LOCK_HELD` / `NOTEAPP_REAL_CHROME` to every child.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'flutter_runner.dart';
import 'test_tags.dart';
import 'workspace.dart';

/// Where tests run.
enum TestPlatform { vm, chrome }

/// Time limit of a member's `tool/prepare_web_test.dart`.
const Duration prepareTimeout = Duration(minutes: 5);

/// Default time limit of one member's `flutter test --platform chrome`
/// (the slowest member, ink_engine, takes about 4 minutes on the
/// container; a hung CanvasKit start never ends).
const Duration defaultChromeMemberTimeout = Duration(minutes: 15);

/// How often a member run that exceeded its time limit is started again.
const int timeoutRetries = 1;

/// Path of the browser test preparation script inside a member.
const String prepareScriptPath = 'tool/prepare_web_test.dart';

/// Exit code of `flutter test` / `dart test` when no test matched.
const int noTestsRanExitCode = 79;

/// The Chrome wrapper with a fake microphone / camera, relative to the
/// repository root (contract 7.4.6).
const String chromeFakeMediaPath = 'tool/chrome-fakemedia';

/// Environment variable that tells [chromeFakeMediaPath] which Chrome to
/// start.
const String realChromeVariable = 'NOTEAPP_REAL_CHROME';

/// Tags whose runs take the heavy test lock (contract 7.4.6 v2.1).
const Set<String> heavyTestTags = {'media', 'emulator'};

/// Options of `ws test`.
final class TestOptions {
  const TestOptions({
    this.packages = const [],
    this.platform = TestPlatform.vm,
    this.tags = const [],
    this.excludeTags,
    this.runSkipped = false,
    this.reporter,
    this.memberTimeout,
    this.dartDefines = const [],
  });

  /// Member names to test; empty = every member.
  final List<String> packages;

  final TestPlatform platform;

  /// `--tags` passed to `flutter test`.
  final List<String> tags;

  /// `--exclude-tags`; `null` = the default `bench` (dropped when `bench` is
  /// explicitly selected with [tags]).
  final List<String>? excludeTags;

  /// `--run-skipped` (integration stage: `ws test --run-skipped -t
  /// integration`).
  final bool runSkipped;

  /// `--reporter` passed to `flutter test`.
  final String? reporter;

  /// Time limit of one member's `flutter test` run; `null` = the platform
  /// default ([defaultChromeMemberTimeout] for chrome, none for vm),
  /// [Duration.zero] = none.
  final Duration? memberTimeout;

  /// `KEY=VALUE` pairs passed to every `flutter test` run as
  /// `--dart-define=KEY=VALUE`, in this order (2차 J15 — V15).
  final List<String> dartDefines;

  /// The time limit that applies, `null` = none.
  Duration? get effectiveMemberTimeout {
    final limit =
        memberTimeout ??
        (platform == TestPlatform.chrome ? defaultChromeMemberTimeout : null);
    return limit == null || limit == Duration.zero ? null : limit;
  }

  List<String> get effectiveExcludeTags =>
      excludeTags ?? (tags.contains('bench') ? const [] : const ['bench']);

  /// `media` tests in Chrome: Chrome is started through
  /// [chromeFakeMediaPath].
  bool get usesFakeMediaChrome =>
      platform == TestPlatform.chrome && tags.contains('media');

  /// Whether this run takes the heavy test lock: the `media` / `emulator`
  /// tags, or a Chrome run without `--package` ([packagesChosen] false —
  /// contract 7.4.6 'full Chrome run').
  bool isHeavy({required bool packagesChosen}) =>
      tags.any(heavyTestTags.contains) ||
      (platform == TestPlatform.chrome && !packagesChosen);
}

/// `--package` named a directory that is not a workspace member.
final class UnknownPackageException implements Exception {
  const UnknownPackageException(this.names, this.known);

  final List<String> names;
  final List<String> known;

  @override
  String toString() =>
      'unknown package(s): ${names.join(', ')} (members: ${known.join(', ')})';
}

/// One `flutter test` invocation.
final class TestTarget {
  const TestTarget({
    required this.member,
    required this.platform,
    required this.paths,
    required this.hasPrepareScript,
  });

  final WorkspaceMember member;
  final TestPlatform platform;

  /// Test paths relative to the member directory.
  final List<String> paths;

  /// chrome only: the member has `tool/prepare_web_test.dart`.
  final bool hasPrepareScript;
}

/// A member without tests for the selected platform.
final class SkippedMember {
  const SkippedMember(this.member, this.reason);

  final WorkspaceMember member;
  final String reason;
}

/// What `ws test` will run, in topological member order.
final class TestPlan {
  const TestPlan(this.platform, this.targets, this.skipped);

  final TestPlatform platform;
  final List<TestTarget> targets;
  final List<SkippedMember> skipped;
}

/// Builds the plan for [options]. Throws [UnknownPackageException].
TestPlan buildTestPlan(Workspace workspace, TestOptions options) {
  final ordered = workspace.topologicalOrder();
  final known = [for (final m in ordered) m.name];
  final unknown = [
    for (final name in options.packages)
      if (!known.contains(name)) name,
  ];
  if (unknown.isNotEmpty) throw UnknownPackageException(unknown, known);
  final selected = options.packages.isEmpty
      ? ordered
      : [
          for (final m in ordered)
            if (options.packages.contains(m.name)) m,
        ];

  final targets = <TestTarget>[];
  final skipped = <SkippedMember>[];
  for (final member in selected) {
    final testFiles = [
      for (final file in memberTestFiles(workspace.root, member))
        if (file.endsWith('_test.dart'))
          p.posix.relative(file, from: member.path),
    ];
    switch (options.platform) {
      case TestPlatform.vm:
        final vmFiles = [
          for (final f in testFiles)
            if (!f.startsWith('test/web/')) f,
        ];
        if (vmFiles.isEmpty) {
          skipped.add(SkippedMember(member, 'no VM tests'));
        } else {
          targets.add(
            TestTarget(
              member: member,
              platform: TestPlatform.vm,
              paths: vmFiles,
              hasPrepareScript: false,
            ),
          );
        }
      case TestPlatform.chrome:
        final hasWebTests = testFiles.any((f) => f.startsWith('test/web/'));
        if (!hasWebTests) {
          skipped.add(SkippedMember(member, 'no test/web/'));
        } else {
          targets.add(
            TestTarget(
              member: member,
              platform: TestPlatform.chrome,
              paths: const ['test/web'],
              hasPrepareScript: File(
                p.join(member.directory, prepareScriptPath),
              ).existsSync(),
            ),
          );
        }
    }
  }
  return TestPlan(options.platform, targets, skipped);
}

/// `flutter test` arguments for [target].
List<String> flutterTestArguments(TestTarget target, TestOptions options) => [
  'test',
  if (target.platform == TestPlatform.chrome) ...['--platform', 'chrome'],
  for (final tag in options.tags) ...['--tags', tag],
  for (final tag in options.effectiveExcludeTags) ...['--exclude-tags', tag],
  if (options.runSkipped) '--run-skipped',
  if (options.reporter != null) ...['--reporter', options.reporter!],
  for (final define in options.dartDefines) '--dart-define=$define',
  ...target.paths,
];

/// Whether [value] is a `--dart-define` value: `KEY=VALUE` with a non-empty
/// key without spaces (the value may be empty and hold `=` or commas).
bool isDartDefine(String value) {
  final equals = value.indexOf('=');
  return equals > 0 && !value.substring(0, equals).contains(RegExp(r'\s'));
}

/// The outcome of one member.
enum MemberOutcome {
  passed,
  failed,
  noTests,
  prepareFailed,

  /// Every try exceeded the time limit.
  timedOut,

  /// Stopped by a signal (from outside, or `ws` stopping); `ws test` does
  /// not go on with the next members.
  interrupted,

  /// Not started because an earlier member was [interrupted].
  notRun,
}

/// Result row of the summary table.
final class MemberTestResult {
  const MemberTestResult({
    required this.member,
    required this.platform,
    required this.prepare,
    required this.outcome,
    required this.elapsed,
    this.passed = 0,
    this.failed = 0,
    this.skipped = 0,
    this.tries = 1,
  });

  final String member;
  final TestPlatform platform;

  /// `-` (no script), `ok` or `failed`.
  final String prepare;

  final MemberOutcome outcome;
  final Duration elapsed;
  final int passed;
  final int failed;
  final int skipped;

  /// `flutter test` starts (more than 1 after a time-out).
  final int tries;

  bool get isFailure => switch (outcome) {
    MemberOutcome.passed || MemberOutcome.noTests => false,
    _ => true,
  };
}

/// Reads the final counts of a `flutter test` run: the last
/// `+passed ~skipped -failed:` counter (compact and expanded reporters) or the
/// last closing line of the github reporter — `🎉 7 tests passed, 2 skipped.`
/// or `::error::4 tests passed, 1 failed, 2 skipped.` (`flutter test` picks
/// that reporter by itself on GitHub Actions, so the CI summary table needs
/// it). Whichever comes last in [output] wins. Returns `null` if there is
/// none.
({int passed, int skipped, int failed})? parseTestCounts(String output) {
  final counter = RegExp(r'\+(\d+)(?: ~(\d+))?(?: -(\d+))?: ')
      .allMatches(output)
      .lastOrNull;
  final github = RegExp(
    r'(?:🎉 |::error::)(\d+) tests? passed'
    r'(?:, (\d+) failed)?(?:, (\d+) skipped)?\.',
  ).allMatches(output).lastOrNull;
  if (counter == null && github == null) return null;
  if (github != null && (counter == null || github.start > counter.start)) {
    return (
      passed: int.parse(github.group(1)!),
      skipped: int.parse(github.group(3) ?? '0'),
      failed: int.parse(github.group(2) ?? '0'),
    );
  }
  return (
    passed: int.parse(counter!.group(1)!),
    skipped: int.parse(counter.group(2) ?? '0'),
    failed: int.parse(counter.group(3) ?? '0'),
  );
}

/// Executes a [TestPlan].
final class TestRunner {
  TestRunner({
    required this.processes,
    required this.flutter,
    required this.dart,
    required this.out,
    this.chrome,
    this.environment = const {},
  });

  final ProcessRunner processes;

  /// Added to the environment of every child (preparation scripts and
  /// `flutter test`): `NOTEAPP_HEAVY_LOCK_HELD=1` while `ws` holds the heavy
  /// test lock, `NOTEAPP_REAL_CHROME` for the fake media wrapper.
  final Map<String, String> environment;

  /// `flutter` executable.
  final String flutter;

  /// `dart` executable (runs the preparation scripts).
  final String dart;

  /// Chrome executable for chrome targets (exported as `CHROME_EXECUTABLE`).
  final String? chrome;

  final StringSink out;

  Future<List<MemberTestResult>> run(TestPlan plan, TestOptions options) async {
    final results = <MemberTestResult>[];
    var stopped = false;
    for (final target in plan.targets) {
      if (stopped) {
        results.add(
          MemberTestResult(
            member: target.member.name,
            platform: target.platform,
            prepare: '-',
            outcome: MemberOutcome.notRun,
            elapsed: Duration.zero,
            tries: 0,
          ),
        );
        continue;
      }
      final result = await _runTarget(target, options);
      results.add(result);
      if (result.outcome == MemberOutcome.interrupted) {
        stopped = true;
        out.writeln(
          '== ${result.member}: stopped by a signal — the remaining members '
          'are not run',
        );
      }
    }
    return results;
  }

  Future<MemberTestResult> _runTarget(
    TestTarget target,
    TestOptions options,
  ) async {
    final stopwatch = Stopwatch()..start();
    final name = target.member.name;
    var prepare = '-';
    if (target.hasPrepareScript) {
      out.writeln('== $name: dart run $prepareScriptPath');
      final result = await processes.run(
        dart,
        const ['run', prepareScriptPath],
        workingDirectory: target.member.directory,
        environment: environment,
        timeout: prepareTimeout,
      );
      if (result.interrupted || result.killedBySignal) {
        return MemberTestResult(
          member: name,
          platform: target.platform,
          prepare: 'failed',
          outcome: MemberOutcome.interrupted,
          elapsed: stopwatch.elapsed,
        );
      }
      if (result.exitCode != 0 || result.timedOut) {
        final reason = result.timedOut
            ? 'timed out after ${prepareTimeout.inMinutes} min'
            : 'exit code ${result.exitCode}';
        out.writeln(
          '== $name: prepare failed ($reason) — browser tests skipped',
        );
        return MemberTestResult(
          member: name,
          platform: target.platform,
          prepare: 'failed',
          outcome: MemberOutcome.prepareFailed,
          elapsed: stopwatch.elapsed,
        );
      }
      prepare = 'ok';
    }

    final arguments = flutterTestArguments(target, options);
    final limit = options.effectiveMemberTimeout;
    late RunResult result;
    var tries = 0;
    while (true) {
      tries++;
      out.writeln(
        '== $name (${target.platform.name}'
        '${tries > 1 ? ', try $tries' : ''}): flutter ${arguments.join(' ')}',
      );
      result = await processes.run(
        flutter,
        arguments,
        workingDirectory: target.member.directory,
        environment: {
          ...environment,
          if (target.platform == TestPlatform.chrome && chrome != null)
            'CHROME_EXECUTABLE': chrome!,
        },
        timeout: limit,
      );
      if (!result.timedOut || result.interrupted) break;
      out.writeln(
        '== $name: timed out after ${_minutes(limit!)} — killed'
        '${tries <= timeoutRetries ? ', trying again' : ''}',
      );
      if (tries > timeoutRetries) break;
    }
    final counts = parseTestCounts(result.output);
    final MemberOutcome outcome;
    if (result.interrupted || result.killedBySignal) {
      outcome = MemberOutcome.interrupted;
    } else if (result.timedOut) {
      outcome = MemberOutcome.timedOut;
    } else if (result.exitCode == 0) {
      outcome = MemberOutcome.passed;
    } else if (result.exitCode == noTestsRanExitCode) {
      outcome = MemberOutcome.noTests;
    } else {
      outcome = MemberOutcome.failed;
    }
    final failedRun =
        outcome == MemberOutcome.failed || outcome == MemberOutcome.timedOut;
    return MemberTestResult(
      member: name,
      platform: target.platform,
      prepare: prepare,
      outcome: outcome,
      elapsed: stopwatch.elapsed,
      passed: counts?.passed ?? 0,
      skipped: counts?.skipped ?? 0,
      failed: counts?.failed ?? (failedRun ? 1 : 0),
      tries: tries,
    );
  }
}

/// The summary table printed at the end of `ws test`.
String formatTestSummary(List<MemberTestResult> results, TestPlan plan) {
  const headers = [
    'member',
    'platform',
    'prepare',
    'passed',
    'failed',
    'skipped',
    'time',
    'result',
  ];
  final rows = <List<String>>[
    for (final r in results)
      [
        r.member,
        r.platform.name,
        r.prepare,
        '${r.passed}',
        '${r.failed}',
        '${r.skipped}',
        '${(r.elapsed.inMilliseconds / 1000).toStringAsFixed(1)}s',
        switch (r.outcome) {
          MemberOutcome.passed when r.tries > 1 =>
            'ok (try ${r.tries}, after a time-out)',
          MemberOutcome.passed => 'ok',
          MemberOutcome.failed when r.tries > 1 =>
            'FAILED (try ${r.tries}, after a time-out)',
          MemberOutcome.failed => 'FAILED',
          MemberOutcome.noTests => 'no matching tests',
          MemberOutcome.prepareFailed => 'PREPARE FAILED',
          MemberOutcome.timedOut => 'TIMED OUT (${r.tries} tries)',
          MemberOutcome.interrupted => 'INTERRUPTED',
          MemberOutcome.notRun => 'not run (interrupted)',
        },
      ],
    for (final s in plan.skipped)
      [s.member.name, plan.platform.name, '-', '-', '-', '-', '-', s.reason],
  ];
  final widths = [
    for (var c = 0; c < headers.length; c++)
      [
        headers[c].length,
        for (final row in rows) row[c].length,
      ].reduce((a, b) => a > b ? a : b),
  ];
  String line(List<String> cells) => [
    for (var c = 0; c < cells.length; c++)
      c == cells.length - 1 ? cells[c] : cells[c].padRight(widths[c]),
  ].join('  ');
  final failures = results.where((r) => r.isFailure).length;
  return [
    line(headers),
    for (final row in rows) line(row),
    failures == 0
        ? 'ws test: ${results.length} member run(s), all passed'
        : 'ws test: $failures of ${results.length} member run(s) failed',
  ].join('\n');
}

String _minutes(Duration d) => d.inSeconds % 60 == 0
    ? '${d.inMinutes} min'
    : '${(d.inMilliseconds / 60000).toStringAsFixed(1)} min';
