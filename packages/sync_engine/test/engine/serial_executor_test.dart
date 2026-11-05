import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/src/engine/serial_executor.dart';

void main() {
  test('runs one task at a time in submission order', () {
    fakeAsync((async) {
      final executor = SerialExecutor();
      final log = <String>[];
      var active = 0;
      Future<int> task(String name, Duration d, int value) async {
        active++;
        expect(active, 1);
        log.add('start $name');
        await Future<void>.delayed(d);
        log.add('end $name');
        active--;
        return value;
      }

      final results = <int>[];
      executor
          .run(() => task('a', const Duration(seconds: 2), 1))
          .then(results.add);
      executor
          .run(() => task('b', const Duration(seconds: 1), 2))
          .then(results.add);
      executor.run(() => task('c', Duration.zero, 3)).then(results.add);
      expect(executor.isBusy, isTrue);
      expect(executor.queueLength, 2);
      async.flushMicrotasks();
      expect(log, ['start a']);
      async.elapse(const Duration(seconds: 3));
      expect(log, [
        'start a', 'end a', 'start b', 'end b', 'start c', 'end c', //
      ]);
      expect(results, [1, 2, 3]);
      expect(executor.isBusy, isFalse);
    });
  });

  test('an error completes only its own task', () {
    fakeAsync((async) {
      final executor = SerialExecutor();
      Object? error;
      int? value;
      executor
          .run<int>(() async => throw StateError('boom'))
          .then<void>((_) {}, onError: (Object e) => error = e);
      executor.run(() async => 42).then((v) => value = v);
      async.flushMicrotasks();
      expect(error, isA<StateError>());
      expect(value, 42);
    });
  });

  test('a task submitted from inside a task runs after it', () {
    fakeAsync((async) {
      final executor = SerialExecutor();
      final log = <String>[];
      executor.run(() async {
        log.add('outer start');
        unawaited(executor.run(() async => log.add('inner')));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        log.add('outer end');
      });
      async.elapse(const Duration(milliseconds: 10));
      expect(log, ['outer start', 'outer end', 'inner']);
    });
  });

  test('idle completes when the queue is empty', () {
    fakeAsync((async) {
      final executor = SerialExecutor();
      var idle = false;
      executor.idle.then((_) => idle = true);
      async.flushMicrotasks();
      expect(idle, isTrue);

      idle = false;
      executor.run(
        () => Future<void>.delayed(const Duration(seconds: 1)),
        label: 'push',
      );
      executor.idle.then((_) => idle = true);
      async.flushMicrotasks();
      expect(executor.currentLabel, 'push');
      expect(idle, isFalse);
      async.elapse(const Duration(seconds: 1));
      expect(idle, isTrue);
      expect(executor.currentLabel, isNull);
    });
  });

  test('close lets the running task finish and fails the waiting ones', () {
    fakeAsync((async) {
      final executor = SerialExecutor();
      var firstDone = false;
      Object? waitingError;
      executor
          .run(() => Future<void>.delayed(const Duration(seconds: 1)))
          .then((_) => firstDone = true);
      executor
          .run(() async => fail('must not run'))
          .then<void>((_) {}, onError: (Object e) => waitingError = e);
      async.flushMicrotasks();
      executor.close();
      async.flushMicrotasks();
      expect(waitingError, isA<StateError>());
      expect(executor.isClosed, isTrue);
      expect(() => executor.run(() async {}), throwsStateError);
      async.elapse(const Duration(seconds: 1));
      expect(firstDone, isTrue);
      var idle = false;
      executor.idle.then((_) => idle = true);
      async.flushMicrotasks();
      expect(idle, isTrue);
    });
  });
}
