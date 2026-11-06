// Recording clock (m5-7/06-pdf 6.7; 8.2 T31a — R-1, R-2, M-1): a Stopwatch over fake time
// (FakeStopwatch + fake_async) driven by engine events — start, user pause, resume, system
// pause, stop. The offset never goes back, pauses are not counted, and offsetNowMs is null
// unless the phase is recording.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/src/record/recording_clock.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/fake_stopwatch.dart';

void main() {
  test('start → pause → resume → system pause → resume → stop', () {
    fakeAsync((async) {
      final clock = RecordingClock(
        stopwatch: () => FakeStopwatch(() => async.elapsed),
      );
      expect(clock.elapsedMs, 0);
      async.elapse(const Duration(seconds: 5)); // before the engine started
      clock.start();
      expect(clock.elapsedMs, 0);
      async.elapse(const Duration(milliseconds: 1200));
      expect(clock.elapsedMs, 1200);
      clock.pause(); // EnginePaused (user)
      async.elapse(const Duration(seconds: 3));
      expect(clock.elapsedMs, 1200);
      clock.resume();
      async.elapse(const Duration(milliseconds: 300));
      expect(clock.elapsedMs, 1500);
      clock.pause(); // EnginePaused (bySystem — a call, a hidden tab)
      async.elapse(const Duration(minutes: 2));
      expect(clock.elapsedMs, 1500);
      clock.resume();
      async.elapse(const Duration(milliseconds: 250));
      expect(clock.stop(), 1750);
      async.elapse(const Duration(seconds: 10));
      expect(clock.elapsedMs, 1750);
    });
  });

  test('monotonic: never goes back, pauses excluded', () {
    fakeAsync((async) {
      final clock = RecordingClock(
        stopwatch: () => FakeStopwatch(() => async.elapsed),
      )..start();
      var last = clock.elapsedMs;
      for (var i = 0; i < 40; i++) {
        async.elapse(Duration(milliseconds: 37 + i));
        if (i % 7 == 3) clock.pause();
        if (i % 7 == 5) clock.resume();
        final now = clock.elapsedMs;
        expect(now, greaterThanOrEqualTo(last));
        last = now;
      }
    });
  });

  test('a second start begins again from 0', () {
    fakeAsync((async) {
      final clock = RecordingClock(
        stopwatch: () => FakeStopwatch(() => async.elapsed),
      )..start();
      async.elapse(const Duration(seconds: 2));
      clock.stop();
      clock.start();
      expect(clock.elapsedMs, 0);
      async.elapse(const Duration(milliseconds: 40));
      expect(clock.elapsedMs, 40);
    });
  });

  test('offsetNowMs: the clock while recording, null in every other phase', () {
    fakeAsync((async) {
      final clock = RecordingClock(
        stopwatch: () => FakeStopwatch(() => async.elapsed),
      )..start();
      async.elapse(const Duration(milliseconds: 900));
      expect(offsetNowMsOf(core.RecorderPhase.recording, clock), 900);
      for (final phase in [
        core.RecorderPhase.idle,
        core.RecorderPhase.starting,
        core.RecorderPhase.paused,
        core.RecorderPhase.finishing,
      ]) {
        expect(offsetNowMsOf(phase, clock), isNull, reason: '$phase');
      }
    });
  });

  test('the default factory is a real Stopwatch', () {
    final clock = RecordingClock()..start();
    expect(clock.elapsedMs, greaterThanOrEqualTo(0));
    clock.stop();
  });
}
