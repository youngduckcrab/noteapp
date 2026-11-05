/// `ws test`: runs `flutter test` in every member directory
/// (docs/plans/01-infra.md 4.2, contract 00-overview 7.4.8).
///
/// - vm: the member's `test/**/*_test.dart` files outside `test/web/`.
/// - chrome: members with a `test/web/` directory only. When the member has
///   `tool/prepare_web_test.dart` it runs first (`dart run`, 5 minutes); if
///   it fails the member is reported as "prepare failed" and its browser
///   tests are skipped.
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

/// Path of the browser test preparation script inside a member.
const String prepareScriptPath = 'tool/prepare_web_test.dart';

/// Exit code of `flutter test` / `dart test` when no test matched.
const int noTestsRanExitCode = 79;

/// Options of `ws test`.
final class TestOptions {
  const TestOptions({
    this.packages = const [],
    this.platform = TestPlatform.vm,
    this.tags = const [],
    this.excludeTags,
    this.runSkipped = false,
    this.reporter,
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

  List<String> get effectiveExcludeTags =>
      excludeTags ?? (tags.contains('bench') ? const [] : const ['bench']);
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
  ...target.paths,
];

/// The outcome of one member.
enum MemberOutcome { passed, failed, noTests, prepareFailed }

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

  bool get isFailure =>
      outcome == MemberOutcome.failed || outcome == MemberOutcome.prepareFailed;
}

/// Reads the final `+passed ~skipped -failed:` counter of a `flutter test`
/// run (compact and expanded reporters). Returns `null` if there is none.
({int passed, int skipped, int failed})? parseTestCounts(String output) {
  final matches = RegExp(r'\+(\d+)(?: ~(\d+))?(?: -(\d+))?: ')
      .allMatches(output);
  if (matches.isEmpty) return null;
  final last = matches.last;
  return (
    passed: int.parse(last.group(1)!),
    skipped: int.parse(last.group(2) ?? '0'),
    failed: int.parse(last.group(3) ?? '0'),
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
  });

  final ProcessRunner processes;

  /// `flutter` executable.
  final String flutter;

  /// `dart` executable (runs the preparation scripts).
  final String dart;

  /// Chrome executable for chrome targets (exported as `CHROME_EXECUTABLE`).
  final String? chrome;

  final StringSink out;

  Future<List<MemberTestResult>> run(TestPlan plan, TestOptions options) async {
    final results = <MemberTestResult>[];
    for (final target in plan.targets) {
      results.add(await _runTarget(target, options));
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
        timeout: prepareTimeout,
      );
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
    out.writeln(
      '== $name (${target.platform.name}): flutter ${arguments.join(' ')}',
    );
    final result = await processes.run(
      flutter,
      arguments,
      workingDirectory: target.member.directory,
      environment: {
        if (target.platform == TestPlatform.chrome && chrome != null)
          'CHROME_EXECUTABLE': chrome!,
      },
    );
    final counts = parseTestCounts(result.output);
    final MemberOutcome outcome;
    if (result.exitCode == 0) {
      outcome = MemberOutcome.passed;
    } else if (result.exitCode == noTestsRanExitCode) {
      outcome = MemberOutcome.noTests;
    } else {
      outcome = MemberOutcome.failed;
    }
    return MemberTestResult(
      member: name,
      platform: target.platform,
      prepare: prepare,
      outcome: outcome,
      elapsed: stopwatch.elapsed,
      passed: counts?.passed ?? 0,
      skipped: counts?.skipped ?? 0,
      failed: counts?.failed ?? (outcome == MemberOutcome.failed ? 1 : 0),
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
          MemberOutcome.passed => 'ok',
          MemberOutcome.failed => 'FAILED',
          MemberOutcome.noTests => 'no matching tests',
          MemberOutcome.prepareFailed => 'PREPARE FAILED',
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
