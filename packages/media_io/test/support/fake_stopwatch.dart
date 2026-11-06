// A Stopwatch over fake time (m5-7/06-pdf 6.7): fake_async does not change Stopwatch, so the
// recording clock gets this through its factory. [now] is usually `() => async.elapsed`.
final class FakeStopwatch implements Stopwatch {
  FakeStopwatch(this.now);

  final Duration Function() now;
  Duration _accumulated = Duration.zero;
  Duration? _startedAt;

  @override
  int get frequency => 1000000;

  @override
  bool get isRunning => _startedAt != null;

  @override
  void start() => _startedAt ??= now();

  @override
  void stop() {
    final started = _startedAt;
    if (started == null) return;
    _accumulated += now() - started;
    _startedAt = null;
  }

  @override
  void reset() {
    _accumulated = Duration.zero;
    if (_startedAt != null) _startedAt = now();
  }

  @override
  Duration get elapsed {
    final started = _startedAt;
    return started == null ? _accumulated : _accumulated + (now() - started);
  }

  @override
  int get elapsedTicks => elapsed.inMicroseconds;

  @override
  int get elapsedMicroseconds => elapsed.inMicroseconds;

  @override
  int get elapsedMilliseconds => elapsed.inMilliseconds;
}
