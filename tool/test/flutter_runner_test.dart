// flutter / Chrome executable lookup (docs/plans/01-infra.md 4.2), and how
// `ws` stops its child processes: time limits kill the whole process tree,
// SIGINT / SIGTERM stop `ws` (TerminationGuard) instead of letting it go on
// with the next member.

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import '../src/flutter_runner.dart';

final class _RecordingTerminator implements ChildTerminator {
  int calls = 0;
  final done = Completer<void>();

  @override
  Future<void> terminateAll() {
    calls++;
    return done.future;
  }
}

/// Whether [pid] is a live process (Linux: a zombie counts as gone — in a
/// container nothing may reap a re-parented child).
bool _alive(int pid) {
  final stat = File('/proc/$pid/stat');
  if (!stat.existsSync()) return false;
  final text = stat.readAsStringSync();
  final state = text.substring(text.lastIndexOf(')') + 2).split(' ').first;
  return state != 'Z' && state != 'X';
}

/// Waits until [pid] is gone (polls; the test time limit is the bound).
Future<void> _gone(int pid) async {
  while (_alive(pid)) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// A shell whose background child keeps the output pipe open: prints the
/// child pid, then waits for it.
const _shellWithChild = ['-c', r'sleep 300 & echo "child $!"; wait'];

int _childPid(String output) =>
    int.parse(RegExp(r'child (\d+)').firstMatch(output)!.group(1)!);

void main() {
  group('TerminationGuard', () {
    late StreamController<ProcessSignal> signals;
    late _RecordingTerminator children;
    late List<int> exits;
    late StringBuffer err;
    late TerminationGuard guard;

    setUp(() {
      signals = StreamController<ProcessSignal>();
      children = _RecordingTerminator();
      exits = [];
      err = StringBuffer();
      guard = TerminationGuard(
        signals: signals.stream,
        children: children,
        exit: exits.add,
        err: err,
      );
    });
    tearDown(() async {
      await guard.cancel();
      await signals.close();
    });

    test('SIGTERM: kill the children first, then exit 143', () async {
      signals.add(ProcessSignal.sigterm);
      await pumpEventQueue();
      expect(children.calls, 1);
      expect(guard.stopping, isTrue);
      expect(exits, isEmpty, reason: 'waits for the children');
      var finished = false;
      unawaited(guard.finished.then((_) => finished = true));
      await pumpEventQueue();
      expect(finished, isFalse);
      children.done.complete();
      await pumpEventQueue();
      expect(exits, [143]);
      expect(finished, isTrue);
      expect(err.toString(), contains('stopping the running processes'));
    });

    test('SIGINT exits 130; a second signal exits at once', () async {
      signals.add(ProcessSignal.sigint);
      await pumpEventQueue();
      signals.add(ProcessSignal.sigint);
      await pumpEventQueue();
      expect(exits, [130]);
      expect(children.calls, 1);
      children.done.complete();
      await pumpEventQueue();
      expect(exits, [130, 130]);
    });

    test('a failing terminateAll still exits', () async {
      final failing = TerminationGuard(
        signals: Stream.value(ProcessSignal.sigterm),
        children: _ThrowingTerminator(),
        exit: exits.add,
        err: err,
      );
      await pumpEventQueue();
      expect(exits, [143]);
      expect(err.toString(), contains('could not stop every process'));
      await failing.cancel();
    });
  });

  group('IoProcessRunner', () {
    test('after terminateAll no new process is started', () async {
      final runner = IoProcessRunner(out: StringBuffer());
      await runner.terminateAll();
      // Would throw a ProcessException if it tried to start it.
      final result = await runner.run('/nonexistent/flutter', const [
        'test',
      ], workingDirectory: Directory.systemTemp.path);
      expect(result.interrupted, isTrue);
      expect(result.killedBySignal, isFalse);
    });

    test(
      'a time-out kills the whole process tree and does not wait for the '
      'pipes a grandchild holds',
      () async {
        final runner = IoProcessRunner(out: StringBuffer());
        final result = await runner.run(
          'sh',
          _shellWithChild,
          workingDirectory: Directory.systemTemp.path,
          timeout: const Duration(seconds: 1),
        );
        expect(result.timedOut, isTrue);
        expect(result.interrupted, isFalse);
        await _gone(_childPid(result.output));
      },
      skip: Platform.isLinux ? false : 'needs /proc',
      tags: ['process'],
    );

    test(
      'terminateAll (SIGINT / SIGTERM of ws) kills a running tree; the run '
      'reports interrupted',
      () async {
        final out = StringBuffer();
        final runner = IoProcessRunner(out: out);
        final running = runner.run(
          'sh',
          _shellWithChild,
          workingDirectory: Directory.systemTemp.path,
        );
        while (!out.toString().contains('child ')) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        await runner.terminateAll();
        final result = await running;
        expect(result.interrupted, isTrue);
        expect(result.timedOut, isFalse);
        await _gone(_childPid(result.output));
      },
      skip: Platform.isLinux ? false : 'needs /proc',
      tags: ['process'],
    );

    test(
      'processTree lists the root first, then its descendants',
      () async {
        final process = await Process.start('sh', _shellWithChild);
        final line = await process.stdout
            .transform(const SystemEncoding().decoder)
            .firstWhere((l) => l.contains('child '));
        final child = _childPid(line);
        final tree = await processTree(process.pid);
        expect(tree.first, process.pid);
        expect(tree, contains(child));
        await killProcessTree(process.pid, exited: process.exitCode);
        expect(await process.exitCode, isNot(0));
        await _gone(child);
      },
      skip: Platform.isWindows ? 'POSIX ps' : false,
      tags: ['process'],
    );
  });

  group('locateFlutter', () {
    String? locate(
      Map<String, String> env, {
      String resolved = '/usr/lib/dart/bin/dart',
      Set<String> files = const {},
    }) => locateFlutter(
      environment: env,
      resolvedExecutable: resolved,
      isFile: files.contains,
    );

    const all = {
      '/custom/flutter',
      '/froot/bin/flutter',
      '/sdk/bin/flutter',
      '/path/bin/flutter',
    };

    test('1. FLUTTER_BIN wins', () {
      expect(
        locate(
          {
            'FLUTTER_BIN': '/custom/flutter',
            'FLUTTER_ROOT': '/froot',
            'PATH': '/path/bin',
          },
          resolved: '/sdk/bin/cache/dart-sdk/bin/dart',
          files: all,
        ),
        '/custom/flutter',
      );
    });

    test('2. then FLUTTER_ROOT/bin/flutter', () {
      expect(
        locate(
          {'FLUTTER_ROOT': '/froot', 'PATH': '/path/bin'},
          resolved: '/sdk/bin/cache/dart-sdk/bin/dart',
          files: all,
        ),
        '/froot/bin/flutter',
      );
    });

    test('3. then the SDK of the running Dart VM', () {
      expect(
        locate(
          {'PATH': '/path/bin'},
          resolved: '/sdk/bin/cache/dart-sdk/bin/dart',
          files: all,
        ),
        '/sdk/bin/flutter',
      );
    });

    test('4. then PATH', () {
      expect(locate({'PATH': '/x:/path/bin'}, files: all), '/path/bin/flutter');
    });

    test('a FLUTTER_BIN that does not exist falls through', () {
      expect(
        locate({
          'FLUTTER_BIN': '/missing/flutter',
          'PATH': '/path/bin',
        }, files: all),
        '/path/bin/flutter',
      );
    });

    test('null when nothing is found', () {
      expect(locate({'PATH': '/nowhere'}), isNull);
    });
  });

  group('locateChrome', () {
    test('CHROME_EXECUTABLE is used as is', () {
      expect(
        locateChrome(
          environment: {
            'CHROME_EXECUTABLE': '/opt/chrome-wrapper',
            'PATH': '/usr/bin',
          },
          isFile: (_) => true,
        ),
        '/opt/chrome-wrapper',
      );
    });

    test('PATH names in order: google-chrome, -stable, chromium, '
        'chromium-browser', () {
      String? find(Set<String> files) =>
          locateChrome(environment: {'PATH': '/a:/b'}, isFile: files.contains);

      expect(find({'/b/google-chrome', '/a/chromium'}), '/b/google-chrome');
      expect(
        find({'/a/chromium', '/b/google-chrome-stable'}),
        '/b/google-chrome-stable',
      );
      expect(find({'/b/chromium-browser', '/a/chromium'}), '/a/chromium');
      expect(find({'/b/chromium-browser'}), '/b/chromium-browser');
      expect(find({}), isNull);
    });
  });
}

final class _ThrowingTerminator implements ChildTerminator {
  @override
  Future<void> terminateAll() => Future.error(StateError('kill failed'));
}
