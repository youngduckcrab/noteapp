// Internal (not exported). Retry delays (6.8.1):
//   delay(n) = min(backoffMax, backoffBase × 2^(n−1)) × U(1 − jitter, 1 + jitter)
// n = consecutive failures (from 1), U from the injected Random. Quota errors wait
// at least quotaBackoff; rules / configuration errors wait misconfiguredBackoff
// (fixed, no jitter). Success resets n. Plain int arithmetic (web-safe, no shifts).
import 'dart:math';

import '../common/errors.dart';
import '../config.dart';

final class Backoff {
  Backoff({required SyncConfig config, required this._random})
    : _base = config.backoffBase,
      _max = config.backoffMax,
      _jitter = config.backoffJitter,
      _quota = config.quotaBackoff,
      _misconfigured = config.misconfiguredBackoff {
    if (_jitter < 0 || _jitter >= 1) {
      throw ArgumentError.value(_jitter, 'backoffJitter', 'must be in [0, 1)');
    }
  }

  final Duration _base, _max, _quota, _misconfigured;
  final double _jitter;
  final Random _random;
  int _failures = 0;

  /// Consecutive failures recorded since the last [reset].
  int get failures => _failures;

  /// Records one more failure and returns how long to wait before retrying.
  /// [code] picks the special waits of 6.5.4 (quota, rules, configuration).
  Duration next([SyncErrorCode? code]) {
    _failures++;
    return switch (code) {
      SyncErrorCode.permissionDenied ||
      SyncErrorCode.failedPrecondition => _misconfigured,
      SyncErrorCode.resourceExhausted => _atLeast(delayOf(_failures), _quota),
      _ => delayOf(_failures),
    };
  }

  /// Success: the next failure starts again at backoffBase.
  void reset() => _failures = 0;

  /// The jittered delay after [n] consecutive failures (draws one number).
  Duration delayOf(int n) {
    final nominal = nominalOf(n).inMicroseconds;
    if (_jitter == 0) return Duration(microseconds: nominal);
    final factor = 1 - _jitter + _random.nextDouble() * 2 * _jitter;
    return Duration(microseconds: (nominal * factor).round());
  }

  /// min(backoffMax, backoffBase × 2^(n−1)) without jitter.
  Duration nominalOf(int n) {
    if (n < 1) throw ArgumentError.value(n, 'n', 'must be at least 1');
    final max = _max.inMicroseconds;
    var micros = _base.inMicroseconds;
    for (var i = 1; i < n && micros < max; i++) {
      micros *= 2;
    }
    return Duration(microseconds: micros < max ? micros : max);
  }

  static Duration _atLeast(Duration d, Duration floor) => d < floor ? floor : d;
}
