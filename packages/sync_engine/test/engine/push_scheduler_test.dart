import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/src/engine/push_scheduler.dart';

const Duration ms100 = Duration(milliseconds: 100);

Duration ms(int n) => Duration(milliseconds: n);

/// A scheduler whose pushes record their start time and take [pushTime].
final class Rig {
  Rig(this.async, {this.pushTime = Duration.zero, bool live = true}) {
    scheduler = PushScheduler(
      debounce: ms(500),
      maxBatchDelay: ms(1000),
      live: live,
      run: () async {
        expect(running, isFalse, reason: 'two pushes at the same time');
        running = true;
        starts.add(async.elapsed);
        await Future<void>.delayed(pushTime);
        running = false;
      },
    );
  }

  final FakeAsync async;
  final Duration pushTime;
  late final PushScheduler scheduler;
  final List<Duration> starts = [];
  bool running = false;
}

void main() {
  test('a single trigger pushes after 500 ms', () {
    fakeAsync((async) {
      final r = Rig(async);
      r.scheduler.trigger();
      expect(r.scheduler.isPending, isTrue);
      async.elapse(ms(499));
      expect(r.starts, isEmpty);
      async.elapse(ms(1));
      expect(r.starts, [ms(500)]);
      async.elapse(const Duration(seconds: 5));
      expect(r.starts, [ms(500)]);
      expect(r.scheduler.isPending, isFalse);
    });
  });

  test('continuous triggers push at 1,000 ms after the first', () {
    fakeAsync((async) {
      final r = Rig(async);
      // A trigger every 100 ms for 3 s (continuous writing).
      for (var i = 0; i < 30; i++) {
        r.scheduler.trigger();
        async.elapse(ms100);
      }
      expect(r.starts, [ms(1000), ms(2000), ms(3000)]);
    });
  });

  test(
    'min(tl + 500, t0 + 1000): last trigger decides when it comes first',
    () {
      fakeAsync((async) {
        final r = Rig(async);
        r.scheduler.trigger(); // t0 = 0
        async.elapse(ms(300));
        r.scheduler.trigger(); // tl = 300 → 800 < 1000
        async.elapse(ms(1000));
        expect(r.starts, [ms(800)]);
      });
    },
  );

  test('triggers while pushing are rescheduled after the push ends', () {
    fakeAsync((async) {
      final r = Rig(async, pushTime: ms(700));
      r.scheduler.trigger();
      async.elapse(ms(500)); // push 1 runs 500..1200
      expect(r.starts, [ms(500)]);
      expect(r.scheduler.isRunning, isTrue);
      r.scheduler.trigger(); // 600: window → due at 1100, during the push
      async.elapse(ms(600)); // 1100
      expect(r.starts, [ms(500)]);
      async.elapse(ms(100)); // 1200: push 1 ends, push 2 starts at once
      expect(r.starts, [ms(500), ms(1200)]);
      async.elapse(ms(700));
      // A trigger late in a push waits for its own window.
      r.scheduler.trigger(); // 1900, push 2 ends at 1900
      async.elapse(ms(499));
      expect(r.starts, hasLength(2));
      async.elapse(ms(1));
      expect(r.starts, [ms(500), ms(1200), ms(2400)]);
    });
  });

  test('a trigger during a push whose window is still open waits for it', () {
    fakeAsync((async) {
      final r = Rig(async, pushTime: ms(200));
      r.scheduler.trigger();
      async.elapse(ms(600)); // push 500..700
      r.scheduler.trigger(); // 600 → 1100
      async.elapse(ms(500));
      expect(r.starts, [ms(500), ms(1100)]);
    });
  });

  test('not live: held, then pushed at once when live', () {
    fakeAsync((async) {
      final r = Rig(async, live: false);
      r.scheduler.trigger();
      async.elapse(const Duration(seconds: 10));
      expect(r.starts, isEmpty);
      expect(r.scheduler.isPending, isTrue);
      r.scheduler.setLive(true);
      async.flushMicrotasks();
      expect(r.starts, [const Duration(seconds: 10)]);

      // A window still open when the engine becomes live also runs at once.
      r.scheduler.setLive(false);
      r.scheduler.trigger();
      async.elapse(ms(100));
      r.scheduler.setLive(true);
      async.flushMicrotasks();
      expect(r.starts.last, const Duration(seconds: 10) + ms(100));
      async.elapse(const Duration(seconds: 2));
      expect(r.starts, hasLength(2));
    });
  });

  test('becoming live with nothing waiting does not push', () {
    fakeAsync((async) {
      final r = Rig(async, live: false);
      r.scheduler.setLive(true);
      async.elapse(const Duration(seconds: 2));
      expect(r.starts, isEmpty);
    });
  });

  test('immediate triggers skip the debounce and never overlap', () {
    fakeAsync((async) {
      final r = Rig(async, pushTime: ms(300));
      r.scheduler.trigger();
      async.elapse(ms(100));
      r.scheduler.trigger(immediate: true); // also closes the open window
      async.flushMicrotasks();
      expect(r.starts, [ms(100)]);
      r.scheduler.trigger(immediate: true); // during the push
      async.elapse(ms(300));
      expect(r.starts, [ms(100), ms(400)]);
      async.elapse(const Duration(seconds: 3));
      expect(r.starts, hasLength(2));
    });
  });

  test('triggerAfter pushes after the delay; cancelDelayed drops it', () {
    fakeAsync((async) {
      final r = Rig(async);
      r.scheduler.triggerAfter(const Duration(seconds: 2));
      expect(r.scheduler.isPending, isTrue);
      async.elapse(const Duration(seconds: 2));
      expect(r.starts, [const Duration(seconds: 2)]);
      r.scheduler.triggerAfter(const Duration(seconds: 2));
      r.scheduler.cancelDelayed();
      async.elapse(const Duration(seconds: 5));
      expect(r.starts, hasLength(1));
      expect(r.scheduler.isPending, isFalse);
    });
  });

  test('flush runs the open window now and completes when idle', () {
    fakeAsync((async) {
      final r = Rig(async, pushTime: ms(200));
      var flushed = false;
      r.scheduler.flush().then((_) => flushed = true);
      async.flushMicrotasks();
      expect(flushed, isTrue);
      expect(r.starts, isEmpty);

      r.scheduler.trigger();
      async.elapse(ms(50));
      flushed = false;
      r.scheduler.flush().then((_) => flushed = true);
      async.flushMicrotasks();
      expect(r.starts, [ms(50)]);
      expect(flushed, isFalse);
      async.elapse(ms(200));
      expect(flushed, isTrue);
    });
  });

  test('drain fires windows that open during a push at once and completes when '
      'nothing runs or is due', () {
    fakeAsync((async) {
      final r = Rig(async, pushTime: ms100);
      var drained = false;
      r.scheduler.trigger(immediate: true);
      r.scheduler.drain().then((_) => drained = true);
      async.elapse(ms(50));
      r.scheduler.trigger(); // during the push: a new 500 ms window
      async.elapse(ms(50));
      // The first push ended at 100 ms; drain fired the window instead of waiting 500 ms.
      expect(r.starts, [Duration.zero, ms100]);
      expect(drained, isFalse);
      async.elapse(ms100);
      expect(drained, isTrue);
      expect(r.scheduler.isPending, isFalse);
      async.elapse(const Duration(seconds: 2));
      expect(r.starts, hasLength(2));
    });
  });

  test('drain completes at once while not live or when nothing waits', () {
    fakeAsync((async) {
      final r = Rig(async, live: false);
      r.scheduler.trigger(immediate: true);
      var drained = false;
      r.scheduler.drain().then((_) => drained = true);
      async.flushMicrotasks();
      expect(drained, isTrue);
      expect(r.starts, isEmpty);
      final idle = Rig(async);
      var idleDrained = false;
      idle.scheduler.drain().then((_) => idleDrained = true);
      async.flushMicrotasks();
      expect(idleDrained, isTrue);
    });
  });

  test('push errors go to onError and the scheduler keeps going', () {
    fakeAsync((async) {
      final errors = <Object>[];
      var calls = 0;
      final scheduler = PushScheduler(
        debounce: ms(500),
        maxBatchDelay: ms(1000),
        live: true,
        onError: (e, _) => errors.add(e),
        run: () async {
          calls++;
          if (calls == 1) throw StateError('boom');
        },
      );
      scheduler.trigger();
      async.elapse(ms(500));
      expect(errors, [isA<StateError>()]);
      scheduler.trigger();
      async.elapse(ms(500));
      expect(calls, 2);
      expect(scheduler.runCount, 2);
    });
  });

  test('dispose cancels everything and ignores later triggers', () {
    fakeAsync((async) {
      final r = Rig(async);
      r.scheduler
        ..trigger()
        ..triggerAfter(ms(200));
      final idle = r.scheduler.whenIdle();
      var done = false;
      unawaited(idle.then((_) => done = true));
      r.scheduler.dispose();
      async.flushMicrotasks();
      expect(done, isTrue);
      r.scheduler.trigger(immediate: true);
      async.elapse(const Duration(seconds: 2));
      expect(r.starts, isEmpty);
    });
  });
}
