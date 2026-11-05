// ServerClock (6.2.4): skew samples, median, monotonic server-time estimate, verdict
// boundaries. Virtual time: the stopwatch comes from the base clock, the wall clock is the
// base clock plus a device offset.
import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/src/engine/server_clock.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../support/fake_time.dart';

final DateTime start = DateTime.utc(2026, 11, 1, 9);

final class ClockRig {
  ClockRig(this.async) {
    base = async.getClock(start);
    clock = ServerClock(
      now: () => base.now().add(offset),
      stopwatch: base.stopwatch,
    );
  }

  final FakeAsync async;
  late final Clock base;
  late final ServerClock clock;
  Duration offset = Duration.zero;

  ServerCursor get serverNow => ServerCursor.fromDateTime(base.now());

  /// A probe answered after [roundTrip]; the server stamps the middle of it.
  void sample({Duration roundTrip = Duration.zero}) {
    final probe = clock.begin();
    async.elapse(roundTrip ~/ 2);
    final stamp = serverNow;
    async.elapse(roundTrip - roundTrip ~/ 2);
    clock.complete(probe, stamp);
  }
}

void withClock(void Function(ClockRig r) body) =>
    fakeAsync((async) => body(ClockRig(async)), initialTime: start);

void main() {
  test('no sample: no skew, no server time, verdict ok', () {
    withClock((r) {
      expect(r.clock.hasSample, isFalse);
      expect(r.clock.skew, isNull);
      expect(r.clock.serverNowMillis(), isNull);
      expect(r.clock.verdict, ClockVerdict.ok);
    });
  });

  test('skew = server − (start wall + round trip / 2)', () {
    withClock((r) {
      r.offset = const Duration(minutes: -3);
      r.sample(roundTrip: const Duration(milliseconds: 100));
      expect(r.clock.skew, const Duration(minutes: 3));
      expect(r.clock.verdict, ClockVerdict.warning);
      expect(r.clock.serverNowMicros(), r.serverNow.micros);
    });
  });

  test('the median of the last five samples; even counts take the mean of '
      'the middle two', () {
    withClock((r) {
      for (final minutes in [1, 2]) {
        r.offset = Duration(minutes: -minutes);
        r.sample();
      }
      expect(r.clock.skew, const Duration(seconds: 90));
      for (final minutes in [100, 3, 4]) {
        r.offset = Duration(minutes: -minutes);
        r.sample();
      }
      expect(r.clock.skew, const Duration(minutes: 3), reason: '1 2 100 3 4');
      r.offset = const Duration(minutes: -200);
      r.sample();
      expect(r.clock.skew, const Duration(minutes: 4), reason: '2 100 3 4 200');
    });
  });

  test('serverNow is monotonic: changing the wall clock does not move it; '
      'the next sample shows the new skew', () {
    withClock((r) {
      r.sample(roundTrip: const Duration(milliseconds: 40));
      r.async.elapse(const Duration(minutes: 10));
      r.offset = const Duration(hours: 2);
      expect(r.clock.serverNowMicros(), r.serverNow.micros);
      expect(r.clock.skew, Duration.zero);
      r.async.elapse(const Duration(hours: 3));
      expect(r.clock.serverNowMicros(), r.serverNow.micros);
      r.sample();
      // Median of 0 and −2 h.
      expect(r.clock.skew, const Duration(hours: -1));
    });
  });

  test('verdict boundaries: 2 min ok, + 1 ms warning, 24 h warning, '
      '+ 1 ms blocked (both signs)', () {
    ClockVerdict verdictAt(Duration offset) {
      late ClockVerdict v;
      withClock((r) {
        r.offset = -offset;
        r.sample();
        expect(r.clock.skew, offset);
        v = r.clock.verdict;
      });
      return v;
    }

    const ms = Duration(milliseconds: 1);
    for (final sign in [1, -1]) {
      expect(verdictAt(const Duration(minutes: 2) * sign), ClockVerdict.ok);
      expect(
        verdictAt((const Duration(minutes: 2) + ms) * sign),
        ClockVerdict.warning,
      );
      expect(verdictAt(const Duration(hours: 24) * sign), ClockVerdict.warning);
      expect(
        verdictAt((const Duration(hours: 24) + ms) * sign),
        ClockVerdict.blocked,
      );
    }
  });

  test('own-commit samples: one per commit, after the commit returned; '
      'unknown or aborted chunks are ignored', () {
    withClock((r) {
      r.offset = const Duration(minutes: 5);
      final probe = r.clock.beginCommit(['c1', 'c2']);
      r.async.elapse(const Duration(milliseconds: 40));
      final stamp = r.serverNow;
      r.async.elapse(const Duration(milliseconds: 40));
      r.clock.endCommit(probe);
      r.clock.onOwnChunk('unknown', stamp);
      expect(r.clock.hasSample, isFalse);
      r.clock.onOwnChunk('c1', stamp);
      expect(r.clock.skew, const Duration(minutes: -5));
      r.offset = Duration.zero;
      r.clock.onOwnChunk('c2', stamp);
      expect(r.clock.skew, const Duration(minutes: -5), reason: 'same commit');

      final aborted = r.clock.beginCommit(['c3']);
      r.clock
        ..endCommit(aborted)
        ..abortCommit(['c3'])
        ..onOwnChunk('c3', r.serverNow);
      expect(r.clock.skew, const Duration(minutes: -5));
    });
  });

  test('a probe around upsertDevice on the fake server', () {
    withClock((r) {
      r.offset = const Duration(hours: -30);
      final server = FakeSyncServer(clock: r.base);
      final backend = server.connect(uid: 'user-1', link: FakeNetworkLink());
      final probe = r.clock.begin();
      final stamp = runFake(
        r.async,
        backend.upsertDevice(
          const DeviceInfo(
            nodeId: 'a1a1a1a1a1a1a1a1',
            platform: DevicePlatform.web,
            appVersion: '0.0.0',
          ),
        ),
      );
      r.clock.complete(probe, stamp);
      expect(r.clock.skew, const Duration(hours: 30));
      expect(r.clock.verdict, ClockVerdict.blocked);
      expect(r.clock.serverNowMillis(), r.base.now().millisecondsSinceEpoch);
    });
  });
}
