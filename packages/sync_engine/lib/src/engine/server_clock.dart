// Internal (not exported). Clock-skew samples and the server-time estimate (6.2.4).
// skew = serverTime − (request-start wall clock + round trip / 2); the median of the last
// five samples is SyncStatus.clockSkew. serverNow = the last sample's server time + the
// monotonic time elapsed since (a changed wall clock does not move it).
import '../common/server_cursor.dart';

/// 6.2.4 verdict on the median skew.
enum ClockVerdict {
  /// |skew| ≤ clockSkewWarning (2 min).
  ok,

  /// clockSkewWarning < |skew| ≤ clockSkewLimit (24 h): clockSkewWarning issue, sync goes on.
  warning,

  /// |skew| > clockSkewLimit: K3 (6.2.5) — no push, no apply.
  blocked,
}

/// A request in flight: the wall clock and the monotonic time when it started.
final class ClockProbe {
  ClockProbe._(this.wallMicros, this.startedMicros);
  final int wallMicros;
  final int startedMicros;

  /// Round trip, set when the request returned (own-commit samples, 6.2.4 ②).
  int? roundTripMicros;
}

final class ServerClock {
  /// [now] is the engine wall clock (= CORE clock); [stopwatch] the monotonic source
  /// (SyncEngine(stopwatch:), the harness base clock in tests).
  ServerClock({
    required this._now,
    required Stopwatch Function() stopwatch,
    this.warning = const Duration(minutes: 2),
    this.limit = const Duration(hours: 24),
    this.window = 5,
  }) : _watch = stopwatch()..start();

  final DateTime Function() _now;
  final Stopwatch _watch;
  final Duration warning, limit;

  /// Samples kept for the median.
  final int window;

  final List<int> _samples = [];
  int? _anchorServerMicros, _anchorElapsedMicros;
  final Map<String, ClockProbe> _commits = {};

  bool get hasSample => _anchorServerMicros != null;

  /// Median of the last [window] samples (mean of the two middle ones for an even count);
  /// null before the first sample.
  Duration? get skew {
    if (_samples.isEmpty) return null;
    final sorted = List.of(_samples)..sort();
    final mid = sorted.length ~/ 2;
    final micros = sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) ~/ 2;
    return Duration(microseconds: micros);
  }

  ClockVerdict get verdict {
    final s = skew;
    if (s == null) return ClockVerdict.ok;
    final abs = s.isNegative ? -s : s;
    if (abs > limit) return ClockVerdict.blocked;
    if (abs > warning) return ClockVerdict.warning;
    return ClockVerdict.ok;
  }

  /// Estimated server time (µs); null without a sample.
  int? serverNowMicros() {
    final server = _anchorServerMicros, at = _anchorElapsedMicros;
    if (server == null || at == null) return null;
    return server + (_watch.elapsedMicroseconds - at);
  }

  /// Estimated server time (ms); null without a sample.
  int? serverNowMillis() {
    final micros = serverNowMicros();
    return micros == null ? null : micros ~/ 1000;
  }

  /// Before a request whose answer carries a server time (upsertDevice, commitChunks).
  ClockProbe begin() =>
      ClockProbe._(_now().microsecondsSinceEpoch, _watch.elapsedMicroseconds);

  /// Sample ① (6.2.4): upsertDevice answered with [serverTime].
  void complete(ClockProbe probe, ServerCursor serverTime) {
    probe.roundTripMicros ??= _watch.elapsedMicroseconds - probe.startedMicros;
    _add(probe, serverTime);
  }

  /// Sample ② bookkeeping: a commit of [chunkIds] is about to start.
  ClockProbe beginCommit(Iterable<String> chunkIds) {
    final probe = begin();
    for (final id in chunkIds) {
      _commits[id] = probe;
    }
    return probe;
  }

  /// The commit returned: its round trip is known.
  void endCommit(ClockProbe probe) {
    probe.roundTripMicros = _watch.elapsedMicroseconds - probe.startedMicros;
  }

  /// The commit failed: forget its chunks.
  void abortCommit(Iterable<String> chunkIds) {
    for (final id in chunkIds) {
      _commits.remove(id);
    }
  }

  /// Sample ② (6.2.4): an own chunk came back (DownloadPipeline.onOwnChunk). One sample per
  /// commit; chunks this session did not commit are ignored.
  void onOwnChunk(String chunkId, ServerCursor serverTime) {
    final probe = _commits.remove(chunkId);
    if (probe == null || probe.roundTripMicros == null) return;
    _commits.removeWhere((_, p) => identical(p, probe));
    _add(probe, serverTime);
  }

  void _add(ClockProbe probe, ServerCursor serverTime) {
    final half = probe.roundTripMicros! ~/ 2;
    _samples.add(serverTime.micros - (probe.wallMicros + half));
    if (_samples.length > window) _samples.removeAt(0);
    _anchorServerMicros = serverTime.micros;
    _anchorElapsedMicros = probe.startedMicros + half;
  }
}
