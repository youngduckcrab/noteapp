import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/src/engine/backoff.dart';
import 'package:sync_engine/sync_engine.dart';

Duration s(num seconds) => Duration(microseconds: (seconds * 1000000).round());

void main() {
  const config = SyncConfig();

  test('nominal delays: 1, 2, 4, 8, 16, 32, 60, 60 … s', () {
    final b = Backoff(config: config, random: Random(1));
    expect(
      [for (var n = 1; n <= 10; n++) b.nominalOf(n)],
      [
        s(1), s(2), s(4), s(8), s(16), s(32), s(60), s(60), s(60), s(60), //
      ],
    );
    expect(b.nominalOf(1000), s(60));
    expect(() => b.nominalOf(0), throwsArgumentError);
  });

  test('a fixed seed gives a fixed jittered sequence within ±20 %', () {
    List<Duration> sequence(int seed) {
      final b = Backoff(config: config, random: Random(seed));
      return [for (var i = 0; i < 12; i++) b.next()];
    }

    final one = sequence(7);
    expect(sequence(7), one);
    expect(sequence(8), isNot(one));
    final nominal = Backoff(config: config, random: Random(1));
    for (var i = 0; i < one.length; i++) {
      final n = nominal.nominalOf(i + 1).inMicroseconds;
      expect(one[i].inMicroseconds, greaterThanOrEqualTo((n * 0.8).floor()));
      expect(one[i].inMicroseconds, lessThanOrEqualTo((n * 1.2).ceil()));
    }
    // The cap is the nominal 60 s; jitter stays around it.
    expect(one.last.inMicroseconds, lessThanOrEqualTo(72000000));
    expect(one.last.inMicroseconds, greaterThanOrEqualTo(48000000));
  });

  test('the sequence is the formula with the injected Random', () {
    final b = Backoff(config: config, random: Random(3));
    final expected = Random(3);
    for (var n = 1; n <= 9; n++) {
      final nominal = b.nominalOf(n).inMicroseconds;
      final factor = 0.8 + expected.nextDouble() * 0.4;
      expect(b.next().inMicroseconds, (nominal * factor).round());
      expect(b.failures, n);
    }
  });

  test('no jitter: exact nominal delays; reset starts again at base', () {
    final b = Backoff(
      config: config.copyWith(backoffJitter: 0),
      random: Random(1),
    );
    expect(
      [for (var i = 0; i < 8; i++) b.next()],
      [
        s(1), s(2), s(4), s(8), s(16), s(32), s(60), s(60), //
      ],
    );
    b.reset();
    expect(b.failures, 0);
    expect(b.next(), s(1));
  });

  test(
    'quota waits at least 5 minutes; rules and configuration 10 minutes',
    () {
      final b = Backoff(config: config, random: Random(5));
      expect(
        b.next(SyncErrorCode.resourceExhausted),
        const Duration(minutes: 5),
      );
      expect(
        b.next(SyncErrorCode.permissionDenied),
        const Duration(minutes: 10),
      );
      expect(
        b.next(SyncErrorCode.failedPrecondition),
        const Duration(minutes: 10),
      );
      expect(b.failures, 3);
      // Transient codes use the exponential delay.
      final d = b.next(SyncErrorCode.unavailable);
      expect(d, greaterThanOrEqualTo(s(8 * 0.8)));
      expect(d, lessThanOrEqualTo(s(8 * 1.2)));

      // A quota floor below the exponential delay keeps the larger one.
      final small = Backoff(
        config: config.copyWith(
          backoffJitter: 0,
          quotaBackoff: const Duration(seconds: 3),
        ),
        random: Random(1),
      );
      for (var i = 0; i < 3; i++) {
        small.next();
      }
      expect(small.next(SyncErrorCode.resourceExhausted), s(8));
    },
  );

  test('custom base and max', () {
    final b = Backoff(
      config: config.copyWith(
        backoffJitter: 0,
        backoffBase: const Duration(milliseconds: 250),
        backoffMax: const Duration(seconds: 3),
      ),
      random: Random(1),
    );
    expect(
      [for (var i = 0; i < 6; i++) b.next()],
      [
        s(0.25), s(0.5), s(1), s(2), s(3), s(3), //
      ],
    );
  });

  test('jitter outside [0, 1) is rejected', () {
    expect(
      () =>
          Backoff(config: config.copyWith(backoffJitter: 1), random: Random(1)),
      throwsArgumentError,
    );
  });
}
