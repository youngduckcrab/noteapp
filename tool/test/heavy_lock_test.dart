// The heavy test lock (docs/plans/m5-7/01-infra.md 6.13, contract 00-overview
// 7.4.6 v2.1): file format compatibility, stale and malformed locks, nesting,
// waiting, time-out, the path variable and `ws with-heavy-lock`. The tests
// at the end run `dart run tool/ws.dart` as real processes (tag `process`).

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../src/cli.dart';
import '../src/flutter_runner.dart';
import '../src/heavy_lock.dart';
import 'support/fake_processes.dart';
import 'support/fixture_workspace.dart';

/// A clock that only moves when the locker sleeps.
final class _Clock {
  _Clock(this.now);

  DateTime now;
  final sleeps = <Duration>[];
  void Function()? onSleep;

  Future<void> sleep(Duration d) async {
    sleeps.add(d);
    now = now.add(d);
    onSleep?.call();
  }
}

void main() {
  late Directory dir;
  late String lockPath;
  late _Clock clock;
  late Set<int> alive;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('heavy_lock_');
    lockPath = p.join(dir.path, 'noteapp-heavy-tests.lock');
    clock = _Clock(DateTime.now());
    alive = {pid};
  });
  tearDown(() {
    releaseHeldHeavyLocks();
    dir.deleteSync(recursive: true);
  });

  HeavyLocker locker({int? ownPid}) => HeavyLocker(
    isAlive: alive.contains,
    now: () => clock.now,
    sleep: clock.sleep,
    ownPid: ownPid ?? pid,
  );

  Future<HeavyLockLease?> acquire({
    int? ownPid,
    Duration timeout = const Duration(minutes: 20),
    StringSink? log,
    String command = 'ws test -t media',
  }) => locker(ownPid: ownPid).acquire(
    path: lockPath,
    command: command,
    timeout: timeout,
    log: log ?? StringBuffer(),
  );

  group('format', () {
    test('one line: <pid> <start ISO-8601 UTC> <command, 120 chars>', () {
      final record = HeavyLockRecord(
        pid: 4242,
        started: DateTime.utc(2026, 11, 5, 9, 30, 1, 250),
        command: 'ws test\n  --platform chrome ${'x' * 200}',
      );
      expect(record.format(), startsWith('4242 2026-11-05T09:30:01.250Z '));
      expect(record.command, hasLength(heavyLockCommandLength));
      expect(record.command, startsWith('ws test --platform chrome x'));
      // Round trip: what one ws writes, another reads (with-heavy-lock ↔
      // ws test).
      final back = HeavyLockRecord.parse('${record.format()}\n')!;
      expect(back.pid, 4242);
      expect(back.started, record.started);
      expect(back.command, record.command);
    });

    test('a hand-written file in the documented format parses (another '
        'implementation, an older ws, a shell script)', () {
      final record = HeavyLockRecord.parse(
        '987 2026-11-05T08:00:00Z bash functions/scripts/emulator_suite.sh\n',
      )!;
      expect(record.pid, 987);
      expect(record.started, DateTime.utc(2026, 11, 5, 8));
      expect(record.command, 'bash functions/scripts/emulator_suite.sh');
      // A command is optional.
      expect(HeavyLockRecord.parse('5 2026-11-05T08:00:00Z')!.command, '');
    });

    test('malformed: empty, no number, no time, pid 0', () {
      for (final text in [
        '',
        '\n',
        'abc 2026-11-05T08:00:00Z x',
        '12',
        '12 yesterday x',
        '0 2026-11-05T08:00:00Z x',
      ]) {
        expect(HeavyLockRecord.parse(text), isNull, reason: text);
      }
    });

    test('path: fixed /tmp file, NOTEAPP_HEAVY_LOCK moves it', () {
      expect(defaultHeavyLockPath, '/tmp/noteapp-heavy-tests.lock');
      expect(heavyLockPath(const {}), defaultHeavyLockPath);
      expect(heavyLockPath({heavyLockPathVariable: ''}), defaultHeavyLockPath);
      expect(heavyLockPath({heavyLockPathVariable: '/x/y.lock'}), '/x/y.lock');
      expect(heavyLockHeldByParent({heavyLockHeldVariable: '1'}), isTrue);
      expect(heavyLockHeldByParent(const {}), isFalse);
    });
  });

  group('acquire', () {
    test('a free lock: the file holds our record until release; the log '
        'gets both lines', () async {
      final lease = (await acquire())!;
      expect(lease.waited, Duration.zero);
      final text = File(lockPath).readAsStringSync();
      expect(HeavyLockRecord.parse(text)!.pid, pid);
      expect(text, endsWith('ws test -t media\n'));
      lease
        ..release()
        ..release(); // idempotent
      expect(File(lockPath).existsSync(), isFalse);
      final log = File(p.join(dir.path, heavyLockLogName))
          .readAsLinesSync()
          .join('\n');
      expect(log, contains('$pid acquired after 0s: ws test -t media'));
      expect(log, contains('$pid released after'));
    });

    test('① a hand-written lock with a live pid: waits, prints the holder '
        'once a minute, gives up at the time-out', () async {
      alive.add(777);
      File(
        lockPath,
      ).writeAsStringSync('777 2026-11-05T08:00:00Z bash emulator_suite.sh\n');
      final log = StringBuffer();
      final lease = await acquire(
        timeout: const Duration(minutes: 3),
        log: log,
      );
      expect(lease, isNull);
      final waits = '$log'
          .split('\n')
          .where((l) => l.contains('잠금 대기'))
          .toList();
      // At 0, 1, 2 minutes (3 = time-out).
      expect(waits, hasLength(3));
      expect(waits.first, contains('pid 777'));
      expect(waits.first, contains('started 2026-11-05T08:00:00.000Z'));
      expect(waits.first, contains('command bash emulator_suite.sh'));
      expect('$log', contains('giving up'));
      expect(File(lockPath).readAsStringSync(), contains('777'));
    });

    test('① a hand-written lock with a dead pid is reclaimed', () async {
      File(lockPath).writeAsStringSync('999999 2026-11-05T08:00:00Z old\n');
      final log = StringBuffer();
      final lease = (await acquire(log: log))!;
      expect('$log', contains('pid 999999 is gone'));
      expect(
        HeavyLockRecord.parse(File(lockPath).readAsStringSync())!.pid,
        pid,
      );
      expect(clock.sleeps, isEmpty);
      lease.release();
    });

    test('③ a malformed file waits while younger than a minute, is '
        'reclaimed after', () async {
      File(lockPath).writeAsStringSync('');
      final log = StringBuffer();
      final lease = (await acquire(log: log))!;
      // Polled every 2 s until the file was a minute old.
      expect(
        clock.sleeps.fold(Duration.zero, (a, b) => a + b),
        greaterThanOrEqualTo(const Duration(seconds: 58)),
      );
      expect('$log', contains('lock file being written or unreadable'));
      expect('$log', contains('(unreadable) — reclaimed'));
      lease.release();

      // Already old: reclaimed at once.
      File(lockPath)
        ..writeAsStringSync('garbage\n')
        ..setLastModifiedSync(clock.now.subtract(const Duration(minutes: 2)));
      clock.sleeps.clear();
      (await acquire())!.release();
      expect(clock.sleeps, isEmpty);
    });

    test('⑤ two takers: the second waits until the first releases', () async {
      alive.add(4321);
      final first = (await acquire(ownPid: 4321, command: 'first'))!;
      clock.onSleep = () {
        if (clock.sleeps.length == 3) first.release();
      };
      final second = (await acquire(command: 'second'))!;
      expect(clock.sleeps, hasLength(3));
      expect(second.waited, const Duration(seconds: 6));
      expect(File(lockPath).readAsStringSync(), contains('second'));
      second.release();
    });

    test('⑥ time-out zero: one look, no sleep', () async {
      File(lockPath).writeAsStringSync('$pid 2026-11-05T08:00:00Z mine\n');
      expect(await acquire(timeout: Duration.zero), isNull);
      expect(clock.sleeps, isEmpty);
    });

    test('release keeps a lock that is no longer ours', () async {
      final lease = (await acquire())!;
      File(lockPath).writeAsStringSync('1 2026-11-05T08:00:00Z someone\n');
      lease.release();
      expect(File(lockPath).readAsStringSync(), contains('someone'));
    });

    test('releaseHeldHeavyLocks (SIGINT / SIGTERM path) releases every '
        'lease', () async {
      final lease = (await acquire())!;
      releaseHeldHeavyLocks();
      expect(lease.isReleased, isTrue);
      expect(File(lockPath).existsSync(), isFalse);
    });

    test('the real liveness check: this process is alive, a finished one '
        'is not', () async {
      expect(processIsAlive(pid), isTrue);
      final done = await Process.start('true', const []);
      await done.exitCode;
      expect(processIsAlive(done.pid), isFalse);
    }, skip: Platform.isWindows ? 'POSIX only' : false);
  });

  group('ws with-heavy-lock (in process)', () {
    late FakeProcesses processes;
    late StringBuffer out;
    late StringBuffer err;

    Future<int> run(List<String> args, {Map<String, String> env = const {}}) {
      out = StringBuffer();
      err = StringBuffer();
      return runWs(
        ['with-heavy-lock', ...args],
        context: WsContext(
          root: dir.path,
          out: out,
          err: err,
          environment: {heavyLockPathVariable: lockPath, ...env},
          processes: processes,
          workingDirectory: dir.path,
          heavyLocker: locker(),
        ),
      );
    }

    setUp(() {
      processes = FakeProcesses((call) {
        // ② the record with-heavy-lock wrote is the format ws test reads.
        final record = HeavyLockRecord.parse(File(lockPath).readAsStringSync());
        return RunResult(exitCode: record?.pid == pid ? 7 : 99);
      });
    });

    test('runs the command under the lock with NOTEAPP_HEAVY_LOCK_HELD=1 and '
        'returns its exit code', () async {
      final code = await run(['--', 'npm', 'run', 'test:emulator']);
      expect(code, 7);
      final call = processes.calls.single;
      expect(call.executable, 'npm');
      expect(call.arguments, ['run', 'test:emulator']);
      expect(call.workingDirectory, dir.path);
      expect(call.environment, {heavyLockHeldVariable: '1'});
      expect(File(lockPath).existsSync(), isFalse);
      expect(
        File(p.join(dir.path, heavyLockLogName)).readAsStringSync(),
        contains('ws with-heavy-lock -- npm run test:emulator'),
      );
    });

    test(
      '④ NOTEAPP_HEAVY_LOCK_HELD=1: runs at once without taking it',
      () async {
        File(lockPath).writeAsStringSync('$pid 2026-11-05T08:00:00Z outer\n');
        processes.handler = (_) => const RunResult(exitCode: 0);
        final code = await run(
          ['--timeout', '0', '--', 'true'],
          env: {heavyLockHeldVariable: '1'},
        );
        expect(code, 0);
        expect(processes.calls, hasLength(1));
        expect(File(lockPath).readAsStringSync(), contains('outer'));
      },
    );

    test('⑥ a live holder and --timeout 0: exit code 4, nothing run', () async {
      File(lockPath).writeAsStringSync('$pid 2026-11-05T08:00:00Z other\n');
      final code = await run(['--timeout', '0', '--', 'true']);
      expect(code, heavyLockTimeoutExitCode);
      expect(processes.calls, isEmpty);
      expect('$err', contains('did not come free within 0 min'));
    });

    test('a command killed by a signal exits 128 + n; a missing command is '
        'a usage error', () async {
      processes.handler = (_) => const RunResult(exitCode: -15);
      expect(await run(['--', 'sleep', '9']), 143);
      expect(await run(['--']), usageExitCode);
      expect('$err', contains('missing the command'));
      expect(await run(['--timeout', 'soon', '--', 'x']), usageExitCode);
    });
  });

  group(
    'real processes',
    () {
      Future<Process> ws(List<String> args, {Map<String, String>? env}) =>
          Process.start(
            Platform.resolvedExecutable,
            ['run', p.join(repoRoot, 'tool', 'ws.dart'), ...args],
            workingDirectory: repoRoot,
            environment: {heavyLockPathVariable: lockPath, ...?env},
          );

      test('⑤ two with-heavy-lock processes never overlap: the second '
          'waits (printing the holder) until the first ends', () async {
        final trace = p.join(dir.path, 'trace');
        final go = p.join(dir.path, 'go');
        final scriptA =
            'echo "start A" >> "$trace"; '
            'while [ ! -f "$go" ]; do sleep 0.1; done; '
            'echo "end A" >> "$trace"';
        final a = await ws(['with-heavy-lock', '--', 'bash', '-c', scriptA]);
        unawaited(a.stdout.drain<void>());
        unawaited(a.stderr.drain<void>());
        final deadline = DateTime.now().add(const Duration(minutes: 1));
        while (!File(trace).existsSync()) {
          if (DateTime.now().isAfter(deadline)) fail('A did not start');
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        final b = await ws([
          'with-heavy-lock',
          '--',
          'bash',
          '-c',
          'echo "start B" >> "$trace"; echo "end B" >> "$trace"',
        ]);
        final bOut = StringBuffer();
        final waiting = Completer<void>();
        b.stdout.transform(const SystemEncoding().decoder).listen((chunk) {
          bOut.write(chunk);
          if ('$bOut'.contains('잠금 대기') && !waiting.isCompleted) {
            waiting.complete();
          }
        });
        unawaited(b.stderr.drain<void>());
        await waiting.future.timeout(const Duration(minutes: 1));
        expect(File(trace).readAsLinesSync(), ['start A']);
        expect('$bOut', contains('pid ${a.pid}'));
        File(go).writeAsStringSync('');
        expect(await a.exitCode, 0);
        expect(await b.exitCode, 0);
        expect(File(trace).readAsLinesSync(), [
          'start A',
          'end A',
          'start B',
          'end B',
        ]);
        expect(File(lockPath).existsSync(), isFalse);
      });

      test('⑨ SIGTERM: the command tree is killed, ws exits 143 and the lock '
          'file is gone', () async {
        final proc = await ws(['with-heavy-lock', '--', 'sleep', '120']);
        final output = StringBuffer();
        proc.stdout
            .transform(const SystemEncoding().decoder)
            .listen(output.write);
        proc.stderr
            .transform(const SystemEncoding().decoder)
            .listen(output.write);
        final deadline = DateTime.now().add(const Duration(minutes: 1));
        while (!File(lockPath).existsSync()) {
          if (DateTime.now().isAfter(deadline)) fail('no lock file: $output');
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        // The child has been started once the lock is ours.
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(
          HeavyLockRecord.parse(File(lockPath).readAsStringSync())!.pid,
          proc.pid,
        );
        expect(proc.kill(), isTrue);
        expect(await proc.exitCode, 143, reason: '$output');
        expect(File(lockPath).existsSync(), isFalse, reason: '$output');
      });
    },
    tags: ['process'],
    skip: Platform.isLinux ? false : 'needs /proc and bash',
  );
}
