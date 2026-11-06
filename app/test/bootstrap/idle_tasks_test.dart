// AppIdleTaskRunner (docs/plans/m5-7/01-infra.md 4.6.2, 6.5.1; contract
// 7.3.3 (v2.1) '시점과 순서'). Widget tests: the time is the tester's fake
// clock, the lifecycle state is driven through the binding.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noteapp/src/bootstrap/idle_tasks.dart';
import 'package:noteapp/src/errors/app_error_log.dart';

import '../fakes/fake_web_platform.dart';

final _value = Provider<String>((ref) => 'root value', name: '_testValue');

final class _Rig {
  final AppErrorLog errorLog = AppErrorLog();
  final List<String> log = [];

  /// Tasks wait for these when given (id → gate).
  final Map<String, Completer<void>> gates = {};
  AppIdleContext? context;

  AppIdleTask task(
    String id, {
    int priority = AppIdlePriority.searchIndex,
    Duration delay = const Duration(seconds: 3),
    bool immediate = false,
    Object? error,
  }) => AppIdleTask(
    id: id,
    priority: priority,
    delay: delay,
    immediate: immediate,
    run: (context) async {
      this.context = context;
      log.add('run:$id');
      final gate = gates[id];
      if (gate != null) await gate.future;
      if (error != null) Error.throwWithStackTrace(error, StackTrace.current);
      log.add('done:$id');
    },
  );

  Future<void> pump(WidgetTester tester, List<AppIdleTask> tasks) =>
      tester.pumpWidget(
        ProviderScope(
          child: AppIdleTaskRunner(
            tasks: tasks,
            errorLog: errorLog,
            web: FakeWebPlatform(),
            child: Builder(
              builder: (context) {
                log.add('build');
                return const SizedBox();
              },
            ),
          ),
        ),
      );
}

Future<void> _lifecycle(WidgetTester tester, AppLifecycleState state) async {
  tester.binding.handleAppLifecycleStateChanged(state);
  await _settle(tester);
}

/// Zero-delay timers (the scheduler's task loop, Timer.run) fire only when
/// the fake clock elapses, which a bare pump() does not do.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(Duration.zero);
  }
}

void main() {
  // Back to 'no state yet' (null) for the next test.
  tearDown(() => TestWidgetsFlutterBinding.instance.resetInternalState());

  testWidgets('nothing runs before the first frame; immediate tasks run '
      'right after it, without the delay and outside the queue', (
    tester,
  ) async {
    final rig = _Rig()..gates['media.recoverDrafts'] = Completer<void>();
    await rig.pump(tester, [
      rig.task(
        'media.recoverDrafts',
        priority: AppIdlePriority.dataProtection,
        delay: Duration.zero,
      ),
      rig.task(
        'media.leaveGuard',
        priority: AppIdlePriority.dataProtection,
        immediate: true,
      ),
    ]);
    // The build came first, the immediate task right after the frame.
    expect(rig.log.take(3), [
      'build',
      'run:media.leaveGuard',
      'done:media.leaveGuard',
    ]);

    await _settle(tester);
    expect(rig.log, contains('run:media.recoverDrafts'));
    // The queued task (delay 0) ran after the immediate one, in the queue.
    rig.gates['media.recoverDrafts']!.complete();
    await _settle(tester);
    expect(rig.log.last, 'done:media.recoverDrafts');
  });

  testWidgets('queued tasks: priority order 0 → 10 → 20 (ties keep list '
      'order), one at a time', (tester) async {
    final rig = _Rig();
    for (final id in ['pdf.a', 'pdf.b', 'media.recoverDrafts', 'rec']) {
      rig.gates[id] = Completer<void>();
    }
    await rig.pump(tester, [
      rig.task('rec', priority: AppIdlePriority.recognition),
      rig.task('pdf.a', priority: AppIdlePriority.searchIndex),
      rig.task('media.recoverDrafts', priority: AppIdlePriority.dataProtection),
      rig.task('pdf.b', priority: AppIdlePriority.searchIndex),
    ]);
    await tester.pump(const Duration(seconds: 3));
    await _settle(tester);

    final order = <String>[];
    for (final id in ['media.recoverDrafts', 'pdf.a', 'pdf.b', 'rec']) {
      final running = rig.log.where((e) => e.startsWith('run:')).toList();
      // Exactly one task is running and not done.
      expect(running.length, order.length + 1, reason: 'before $id');
      expect(running.last, 'run:$id');
      order.add(id);
      rig.gates[id]!.complete();
      await _settle(tester);
      await _settle(tester);
    }
    expect(rig.log.where((e) => e.startsWith('done:')), [
      'done:media.recoverDrafts',
      'done:pdf.a',
      'done:pdf.b',
      'done:rec',
    ]);
  });

  testWidgets('each delay counts from the first frame; a task whose delay '
      'passed while an earlier one ran starts at once', (tester) async {
    final rig = _Rig()..gates['slow'] = Completer<void>();
    await rig.pump(tester, [
      rig.task('slow', priority: 0, delay: const Duration(seconds: 3)),
      rig.task('next', priority: 1, delay: const Duration(seconds: 4)),
    ]);
    await tester.pump(const Duration(milliseconds: 2900));
    expect(rig.log, ['build']);
    await tester.pump(const Duration(milliseconds: 100));
    await _settle(tester);
    expect(rig.log, ['build', 'run:slow']);

    await tester.pump(const Duration(seconds: 10));
    expect(rig.log, ['build', 'run:slow']);
    rig.gates['slow']!.complete();
    await _settle(tester);
    await _settle(tester);
    expect(rig.log, [
      'build',
      'run:slow',
      'done:slow',
      'run:next',
      'done:next',
    ]);
  });

  group('lifecycle', () {
    for (final state in [
      AppLifecycleState.resumed,
      AppLifecycleState.inactive,
    ]) {
      testWidgets('${state.name}: runs', (tester) async {
        final rig = _Rig();
        await rig.pump(tester, [rig.task('t')]);
        await _lifecycle(tester, state);
        await tester.pump(const Duration(seconds: 3));
        await _settle(tester);
        expect(rig.log, ['build', 'run:t', 'done:t']);
      });
    }

    testWidgets('no state yet (null): runs', (tester) async {
      expect(tester.binding.lifecycleState, isNull);
      final rig = _Rig();
      await rig.pump(tester, [rig.task('t')]);
      await tester.pump(const Duration(seconds: 3));
      await _settle(tester);
      expect(rig.log, ['build', 'run:t', 'done:t']);
    });

    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      testWidgets('${state.name}: waits, runs once visible again', (
        tester,
      ) async {
        final rig = _Rig();
        await rig.pump(tester, [
          rig.task('a', priority: 0),
          rig.task('b', priority: 1),
        ]);
        await _lifecycle(tester, AppLifecycleState.inactive);
        if (state != AppLifecycleState.hidden) {
          await _lifecycle(tester, AppLifecycleState.hidden);
        }
        await _lifecycle(tester, state);
        await tester.pump(const Duration(minutes: 1));
        expect(rig.log, ['build']);

        await _lifecycle(tester, AppLifecycleState.resumed);
        await _settle(tester);
        await _settle(tester);
        expect(rig.log, ['build', 'run:a', 'done:a', 'run:b', 'done:b']);
      });
    }
  });

  testWidgets('a throwing task is logged (source module) and the next one '
      'runs', (tester) async {
    final rig = _Rig();
    await rig.pump(tester, [
      rig.task('pdf.searchIndexer', priority: 10, error: StateError('boom')),
      rig.task('recognition.indexer', priority: 20),
    ]);
    await tester.pump(const Duration(seconds: 3));
    await _settle(tester);
    await _settle(tester);
    expect(rig.log, [
      'build',
      'run:pdf.searchIndexer',
      'run:recognition.indexer',
      'done:recognition.indexer',
    ]);
    final record = rig.errorLog.records.single;
    expect(record.source, AppErrorSource.module);
    expect(record.summary, startsWith('idle task pdf.searchIndexer failed: '));
    expect(record.summary, contains('boom'));
  });

  testWidgets('a task running for 30 s leaves one note; it is not cancelled '
      'and the next task waits', (tester) async {
    final rig = _Rig()..gates['media.recoverDrafts'] = Completer<void>();
    await rig.pump(tester, [
      rig.task('media.recoverDrafts', priority: 0),
      rig.task('pdf.searchIndexer', priority: 10),
    ]);
    await tester.pump(const Duration(seconds: 3));
    await _settle(tester);
    await tester.pump(const Duration(seconds: 30));
    expect(rig.errorLog.records.map((r) => r.summary), [
      'idle task media.recoverDrafts still running after 30 s',
    ]);
    await tester.pump(const Duration(minutes: 5));
    expect(rig.log, ['build', 'run:media.recoverDrafts']);
    rig.gates['media.recoverDrafts']!.complete();
    await _settle(tester);
    await _settle(tester);
    expect(rig.log.last, 'done:pdf.searchIndexer');
    expect(rig.errorLog.totalCount, 1);
  });

  testWidgets('context.read reads the root container', (tester) async {
    String? seen;
    final rig = _Rig();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [_value.overrideWithValue('overridden')],
        child: AppIdleTaskRunner(
          tasks: [
            AppIdleTask(
              id: 'x.read',
              priority: 0,
              immediate: true,
              run: (c) async => seen = c.read(_value),
            ),
          ],
          errorLog: rig.errorLog,
          web: FakeWebPlatform(),
          child: const SizedBox(),
        ),
      ),
    );
    expect(seen, 'overridden');
  });

  testWidgets('dispose: tasks not started never start; onDispose callbacks '
      'in reverse order, each ≤ 2 s, a throw is logged and the rest still '
      'run; a late registration is called at once', (tester) async {
    final rig = _Rig()..gates['first'] = Completer<void>();
    final calls = <String>[];
    final hang = Completer<void>();
    await rig.pump(tester, [
      AppIdleTask(
        id: 'x.register',
        priority: 0,
        immediate: true,
        run: (c) async {
          c.onDispose(() => calls.add('1'));
          c.onDispose(() => throw StateError('cleanup boom'));
          c.onDispose(() => hang.future);
          c.onDispose(() async => calls.add('4'));
        },
      ),
      rig.task('first', priority: 0),
      rig.task('never', priority: 10),
    ]);
    await tester.pump(const Duration(seconds: 3));
    await _settle(tester);
    expect(rig.log, ['build', 'run:first']);
    final context = rig.context!;
    expect(context.isDisposed, isFalse);

    await tester.pumpWidget(const SizedBox());
    expect(context.isDisposed, isTrue);
    expect(calls, ['4']);
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(calls, ['4', '1']);
    expect(rig.errorLog.records.map((r) => r.summary.split(':').first), [
      'idle task clean-up failed',
      'idle task clean-up failed',
    ]);

    // The running task finishes after the scope went away and registers.
    context.onDispose(() => calls.add('late'));
    await _settle(tester);
    expect(calls, ['4', '1', 'late']);
    rig.gates['first']!.complete();
    await tester.pump(const Duration(seconds: 10));
    expect(rig.log, ['build', 'run:first', 'done:first']);
  });
}
